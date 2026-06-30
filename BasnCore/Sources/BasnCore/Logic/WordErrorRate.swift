import Foundation

/// Word-error-rate scoring for the end-to-end audio test layer.
///
/// WhisperKit / Parakeet output varies across model versions, hardware, and
/// ambient conditions, so audio tests assert a *fuzzy* WER threshold rather than
/// an exact string match (see `docs/reference/integration-testing-plan.md`).
public enum WordErrorRate {

    /// Word-error-rate of `hypothesis` against `reference`, in `[0, 1+]`.
    ///
    /// WER = (substitutions + insertions + deletions) / reference word count,
    /// computed as Levenshtein edit distance over normalized word tokens.
    /// Returns 0 when both are empty, and 1 when only the reference is empty but
    /// the hypothesis is not (every hypothesis word is an insertion).
    public static func compute(reference: String, hypothesis: String) -> Double {
        let ref = tokenize(reference)
        let hyp = tokenize(hypothesis)

        if ref.isEmpty { return hyp.isEmpty ? 0.0 : 1.0 }

        let distance = editDistance(ref, hyp)
        return Double(distance) / Double(ref.count)
    }

    /// Lowercase, strip punctuation, collapse whitespace, split on spaces.
    static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let stripped = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                return Character(scalar)
            }
            return " "
        }
        return String(stripped)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// Standard Levenshtein distance over token arrays (two-row DP).
    private static func editDistance(_ a: [String], _ b: [String]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,        // deletion
                    current[j - 1] + 1,     // insertion
                    previous[j - 1] + cost  // substitution / match
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
