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

    /// Spelling slips of the Parakeet engine, fixed after the credits are removed.
    private static let spellingFixes = [
        (#"\b([Ii]l) ya\b"#, "$1 y a"),
        (#"(?i)\bmvp\b"#, "MVP"),
    ]

    /// Outputs made only of these words are discarded (whisper's reflex on silence).
    private static let courtesyWords: Set<String> = ["thank", "thanks", "you", "for", "watching"]

    static func clean(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        for pattern in creditPatterns {
            text = text.replacingOccurrences(
                of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        for (pattern, replacement) in spellingFixes {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let words = text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        if words.isEmpty || words.allSatisfy(courtesyWords.contains) { return "" }
        return typography(text)
    }

    /// Parakeet skips two conventions whisper follows: capital after a sentence end,
    /// and the French space before ? and !. Idempotent on already correct text.
    private static func typography(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: #"(?<=[^\s?!])([?!])"#, with: " $1", options: .regularExpression)
        var capitalizeNext = true
        result = String(result.map { char -> Character in
            defer {
                if ".?!".contains(char) { capitalizeNext = true }
                else if !char.isWhitespace { capitalizeNext = false }
            }
            return capitalizeNext && char.isLetter ? Character(char.uppercased()) : char
        })
        return result
    }
}
