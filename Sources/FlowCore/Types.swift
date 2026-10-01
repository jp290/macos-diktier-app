import Foundation

public enum FlowError: LocalizedError, Equatable {
    case missingEngine, missingModel, invalidAudio, tooShort, tooLong, noSpeech, busy, timeout
    case engineFailed(Int32), invalidDownload, storage(String), audioDevice(String)

    public var errorDescription: String? {
        switch self {
        case .missingEngine: return "Die lokale Whisper-Engine fehlt. Bitte die App neu bauen oder installieren."
        case .missingModel: return "Lade zuerst ein Sprachmodell in den Einstellungen herunter."
        case .invalidAudio: return "Die Audiodatei ist ungültig. Erwartet wird WAV mit 16 kHz, mono und 16 Bit."
        case .tooShort: return "Die Aufnahme war zu kurz. Sprich mindestens eine halbe Sekunde."
        case .tooLong: return "Ein Diktat darf höchstens zwei Minuten dauern."
        case .noSpeech: return "Keine Sprache erkannt. Prüfe dein Mikrofon und versuche es erneut."
        case .busy: return "Ein Diktat wird bereits verarbeitet."
        case .timeout: return "Die Transkription hat zu lange gedauert. Versuche ein kürzeres Diktat."
        case .engineFailed(let code): return "Die Whisper-Engine wurde mit Fehler \(code) beendet."
        case .invalidDownload: return "Das Sprachmodell ist unvollständig oder beschädigt. Bitte erneut herunterladen."
        case .storage(let message): return "Der lokale Verlauf konnte nicht gespeichert werden: \(message)"
        case .audioDevice(let message): return message
        }
    }
}

public enum SpeechLanguage: String, Codable, CaseIterable, Identifiable {
    case german = "de", automatic = "auto", english = "en"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .german: return "Deutsch"
        case .automatic: return "Automatisch erkennen"
        case .english: return "Englisch"
        }
    }
}

public enum ModelPreset: String, CaseIterable, Identifiable {
    case qwen, turbo, small
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .qwen: return "Qwen3-ASR 1.7B · Hohe Qualität"
        case .turbo: return "Whisper Large v3 Turbo"
        case .small: return "Whisper Small · Wenig Speicher"
        }
    }
    public var filename: String {
        switch self {
        case .qwen: return "Qwen3-ASR-1.7B-8bit"
        case .turbo: return "ggml-large-v3-turbo-q5_0.bin"
        case .small: return "ggml-small-q5_1.bin"
        }
    }
    public var bytes: Int64 {
        switch self {
        case .qwen: return files.reduce(0) { $0 + $1.bytes }
        case .turbo: return 574_041_195
        case .small: return 190_085_487
        }
    }
    public var sha256: String {
        switch self {
        case .qwen: return "bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c"
        case .turbo: return "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
        case .small: return "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"
        }
    }
    public var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }
    public var engineFilename: String { self == .qwen ? "flow-qwen" : "whisper-cli" }
    public var downloadLabel: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
    }
}

public struct Transcript: Codable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let text: String
    public let audioSeconds: Double
    public let processingSeconds: Double

    public init(text: String, audioSeconds: Double, processingSeconds: Double, date: Date = Date()) {
        id = UUID()
        self.date = date
        self.text = text
        self.audioSeconds = audioSeconds
        self.processingSeconds = processingSeconds
    }
    public var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace }).count }
}
