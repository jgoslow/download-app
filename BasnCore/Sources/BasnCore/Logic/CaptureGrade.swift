import Foundation

/// A grade for an archived capture's value as a *test recording*.
///
/// Split into auto-computed fields (written at archive time, free) and human
/// feedback (filled in via the debug review step). A composite `testValue`
/// ranks captures for promotion into the audio corpus, and lets us track an
/// aggregate grade trend over time as tangible evidence the app is improving.
public struct CaptureGrade: Codable, Sendable, Equatable {

    // MARK: - Auto-computed

    /// Number of actions the pipeline produced for this capture.
    public var actionCount: Int
    /// "heuristic" or "castellum".
    public var routedVia: String
    /// Castellum returned an error or an empty plan when one was expected.
    public var castellumErrored: Bool
    public var durationSeconds: Double
    public var wordCount: Int
    /// Objective audio metrics, when samples were available.
    public var audio: AudioQualityMetrics?
    /// Best-effort transcription confidence in `[0, 1]`. Optional — populated
    /// only if the transcriber surfaces it.
    public var transcriptionConfidence: Double?

    // MARK: - Human feedback (nil until graded)

    public var outcomeAccuracy: Accuracy?
    /// Should this capture be promoted into the audio test corpus?
    public var keepAsFixture: Bool?
    public var notes: String?

    // MARK: - Derived / metadata

    /// Composite 0–100 test-value score. Recompute via `recomputeTestValue()`.
    public var testValue: Int
    /// App version that produced the capture — used to group trend reports.
    public var appVersion: String
    /// When human feedback was last applied. Nil if only auto-graded.
    public var gradedAt: Date?

    public enum Accuracy: String, Codable, Sendable, CaseIterable {
        case correct
        case partial
        case incorrect
        case errored
    }

    public init(
        actionCount: Int,
        routedVia: String,
        castellumErrored: Bool,
        durationSeconds: Double,
        wordCount: Int,
        appVersion: String,
        audio: AudioQualityMetrics? = nil,
        transcriptionConfidence: Double? = nil,
        outcomeAccuracy: Accuracy? = nil,
        keepAsFixture: Bool? = nil,
        notes: String? = nil,
        gradedAt: Date? = nil
    ) {
        self.actionCount = actionCount
        self.routedVia = routedVia
        self.castellumErrored = castellumErrored
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.appVersion = appVersion
        self.audio = audio
        self.transcriptionConfidence = transcriptionConfidence
        self.outcomeAccuracy = outcomeAccuracy
        self.keepAsFixture = keepAsFixture
        self.notes = notes
        self.gradedAt = gradedAt
        self.testValue = 0
        self.testValue = Self.computeTestValue(
            actionCount: actionCount,
            routedVia: routedVia,
            castellumErrored: castellumErrored,
            wordCount: wordCount,
            audio: audio,
            outcomeAccuracy: outcomeAccuracy,
            keepAsFixture: keepAsFixture
        )
    }

    /// Recompute `testValue` after mutating any contributing field.
    public mutating func recomputeTestValue() {
        testValue = Self.computeTestValue(
            actionCount: actionCount,
            routedVia: routedVia,
            castellumErrored: castellumErrored,
            wordCount: wordCount,
            audio: audio,
            outcomeAccuracy: outcomeAccuracy,
            keepAsFixture: keepAsFixture
        )
    }

    /// Weighted 0–100 blend favouring captures that make *useful tests*:
    /// they produce actions, exercise the richer Castellum path, contain real
    /// speech, and (once reviewed) routed correctly. Audio noise is NOT a
    /// penalty — the corpus needs noisy samples for robustness coverage — so it
    /// only contributes a small "is there real audio" signal.
    static func computeTestValue(
        actionCount: Int,
        routedVia: String,
        castellumErrored: Bool,
        wordCount: Int,
        audio: AudioQualityMetrics?,
        outcomeAccuracy: Accuracy?,
        keepAsFixture: Bool?
    ) -> Int {
        if castellumErrored { return 0 }

        var score = 0.0

        // Action yield (up to 25): more actions = more to assert. Saturates at 3.
        score += min(Double(actionCount), 3.0) / 3.0 * 25.0

        // Path coverage (15): Castellum exercises more of the pipeline.
        if routedVia == "castellum" { score += 15.0 }

        // Real content (15): needs enough words to be a meaningful utterance.
        score += min(Double(wordCount), 12.0) / 12.0 * 15.0

        // Has usable audio (15): some signal present (not silence).
        if let audio, audio.rms > 0.002 { score += 15.0 }

        // Human outcome (up to 30): the strongest signal once reviewed.
        switch outcomeAccuracy {
        case .correct:   score += 30.0
        case .partial:   score += 15.0
        case .incorrect: score += 0.0
        case .errored:   return 0
        case nil:        break  // not yet reviewed
        }

        // Explicit keep flag (bonus, capped at 100).
        if keepAsFixture == true { score += 10.0 }

        return Int(min(100.0, max(0.0, score.rounded())))
    }
}
