import Foundation
import Testing
@testable import BasnCore

struct StructuredCaptureTests {

    // MARK: - from(session:)

    @Test
    func fromSessionSplitsOnSentenceBoundaries() throws {
        let session = makeSession(rawText: "First idea. Second idea. Third idea.")
        let capture = StructuredCapture.from(session: session)
        #expect(capture.entries.count == 3)
        #expect(capture.entries[0].sentence == "First idea")
        #expect(capture.entries[1].sentence == "Second idea")
        #expect(capture.entries[2].sentence == "Third idea")
    }

    @Test
    func fromSessionSingleSentenceProducesOneEntry() {
        let session = makeSession(rawText: "Just one thought here")
        let capture = StructuredCapture.from(session: session)
        #expect(capture.entries.count == 1)
        #expect(capture.entries[0].sentence == "Just one thought here")
    }

    @Test
    func fromSessionEmptyTextProducesOneEntryWithEmptyString() {
        let session = makeSession(rawText: "")
        let capture = StructuredCapture.from(session: session)
        #expect(capture.entries.count == 1)
    }

    @Test
    func fromSessionPreservesMetadata() {
        let session = makeSession(rawText: "some text")
        let capture = StructuredCapture.from(session: session)
        #expect(capture.captureID == session.id)
        #expect(capture.flowID == session.flowID)
        #expect(capture.durationSeconds == session.durationSeconds)
    }

    @Test
    func fromSessionUnpromptedEntriesHaveNilPromptFields() {
        let session = makeSession(rawText: "Note to self. Follow up tomorrow.")
        let capture = StructuredCapture.from(session: session)
        for entry in capture.entries {
            #expect(entry.promptIndex == nil)
            #expect(entry.promptTitle == nil)
            #expect(entry.chips.isEmpty)
        }
    }

    // MARK: - rawText

    @Test
    func rawTextJoinsAllSentencesWithSpace() {
        let capture = makeCapture(entries: [
            CaptureEntry(sentence: "First"),
            CaptureEntry(sentence: "Second"),
            CaptureEntry(sentence: "Third")
        ])
        #expect(capture.rawText == "First Second Third")
    }

    @Test
    func rawTextEmptyWhenNoEntries() {
        let capture = makeCapture(entries: [])
        #expect(capture.rawText == "")
    }

    // MARK: - wordCount

    @Test
    func wordCountSumsAcrossEntries() {
        let capture = makeCapture(entries: [
            CaptureEntry(sentence: "one two three"),   // 3
            CaptureEntry(sentence: "four five")        // 2
        ])
        #expect(capture.wordCount == 5)
    }

    @Test
    func wordCountZeroForEmptyEntries() {
        let capture = makeCapture(entries: [CaptureEntry(sentence: "")])
        #expect(capture.wordCount == 0)
    }

    // MARK: - Structured path (prompt-tagged entries)

    @Test
    func entryWithPromptContextPreservesFields() {
        let entry = CaptureEntry(
            sentence: "I want to ship the new onboarding flow",
            promptIndex: 0,
            promptTitle: "What's your main goal today?",
            chips: ["jira"]
        )
        #expect(entry.promptIndex == 0)
        #expect(entry.promptTitle == "What's your main goal today?")
        #expect(entry.chips == ["jira"])
    }

    @Test
    func entryWithNoPromptHasNilFields() {
        let entry = CaptureEntry(sentence: "Random thought between prompts")
        #expect(entry.promptIndex == nil)
        #expect(entry.promptTitle == nil)
        #expect(entry.chips.isEmpty)
    }

    @Test
    func mixedOrderEntriesPreservePositionalContext() {
        let entries: [CaptureEntry] = [
            CaptureEntry(sentence: "Good morning"),                                // no prompt
            CaptureEntry(sentence: "Ship onboarding", promptIndex: 0, promptTitle: "Goal"),
            CaptureEntry(sentence: "Side thought"),                                // no prompt
            CaptureEntry(sentence: "Review designs", promptIndex: 1, promptTitle: "Priorities")
        ]
        let capture = makeCapture(entries: entries)
        #expect(capture.entries[0].promptIndex == nil)
        #expect(capture.entries[1].promptIndex == 0)
        #expect(capture.entries[2].promptIndex == nil)
        #expect(capture.entries[3].promptIndex == 1)
    }

    // MARK: - Codable roundtrip

    @Test
    func captureEntryRoundtrips() throws {
        let entry = CaptureEntry(
            sentence: "Deploy to staging by end of week",
            promptIndex: 1,
            promptTitle: "Blockers",
            chips: ["jira", "slack"]
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(CaptureEntry.self, from: data)
        #expect(decoded == entry)
    }

    @Test
    func captureEntryWithNilFieldsRoundtrips() throws {
        let entry = CaptureEntry(sentence: "Just a plain sentence")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(CaptureEntry.self, from: data)
        #expect(decoded == entry)
    }

    // MARK: - Helpers

    private func makeSession(rawText: String) -> Session {
        Session(
            id: "test-session-id",
            timestamp: Date(timeIntervalSince1970: 0),
            device: "MacBook",
            flowID: "morning",
            rawText: rawText,
            durationSeconds: 30,
            wordCount: rawText.split(separator: " ").count,
            metadata: Session.Metadata(appVersion: "1.0", whisperModel: "test")
        )
    }

    private func makeCapture(entries: [CaptureEntry]) -> StructuredCapture {
        StructuredCapture(
            captureID: "test-capture",
            flowID: "open",
            timestamp: Date(timeIntervalSince1970: 0),
            durationSeconds: 10,
            entries: entries
        )
    }
}
