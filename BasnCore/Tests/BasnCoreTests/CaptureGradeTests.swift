import Testing
import Foundation
@testable import BasnCore

struct CaptureGradeTests {

    private func audio(rms: Float) -> AudioQualityMetrics {
        AudioQualityMetrics(rms: rms, peak: rms * 2, estimatedSNR: 20, clippingRatio: 0, noiseScore: 0.3)
    }

    @Test
    func erroredCaptureScoresZero() {
        let grade = CaptureGrade(
            actionCount: 2,
            routedVia: "castellum",
            castellumErrored: true,
            durationSeconds: 5,
            wordCount: 20,
            appVersion: "1.0",
            audio: audio(rms: 0.1)
        )
        #expect(grade.testValue == 0)
    }

    @Test
    func richCorrectCaptureScoresHigherThanSparseUnreviewed() {
        let rich = CaptureGrade(
            actionCount: 3,
            routedVia: "castellum",
            castellumErrored: false,
            durationSeconds: 8,
            wordCount: 20,
            appVersion: "1.0",
            audio: audio(rms: 0.1),
            outcomeAccuracy: .correct,
            keepAsFixture: true
        )
        let sparse = CaptureGrade(
            actionCount: 0,
            routedVia: "heuristic",
            castellumErrored: false,
            durationSeconds: 1,
            wordCount: 2,
            appVersion: "1.0",
            audio: audio(rms: 0.1)
        )
        #expect(rich.testValue > sparse.testValue)
        #expect(rich.testValue >= 90)
    }

    @Test
    func recomputeReflectsHumanFeedback() {
        var grade = CaptureGrade(
            actionCount: 1,
            routedVia: "heuristic",
            castellumErrored: false,
            durationSeconds: 4,
            wordCount: 10,
            appVersion: "1.0",
            audio: audio(rms: 0.1)
        )
        let before = grade.testValue
        grade.outcomeAccuracy = .correct
        grade.keepAsFixture = true
        grade.recomputeTestValue()
        #expect(grade.testValue > before)
    }

    @Test
    func incorrectOutcomeAddsNothing() {
        let correct = CaptureGrade(
            actionCount: 1, routedVia: "heuristic", castellumErrored: false,
            durationSeconds: 4, wordCount: 10, appVersion: "1.0",
            audio: audio(rms: 0.1), outcomeAccuracy: .correct
        )
        let incorrect = CaptureGrade(
            actionCount: 1, routedVia: "heuristic", castellumErrored: false,
            durationSeconds: 4, wordCount: 10, appVersion: "1.0",
            audio: audio(rms: 0.1), outcomeAccuracy: .incorrect
        )
        #expect(correct.testValue > incorrect.testValue)
    }

    @Test
    func roundTripsThroughJSON() throws {
        let grade = CaptureGrade(
            actionCount: 2, routedVia: "castellum", castellumErrored: false,
            durationSeconds: 6, wordCount: 15, appVersion: "1.2.3",
            audio: audio(rms: 0.05), outcomeAccuracy: .partial,
            keepAsFixture: false, notes: "café noise"
        )
        let data = try JSONEncoder().encode(grade)
        let decoded = try JSONDecoder().decode(CaptureGrade.self, from: data)
        #expect(decoded == grade)
    }
}
