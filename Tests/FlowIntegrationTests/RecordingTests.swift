import AVFoundation
import FlowCore
import XCTest
@testable import DiktierApp

final class RecordingTests: XCTestCase {
    @MainActor
    func testUnavailableMicrophoneIsRejectedBeforeCaptureStarts() {
        let recorder = Recorder()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("unavailable-\(UUID()).wav")
        XCTAssertThrowsError(try recorder.start(at: output, deviceUID: "nonexistent-flow-input-\(UUID())")) {
            XCTAssertEqual($0 as? FlowError, .audioDevice("Das gewählte Mikrofon ist nicht verbunden. Wähle es erneut in den Einstellungen."))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(recorder.elapsed, 0)
    }

    func testNativeStereoCaptureConvertsToValidTranscriptionAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("flow-record-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                  channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        for channel in 0..<2 {
            for index in 0..<48_000 { buffer.floatChannelData![channel][index] = 0.2 * sin(Float(index) * 0.1) }
        }
        let native = root.appendingPathComponent("native.caf")
        let sink = try RecordingSink(url: native, format: format)
        sink.append(buffer)
        XCTAssertNil(sink.snapshot().failure)
        XCTAssertGreaterThan(sink.snapshot().level, 0.5)
        sink.close()
        sink.append(buffer)
        let output = root.appendingPathComponent("output.wav")
        try AudioPreparation.convert(native, to: output)
        XCTAssertEqual(try AudioPreparation.validate(output), 1, accuracy: 0.01)
    }

    func testSilenceFromCaptureDoesNotBecomeATranscript() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("flow-silent-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                  channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        buffer.floatChannelData![0].initialize(repeating: 0, count: 16_000)
        let native = root.appendingPathComponent("silent.caf")
        let sink = try RecordingSink(url: native, format: format)
        sink.append(buffer)
        XCTAssertEqual(sink.snapshot().level, 0)
        sink.close()
        let output = root.appendingPathComponent("silent.wav")
        try AudioPreparation.convert(native, to: output)
        XCTAssertThrowsError(try AudioPreparation.validate(output)) { XCTAssertEqual($0 as? FlowError, .noSpeech) }
    }
}
