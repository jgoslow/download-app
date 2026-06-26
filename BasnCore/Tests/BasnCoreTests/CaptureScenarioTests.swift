import Testing
@testable import BasnCore

/// Fixture-based tests for the full routing pipeline.
///
/// Each test loads a JSON scenario from `Fixtures/Scenarios/`, runs it through
/// the appropriate layer (HeuristicRouter or CastellumResponseParser), and
/// asserts the expected output.
///
/// To add a new scenario:
/// 1. Enable "Record scenarios" in the DebugBar (debug build, bottom of HomeView).
/// 2. Trigger a capture (voice or text input).
/// 3. Collect the JSON from ~/Library/Containers/com.lyra.basn.debug/Data/Documents/
/// 4. For Castellum fixtures: fill in `expected.actions` from `rawContentBlocks`.
///    For heuristic fixtures: `expected.actions` is pre-populated automatically.
/// 5. Rename the file and move it to `BasnCore/Tests/BasnCoreTests/Fixtures/Scenarios/`.
/// 6. Add a `@Test` function here following the pattern below.
struct CaptureScenarioTests {

    // MARK: - Heuristic path

    @Test
    func togglSimpleTimer() throws {
        let scenario = try CaptureScenario.load(named: "toggl-simple-timer")
        #expect(scenario.routedVia == .heuristic)
        let actions = HeuristicRouter.route(
            transcript: scenario.rawText,
            connectedToolIDs: Set(scenario.connectedToolIDs)
        )
        guard let actions else {
            Issue.record("HeuristicRouter returned nil — expected a match")
            return
        }
        assertActions(actions, match: scenario.expected.actions)
    }

    @Test
    func togglStartTimer() throws {
        let scenario = try CaptureScenario.load(named: "toggl-start-timer")
        #expect(scenario.routedVia == .heuristic)
        let actions = HeuristicRouter.route(
            transcript: scenario.rawText,
            connectedToolIDs: Set(scenario.connectedToolIDs)
        )
        guard let actions else {
            Issue.record("HeuristicRouter returned nil — expected a match")
            return
        }
        assertActions(actions, match: scenario.expected.actions)
    }

    // MARK: - Castellum path

    @Test
    func jiraOnlyTicket() throws {
        let scenario = try CaptureScenario.load(named: "jira-only-ticket")
        #expect(scenario.routedVia == .castellum)
        let (analysis, actions) = CastellumResponseParser.parse(
            scenario.toContentBlocks(), captureID: "test"
        )
        #expect(!analysis.summary.isEmpty)
        assertActions(actions, match: scenario.expected.actions)
    }

    @Test
    func jiraSlackStandup() throws {
        let scenario = try CaptureScenario.load(named: "jira-slack-standup")
        #expect(scenario.routedVia == .castellum)
        let (analysis, actions) = CastellumResponseParser.parse(
            scenario.toContentBlocks(), captureID: "test"
        )
        #expect(!analysis.summary.isEmpty)
        assertActions(actions, match: scenario.expected.actions)
    }

    @Test
    func togglJiraMultiIntent() throws {
        let scenario = try CaptureScenario.load(named: "toggl-jira-multi-intent")
        #expect(scenario.routedVia == .castellum)
        // Verify HeuristicRouter correctly falls through for multi-intent
        let heuristic = HeuristicRouter.route(
            transcript: scenario.rawText,
            connectedToolIDs: Set(scenario.connectedToolIDs)
        )
        #expect(heuristic == nil, "Multi-intent should not match HeuristicRouter")
        let (analysis, actions) = CastellumResponseParser.parse(
            scenario.toContentBlocks(), captureID: "test"
        )
        #expect(!analysis.summary.isEmpty)
        assertActions(actions, match: scenario.expected.actions)
    }

    @Test
    func noActionsJournal() throws {
        let scenario = try CaptureScenario.load(named: "no-actions-journal")
        #expect(scenario.routedVia == .castellum)
        let (analysis, actions) = CastellumResponseParser.parse(
            scenario.toContentBlocks(), captureID: "test"
        )
        #expect(!analysis.summary.isEmpty)
        #expect(actions.isEmpty, "Journal entry should produce no tool actions")
    }

    @Test
    func googleCalendarEvent() throws {
        let scenario = try CaptureScenario.load(named: "google-calendar-event")
        #expect(scenario.routedVia == .castellum)
        let (analysis, actions) = CastellumResponseParser.parse(
            scenario.toContentBlocks(), captureID: "test"
        )
        #expect(!analysis.summary.isEmpty)
        assertActions(actions, match: scenario.expected.actions)
    }

    // MARK: - Pending (not yet connected)

    // @Test
    // func waveExpense() throws {
    //     let scenario = try CaptureScenario.load(named: "wave-expense")
    //     let (analysis, actions) = CastellumResponseParser.parse(
    //         scenario.toContentBlocks(), captureID: "test"
    //     )
    //     #expect(!analysis.summary.isEmpty)
    //     assertActions(actions, match: scenario.expected.actions)
    // }
}
