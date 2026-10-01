import AppKit
import FlowCore
import SwiftUI

enum FlowTheme {
    static let ink = Color(red: 0.08, green: 0.15, blue: 0.25)
    static let blue = Color(red: 0.15, green: 0.39, blue: 0.70)
    static let rail = Color(red: 0.92, green: 0.95, blue: 0.98)
    static let muted = Color(red: 0.40, green: 0.47, blue: 0.55)
}

enum AppTab: String, CaseIterable {
    case dictate = "Diktieren", history = "Verlauf", settings = "Einstellungen"
    var icon: String {
        switch self {
        case .dictate: return "waveform"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct ContentView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var models: ModelManager
    @State private var tab: AppTab = .dictate

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform").font(.system(size: 25, weight: .semibold)).foregroundStyle(FlowTheme.blue)
                    Text("macOS-\nDiktier-App").font(.system(size: 18, weight: .semibold)).lineSpacing(0)
                }.padding(.top, 22)
                VStack(spacing: 6) {
                    ForEach(AppTab.allCases, id: \.self) { destination in
                        Button { tab = destination } label: {
                            Label(destination.rawValue, systemImage: destination.icon)
                                .font(.system(size: 13, weight: tab == destination ? .semibold : .medium))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 11).padding(.horizontal, 12)
                                .foregroundStyle(tab == destination ? FlowTheme.blue : FlowTheme.muted)
                                .background(tab == destination ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Auf deinem Mac", systemImage: "lock.shield")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(FlowTheme.blue)
                    Text("Audio und Text bleiben lokal.")
                        .font(.system(size: 11)).foregroundStyle(FlowTheme.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(.bottom, 20)
            }.padding(.horizontal, 16).frame(width: 180).background(FlowTheme.rail)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(tab.rawValue).font(.system(size: 13, weight: .medium)).foregroundStyle(FlowTheme.muted)
                    Spacer()
                    Circle().fill(controller.ready ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(controller.ready ? "Lokal bereit" : "Modell einrichten")
                        .font(.system(size: 12)).foregroundStyle(FlowTheme.muted)
                }.padding(.horizontal, 34).padding(.vertical, 20)
                Divider().opacity(0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let error = controller.error {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 13))
                                if controller.canRetry {
                                    HStack {
                                        Button("Erneut transkribieren") { controller.retry() }
                                        Button("Aufnahme verwerfen") { controller.discardAudio(); controller.error = nil }
                                    }
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(FlowTheme.ink)
                        }
                        switch tab {
                        case .dictate: DictationView(controller: controller, recorder: controller.recorder) { tab = .settings }
                        case .history: HistoryView(controller: controller)
                        case .settings: SettingsView(controller: controller, models: models)
                        }
                    }.padding(34)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
        }.foregroundStyle(FlowTheme.ink).preferredColorScheme(.light)
            .frame(minWidth: 820, minHeight: 610)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                controller.refreshPermissions()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showFlowSettings)) { _ in tab = .settings }
    }
}

struct DictationView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var recorder: Recorder
    let settings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Deine Stimme.\nÜberall als Text.").font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-0.7)
                Text("Sprich Deutsch, Englisch oder beides.\nDein Diktat landet dort, wo du gerade schreibst.")
                    .font(.system(size: 14)).foregroundStyle(FlowTheme.muted).lineSpacing(4)
            }
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(FlowTheme.rail).frame(width: 90, height: 90)
                    if controller.phase == .processing || controller.phase == .permission || controller.phase == .inserting {
                        ProgressView().controlSize(.large).tint(FlowTheme.blue)
                    } else {
                        Image(systemName: controller.phase == .recording ? "waveform" : "mic")
                            .font(.system(size: 34, weight: .medium)).foregroundStyle(FlowTheme.blue)
                    }
                }
                if controller.phase == .recording {
                    WaveformView(level: recorder.level).frame(width: 200, height: 26)
                    Text(String(format: "%02d:%02d / 02:00", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60))
                        .monospacedDigit().font(.system(size: 12)).foregroundStyle(FlowTheme.muted)
                }
                Text(controller.message).font(.system(size: 13)).foregroundStyle(FlowTheme.muted)
                Button {
                    if controller.ready { controller.toggle() } else { settings() }
                } label: {
                    Label(buttonTitle, systemImage: controller.phase == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 22).padding(.vertical, 10)
                }.buttonStyle(.borderedProminent).tint(FlowTheme.blue)
                    .disabled(controller.busy && controller.phase != .recording)
                HStack(spacing: 6) {
                    Text(controller.shortcutChoice.title).font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 5).background(.white, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(FlowTheme.rail, lineWidth: 1))
                    Text("zum Starten und Stoppen").font(.system(size: 11)).foregroundStyle(FlowTheme.muted)
                }
                if controller.busy { Button("Abbrechen") { controller.cancel() }.buttonStyle(.plain).font(.system(size: 12)) }
            }.padding(.vertical, 24).frame(maxWidth: .infinity)
            Divider()
            if let transcript = controller.lastTranscript {
                HStack {
                    Text("Letztes Diktat").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button { TextInsertion.copy(transcript.text); controller.message = "Text kopiert." } label: {
                        Label("Kopieren", systemImage: "doc.on.doc")
                    }.buttonStyle(.plain).foregroundStyle(FlowTheme.blue)
                }
                Text(transcript.text).font(.system(size: 14)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(transcript.wordCount) Wörter · \(transcript.processingSeconds.formatted(.number.precision(.fractionLength(1)))) s Verarbeitung")
                    .font(.system(size: 11)).foregroundStyle(FlowTheme.muted)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "text.cursor").font(.system(size: 21)).foregroundStyle(FlowTheme.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cursor setzen. Sprechen. Weiterschreiben.").font(.system(size: 13, weight: .medium))
                        Text("Nach dem Stoppen wird der fertige Text eingefügt. Du findest ihn auch hier.")
                            .font(.system(size: 12)).foregroundStyle(FlowTheme.muted)
                    }
                }
            }
        }
    }

    private var buttonTitle: String {
        if !controller.ready { return "Sprachmodell einrichten" }
        switch controller.phase {
        case .idle: return "Diktat starten"
        case .recording: return "Stoppen und einfügen"
        case .permission: return "Mikrofon freigeben …"
        case .processing: return "Wird transkribiert …"
        case .inserting: return "Text wird eingefügt …"
        }
    }
}

struct WaveformView: View {
    let level: Double
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<27, id: \.self) { index in
                Capsule().fill(FlowTheme.blue.opacity(0.35 + level * 0.65))
                    .frame(width: 3, height: 3 + level * (8 + abs(sin(Double(index) * 1.7)) * 18))
            }
        }.animation(.easeOut(duration: 0.08), value: level)
    }
}

struct HistoryView: View {
    @ObservedObject var controller: AppController
    @State private var search = ""
    @State private var confirmClear = false
    var entries: [Transcript] {
        controller.history.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Deine letzten Worte.").font(.system(size: 27, weight: .semibold, design: .rounded))
            Text("Die letzten 50 Diktate werden ausschließlich auf diesem Mac gespeichert.")
                .font(.system(size: 13)).foregroundStyle(FlowTheme.muted)
            HStack {
                TextField("Diktate durchsuchen", text: $search).textFieldStyle(.roundedBorder)
                Button("Verlauf löschen", role: .destructive) { confirmClear = true }.disabled(controller.history.isEmpty)
            }
            if entries.isEmpty {
                ContentUnavailableView(controller.keepHistory ? "Noch keine Diktate" : "Verlauf ausgeschaltet",
                    systemImage: "text.bubble", description: Text("Dein nächster Text erscheint nach dem Diktieren hier."))
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11)).foregroundStyle(FlowTheme.muted)
                            Spacer()
                            Button { TextInsertion.copy(entry.text) } label: { Label("Kopieren", systemImage: "doc.on.doc") }
                                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(FlowTheme.blue)
                        }
                        Text(entry.text).font(.system(size: 14)).textSelection(.enabled).lineSpacing(4)
                        Divider()
                    }
                }
            }
        }.alert("Lokalen Verlauf löschen?", isPresented: $confirmClear) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { controller.clearHistory() }
        } message: { Text("Die gespeicherten Diktate werden von diesem Mac entfernt.") }
    }
}
