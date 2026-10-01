import Darwin
import Foundation

final class QwenWorker {
    private var process: Process?
    private var input: Pipe?
    private var directory: URL?
    private var engine: URL?
    private var model: URL?

    var running: Bool { process?.isRunning == true }

    deinit { stop() }

    func start(engine: URL, model: URL) throws {
        if running, self.engine == engine, self.model == model { return }
        stop()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("flow-qwen-worker-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let worker = Process()
        let pipe = Pipe()
        worker.executableURL = engine
        worker.arguments = ["--worker", model.path, root.appendingPathComponent("ready").path]
        worker.environment = ProcessInfo.processInfo.environment.filter {
            ["HOME", "TMPDIR", "PATH", "LANG", "LC_ALL"].contains($0.key)
        }
        worker.standardInput = pipe
        worker.standardOutput = FileHandle.nullDevice
        worker.standardError = FileHandle.nullDevice
        do { try worker.run() }
        catch { try? FileManager.default.removeItem(at: root); throw error }
        process = worker
        input = pipe
        directory = root
        self.engine = engine
        self.model = model
    }

    func transcribe(audio: URL, engine: URL, model: URL, language: SpeechLanguage,
                    vocabulary: String, timeout: Double) async throws -> String {
        try start(engine: engine, model: model)
        guard let worker = process, let input, let directory else { throw FlowError.engineFailed(-1) }
        let started = Date()
        let output = directory.appendingPathComponent("\(UUID()).txt")
        let completion = output.appendingPathExtension("complete")
        defer {
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: completion)
        }
        do {
            try await wait(for: directory.appendingPathComponent("ready"), worker: worker,
                           started: started, timeout: timeout)
            let request = Request(audio: audio.path, output: output.path, completion: completion.path,
                                  language: language.rawValue, vocabulary: String(vocabulary.prefix(500)))
            var data = try JSONEncoder().encode(request)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
            try await wait(for: completion, worker: worker, started: started, timeout: timeout)
            let replyData = try Data(contentsOf: completion)
            guard replyData.count <= 16_384,
                  let reply = try? JSONDecoder().decode(Reply.self, from: replyData), reply.success,
                  let text = try? String(contentsOf: output, encoding: .utf8) else {
                throw FlowError.engineFailed(-1)
            }
            return text
        } catch { stop(); throw error }
    }

    private func wait(for file: URL, worker: Process, started: Date, timeout: Double) async throws {
        while true {
            try Task.checkCancellation()
            if Date().timeIntervalSince(started) >= timeout { throw FlowError.timeout }
            if FileManager.default.fileExists(atPath: file.path) { return }
            guard worker.isRunning else { throw FlowError.engineFailed(worker.terminationStatus) }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    func stop() {
        try? input?.fileHandleForWriting.close()
        if let process, process.isRunning {
            process.terminate()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process = nil
        input = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        engine = nil
        model = nil
    }

    private struct Request: Encodable {
        let audio: String
        let output: String
        let completion: String
        let language: String
        let vocabulary: String
    }

    private struct Reply: Decodable { let success: Bool }
}
