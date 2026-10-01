import Foundation
import Darwin

public actor Transcriber {
    private var process: Process?
    private let qwen = QwenWorker()
    private var busy = false
    private var idleTask: Task<Void, Never>?
    private let idleSeconds: Double
    public init(idleSeconds: Double = 120) { self.idleSeconds = max(0.1, idleSeconds) }

    public func prepare(engine: URL, model: URL) throws {
        try Task.checkCancellation()
        guard !busy, engine.lastPathComponent == "flow-qwen" else { return }
        guard FileManager.default.isExecutableFile(atPath: engine.path) else { throw FlowError.missingEngine }
        guard FileManager.default.fileExists(atPath: model.path) else { throw FlowError.missingModel }
        idleTask?.cancel()
        try qwen.start(engine: engine, model: model)
        scheduleRelease()
    }

    public func shutdown() {
        idleTask?.cancel()
        qwen.stop()
        if let process, process.isRunning { process.terminate() }
    }

    private func scheduleRelease() {
        guard qwen.running else { return }
        idleTask?.cancel()
        idleTask = Task { [weak self, idleSeconds] in
            do { try await Task.sleep(nanoseconds: UInt64(idleSeconds * 1_000_000_000)) }
            catch { return }
            await self?.releaseIdleModel()
        }
    }

    private func releaseIdleModel() { if !busy { qwen.stop() } }

    public func transcribe(audio: URL, engine: URL, model: URL, language: SpeechLanguage,
                           spokenCommands: Bool = true, vocabulary: String = "",
                           timeout: Double = 180) async throws -> Transcript {
        guard !busy else { throw FlowError.busy }
        guard FileManager.default.isExecutableFile(atPath: engine.path) else { throw FlowError.missingEngine }
        guard FileManager.default.fileExists(atPath: model.path) else { throw FlowError.missingModel }
        let seconds = try AudioPreparation.validate(audio)
        busy = true
        idleTask?.cancel()
        defer { busy = false; scheduleRelease() }
        if engine.lastPathComponent == "flow-qwen" {
            let started = Date()
            let raw = try await qwen.transcribe(audio: audio, engine: engine, model: model,
                                               language: language, vocabulary: vocabulary, timeout: timeout)
            let text = TextFormatter.format(raw, spokenCommands: spokenCommands)
            guard !text.isEmpty else { throw FlowError.noSpeech }
            return Transcript(text: text, audioSeconds: seconds, processingSeconds: Date().timeIntervalSince(started))
        }
        qwen.stop()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("diktier-app-transcribe-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("result")
        let log = directory.appendingPathComponent("engine.log")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let worker = Process()
        worker.executableURL = engine
        worker.environment = ProcessInfo.processInfo.environment.filter {
            ["HOME", "TMPDIR", "PATH", "LANG", "LC_ALL"].contains($0.key)
        }
        worker.arguments = ["-m", model.path, "-f", audio.path, "-l", language.rawValue,
            "-t", "4", "-bo", "1", "-bs", "1", "-otxt", "-of", output.path, "-np", "-sns"]
        if !vocabulary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            worker.arguments?.append(contentsOf: ["--prompt", String(vocabulary.prefix(500))])
        }
        worker.standardOutput = handle
        worker.standardError = handle
        worker.standardInput = FileHandle.nullDevice
        process = worker
        defer { process = nil }
        let started = Date()
        try Task.checkCancellation()
        try worker.run()
        do {
            while worker.isRunning {
                try Task.checkCancellation()
                if Date().timeIntervalSince(started) >= timeout { throw FlowError.timeout }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        } catch {
            if worker.isRunning {
                worker.terminate()
                try? await Task.sleep(nanoseconds: 150_000_000)
                if worker.isRunning { kill(worker.processIdentifier, SIGKILL) }
                worker.waitUntilExit()
            }
            throw error
        }
        try Task.checkCancellation()
        guard worker.terminationStatus == 0 else { throw FlowError.engineFailed(worker.terminationStatus) }
        guard let raw = try? String(contentsOf: output.appendingPathExtension("txt"), encoding: .utf8) else {
            throw FlowError.engineFailed(-1)
        }
        let text = TextFormatter.format(raw, spokenCommands: spokenCommands)
        guard !text.isEmpty else { throw FlowError.noSpeech }
        return Transcript(text: text, audioSeconds: seconds, processingSeconds: Date().timeIntervalSince(started))
    }
}
