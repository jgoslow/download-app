import Testing
@testable import BasnCore

struct ModelPatternMatcherTests {

    // MARK: - matches(_:_:)

    @Test
    func exactMatchReturnsTrue() {
        #expect(ModelPatternMatcher.matches("openai-whisper-large-v3", "openai-whisper-large-v3"))
    }

    @Test
    func exactNonMatchReturnsFalse() {
        #expect(!ModelPatternMatcher.matches("openai-whisper-large-v3", "openai-whisper-large-v2"))
    }

    @Test
    func wildcardMatchesConcreteVariant() {
        #expect(ModelPatternMatcher.matches("distil*large-v3", "distil-whisper-large-v3"))
    }

    @Test
    func wildcardMatchesMultipleSegments() {
        #expect(ModelPatternMatcher.matches("*large*", "openai-whisper-large-v3"))
    }

    @Test
    func wildcardDoesNotMatchUnrelatedString() {
        #expect(!ModelPatternMatcher.matches("distil*large-v3", "openai-whisper-large-v3"))
    }

    @Test
    func questionMarkMatchesSingleCharacter() {
        #expect(ModelPatternMatcher.matches("whisper-large-v?", "whisper-large-v3"))
    }

    // MARK: - resolvePattern(_:from:)

    @Test
    func exactPatternReturnsAsIs() {
        let result = ModelPatternMatcher.resolvePattern(
            "whisper-large-v3",
            from: [("whisper-large-v3", false)]
        )
        #expect(result == "whisper-large-v3")
    }

    @Test
    func noMatchReturnsNil() {
        let result = ModelPatternMatcher.resolvePattern(
            "distil*large-v3",
            from: [("openai-whisper-base", false), ("openai-whisper-medium", true)]
        )
        #expect(result == nil)
    }

    @Test
    func singleMatchNotDownloadedReturnsIt() {
        let result = ModelPatternMatcher.resolvePattern(
            "distil*large-v3",
            from: [("distil-whisper-large-v3", false)]
        )
        #expect(result == "distil-whisper-large-v3")
    }

    @Test
    func prefersDownloadedOverNotDownloaded() {
        let models: [(name: String, isDownloaded: Bool)] = [
            ("distil-whisper-large-v3", false),
            ("distil-whisper-large-v3-turbo", true)
        ]
        // Both match; turbo is downloaded — but non-turbo preference should lose to downloaded
        let result = ModelPatternMatcher.resolvePattern("distil*large-v3*", from: models)
        #expect(result != nil)
        // The downloaded one is returned (turbo or not — downloaded wins over non-downloaded)
        #expect(result == "distil-whisper-large-v3-turbo")
    }

    @Test
    func prefersNonTurboWhenBothDownloaded() {
        let models: [(name: String, isDownloaded: Bool)] = [
            ("distil-whisper-large-v3", true),
            ("distil-whisper-large-v3-turbo", true)
        ]
        let result = ModelPatternMatcher.resolvePattern("distil*large-v3*", from: models)
        #expect(result == "distil-whisper-large-v3")
    }

    @Test
    func prefersNonTurboWhenNoneDownloaded() {
        let models: [(name: String, isDownloaded: Bool)] = [
            ("distil-whisper-large-v3-turbo", false),
            ("distil-whisper-large-v3", false)
        ]
        let result = ModelPatternMatcher.resolvePattern("distil*large-v3*", from: models)
        #expect(result == "distil-whisper-large-v3")
    }

    @Test
    func emptyModelListReturnsNilForWildcard() {
        let result = ModelPatternMatcher.resolvePattern("distil*large-v3", from: [])
        #expect(result == nil)
    }
}
