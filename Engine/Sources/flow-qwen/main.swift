import Foundation
import MLXAudioCore
import MLXAudioSTT
import MLX

@main
struct QwenEngine {
    private struct Request: Decodable {
        let audio: String
        let output: String
        let completion: String
        let language: String
        let vocabulary: String
    }

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let workerMode = args.count == 3 && args[0] == "--worker"
        guard args.count == 5 || workerMode else {
            FileHandle.standardError.write(Data("Usage: flow-qwen AUDIO MODEL_DIR OUTPUT LANGUAGE VOCABULARY\n".utf8))
            exit(2)
        }
        do {
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            let resources = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
            if FileManager.default.fileExists(atPath: resources.appendingPathComponent("default.metallib").path) {
                guard FileManager.default.changeCurrentDirectoryPath(resources.path) else {
                    throw NSError(domain: "FlowResources", code: 1)
                }
            }
            Memory.cacheLimit = 128 * 1_024 * 1_024
            let started = Date()
            let model = try await Qwen3ASRModel.fromModelDirectory(URL(fileURLWithPath: args[1]))
            let loaded = Date()
            if workerMode {
                try "ready".write(to: URL(fileURLWithPath: args[2]), atomically: true, encoding: .utf8)
                while let line = readLine() {
                    let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
                    do {
                        let result = try transcribe(model, audio: request.audio, output: request.output,
                                                    language: request.language, vocabulary: request.vocabulary)
                        let reply = try JSONSerialization.data(withJSONObject: ["success": true,
                            "inferenceSeconds": result.totalTime, "peakMLXGB": result.peakMemoryUsage])
                        try reply.write(to: URL(fileURLWithPath: request.completion), options: .atomic)
                    } catch {
                        try Data("{\"success\":false}".utf8).write(to: URL(fileURLWithPath: request.completion), options: .atomic)
                    }
                    Memory.clearCache()
                }
                return
            }
            let result = try transcribe(model, audio: args[0], output: args[2], language: args[3], vocabulary: args[4])
            FileHandle.standardError.write(Data(String(format: "engine=qwen load=%.2fs inference=%.2fs peak_mlx=%.2fGB\n",
                loaded.timeIntervalSince(started), result.totalTime, result.peakMemoryUsage).utf8))
        } catch {
            FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func transcribe(_ model: Qwen3ASRModel, audio: String, output: String,
                                   language: String, vocabulary: String) throws -> STTOutput {
        let (rate, samples) = try loadAudioArray(from: URL(fileURLWithPath: audio))
        guard rate == 16_000, ["auto", "de", "en"].contains(language) else {
            throw NSError(domain: "FlowAudio", code: 1)
        }
        let selected: String? = language == "auto" ? nil : (language == "de" ? "German" : "English")
        let result = model.generate(audio: samples, maxTokens: 2_048, temperature: 0,
            context: String(vocabulary.prefix(500)), language: selected, chunkDuration: 30)
        try result.text.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
        return result
    }
}
