import AVFoundation
import Foundation

public enum AudioPreparation {
    public static let maxSeconds: Double = 120

    public static func validate(_ url: URL) throws -> Double {
        guard let file = try? AVAudioFile(forReading: url),
              file.fileFormat.sampleRate == 16_000,
              file.fileFormat.channelCount == 1,
              file.fileFormat.commonFormat == .pcmFormatInt16 else { throw FlowError.invalidAudio }
        let seconds = Double(file.length) / 16_000
        guard seconds >= 0.35 else { throw FlowError.tooShort }
        guard seconds <= maxSeconds + 0.5 else { throw FlowError.tooLong }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8_192) else {
            throw FlowError.invalidAudio
        }
        var energy: Double = 0
        var count = 0
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard let samples = buffer.floatChannelData?[0] else { throw FlowError.invalidAudio }
            for index in 0..<Int(buffer.frameLength) {
                energy += Double(samples[index] * samples[index])
            }
            count += Int(buffer.frameLength)
        }
        guard count > 0, sqrt(energy / Double(count)) > 0.0002 else { throw FlowError.noSpeech }
        return seconds
    }

    public static func convert(_ input: URL, to output: URL) throws {
        let source = try AVAudioFile(forReading: input)
        guard Double(source.length) / source.processingFormat.sampleRate <= maxSeconds + 0.5,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                        channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source.processingFormat, to: format),
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 8_192),
              let targetBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_192)
        else { throw FlowError.invalidAudio }
        let destination = try AVAudioFile(forWriting: output, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        var sourceError: Error?
        while true {
            var conversionError: NSError?
            let status = converter.convert(to: targetBuffer, error: &conversionError) { frames, state in
                do {
                    let remaining = source.length - source.framePosition
                    guard remaining > 0 else { state.pointee = .endOfStream; return nil }
                    try source.read(into: sourceBuffer,
                        frameCount: min(frames, sourceBuffer.frameCapacity, AVAudioFrameCount(remaining)))
                    state.pointee = .haveData
                    return sourceBuffer
                } catch {
                    sourceError = error
                    state.pointee = .endOfStream
                    return nil
                }
            }
            if let sourceError { throw sourceError }
            if let conversionError { throw conversionError }
            if targetBuffer.frameLength > 0 { try destination.write(from: targetBuffer) }
            if status == .endOfStream { break }
            if status == .error { throw FlowError.invalidAudio }
        }
    }
}
