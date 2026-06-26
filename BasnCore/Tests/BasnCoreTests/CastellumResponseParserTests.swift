import Testing
import Foundation
@testable import BasnCore

struct CastellumResponseParserTests {

    // MARK: - Text block parsing

    @Test
    func cleanJsonTextBlockDecodesAnalysis() {
        let json = """
        {"summary": "Auth bug fix planned", "mood_tag": "focused",
         "tasks": ["Fix auth"], "routing": ["jira"], "delegations": [],
         "integrations": ["jira"], "prompts_addressed": [0]}
        """
        let content: [[String: Any]] = [["type": "text", "text": json]]
        let (analysis, actions) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(analysis.summary == "Auth bug fix planned")
        #expect(analysis.moodTag == "focused")
        #expect(analysis.tasks == ["Fix auth"])
        #expect(actions.isEmpty)
    }

    @Test
    func textBlockWithSurroundingProseExtractsJson() {
        let content: [[String: Any]] = [[
            "type": "text",
            "text": "Here is the analysis: {\"summary\": \"Standup note\", \"tasks\": [], \"routing\": [], \"delegations\": [], \"integrations\": [], \"prompts_addressed\": []} — done."
        ]]
        let (analysis, _) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(analysis.summary == "Standup note")
    }

    @Test
    func malformedTextBlockUsesFallbackAnalysis() {
        let content: [[String: Any]] = [["type": "text", "text": "not json at all"]]
        let (analysis, actions) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(analysis.summary == "Capture processed")
        #expect(actions.isEmpty)
    }

    @Test
    func missingTextBlockUsesFallbackAnalysis() {
        let content: [[String: Any]] = []
        let (analysis, _) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(analysis.summary == "Capture processed")
    }

    // MARK: - Tool use block parsing

    @Test
    func singleToolUseBlockParsesCorrectly() {
        let content: [[String: Any]] = [
            ["type": "text", "text": "{\"summary\": \"s\", \"tasks\": [], \"routing\": [], \"delegations\": [], \"integrations\": [], \"prompts_addressed\": []}"],
            ["type": "tool_use", "name": "jira_create_issue", "input": ["summary": "Auth bug", "project": "BASN"]]
        ]
        let (_, actions) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(actions.count == 1)
        #expect(actions[0].toolID == "jira")
        #expect(actions[0].actionType == "create_issue")
        #expect(actions[0].parameters["summary"] == "Auth bug")
        #expect(actions[0].parameters["project"] == "BASN")
    }

    @Test
    func toolNameWithMultipleUnderscoresSplitsOnFirstOnly() {
        // "toggl_create_time_entry" → toolID: "toggl", actionType: "create_time_entry"
        let content: [[String: Any]] = [
            ["type": "tool_use", "name": "toggl_create_time_entry", "input": ["description": "deep work"]]
        ]
        let (_, actions) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(actions.count == 1)
        #expect(actions[0].toolID == "toggl")
        #expect(actions[0].actionType == "create_time_entry")
    }

    @Test
    func multipleToolUseBlocksAllParsed() {
        let textBlock: [String: Any] = ["type": "text", "text": "{\"summary\": \"s\", \"tasks\": [], \"routing\": [], \"delegations\": [], \"integrations\": [], \"prompts_addressed\": []}"]
        let jiraBlock: [String: Any] = ["type": "tool_use", "name": "jira_create_issue", "input": ["summary": "Bug"]]
        let slackBlock: [String: Any] = ["type": "tool_use", "name": "slack_send_message", "input": ["text": "FYI"]]
        let content: [[String: Any]] = [textBlock, jiraBlock, slackBlock]
        let (_, actions) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(actions.count == 2)
        #expect(actions[0].toolID == "jira")
        #expect(actions[1].toolID == "slack")
    }

    @Test
    func zeroToolUseBlocksProducesEmptyActions() {
        let content: [[String: Any]] = [
            ["type": "text", "text": "{\"summary\": \"Journal entry\", \"tasks\": [], \"routing\": [], \"delegations\": [], \"integrations\": [], \"prompts_addressed\": []}"]
        ]
        let (analysis, actions) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(analysis.summary == "Journal entry")
        #expect(actions.isEmpty)
    }

    @Test
    func onlyToolUseBlocksNoTextBlockUsesFallback() {
        let content: [[String: Any]] = [
            ["type": "tool_use", "name": "toggl_create_time_entry", "input": ["description": "work"]]
        ]
        let (analysis, actions) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(analysis.summary == "Capture processed")
        #expect(actions.count == 1)
    }

    // MARK: - Parameter type coercion

    @Test
    func nsNumberParamCoercedToString() {
        let content: [[String: Any]] = [
            ["type": "tool_use", "name": "toggl_create_time_entry",
             "input": ["duration_minutes": NSNumber(value: 30)]]
        ]
        let (_, actions) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(actions[0].parameters["duration_minutes"] == "30")
    }

    @Test
    func stringArrayParamJoinedWithComma() {
        let content: [[String: Any]] = [
            ["type": "tool_use", "name": "jira_create_issue",
             "input": ["labels": ["bug", "auth", "p1"]]]
        ]
        let (_, actions) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(actions[0].parameters["labels"] == "bug, auth, p1")
    }

    // MARK: - Malformed tool_use blocks

    @Test
    func toolUseWithMissingInputSkipped() {
        let content: [[String: Any]] = [
            ["type": "tool_use", "name": "jira_create_issue"]  // no "input"
        ]
        let (_, actions) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(actions.isEmpty)
    }

    @Test
    func toolUseWithNoUnderscoreInNameSkipped() {
        // Name must be "toolID_actionType" — no underscore → invalid
        let content: [[String: Any]] = [
            ["type": "tool_use", "name": "createissue", "input": ["summary": "test"]]
        ]
        let (_, actions) = CastellumResponseParser.parse(content, captureID: "test")
        #expect(actions.isEmpty)
    }

    // MARK: - labelLookup

    @Test
    func labelLookupClosureIsCalledForLabel() {
        var calledWith: (String, String)?
        let content: [[String: Any]] = [
            ["type": "tool_use", "name": "jira_create_issue", "input": [:]]
        ]
        _ = CastellumResponseParser.parse(content, captureID: "test") { toolID, actionType in
            calledWith = (toolID, actionType)
            return "Create Issue"
        }
        #expect(calledWith?.0 == "jira")
        #expect(calledWith?.1 == "create_issue")
    }

    @Test
    func nilLabelLookupFallsBackToCapitalizedActionType() {
        let content: [[String: Any]] = [
            ["type": "tool_use", "name": "jira_create_issue", "input": [:]]
        ]
        let (_, actions) = CastellumResponseParser.parse(content, captureID: "test", labelLookup: nil)
        // "create_issue" → "Create Issue" (underscores replaced, capitalized)
        #expect(actions[0].label == "Create Issue")
    }
}
