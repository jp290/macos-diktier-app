import AppKit
import FlowCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var models: ModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("So hört die App zu.").font(.system(size: 27, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 14) {
                Text("Spracherkennung").font(.system(size: 14, weight: .semibold))
                Picker("Sprache", selection: $controller.language) {
                    ForEach(SpeechLanguage.allCases) { language in Text(language.title).tag(language) }
                }
                Text("Automatisch erkennt Deutsch und Englisch ohne Umschalten. Gesprochene Wörter werden nicht übersetzt.")
                    .font(.system(size: 12)).foregroundStyle(FlowTheme.muted)
                Picker("Modell", selection: $controller.preset) {
                    ForEach(ModelPreset.allCases) { preset in Text(preset.title).tag(preset) }
                }.disabled(models.downloading)
                Text(modelDescription).font(.system(size: 12)).foregroundStyle(FlowTheme.muted)
                if controller.ready {
                    Label("Heruntergeladen · Offline verfügbar", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(FlowTheme.blue).font(.system(size: 12))
                } else if models.downloading {
                    if models.verifying {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(models.status).font(.system(size: 12))
                        }
                    } else {
                        ProgressView(value: models.progress).tint(FlowTheme.blue)
                            .accessibilityLabel("Modelldownload")
                            .accessibilityValue("\(Int(models.progress * 100)) Prozent")
                    }
                    HStack {
                        Text(models.verifying ? models.transferLabel : "\(Int(models.progress * 100)) % · \(models.transferLabel)")
                            .font(.system(size: 12)).monospacedDigit()
                        Spacer()
                        Button("Abbrechen") { models.cancel() }
                    }
                } else {
                    Button("Modell herunterladen (\(controller.preset.downloadLabel))") { models.download(controller.preset) }
                        .buttonStyle(.borderedProminent).tint(FlowTheme.blue)
                }
                if !models.status.isEmpty && !models.downloading { Text(models.status).font(.system(size: 12)).textSelection(.enabled) }
                Text("Nur der Modelldownload benötigt Internet. Es werden keine Aufnahmen hochgeladen.")
                    .font(.system(size: 11)).foregroundStyle(FlowTheme.muted)
            }.disabled(controller.busy || models.downloading && controller.ready)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Diktieren").font(.system(size: 14, weight: .semibold))
                MicrophonePicker(controller: controller, devices: controller.audioDevices)
                Picker("Tastenkürzel", selection: $controller.shortcutChoice) {
                    ForEach(DictationShortcut.allCases) { shortcut in Text(shortcut.title).tag(shortcut) }
                }
                if controller.shortcutChoice == .doubleCommand {
                    Text("Command zweimal kurz drücken: starten oder stoppen. Auf Windows-Tastaturen normalerweise die Windows-Taste. Benötigt die Freigabe für Bedienungshilfen.")
                        .font(.system(size: 12)).foregroundStyle(FlowTheme.muted)
                }
                Toggle("Text automatisch in die aktive App einfügen", isOn: $controller.autoPaste)
                Toggle("„Neue Zeile“ und „Neuer Absatz“ als Umbruch schreiben", isOn: $controller.spokenCommands)
                Toggle("Die letzten 50 Diktate lokal speichern", isOn: $controller.keepHistory)
                TextField("Eigennamen und Fachbegriffe, mit Kommas getrennt", text: $controller.vocabulary)
                    .textFieldStyle(.roundedBorder)
                Text("Diese Begriffe helfen dem Modell bei der Erkennung. Maximal 500 Zeichen.")
                    .font(.system(size: 11)).foregroundStyle(FlowTheme.muted)
            }.font(.system(size: 13)).disabled(controller.busy)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Mac-Berechtigungen").font(.system(size: 14, weight: .semibold))
                permissionRow("Mikrofon", detail: "Damit die App deine Stimme aufnehmen kann.",
                    allowed: controller.microphoneGranted, action: controller.requestMicrophone)
                permissionRow("Bedienungshilfen", detail: "Damit die App den Text am Cursor einfügen kann.",
                    allowed: controller.accessibilityGranted) {
                    TextInsertion.requestPermission()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }.onChange(of: models.downloading) { _, _ in controller.objectWillChange.send() }
    }

    private var modelDescription: String {
        switch controller.preset {
        case .qwen: return "Qualitätsmodus für Deutsch und Englisch. 8-Bit-Modell, 2,5 GB Download. Für Apple Silicon mit 16 GB RAM vorgesehen."
        case .turbo: return "Mehrsprachiges Whisper-Modell mit Metal-Beschleunigung. 574 MB Download. Gute Alternative mit geringerem Speicherbedarf."
        case .small: return "Kompaktes Modell mit 190 MB Download. Weniger präzise bei Eigennamen und gemischten Sprachen."
        }
    }

    private func permissionRow(_ title: String, detail: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: allowed ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(allowed ? FlowTheme.blue : FlowTheme.muted)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(FlowTheme.muted)
            }
            Spacer()
            if allowed { Text("Erlaubt").font(.system(size: 12)).foregroundStyle(FlowTheme.muted) }
            else { Button("Freigeben", action: action) }
        }
    }
}

struct MicrophonePicker: View {
    @ObservedObject var controller: AppController
    @ObservedObject var devices: AudioDevices

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Picker("Mikrofon", selection: $controller.microphoneUID) {
                Text("Systemstandard").tag("")
                ForEach(devices.inputs) { device in Text(device.name).tag(device.id) }
                if !controller.microphoneUID.isEmpty, !devices.inputs.contains(where: { $0.id == controller.microphoneUID }) {
                    Text("Gewähltes Mikrofon nicht verbunden").tag(controller.microphoneUID)
                }
            }
            Text("Gilt nur für diese App. Die macOS-Geräteeinstellung bleibt erhalten.")
                .font(.system(size: 11)).foregroundStyle(FlowTheme.muted)
        }.onAppear { devices.refresh() }
    }
}
