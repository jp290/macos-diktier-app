import AudioToolbox
import AVFoundation
import FlowCore
import XCTest
@testable import DiktierApp

final class HardwareRecordingTests: XCTestCase {
    @MainActor
    func testSelected48kMicrophoneReplacesStale16kAnd44kFormatsBeforeStarting() throws {
        for oldRate in [16_000.0, 44_100.0] {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let device = TestMicrophone(previousRate: oldRate)
            let recorder = Recorder(makeHardware: { device }, resolveDevice: { uid in
                XCTAssertEqual(uid, "usb-microphone")
                return 42
            })
            defer { recorder.stop() }
            let output = root.appendingPathComponent("recording.wav")

            try recorder.start(at: output, deviceUID: "usb-microphone")

            XCTAssertEqual(device.events, ["select:42", "hardware-format", "client:48000", "initialize", "start"])
            XCTAssertEqual(device.clientFormat?.sampleRate, 48_000)
            XCTAssertEqual(device.clientFormat?.channelCount, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            try device.emit(frames: 48_000)
            try recorder.finish()

            let file = try AVAudioFile(forReading: output)
            XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
            XCTAssertEqual(file.fileFormat.channelCount, 1)
            XCTAssertEqual(file.fileFormat.commonFormat, .pcmFormatInt16)
            XCTAssertEqual(try AudioPreparation.validate(output), 1, accuracy: 0.01)
            XCTAssertEqual(device.events.last, "stop")
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("recording.caf").path))
        }
    }

    @MainActor
    func testNative44kStereoMicrophoneKeepsItsHardwareRateAndChannels() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let device = TestMicrophone(rate: 44_100, channels: 2)
        let recorder = Recorder(makeHardware: { device }, resolveDevice: { _ in 73 })
        defer { recorder.stop() }
        let output = root.appendingPathComponent("recording.wav")

        try recorder.start(at: output)
        XCTAssertEqual(device.clientFormat?.sampleRate, 44_100)
        XCTAssertEqual(device.clientFormat?.channelCount, 2)
        try device.emit(frames: 44_100)
        try recorder.finish()

        XCTAssertEqual(try AudioPreparation.validate(output), 1, accuracy: 0.01)
    }

    @MainActor
    func testFailedInitializationNeverStartsHardwareAndRemovesPartialCapture() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let device = TestMicrophone()
        device.failInitialization = true
        let recorder = Recorder(makeHardware: { device }, resolveDevice: { _ in 42 })
        let output = root.appendingPathComponent("recording.wav")

        XCTAssertThrowsError(try recorder.start(at: output)) {
            XCTAssertEqual($0 as? FlowError, .audioDevice("Mikrofon initialisieren fehlgeschlagen (CoreAudio -10877)."))
        }

        XCTAssertEqual(device.events, ["select:42", "hardware-format", "client:48000", "initialize", "stop"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        XCTAssertEqual(recorder.elapsed, 0)
    }

    @MainActor
    func testFailedHardwareStartCleansUpInitializedInput() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let device = TestMicrophone()
        device.failStart = true
        let recorder = Recorder(makeHardware: { device }, resolveDevice: { _ in 42 })

        XCTAssertThrowsError(try recorder.start(at: root.appendingPathComponent("recording.wav"))) {
            XCTAssertEqual($0 as? FlowError, .audioDevice("Aufnahme starten fehlgeschlagen (CoreAudio -50)."))
        }
        XCTAssertEqual(device.events.suffix(3), ["initialize", "start", "stop"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    @MainActor
    func testHardwareFailureIsReportedByMainThreadPolling() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let device = TestMicrophone()
        let recorder = Recorder(makeHardware: { device }, resolveDevice: { _ in 42 })
        defer { recorder.stop() }
        var errors: [String] = []
        recorder.onFailure = { errors.append($0) }
        try recorder.start(at: root.appendingPathComponent("recording.wav"))

        device.failure?("Mikrofon getrennt (CoreAudio -10877).")
        recorder.poll()

        XCTAssertEqual(errors, ["Mikrofon getrennt (CoreAudio -10877)."])
    }

    @MainActor
    func testStoppedInputCannotReportLateHardwareFailures() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let device = TestMicrophone()
        let recorder = Recorder(makeHardware: { device }, resolveDevice: { _ in 42 })
        var errors: [String] = []
        recorder.onFailure = { errors.append($0) }
        try recorder.start(at: root.appendingPathComponent("recording.wav"))
        let lateCallback = device.failure
        recorder.stop()

        lateCallback?("Veralteter Hardwarefehler")
        recorder.poll(at: Date(timeIntervalSinceNow: 10))

        XCTAssertEqual(errors, [])
    }

    @MainActor
    func testInputThatNeverDeliversFramesProducesAnActionableError() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let device = TestMicrophone()
        let recorder = Recorder(makeHardware: { device }, resolveDevice: { _ in 42 })
        defer { recorder.stop() }
        var errors: [String] = []
        recorder.onFailure = { errors.append($0) }
        try recorder.start(at: root.appendingPathComponent("recording.wav"))

        recorder.poll(at: Date(timeIntervalSinceNow: 4))

        XCTAssertEqual(errors, ["Das Mikrofon liefert keine Audiodaten. Prüfe das Eingabegerät und starte das Diktat erneut."])
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hardware-capture-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private final class TestMicrophone: MicrophoneHardware {
    private let rate: Double
    private let channels: AVAudioChannelCount
    private var selected = false
    var clientFormat: AVAudioFormat?
    var events: [String] = []
    var failInitialization = false
    var failStart = false
    var receive: ((AVAudioPCMBuffer) -> Void)?
    var failure: ((String) -> Void)?

    init(rate: Double = 48_000, channels: AVAudioChannelCount = 1, previousRate: Double = 16_000) {
        self.rate = rate
        self.channels = channels
        clientFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: previousRate,
            channels: channels, interleaved: false)
    }

    func selectDevice(_ id: AudioDeviceID) throws { events.append("select:\(id)"); selected = true }

    func inputFormat() throws -> AVAudioFormat {
        events.append("hardware-format")
        guard selected else { throw FlowError.audioDevice("Gerät wurde vor dem Format nicht ausgewählt.") }
        return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)!
    }

    func setClientFormat(_ format: AVAudioFormat) throws {
        events.append("client:\(Int(format.sampleRate))")
        clientFormat = format
    }

    func initialize(receive: @escaping (AVAudioPCMBuffer) -> Void, failure: @escaping (String) -> Void) throws {
        events.append("initialize")
        if failInitialization { throw FlowError.audioDevice("Mikrofon initialisieren fehlgeschlagen (CoreAudio -10877).") }
        guard clientFormat?.sampleRate == rate, clientFormat?.channelCount == channels else {
            throw FlowError.audioDevice("Hardware- und Aufnahmeformat stimmen nicht überein.")
        }
        self.receive = receive
        self.failure = failure
    }

    func start() throws {
        events.append("start")
        if failStart { throw FlowError.audioDevice("Aufnahme starten fehlgeschlagen (CoreAudio -50).") }
    }

    func stop() { events.append("stop"); receive = nil; failure = nil }

    func emit(frames: AVAudioFrameCount) throws {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: try XCTUnwrap(clientFormat), frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for index in 0..<Int(frames) { buffer.floatChannelData![channel][index] = 0.2 * sin(Float(index) * 0.1) }
        }
        receive?(buffer)
    }
}
