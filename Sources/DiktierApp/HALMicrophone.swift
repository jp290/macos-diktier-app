import AudioToolbox
import AVFoundation
import CoreAudio
import FlowCore

protocol MicrophoneHardware: AnyObject {
    func selectDevice(_ id: AudioDeviceID) throws
    func inputFormat() throws -> AVAudioFormat
    func setClientFormat(_ format: AVAudioFormat) throws
    func initialize(receive: @escaping (AVAudioPCMBuffer) -> Void,
                    failure: @escaping (String) -> Void) throws
    func start() throws
    func stop()
}

final class HALMicrophone: MicrophoneHardware {
    private var unit: AudioUnit?
    private var format: AVAudioFormat?
    private var buffer: AVAudioPCMBuffer?
    private var receive: ((AVAudioPCMBuffer) -> Void)?
    private var failure: ((String) -> Void)?

    init() throws {
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw FlowError.audioDevice("Der Mikrofoneingang ist nicht verfügbar.")
        }
        try check(AudioComponentInstanceNew(component, &unit), operation: "Mikrofoneingang öffnen")
    }

    deinit { stop() }

    func selectDevice(_ id: AudioDeviceID) throws {
        var enabled: UInt32 = 1
        try set(kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Input, bus: 1, value: &enabled)
        enabled = 0
        try set(kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Output, bus: 0, value: &enabled)
        var device = id
        try set(kAudioOutputUnitProperty_CurrentDevice, scope: kAudioUnitScope_Global, bus: 0, value: &device)
        let bound: AudioDeviceID = try get(kAudioOutputUnitProperty_CurrentDevice,
            scope: kAudioUnitScope_Global, bus: 0, initial: 0)
        guard bound == id else { throw FlowError.audioDevice("Das gewählte Mikrofon konnte nicht aktiviert werden.") }
    }

    func inputFormat() throws -> AVAudioFormat {
        let stream: AudioStreamBasicDescription = try get(kAudioUnitProperty_StreamFormat,
            scope: kAudioUnitScope_Input, bus: 1, initial: AudioStreamBasicDescription())
        guard stream.mSampleRate.isFinite, stream.mSampleRate > 0, stream.mChannelsPerFrame > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: stream.mSampleRate,
                  channels: stream.mChannelsPerFrame, interleaved: false) else {
            throw FlowError.audioDevice("Das Mikrofon liefert kein nutzbares Audioformat.")
        }
        return format
    }

    func setClientFormat(_ format: AVAudioFormat) throws {
        var stream = format.streamDescription.pointee
        try set(kAudioUnitProperty_StreamFormat, scope: kAudioUnitScope_Output, bus: 1, value: &stream)
        self.format = format
    }

    func initialize(receive: @escaping (AVAudioPCMBuffer) -> Void,
                    failure: @escaping (String) -> Void) throws {
        guard let unit, let format else { throw FlowError.invalidAudio }
        var capacity: UInt32 = 4_096
        try set(kAudioUnitProperty_MaximumFramesPerSlice, scope: kAudioUnitScope_Global, bus: 0, value: &capacity)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw FlowError.invalidAudio
        }
        self.buffer = buffer
        self.receive = receive
        self.failure = failure
        var callback = AURenderCallbackStruct(inputProc: { context, flags, time, bus, frames, _ in
            return Unmanaged<HALMicrophone>.fromOpaque(context).takeUnretainedValue()
                .render(flags: flags, time: time, bus: bus, frames: frames)
        }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try set(kAudioOutputUnitProperty_SetInputCallback, scope: kAudioUnitScope_Global, bus: 0, value: &callback)
        try check(AudioUnitInitialize(unit), operation: "Mikrofon initialisieren")
        let native = try inputFormat()
        guard native.sampleRate == format.sampleRate, native.channelCount == format.channelCount else {
            throw FlowError.audioDevice("Das Mikrofonformat hat sich beim Start geändert. Starte das Diktat erneut.")
        }
    }

    func start() throws {
        guard let unit else { throw FlowError.invalidAudio }
        try check(AudioOutputUnitStart(unit), operation: "Aufnahme starten")
    }

    func stop() {
        guard let unit else { return }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.unit = nil
        buffer = nil
        receive = nil
        failure = nil
    }

    private func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                        time: UnsafePointer<AudioTimeStamp>, bus: UInt32, frames: UInt32) -> OSStatus {
        guard let unit, let buffer, frames <= buffer.frameCapacity else {
            failure?("Der Mikrofoneingang hat einen ungültigen Audiopuffer geliefert.")
            return kAudio_ParamError
        }
        buffer.frameLength = frames
        let status = AudioUnitRender(unit, flags, time, bus, frames, buffer.mutableAudioBufferList)
        if status == noErr { receive?(buffer) }
        else { failure?("Der Mikrofoneingang wurde unterbrochen (CoreAudio \(status)).") }
        return status
    }

    private func set<Value>(_ property: AudioUnitPropertyID, scope: AudioUnitScope,
                            bus: AudioUnitElement, value: inout Value) throws {
        guard let unit else { throw FlowError.invalidAudio }
        let status = withUnsafePointer(to: &value) {
            AudioUnitSetProperty(unit, property, scope, bus, $0, UInt32(MemoryLayout<Value>.size))
        }
        try check(status, operation: "Mikrofon konfigurieren")
    }

    private func get<Value>(_ property: AudioUnitPropertyID, scope: AudioUnitScope,
                            bus: AudioUnitElement, initial: Value) throws -> Value {
        guard let unit else { throw FlowError.invalidAudio }
        var value = initial
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioUnitGetProperty(unit, property, scope, bus, $0, &size) }
        try check(status, operation: "Mikrofonformat lesen")
        return value
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else { throw FlowError.audioDevice("\(operation) fehlgeschlagen (CoreAudio \(status)).") }
    }
}
