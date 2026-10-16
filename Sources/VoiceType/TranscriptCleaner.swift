import Foundation

/// Removes whisper hallucinations: subtitle credits learned from YouTube/TV training data,
/// which the model appends after silences, and courtesy-only outputs on near-empty audio.
enum TranscriptCleaner {
    /// Removed wherever they appear. None of these is ever a genuine dictation.
    private static let creditPatterns = [
        #"Sous-titrage (?:Société )?Radio-Canada\.?"#,
        #"Sous-titrage ST'? ?\d+\.?"#,
        #"Sous-titres? (?:réalisés?|faits?) par la communauté d'Amara\.org"#,
        #"Sous-titres? (?:réalisés?|faits?) (?:para?|by) [^.]*(?:\.|$)"#,
        #"(?:par la communauté d')?Amara\.org"#,
        #"\[(?:BLANK_AUDIO|Musique|Music|Applaudissements|Rires)\]"#,
        #"\((?:crickets chirping|musique|music)\)"#,
        #"\*(?:Musique|Music)\*"#,
        #"Merci d'avoir regardé(?: cette vidéo)?\s*[.!]?\s*$"#,
        #"Thanks? (?:you )?for watching[.!]?\s*$"#,
    ]

    /// Outputs made only of these words are discarded (whisper's reflex on silence).
    private static let courtesyWords: Set<String> = ["thank", "thanks", "you", "for", "watching"]

    static func clean(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        for pattern in creditPatterns {
            text = text.replacingOccurrences(
                of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let words = text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        if words.isEmpty || words.allSatisfy(courtesyWords.contains) { return "" }
        return text
    }
}
