import Foundation

public enum SessionComplexity {
    case simple     // → Haiku 4.5
    case standard   // → Haiku 4.5
    case complex    // → Sonnet 4.6

    public var modelID: String {
        switch self {
        case .simple, .standard: return "claude-haiku-4-5-20251001"
        case .complex: return "claude-sonnet-4-6"
        }
    }
}

public struct SessionComplexityClassifier {
    public static func classify(wordCount: Int, connectedToolCount: Int, rawText: String) -> SessionComplexity {
        if wordCount < 100, connectedToolCount <= 2 { return .simple }
        if wordCount > 500 { return .complex }
        if connectedToolCount > 4 { return .complex }
        if detectMultiplePeople(in: rawText) { return .complex }
        if detectDateArithmetic(in: rawText) { return .complex }
        return .standard
    }

    // Heuristic: ≥3 capitalized words that don't start a sentence = likely multiple person names.
    private static func detectMultiplePeople(in text: String) -> Bool {
        let words = text.split(separator: " ").map(String.init)
        var count = 0
        for i in 1..<words.count {
            let word = words[i].trimmingCharacters(in: .punctuationCharacters)
            guard !word.isEmpty, word.count > 2 else { continue }
            let prev = words[i - 1]
            let sentenceEnd = prev.hasSuffix(".") || prev.hasSuffix("?") || prev.hasSuffix("!")
            if !sentenceEnd, word.first?.isUppercase == true {
                count += 1
                if count >= 3 { return true }
            }
        }
        return false
    }

    private static func detectDateArithmetic(in text: String) -> Bool {
        let lower = text.lowercased()
        let patterns = [
            "next \\w+day", "next week", "next month",
            "in \\d+ (day|week|month)", "this \\w+day",
            "\\d+ days? (from|after)", "end of (the )?(week|month|quarter)"
        ]
        return patterns.contains { pattern in
            (try? NSRegularExpression(pattern: pattern))
                .map { $0.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil }
                ?? false
        }
    }
}
