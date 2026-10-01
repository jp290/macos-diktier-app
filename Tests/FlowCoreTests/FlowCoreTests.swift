import AVFoundation
import FlowCore
import XCTest

final class FlowCoreTests: XCTestCase {
    func testFormatterPreservesWordsAndPunctuation() {
        XCTAssertEqual(TextFormatter.format("  Hallo,\t Welt!  "), "Hallo, Welt!")
        XCTAssertEqual(TextFormatter.format("Ich sage äh und ähm."), "Ich sage äh und ähm.")
        XCTAssertEqual(TextFormatter.format("Das steht [wirklich] hier."), "Das steht [wirklich] hier.")
    }

    func testSpokenParagraphAndLineBreaks() {
        XCTAssertEqual(TextFormatter.format("Hallo. Neuer Absatz. Welt."), "Hallo.\n\nWelt.")
        XCTAssertEqual(TextFormatter.format("Eins, neue Zeile, zwei."), "Eins\nzwei.")
        XCTAssertEqual(TextFormatter.format("Hallo. Neuer Absatz. Welt.", spokenCommands: false),
                       "Hallo. Neuer Absatz. Welt.")
        XCTAssertEqual(TextFormatter.format("Ein neuer Absatzmarkt."), "Ein neuer Absatzmarkt.")
    }

    func testSilenceMarkersAndEmptyTextAreRejected() {
        for input in ["", " \n ", "[BLANK_AUDIO]", "[Musik]", "(Musik)"] {
            XCTAssertEqual(TextFormatter.format(input), "")
        }
    }

    func testHistoryPersistsFiftyNewestEntriesWithPrivatePermissions() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(url: directory.appendingPathComponent("history.json"))
        XCTAssertEqual(try store.load(), [])
        let entries = (0..<55).map { Transcript(text: "Diktat \($0)", audioSeconds: 2, processingSeconds: 1) }
        try store.save(entries)
        XCTAssertEqual(try store.load(), Array(entries.prefix(50)))
        let permissions = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        try store.clear()
        XCTAssertEqual(try store.load(), [])
    }

    func testCorruptHistoryFailsInsteadOfDiscardingData() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = HistoryStore(url: directory.appendingPathComponent("history.json"))
        try Data("broken".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
    }

    func testAudioConversionProducesMonoSixteenKhzPCM() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.wav")
        try writeAudio(to: source, sampleRate: 48_000, seconds: 1, amplitude: 0.2)
        let target = directory.appendingPathComponent("target.wav")
        try AudioPreparation.convert(source, to: target)
        XCTAssertEqual(try AudioPreparation.validate(target), 1, accuracy: 0.01)
    }

    func testAudioRejectsSilenceShortAndIncorrectFormat() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, rate, seconds, amplitude, error) in [
            ("silent", 16_000.0, 1.0, 0.0, FlowError.noSpeech),
            ("short", 16_000.0, 0.1, 0.2, .tooShort),
            ("wrong-rate", 48_000.0, 1.0, 0.2, .invalidAudio),
            ("long", 16_000.0, 121.0, 0.2, .tooLong)
        ] {
            let url = directory.appendingPathComponent("\(name).wav")
            try writeAudio(to: url, sampleRate: rate, seconds: seconds, amplitude: amplitude)
            XCTAssertThrowsError(try AudioPreparation.validate(url)) { XCTAssertEqual($0 as? FlowError, error) }
        }
        XCTAssertThrowsError(try AudioPreparation.validate(directory.appendingPathComponent("missing.wav")))
    }

    func testMissingEngineAndModelFailClearly() async {
        let transcriber = Transcriber()
        let missing = URL(fileURLWithPath: "/nonexistent-flow-test")
        do {
            _ = try await transcriber.transcribe(audio: missing, engine: missing, model: missing, language: .german)
            XCTFail("Expected missing engine")
        } catch { XCTAssertEqual(error as? FlowError, .missingEngine) }
        do {
            _ = try await transcriber.transcribe(audio: missing, engine: URL(fileURLWithPath: "/usr/bin/true"),
                                                model: missing, language: .german)
            XCTFail("Expected missing model")
        } catch { XCTAssertEqual(error as? FlowError, .missingModel) }
    }

    func testModelIntegrityRejectsCorruptionAndTruncation() throws {
        let url = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = ModelFile(name: "model", bytes: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            url: URL(string: "https://example.com/model")!)
        try Data("abc".utf8).write(to: url)
        XCTAssertNoThrow(try ModelFile.verify(url, expected: file))
        try Data("abd".utf8).write(to: url)
        XCTAssertThrowsError(try ModelFile.verify(url, expected: file)) { XCTAssertEqual($0 as? FlowError, .invalidDownload) }
        try Data("ab".utf8).write(to: url)
        XCTAssertThrowsError(try ModelFile.verify(url, expected: file)) { XCTAssertEqual($0 as? FlowError, .invalidDownload) }
    }

    func testModelCatalogHasQualityDefaultAndVerifiedDownloads() {
        XCTAssertEqual(ModelPreset.qwen.files.count, 9)
        XCTAssertEqual(ModelPreset.qwen.bytes, 2_467_856_503)
        XCTAssertEqual(ModelPreset.turbo.bytes, 574_041_195)
        for preset in ModelPreset.allCases {
            for file in preset.files {
                XCTAssertEqual(file.sha256.count, 64)
                XCTAssertEqual(file.url.scheme, "https")
                XCTAssertGreaterThan(file.bytes, 0)
            }
        }
    }

    func testEngineFailureAndTimeoutKeepSourceAudio() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audio = directory.appendingPathComponent("audio.wav")
        try writeAudio(to: audio, sampleRate: 16_000, seconds: 1, amplitude: 0.2)
        let model = directory.appendingPathComponent("model")
        try Data("external model boundary".utf8).write(to: model)
        let engine = directory.appendingPathComponent("engine")
        try "#!/bin/sh\nexit 7\n".write(to: engine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.path)
        let transcriber = Transcriber()
        do {
            _ = try await transcriber.transcribe(audio: audio, engine: engine, model: model, language: .automatic)
            XCTFail("Expected engine failure")
        } catch { XCTAssertEqual(error as? FlowError, .engineFailed(7)) }
        try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: engine, atomically: true, encoding: .utf8)
        do {
            _ = try await transcriber.transcribe(audio: audio, engine: engine, model: model,
                                                language: .automatic, timeout: 0.1)
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? FlowError, .timeout) }
        XCTAssertEqual(try AudioPreparation.validate(audio), 1, accuracy: 0.01)
    }

    func testConcurrentTranscriptionIsRejectedAndCancellationReleasesEngine() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audio = directory.appendingPathComponent("audio.wav")
        try writeAudio(to: audio, sampleRate: 16_000, seconds: 1, amplitude: 0.2)
        let model = directory.appendingPathComponent("model")
        try Data("model".utf8).write(to: model)
        let engine = directory.appendingPathComponent("engine")
        try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: engine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.path)
        let transcriber = Transcriber()
        let first = Task { try await transcriber.transcribe(audio: audio, engine: engine, model: model, language: .automatic) }
        try await Task.sleep(nanoseconds: 100_000_000)
        do {
            _ = try await transcriber.transcribe(audio: audio, engine: engine, model: model, language: .automatic)
            XCTFail("Expected busy")
        } catch { XCTAssertEqual(error as? FlowError, .busy) }
        first.cancel()
        do { _ = try await first.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError, "Expected cancellation, received \(error)") }
        try "#!/bin/sh\nexit 8\n".write(to: engine, atomically: true, encoding: .utf8)
        do {
            _ = try await transcriber.transcribe(audio: audio, engine: engine, model: model, language: .automatic)
            XCTFail("Expected failure after released engine")
        } catch { XCTAssertEqual(error as? FlowError, .engineFailed(8)) }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("flow-test-\(UUID())")
    }

    private func writeAudio(to url: URL, sampleRate: Double, seconds: Double, amplitude: Double) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1,
                                   interleaved: false)!
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            buffer.floatChannelData![0][index] = Float(amplitude * sin(2 * .pi * 440 * Double(index) / sampleRate))
        }
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}
