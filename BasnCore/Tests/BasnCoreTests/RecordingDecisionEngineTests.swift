import Testing
import Foundation
import Sauce
@testable import BasnCore

struct RecordingDecisionEngineTests {

    // MARK: - Helpers

    private func context(
        key: Key?,
        minimumKeyTime: TimeInterval,
        elapsed: TimeInterval
    ) -> RecordingDecisionEngine.Context {
        // Use reference date (Jan 1 2001) as base to avoid precision loss
        // that occurs when converting small TimeIntervals near Unix epoch.
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let now = Date(timeIntervalSinceReferenceDate: elapsed)
        return RecordingDecisionEngine.Context(
            hotkey: HotKey(key: key, modifiers: [.option]),
            minimumKeyTime: minimumKeyTime,
            recordingStartTime: start,
            currentTime: now
        )
    }

    // MARK: - Modifier-only hotkeys (key == nil)

    @Test
    func modifierOnlyBelowFloorDiscards() {
        // 0.1s elapsed, floor is 0.3s
        let result = RecordingDecisionEngine.decide(context(key: nil, minimumKeyTime: 0.2, elapsed: 0.1))
        #expect(result == .discardShortRecording)
    }

    @Test
    func modifierOnlyAtExactFloorProceeds() {
        // elapsed == modifierOnlyMinimumDuration (0.3s)
        let floor = RecordingDecisionEngine.modifierOnlyMinimumDuration
        let result = RecordingDecisionEngine.decide(context(key: nil, minimumKeyTime: 0.2, elapsed: floor))
        #expect(result == .proceedToTranscription)
    }

    @Test
    func modifierOnlyAboveFloorProceeds() {
        let result = RecordingDecisionEngine.decide(context(key: nil, minimumKeyTime: 0.2, elapsed: 0.5))
        #expect(result == .proceedToTranscription)
    }

    @Test
    func modifierOnlyUsersMinimumKeyTimeHigherThanFloor() {
        // User set minimumKeyTime = 0.5s; elapsed = 0.4s → below user preference
        let result = RecordingDecisionEngine.decide(context(key: nil, minimumKeyTime: 0.5, elapsed: 0.4))
        #expect(result == .discardShortRecording)
    }

    @Test
    func modifierOnlyMeetsUserMinimumKeyTimeAboveFloor() {
        // User set minimumKeyTime = 0.5s; elapsed = 0.6s → meets both floor and preference
        let result = RecordingDecisionEngine.decide(context(key: nil, minimumKeyTime: 0.5, elapsed: 0.6))
        #expect(result == .proceedToTranscription)
    }

    @Test
    func modifierOnlyNoRecordingStartTimeDiscards() {
        let ctx = RecordingDecisionEngine.Context(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            minimumKeyTime: 0.2,
            recordingStartTime: nil,   // elapsed → 0
            currentTime: Date(timeIntervalSinceReferenceDate: 1.0)
        )
        #expect(RecordingDecisionEngine.decide(ctx) == .discardShortRecording)
    }

    // MARK: - Key+modifier hotkeys (key != nil, always proceeds)

    @Test
    func keyModifierAtZeroDurationAlwaysProceeds() {
        let ctx = RecordingDecisionEngine.Context(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            minimumKeyTime: 0.2,
            recordingStartTime: Date(timeIntervalSince1970: 0),
            currentTime: Date(timeIntervalSince1970: 0)  // elapsed == 0
        )
        #expect(RecordingDecisionEngine.decide(ctx) == .proceedToTranscription)
    }

    @Test
    func keyModifierVeryShortRecordingProceeds() {
        let ctx = RecordingDecisionEngine.Context(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            minimumKeyTime: 0.2,
            recordingStartTime: Date(timeIntervalSince1970: 0),
            currentTime: Date(timeIntervalSince1970: 0.05)
        )
        #expect(RecordingDecisionEngine.decide(ctx) == .proceedToTranscription)
    }

    @Test
    func keyModifierNoRecordingStartTimeProceeds() {
        let ctx = RecordingDecisionEngine.Context(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            minimumKeyTime: 0.2,
            recordingStartTime: nil,   // elapsed → 0, but key present → proceed
            currentTime: Date(timeIntervalSinceReferenceDate: 1.0)
        )
        #expect(RecordingDecisionEngine.decide(ctx) == .proceedToTranscription)
    }
}
