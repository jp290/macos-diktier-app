import AudioToolbox
import AVFoundation
import Combine
import FlowCore
import Foundation
import OSLog

final class RecordingSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var level: Double = 0
    private var failure: String?
    private var frames: UInt64 = 0

    init(url: URL, format: AVAudioFormat) throws {
        file = try AVAudioFile(forWriting: url, settings: format.settings)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let file, failure == nil else { return }
        do { try file.write(from: buffer) }
        catch { failure = error.localizedDescription; return }
        frames += UInt64(buffer.frameLength)
        if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var energy: Double = 0
            for index in 0..<Int(buffer.frameLength) { energy += Double(samples[index] * samples[index]) }
            let decibels = 20 * log10(max(0.00001, sqrt(energy / Double(buffer.frameLength))))
            level = max(0, min(1, (decibels + 55) / 55))
        }
    }

    func snapshot() -> (level: Double, failure: String?, frames: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (level, failure, frames)
    }

    func fail(_ message: String) {
        lock.lock()
        if failure == nil { failure = message }
        lock.unlock()
    }

    func close() {
        lock.lock()
        file = nil
        lock.unlock()
    }
}

@MainActor
final class Recorder: ObservableObject {
    @Published var level: Double = 0
    @Published var elapsed: Double = 0
    private var hardware: MicrophoneHardware?
    private var sink: RecordingSink?
    private var timer: Timer?
    private var started: Date?
    private var nativeURL: URL?
    private var outputURL: URL?
    private var lastFrameAt: Date?
    private var lastFrameCount: UInt64 = 0
    private let makeHardware: () throws -> MicrophoneHardware
    private let resolveDevice: @MainActor (String) throws -> AudioDeviceID
    private let logger = Logger(subsystem: "de.local.whisperflow", category: "recording")
    var onLimit: (() -> Void)?
    var onFailure: ((String) -> Void)?

    init(makeHardware: @escaping () throws -> MicrophoneHardware = { try HALMicrophone() },
         resolveDevice: @escaping @MainActor (String) throws -> AudioDeviceID = { try AudioDevices.resolveInput($0) }) {
        self.makeHardware = makeHardware
        self.resolveDevice = resolveDevice
    }

    func start(at url: URL, deviceUID: String = "") throws {
        stop()
        let device = try resolveDevice(deviceUID)
        let hardware = try makeHardware()
        let native = url.deletingPathExtension().appendingPathExtension("caf")
        do {
            try hardware.selectDevice(device)
            let format = try hardware.inputFormat()
            guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
                throw FlowError.audioDevice("Das Mikrofon liefert kein nutzbares Audioformat.")
            }
            try hardware.setClientFormat(format)
            let sink = try RecordingSink(url: native, format: format)
            self.sink = sink
            try hardware.initialize(receive: { sink.append($0) }, failure: { sink.fail($0) })
            try hardware.start()
            self.hardware = hardware
            logger.info("Microphone started: device=\(device), rate=\(format.sampleRate), channels=\(format.channelCount)")
        } catch {
            hardware.stop()
            sink?.close()
            sink = nil
            try? FileManager.default.removeItem(at: native)
            logger.error("Microphone start failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        nativeURL = native
        outputURL = url
        started = Date()
        lastFrameAt = started
        lastFrameCount = 0
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func poll(at now: Date = Date()) {
        guard let sink, let started else { return }
        let state = sink.snapshot()
        if let failure = state.failure { onFailure?(failure); return }
        if state.frames != lastFrameCount { lastFrameCount = state.frames; lastFrameAt = now }
        if let lastFrameAt, now.timeIntervalSince(lastFrameAt) >= 3 {
            onFailure?("Das Mikrofon liefert keine Audiodaten. Prüfe das Eingabegerät und starte das Diktat erneut.")
            return
        }
        level = state.level
        elapsed = now.timeIntervalSince(started)
        if elapsed >= AudioPreparation.maxSeconds { onLimit?() }
    }

    func finish() throws {
        guard let nativeURL, let outputURL else { throw FlowError.invalidAudio }
        stop()
        try AudioPreparation.convert(nativeURL, to: outputURL)
        try? FileManager.default.removeItem(at: nativeURL)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hardware?.stop()
        hardware = nil
        sink?.close()
        sink = nil
        started = nil
        nativeURL = nil
        outputURL = nil
        lastFrameAt = nil
        lastFrameCount = 0
        level = 0
    }
}
