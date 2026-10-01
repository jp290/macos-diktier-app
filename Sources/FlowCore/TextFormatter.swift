import Foundation

public enum TextFormatter {
    public static func format(_ raw: String, spokenCommands: Bool = true) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let silenceMarkers = ["[BLANK_AUDIO]", "[SILENCE]", "[Music]", "[Musik]", "(Musik)"]
        if silenceMarkers.contains(where: { text.caseInsensitiveCompare($0) == .orderedSame }) {
            return ""
        }
        text = text.replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
        text = text.replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
        if spokenCommands {
            for (pattern, replacement) in [
                (#"[ ,]*\b(?:neuer Absatz|new paragraph)\b[ ,.;:!?]*"#, "\n\n"),
                (#"[ ,]*\b(?:neue Zeile|new line)\b[ ,.;:!?]*"#, "\n")
            ] {
                text = text.replacingOccurrences(of: pattern, with: replacement,
                                                options: [.regularExpression, .caseInsensitive])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
