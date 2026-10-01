import AVFoundation
import FlowCore
import XCTest

final class WarmTranscriberTests: XCTestCase {
    func testConsecutiveDictationsReuseModelAndPreserveRequestText() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let transcriber = Transcriber()
        try await transcriber.prepare(engine: fixture.engine, model: fixture.model)
        let first = try await transcriber.transcribe(audio: fixture.audio, engine: fixture.engine,
            model: fixture.model, language: .automatic, vocabulary: "Deutsch, English")
        let second = try await transcriber.transcribe(audio: fixture.audio, engine: fixture.engine,
            model: fixture.model, language: .english, vocabulary: "second request")
        XCTAssertEqual(first.text, "auto: Deutsch, English")
        XCTAssertEqual(second.text, "en: second request")
        XCTAssertEqual(try String(contentsOf: fixture.root.appendingPathComponent("launches")), "start\n")
        await transcriber.shutdown()
    }

    func testIdleModelIsReleasedAndNextDictationStartsFreshWorker() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let transcriber = Transcriber(idleSeconds: 0.1)
        _ = try await transcriber.transcribe(audio: fixture.audio, engine: fixture.engine,
            model: fixture.model, language: .automatic)
        try await Task.sleep(nanoseconds: 300_000_000)
        _ = try await transcriber.transcribe(audio: fixture.audio, engine: fixture.engine,
            model: fixture.model, language: .automatic)
        XCTAssertEqual(try String(contentsOf: fixture.root.appendingPathComponent("launches")), "start\nstart\n")
        await transcriber.shutdown()
    }

    func testCancelledWarmJobKeepsAudioAndCanStartAgain() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let transcriber = Transcriber()
        let operation = Task {
            try await transcriber.transcribe(audio: fixture.audio, engine: fixture.engine,
                model: fixture.model, language: .automatic, vocabulary: "hang")
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        operation.cancel()
        do { _ = try await operation.value; XCTFail("Cancelled job must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try AudioPreparation.validate(fixture.audio), 1, accuracy: 0.01)
        let next = try await transcriber.transcribe(audio: fixture.audio, engine: fixture.engine,
            model: fixture.model, language: .german, vocabulary: "recovered")
        XCTAssertEqual(next.text, "de: recovered")
        await transcriber.shutdown()
    }

    func testWorkerFailureDoesNotInsertOrReturnPartialText() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let transcriber = Transcriber()
        do {
            _ = try await transcriber.transcribe(audio: fixture.audio, engine: fixture.engine,
                model: fixture.model, language: .automatic, vocabulary: "fail")
            XCTFail("Failed worker must not return a transcript")
        } catch { XCTAssertEqual(error as? FlowError, .engineFailed(-1)) }
        await transcriber.shutdown()
    }

    private func makeFixture() throws -> (root: URL, audio: URL, engine: URL, model: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("warm-flow-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = root.appendingPathComponent("model")
        try Data("model".utf8).write(to: model)
        let audio = root.appendingPathComponent("audio.wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                  channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for index in 0..<16_000 { buffer.floatChannelData![0][index] = 0.2 * sin(Float(index) * 0.17) }
        let file = try AVAudioFile(forWriting: audio, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
        let engine = root.appendingPathComponent("flow-qwen")
        try """
        #!/usr/bin/python3
        import json, pathlib, sys, time
        root = pathlib.Path(__file__).parent
        with (root / 'launches').open('a') as log:
            log.write('start\\n')
        assert sys.argv[1] == '--worker'
        pathlib.Path(sys.argv[3]).write_text('ready')
        for line in sys.stdin:
            request = json.loads(line)
            if request['vocabulary'] == 'hang':
                time.sleep(30)
            success = request['vocabulary'] != 'fail'
            pathlib.Path(request['output']).write_text(request['language'] + ': ' + request['vocabulary'])
            pathlib.Path(request['completion']).write_text(json.dumps({'success': success}))
        """.write(to: engine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.path)
        return (root, audio, engine, model)
    }
}
