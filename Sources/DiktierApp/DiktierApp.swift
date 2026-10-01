import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let showFlowSettings = Notification.Name("showFlowSettings")
}

@main
struct DiktierApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var controller: AppController!
    private var window: NSWindow!
    private var hud: NSPanel!
    private var item: NSStatusItem!
    private var menu: NSMenu!
    private var permissionTimer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = AppController()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "macOS-Diktier-App"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 820, height: 650)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(controller: controller, models: controller.models))
        window.center()
        hud = DictationPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hud.isFloatingPanel = true
        hud.hidesOnDeactivate = false
        hud.level = .floating
        hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hud.isOpaque = false
        hud.backgroundColor = .clear
        hud.hasShadow = true
        hud.contentView = NSHostingView(rootView: RecordingHUD(controller: controller, recorder: controller.recorder))
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "macOS-Diktier-App")
        menu = NSMenu()
        item.menu = menu
        controller.showWindow = { [weak self] in self?.showMainWindow() }
        controller.onRecordingStart = { [weak self] in
            self?.window.orderOut(nil)
            NSApp.hide(nil)
        }
        controller.onStateChange = { [weak self] in self?.refreshState() }
        controller.models.$revision.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshState() }
        }.store(in: &subscriptions)
        controller.$preset.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshState() }
        }.store(in: &subscriptions)
        configureApplicationMenu()
        refreshState()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.refreshPermissions() }
        }
        showMainWindow()
    }

    private func configureApplicationMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "macOS-Diktier-App beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Bearbeiten")
        for (title, action, key) in [
            ("Widerrufen", Selector(("undo:")), "z"),
            ("Ausschneiden", #selector(NSText.cut(_:)), "x"),
            ("Kopieren", #selector(NSText.copy(_:)), "c"),
            ("Einfügen", #selector(NSText.paste(_:)), "v"),
            ("Alles auswählen", #selector(NSText.selectAll(_:)), "a")
        ] { editMenu.addItem(withTitle: title, action: action, keyEquivalent: key) }
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }

    private func refreshState() {
        menu.removeAllItems()
        addMenuItem(controller.phase == .recording ? "Diktat stoppen" : "Diktat starten", action: #selector(toggleRecording))
        menu.items.last?.isEnabled = controller.ready && (!controller.busy || controller.phase == .recording)
        if controller.busy { addMenuItem("Diktat abbrechen", action: #selector(cancelRecording)) }
        menu.addItem(.separator())
        addMenuItem("macOS-Diktier-App öffnen", action: #selector(showMainWindow))
        addMenuItem("Einstellungen …", action: #selector(showSettings))
        if controller.lastTranscript != nil { addMenuItem("Letztes Diktat kopieren", action: #selector(copyLast)) }
        menu.addItem(.separator())
        addMenuItem("Beenden", action: #selector(quit))
        item.button?.image = NSImage(systemSymbolName: controller.phase == .recording ? "mic.fill" : "waveform",
                                   accessibilityDescription: "macOS-Diktier-App")
        if controller.phase == .recording || controller.phase == .processing || controller.phase == .inserting {
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
                hud.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - hud.frame.width / 2,
                                          y: screen.visibleFrame.minY + 18))
            }
            hud.orderFrontRegardless()
        } else { hud.orderOut(nil) }
    }

    private func addMenuItem(_ title: String, action: Selector) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        menu.addItem(entry)
    }

    @objc func showMainWindow() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        controller.refreshPermissions()
    }
    @objc private func showSettings() { showMainWindow(); NotificationCenter.default.post(name: .showFlowSettings, object: nil) }
    @objc private func toggleRecording() { controller.toggle() }
    @objc private func cancelRecording() { controller.cancel() }
    @objc private func copyLast() { if let transcript = controller.lastTranscript { TextInsertion.copy(transcript.text) } }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller.cancel()
        Task {
            await controller.transcriber.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        controller.shutdown()
        NSStatusBar.system.removeStatusItem(item)
    }
}

final class DictationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct RecordingHUD: View {
    @ObservedObject var controller: AppController
    @ObservedObject var recorder: Recorder
    var body: some View {
        HStack(spacing: 10) {
            if controller.phase == .recording {
                HStack(spacing: 3) {
                    ForEach(0..<9, id: \.self) { index in
                        Capsule().fill(FlowTheme.blue)
                            .frame(width: 3, height: 3 + recorder.level * (5 + abs(sin(Double(index) * 1.7)) * 15))
                    }
                }.frame(width: 54, height: 24).accessibilityLabel("Mikrofonpegel")
                Text(String(format: "%02d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { controller.finishRecording() } label: { Image(systemName: "stop.fill") }
                    .accessibilityLabel("Stoppen und einfügen").help("Stoppen und einfügen")
            } else {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 18)
                Text(controller.phase == .inserting ? "Einfügen …" : "Erkennen …").font(.system(size: 12))
                Spacer(minLength: 0)
            }
            Button { controller.cancel() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Diktat abbrechen").help("Diktat abbrechen")
        }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 13).frame(width: 200, height: 40)
            .background(.regularMaterial, in: Capsule()).foregroundStyle(.primary)
    }
}
