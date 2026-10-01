import AppKit
import AVFoundation
import Combine
import FlowCore
import Foundation
import OSLog

enum DictationPhase { case idle, permission, recording, processing, inserting }

@MainActor
final class AppController: ObservableObject {
    @Published var phase: DictationPhase = .idle
    @Published var message = "Bereit für deine Gedanken."
    @Published var error: String?
    @Published var lastTranscript: Transcript?
    @Published var history: [Transcript] = []
    @Published var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var accessibilityGranted = TextInsertion.permitted
    @Published var language: SpeechLanguage {
        didSet { defaults.set(language.rawValue, forKey: "language") }
    }
    @Published var preset: ModelPreset {
        didSet { defaults.set(preset.rawValue, forKey: "model") }
    }
    @Published var shortcutChoice: DictationShortcut {
        didSet {
            defaults.set(shortcutChoice.rawValue, forKey: "shortcut")
            if !shortcut.register(shortcutChoice) { error = shortcutChoice.registrationError }
        }
    }
    @Published var autoPaste: Bool { didSet { defaults.set(autoPaste, forKey: "autoPaste") } }
    @Published var spokenCommands: Bool { didSet { defaults.set(spokenCommands, forKey: "spokenCommands") } }
    @Published var keepHistory: Bool {
        didSet {
            defaults.set(keepHistory, forKey: "keepHistory")
            if !keepHistory { clearHistory() }
        }
    }
    @Published var vocabulary: String { didSet { defaults.set(vocabulary, forKey: "vocabulary") } }
    @Published var microphoneUID: String { didSet { defaults.set(microphoneUID, forKey: "microphoneUID") } }
    let models: ModelManager
    let audioDevices = AudioDevices()
    let recorder = Recorder()
    let shortcut = GlobalShortcut()
    let transcriber = Transcriber()
    let historyStore: HistoryStore
    private let defaults = UserDefaults.standard
    private var operation: Task<Void, Never>?
    private var preparation: Task<Void, Never>?
    private var recordingID: UUID?
    private var audioURL: URL?
    private var target: InsertionTarget?
    private var previousExternalApp: NSRunningApplication?
    private var workspaceObserver: NSObjectProtocol?
    var onStateChange: (() -> Void)?
    var onRecordingStart: (() -> Void)?
    var showWindow: (() -> Void)?

    init() {
        // Kept from the app's former name so existing models and history stay in place.
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperFlow")
        models = ModelManager(root: root.appendingPathComponent("Models"))
        historyStore = HistoryStore(url: root.appendingPathComponent("history.json"))
        language = SpeechLanguage(rawValue: defaults.string(forKey: "language") ?? "auto") ?? .automatic
        preset = ModelPreset(rawValue: defaults.string(forKey: "model") ?? "qwen") ?? .qwen
        shortcutChoice = DictationShortcut.restored(from: defaults.string(forKey: "shortcut"))
        autoPaste = defaults.object(forKey: "autoPaste") as? Bool ?? true
        spokenCommands = defaults.object(forKey: "spokenCommands") as? Bool ?? true
        keepHistory = defaults.object(forKey: "keepHistory") as? Bool ?? true
        vocabulary = defaults.string(forKey: "vocabulary") ?? ""
        microphoneUID = defaults.string(forKey: "microphoneUID") ?? ""
        if keepHistory {
            do { history = try historyStore.load() }
            catch { self.error = "Der Verlauf konnte nicht gelesen werden. Die Datei bleibt erhalten." }
        }
        previousExternalApp = NSWorkspace.shared.frontmostApplication
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self?.previousExternalApp = app
            }
        }
        shortcut.action = { [weak self] in self?.toggle() }
        if !shortcut.register(shortcutChoice) { error = shortcutChoice.registrationError }
        recorder.onLimit = { [weak self] in self?.finishRecording() }
        recorder.onFailure = { [weak self] message in self?.recordingFailed(message) }
    }

    var ready: Bool { models.available(preset) }
    var busy: Bool { phase != .idle }
    var canRetry: Bool { audioURL != nil && phase == .idle }
    var engineURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(preset.engineFilename)")
    }

    func refreshPermissions() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let permitted = TextInsertion.permitted
        if permitted != accessibilityGranted, shortcutChoice == .doubleCommand,
           !shortcut.register(shortcutChoice) { error = shortcutChoice.registrationError }
        accessibilityGranted = permitted
    }

    func requestMicrophone() {
        Task {
            microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
            if !microphoneGranted {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
        }
    }

    func toggle() {
        if phase == .recording { finishRecording(); return }
        guard phase == .idle else { return }
        guard ready else { error = "Lade zuerst das Sprachmodell in den Einstellungen herunter."; showWindow?(); return }
        guard FileManager.default.isExecutableFile(atPath: engineURL.path) else {
            error = FlowError.missingEngine.localizedDescription; showWindow?(); return
        }
        discardAudio()
        error = nil
        let id = UUID()
        recordingID = id
        let active = NSWorkspace.shared.frontmostApplication
        target = TextInsertion.capture(active?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? previousExternalApp : active)
        phase = .permission
        onStateChange?()
        operation = Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled, recordingID == id else { return }
            microphoneGranted = allowed
            guard allowed else {
                phase = .idle
                error = "Erlaube den Mikrofonzugriff in den Systemeinstellungen, um zu diktieren."
                onStateChange?(); showWindow?(); return
            }
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("diktier-app-\(id)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                let url = directory.appendingPathComponent("recording.wav")
                audioURL = url
                try recorder.start(at: url, deviceUID: microphoneUID)
                phase = .recording
                message = "Ich höre zu …"
                onRecordingStart?()
                onStateChange?()
                let engine = engineURL
                let model = models.modelURL(preset)
                preparation = Task {
                    guard recordingID == id, phase == .recording else { return }
                    try? await transcriber.prepare(engine: engine, model: model)
                }
            } catch { recordingFailed(error.localizedDescription) }
        }
    }

    private func recordingFailed(_ description: String) {
        guard phase == .recording || phase == .permission else { return }
        cancel()
        error = description
        message = "Die Aufnahme konnte nicht fortgesetzt werden."
        Logger(subsystem: "de.local.whisperflow", category: "recording").error("Recording failed: \(description, privacy: .public)")
        onStateChange?()
        showWindow?()
    }

    func finishRecording() {
        guard phase == .recording else { return }
        do { try recorder.finish(); processAudio() }
        catch {
            phase = .idle
            self.error = error.localizedDescription
            discardAudio()
            onStateChange?()
            showWindow?()
        }
    }

    func retry() { guard canRetry else { return }; processAudio() }

    private func processAudio() {
        guard let audioURL else { return }
        let id = UUID()
        recordingID = id
        phase = .processing
        message = "Deine Worte werden zu Text …"
        error = nil
        let engine = engineURL
        let model = models.modelURL(preset)
        let selectedLanguage = language
        let commands = spokenCommands
        let words = vocabulary
        onStateChange?()
        operation = Task {
            do {
                let result = try await transcriber.transcribe(audio: audioURL, engine: engine, model: model,
                    language: selectedLanguage, spokenCommands: commands, vocabulary: words)
                guard !Task.isCancelled, recordingID == id else { return }
                lastTranscript = result
                discardAudio()
                if autoPaste {
                    phase = .inserting
                    onStateChange?()
                    let submitted = await TextInsertion.paste(result.text, into: target)
                    guard !Task.isCancelled, recordingID == id else { return }
                    message = submitted ? "Einfügen ausgelöst. Dein Text liegt auch im Verlauf." : "Text fertig. Kopiere ihn hier oder aus dem Verlauf."
                    if !submitted { showWindow?() }
                } else { message = "Text fertig. Du kannst ihn jetzt kopieren."; showWindow?() }
                if keepHistory {
                    history = Array(([result] + history).prefix(50))
                    do { try historyStore.save(history) } catch { self.error = error.localizedDescription }
                }
                phase = .idle
                onStateChange?()
            } catch is CancellationError {
                if recordingID == id { phase = .idle; onStateChange?() }
            } catch {
                guard recordingID == id else { return }
                phase = .idle
                self.error = error.localizedDescription
                message = "Die Aufnahme bleibt für einen erneuten Versuch erhalten."
                onStateChange?()
                showWindow?()
            }
        }
    }

    func cancel() {
        recordingID = nil
        operation?.cancel()
        operation = nil
        preparation?.cancel()
        preparation = nil
        Task { await transcriber.shutdown() }
        recorder.stop()
        discardAudio()
        phase = .idle
        message = "Diktat abgebrochen."
        onStateChange?()
    }

    func discardAudio() {
        if let audioURL { try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent()) }
        audioURL = nil
    }

    func clearHistory() {
        do { try historyStore.clear(); history = [] }
        catch { self.error = error.localizedDescription }
    }

    func shutdown() {
        cancel()
        models.cancel()
        audioDevices.stopWatching()
        shortcut.unregister()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
    }
}
