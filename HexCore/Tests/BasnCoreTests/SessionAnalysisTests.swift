import Testing
import Foundation
@testable import BasnCore

struct SessionAnalysisTests {

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: - Codable roundtrip

    @Test
    func fullRoundtrip() throws {
        let original = SessionAnalysis(
            summary: "Discussed auth bug and planned fix",
            moodTag: "focused",
            tasks: ["Fix auth bug", "Write tests"],
            routing: [.jira, .slack],
            delegations: ["Diego: review the PR"],
            integrations: [.jira, .slack],
            promptsAddressed: [0, 2]
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SessionAnalysis.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Snake_case CodingKeys

    @Test
    func decodesSnakeCaseMoodTag() throws {
        let json = """
        {"summary": "Quick note", "mood_tag": "energized", "tasks": [], "routing": [],
         "delegations": [], "integrations": [], "prompts_addressed": []}
        """
        let result = try decoder.decode(SessionAnalysis.self, from: json.data(using: .utf8)!)
        #expect(result.moodTag == "energized")
    }

    @Test
    func decodesSnakeCasePromptsAddressed() throws {
        let json = """
        {"summary": "s", "tasks": [], "routing": [], "delegations": [],
         "integrations": [], "prompts_addressed": [1, 3]}
        """
        let result = try decoder.decode(SessionAnalysis.self, from: json.data(using: .utf8)!)
        #expect(result.promptsAddressed == [1, 3])
    }

    // MARK: - Optional / missing fields

    @Test
    func absentMoodTagDecodesAsNil() throws {
        let json = """
        {"summary": "s", "tasks": [], "routing": [], "delegations": [],
         "integrations": [], "prompts_addressed": []}
        """
        let result = try decoder.decode(SessionAnalysis.self, from: json.data(using: .utf8)!)
        #expect(result.moodTag == nil)
    }

    @Test
    func missingRequiredArrayFieldThrows() throws {
        // SessionAnalysis requires all array fields — if Claude omits them, decoding
        // fails and CastellumResponseParser falls back to SessionAnalysis(summary: "Capture processed").
        // This test pins that expectation so a future resilience change is deliberate.
        let json = """
        {"summary": "Just a summary"}
        """
        #expect(throws: DecodingError.self) {
            try decoder.decode(SessionAnalysis.self, from: json.data(using: .utf8)!)
        }
    }

    @Test
    func unknownTopLevelKeyIsIgnored() throws {
        let json = """
        {"summary": "s", "tasks": [], "routing": [], "delegations": [],
         "integrations": [], "prompts_addressed": [], "future_field": "ignored"}
        """
        let result = try decoder.decode(SessionAnalysis.self, from: json.data(using: .utf8)!)
        #expect(result.summary == "s")
    }

    // MARK: - Routing destination raw values

    @Test
    func allRoutingDestinationsDecodeFromRawValues() throws {
        let json = """
        {"summary": "s", "routing": ["jira", "calendar", "notes", "slack", "email", "castellum"],
         "tasks": [], "delegations": [], "integrations": [], "prompts_addressed": []}
        """
        let result = try decoder.decode(SessionAnalysis.self, from: json.data(using: .utf8)!)
        #expect(result.routing.count == 6)
        #expect(result.routing.contains(.jira))
        #expect(result.routing.contains(.calendar))
        #expect(result.routing.contains(.notes))
        #expect(result.routing.contains(.slack))
        #expect(result.routing.contains(.email))
        #expect(result.routing.contains(.castellum))
    }

    // MARK: - Integration raw values

    @Test
    func allIntegrationsDecodeFromRawValues() throws {
        let json = """
        {"summary": "s", "tasks": [], "routing": [], "delegations": [], "prompts_addressed": [],
         "integrations": ["jira", "toggl", "slack", "email", "calendar", "docs", "wave", "github"]}
        """
        let result = try decoder.decode(SessionAnalysis.self, from: json.data(using: .utf8)!)
        #expect(result.integrations.count == 8)
        for integration in SessionAnalysis.Integration.allCases {
            #expect(result.integrations.contains(integration))
        }
    }

    // MARK: - ExecutionPlan and PlannedAction Codable

    @Test
    func executionPlanRoundtrip() throws {
        let action = PlannedAction(
            id: "action-1",
            toolID: "jira",
            actionType: "create_issue",
            label: "Create Jira: auth bug",
            parameters: ["summary": "Auth bug fix", "project": "BASN"],
            status: .pending
        )
        let plan = ExecutionPlan(
            id: "plan-1",
            captureID: "capture-1",
            actions: [action],
            createdAt: Date(timeIntervalSince1970: 0),
            modelUsed: "claude-haiku-4-5-20251001"
        )
        let data = try encoder.encode(plan)
        let decoded = try decoder.decode(ExecutionPlan.self, from: data)
        #expect(decoded == plan)
    }

    @Test
    func plannedActionRoundtrip() throws {
        let action = PlannedAction(
            id: "a1",
            toolID: "toggl",
            actionType: "create_time_entry",
            label: "Log time: deep work",
            parameters: ["description": "deep work", "duration_minutes": "30"],
            status: .succeeded,
            channelID: "ch-1",
            stepIndex: 0
        )
        let data = try encoder.encode(action)
        let decoded = try decoder.decode(PlannedAction.self, from: data)
        #expect(decoded == action)
    }

    @Test
    func hasActionableItemsTrueWhenActionsExist() {
        let plan = ExecutionPlan(
            captureID: "c",
            actions: [PlannedAction(toolID: "toggl", actionType: "create_time_entry", label: "Log")]
        )
        #expect(plan.hasActionableItems)
    }

    @Test
    func hasActionableItemsFalseWhenEmpty() {
        let plan = ExecutionPlan(captureID: "c", actions: [])
        #expect(!plan.hasActionableItems)
    }
}
