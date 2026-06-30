import Testing
@testable import BasnCore

struct WordErrorRateTests {

    @Test
    func identicalStringsScoreZero() {
        let wer = WordErrorRate.compute(
            reference: "log time for two hours",
            hypothesis: "log time for two hours"
        )
        #expect(wer == 0.0)
    }

    @Test
    func caseAndPunctuationAreNormalized() {
        let wer = WordErrorRate.compute(
            reference: "Log time for two hours.",
            hypothesis: "log time for two hours"
        )
        #expect(wer == 0.0)
    }

    @Test
    func oneSubstitutionInFiveWords() {
        // "hours" -> "minutes": one substitution out of five reference words.
        let wer = WordErrorRate.compute(
            reference: "log time for two hours",
            hypothesis: "log time for two minutes"
        )
        #expect(abs(wer - 0.2) < 0.0001)
    }

    @Test
    func deletionCounts() {
        // Drop one word out of five.
        let wer = WordErrorRate.compute(
            reference: "log time for two hours",
            hypothesis: "log time for hours"
        )
        #expect(abs(wer - 0.2) < 0.0001)
    }

    @Test
    func insertionCounts() {
        // Add one word; reference has five words.
        let wer = WordErrorRate.compute(
            reference: "log time for two hours",
            hypothesis: "please log time for two hours"
        )
        #expect(abs(wer - 0.2) < 0.0001)
    }

    @Test
    func bothEmptyIsZero() {
        #expect(WordErrorRate.compute(reference: "", hypothesis: "") == 0.0)
    }

    @Test
    func emptyReferenceNonEmptyHypothesisIsOne() {
        #expect(WordErrorRate.compute(reference: "", hypothesis: "unexpected words") == 1.0)
    }

    @Test
    func completelyWrongScoresOne() {
        let wer = WordErrorRate.compute(
            reference: "alpha beta gamma",
            hypothesis: "delta epsilon zeta"
        )
        #expect(wer == 1.0)
    }

    @Test
    func tokenizeStripsPunctuation() {
        #expect(WordErrorRate.tokenize("Hello, world!") == ["hello", "world"])
    }
}
