import FlowCore
import Foundation

@main
struct FlowCheck {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data("Usage: FlowCheck AUDIO ENGINE MODEL [de|en|auto]\n".utf8))
            exit(2)
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("flow-check-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let transcriber = Transcriber()
        do {
            try AudioPreparation.convert(URL(fileURLWithPath: args[0]), to: temporary)
            let count = args.count > 4 ? Int(args[4]) ?? 1 : 1
            guard (1...5).contains(count) else { throw FlowError.invalidAudio }
            for _ in 0..<count {
                let transcript = try await transcriber.transcribe(audio: temporary,
                    engine: URL(fileURLWithPath: args[1]), model: URL(fileURLWithPath: args[2]),
                    language: args.count > 3 ? SpeechLanguage(rawValue: args[3]) ?? .automatic : .automatic)
                print(transcript.text)
                FileHandle.standardError.write(Data(String(format: "audio=%.2fs processing=%.2fs words=%d\n",
                    transcript.audioSeconds, transcript.processingSeconds, transcript.wordCount).utf8))
            }
            await transcriber.shutdown()
        } catch {
            await transcriber.shutdown()
            FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
