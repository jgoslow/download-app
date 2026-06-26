import Testing
@testable import BasnCore

struct SessionComplexityClassifierTests {

    // MARK: - .simple path

    @Test
    func shortCaptureWithFewTools() {
        let result = SessionComplexityClassifier.classify(wordCount: 50, connectedToolCount: 2, rawText: "start a timer for deep work")
        #expect(result == .simple)
    }

    @Test
    func boundaryBelowSimpleThreshold() {
        let result = SessionComplexityClassifier.classify(wordCount: 99, connectedToolCount: 2, rawText: "quick note to self")
        #expect(result == .simple)
    }

    // MARK: - .standard path

    @Test
    func moderateCaptureReturnsStandard() {
        let result = SessionComplexityClassifier.classify(wordCount: 200, connectedToolCount: 3, rawText: "review the design doc and add a jira ticket")
        #expect(result == .standard)
    }

    // MARK: - .complex: word count

    @Test
    func longCaptureEscalatesToComplex() {
        let words = Array(repeating: "word", count: 501).joined(separator: " ")
        let result = SessionComplexityClassifier.classify(wordCount: 501, connectedToolCount: 2, rawText: words)
        #expect(result == .complex)
    }

    @Test
    func exactlyAtWordCountThreshold() {
        let result = SessionComplexityClassifier.classify(wordCount: 500, connectedToolCount: 2, rawText: "some text")
        #expect(result != .complex)
    }

    // MARK: - .complex: tool count

    @Test
    func manyToolsEscalatesToComplex() {
        let result = SessionComplexityClassifier.classify(wordCount: 100, connectedToolCount: 5, rawText: "create a ticket and send to slack")
        #expect(result == .complex)
    }

    @Test
    func exactlyFourToolsDoesNotEscalate() {
        let result = SessionComplexityClassifier.classify(wordCount: 100, connectedToolCount: 4, rawText: "create a ticket")
        #expect(result != .complex)
    }

    // MARK: - .complex: multiple people

    @Test
    func threePersonNamesEscalatesToComplex() {
        let result = SessionComplexityClassifier.classify(wordCount: 100, connectedToolCount: 2, rawText: "tell Alice and Bob and Carol about the update")
        #expect(result == .complex)
    }

    @Test
    func twoPersonNamesDoesNotEscalate() {
        let result = SessionComplexityClassifier.classify(wordCount: 100, connectedToolCount: 2, rawText: "tell Alice and Bob about the update")
        #expect(result != .complex)
    }

    // MARK: - .complex: date arithmetic

    @Test
    func nextWeekdayEscalatesToComplex() {
        let result = SessionComplexityClassifier.classify(wordCount: 100, connectedToolCount: 2, rawText: "schedule the review for next Tuesday")
        #expect(result == .complex)
    }

    @Test
    func nextWeekEscalatesToComplex() {
        let result = SessionComplexityClassifier.classify(wordCount: 100, connectedToolCount: 2, rawText: "follow up next week on the proposal")
        #expect(result == .complex)
    }

    @Test
    func noDatesDoesNotEscalate() {
        let result = SessionComplexityClassifier.classify(wordCount: 100, connectedToolCount: 2, rawText: "log the sprint progress")
        #expect(result != .complex)
    }

    // MARK: - modelID

    @Test
    func simpleAndStandardBothReturnHaiku() {
        #expect(SessionComplexity.simple.modelID == "claude-haiku-4-5-20251001")
        #expect(SessionComplexity.standard.modelID == "claude-haiku-4-5-20251001")
    }

    @Test
    func complexReturnsSonnet() {
        #expect(SessionComplexity.complex.modelID == "claude-sonnet-4-6")
    }
}
