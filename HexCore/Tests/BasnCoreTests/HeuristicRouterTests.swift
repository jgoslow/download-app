import Testing
@testable import BasnCore

struct HeuristicRouterTests {

    private let togglConnected: Set<String> = ["toggl"]
    private let togglDisconnected: Set<String> = []
    private let togglAndJira: Set<String> = ["toggl", "jira"]

    // MARK: - Toggl timer matches

    @Test
    func startTimerReturnsTogglAction() {
        let actions = HeuristicRouter.route(transcript: "start timer for deep work", connectedToolIDs: togglConnected)
        #expect(actions?.count == 1)
        #expect(actions?.first?.toolID == "toggl")
        #expect(actions?.first?.actionType == "create_time_entry")
    }

    @Test
    func startTimerCapturesDescriptionAfterTrigger() {
        let actions = HeuristicRouter.route(transcript: "start timer for deep work", connectedToolIDs: togglConnected)
        // "start timer" is stripped; leading "for" is also stripped → clean description
        #expect(actions?.first?.parameters["description"] == "deep work")
    }

    @Test
    func logTimeForMatches() {
        let actions = HeuristicRouter.route(transcript: "log time for the design review", connectedToolIDs: togglConnected)
        #expect(actions?.count == 1)
        #expect(actions?.first?.toolID == "toggl")
    }

    @Test
    func trackTimeForMatches() {
        let actions = HeuristicRouter.route(transcript: "track time for the weekly sync", connectedToolIDs: togglConnected)
        #expect(actions?.count == 1)
    }

    @Test
    func trackTimeOnMatches() {
        let actions = HeuristicRouter.route(transcript: "track time on the backend refactor", connectedToolIDs: togglConnected)
        #expect(actions?.count == 1)
    }

    // MARK: - Toggl not connected

    @Test
    func togglTriggerWithToolDisconnectedReturnsNil() {
        let actions = HeuristicRouter.route(transcript: "start timer for deep work", connectedToolIDs: togglDisconnected)
        #expect(actions == nil)
    }

    // MARK: - Unrelated captures

    @Test
    func unrelatedCaptureReturnsNil() {
        let actions = HeuristicRouter.route(transcript: "reminder to call mom tonight", connectedToolIDs: togglConnected)
        #expect(actions == nil)
    }

    @Test
    func emptyTranscriptReturnsNil() {
        let actions = HeuristicRouter.route(transcript: "", connectedToolIDs: togglConnected)
        #expect(actions == nil)
    }

    // MARK: - Case insensitivity

    @Test
    func uppercaseTriggerMatches() {
        let actions = HeuristicRouter.route(transcript: "Start Timer for morning standup", connectedToolIDs: togglConnected)
        #expect(actions?.count == 1)
    }
}
