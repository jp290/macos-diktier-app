import AppKit
import Carbon
import Combine
import FlowCore

enum DictationShortcut: String, CaseIterable, Identifiable {
    case doubleCommand, optionSpace, controlSpace, optionD
    var id: String { rawValue }
    var title: String {
        switch self {
        case .doubleCommand: return "⌘ zweimal drücken"
        case .optionSpace: return "⌥ ⌘ Leertaste"
        case .controlSpace: return "⌃ ⌘ Leertaste"
        case .optionD: return "⌥ ⌘ D"
        }
    }
    static func restored(from value: String?) -> Self {
        value.flatMap(Self.init(rawValue:)) ?? .doubleCommand
    }
    var registrationError: String {
        self == .doubleCommand
            ? "Der Kurzbefehl konnte nicht eingerichtet werden. Prüfe die Freigabe für Bedienungshilfen."
            : "Dieses Tastenkürzel ist bereits belegt. Wähle ein anderes."
    }
    var key: UInt32 { self == .optionD ? UInt32(kVK_ANSI_D) : UInt32(kVK_Space) }
    var modifiers: UInt32 { UInt32(cmdKey | (self == .controlSpace ? controlKey : optionKey)) }
}

@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var doubleTap = DoubleCommandTap()
    var action: (() -> Void)?

    func register(_ shortcut: DictationShortcut) -> Bool {
        unregister()
        if shortcut == .doubleCommand {
            let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown,
                                              .rightMouseDown, .otherMouseDown]
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                MainActor.assumeIsolated { self?.handleDoubleCommandEvent(event) }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                MainActor.assumeIsolated { self?.handleDoubleCommandEvent(event) }
                return event
            }
            guard globalMonitor != nil, localMonitor != nil else { unregister(); return false }
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.doubleTap.interrupt() }
            }
            return true
        }
        var specification = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let object = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { object.action?() }
            return noErr
        }, 1, &specification, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { unregister(); return false }
        let identifier = EventHotKeyID(signature: 0x57464C57, id: 1)
        let registered = RegisterEventHotKey(shortcut.key, shortcut.modifiers, identifier,
                                            GetApplicationEventTarget(), 0, &hotKey) == noErr
        if !registered { unregister() }
        return registered
    }

    func handleDoubleCommandEvent(_ event: NSEvent) {
        guard event.type == .flagsChanged else { doubleTap.interrupt(); return }
        let otherModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .function]
        if doubleTap.flagsChanged(commandDown: event.modifierFlags.contains(.command),
                                  otherModifierDown: !event.modifierFlags.intersection(otherModifiers).isEmpty,
                                  at: event.timestamp) {
            action?()
        }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        hotKey = nil
        handler = nil
        globalMonitor = nil
        localMonitor = nil
        activationObserver = nil
        doubleTap.reset()
    }
}

@MainActor
struct InsertionTarget {
    let application: NSRunningApplication
    let element: AXUIElement?
}

@MainActor
enum TextInsertion {
    static var permitted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func capture(_ application: NSRunningApplication?) -> InsertionTarget? {
        guard permitted, let application, !application.isTerminated,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return InsertionTarget(application: application, element: focusedElement(application))
    }

    private static func focusedElement(_ application: NSRunningApplication) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(application.processIdentifier),
                                                   kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func stillFocused(_ target: InsertionTarget) -> Bool {
        guard !target.application.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.application.processIdentifier else { return false }
        guard let element = target.element else { return true }
        guard let current = focusedElement(target.application) else { return false }
        return CFEqual(current, element)
    }

    static func paste(_ text: String, into target: InsertionTarget?) async -> Bool {
        guard permitted, !text.isEmpty, let target, stillFocused(target) else { return false }
        try? await Task.sleep(nanoseconds: 70_000_000)
        guard !Task.isCancelled, stillFocused(target),
              let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return false }
        let board = NSPasteboard.general
        let previous = board.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        board.clearContents()
        board.setString(text, forType: .string)
        let ownChange = board.changeCount
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if board.changeCount == ownChange {
                board.clearContents()
                if !previous.isEmpty { board.writeObjects(previous) }
            }
        }
        return true
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
