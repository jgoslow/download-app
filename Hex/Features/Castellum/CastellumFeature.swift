//
//  CastellumFeature.swift
//  Basin
//
//  The Castellum — Basin's execution engine. Receives a SessionAnalysis,
//  plans actions using connected tools and enabled channels, presents them
//  for user confirmation, and dispatches execution to per-tool API clients.
//

import ComposableArchitecture
import HexCore
import SwiftData

private let castellumLogger = HexLog.app

// MARK: - Dependencies (stubs for Phase 1)

@DependencyClient
struct CastellumPlannerClient {
    /// Build an execution plan from a session analysis.
    var createPlan: @Sendable (
        SessionAnalysis,
        String,        // captureID
        [Tool],        // connected tools
        [Workflow],    // enabled workflows (formerly channels)
        String         // Anthropic API key
    ) async throws -> ExecutionPlan = { _, captureID, _, _, _ in
        ExecutionPlan(captureID: captureID, actions: [])
    }
}

@DependencyClient
struct ToolExecutionClient {
    /// Execute a single planned action against its tool's API.
    var execute: @Sendable (PlannedAction, Tool) async -> ActionResult = { action, _ in
        ActionResult(actionID: action.id, success: false, error: "Not implemented")
    }
}

extension CastellumPlannerClient: DependencyKey {
    static let liveValue = CastellumPlannerClient.live()
    static let testValue = CastellumPlannerClient()
}

extension ToolExecutionClient: DependencyKey {
    static let liveValue = ToolExecutionClient(
        execute: { action, tool in
            // Try generic data-driven executor first (reads from JSON definitions)
            if let result = await GenericToolExecutor.execute(action: action, tool: tool) {
                return result
            }

            // Fall back to legacy per-tool Swift clients
            switch action.toolID {
            case "jira":
                return await JiraActionClient.execute(action: action, tool: tool)
            case "slack":
                return await SlackActionClient.execute(action: action, tool: tool)
            case "toggl":
                return await TogglActionClient.execute(action: action, tool: tool)
            default:
                return ActionResult(actionID: action.id, success: false, error: "Tool '\(action.toolID)' not yet implemented")
            }
        }
    )
    static let testValue = ToolExecutionClient()
}

extension DependencyValues {
    var castellumPlanner: CastellumPlannerClient {
        get { self[CastellumPlannerClient.self] }
        set { self[CastellumPlannerClient.self] = newValue }
    }
    var toolExecution: ToolExecutionClient {
        get { self[ToolExecutionClient.self] }
        set { self[ToolExecutionClient.self] = newValue }
    }
}

// MARK: - Feature

@Reducer
struct CastellumFeature {
    @ObservableState
    struct State: Equatable {
        var currentPlan: ExecutionPlan?
        var actionResults: [String: ActionResult] = [:]
        var isPlanning: Bool = false
        var isExecuting: Bool = false
        var planningError: String?
        var selectedActions: Set<String> = []
        var expandedActions: Set<String> = []
    }

    enum Action {
        // Planning
        case planExecution(SessionAnalysis, captureID: String)
        case planReceived(ExecutionPlan)
        case planningFailed(String)

        // User interaction
        case toggleAction(String)
        case toggleActionDetail(String)
        case executeSelected
        case retryAction(String)
        case dismissPlan

        // Execution
        case actionStarted(String)
        case actionCompleted(ActionResult)
        case executionFinished
    }

    @Dependency(\.castellumPlanner) var planner
    @Dependency(\.toolExecution) var toolExecution
    @Dependency(\.modelContext) var basinDB

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            // MARK: Planning

            case let .planExecution(analysis, captureID):
                // Only plan if there are tasks and integrations
                guard !analysis.tasks.isEmpty, !analysis.integrations.isEmpty else {
                    return .none
                }

                state.isPlanning = true
                state.planningError = nil
                state.currentPlan = nil

                return .run { send in
                    @Shared(.hexSettings) var hexSettings: HexSettings
                    let apiKey = hexSettings.basinSettings.anthropicAPIKey

                    // Fetch connected tools and enabled workflows from SwiftData
                    let tools = try await basinDB.fetchTools()
                    let connectedTools = tools.filter { $0.isConnected }
                    let workflows = try await basinDB.fetchWorkflows()
                    let enabledWorkflows = workflows.filter { $0.isEnabled }

                    guard !connectedTools.isEmpty else {
                        await send(.planningFailed("No tools connected. Connect tools in Settings."))
                        return
                    }

                    do {
                        let plan = try await planner.createPlan(
                            analysis,
                            captureID,
                            connectedTools,
                            enabledWorkflows,
                            apiKey
                        )

                        if plan.hasActionableItems {
                            await send(.planReceived(plan))
                        } else {
                            // No matching actions — silently skip
                            castellumLogger.info("Castellum: no actionable items for capture \(captureID)")
                        }
                    } catch {
                        await send(.planningFailed(error.localizedDescription))
                    }
                }

            case let .planReceived(plan):
                state.isPlanning = false
                state.currentPlan = plan
                state.selectedActions = Set(plan.actions.map(\.id))
                state.actionResults = [:]
                // If every tool involved has auto-execute on ("Requires Approval" off),
                // skip the approval step and execute immediately.
                return .run { send in
                    let tools = try await basinDB.fetchTools()
                    let toolIDs = Set(plan.actions.map(\.toolID))
                    let involved = tools.filter { toolIDs.contains($0.id) }
                    if !involved.isEmpty && involved.allSatisfy(\.autoExecute) {
                        await send(.executeSelected)
                    }
                }

            case let .planningFailed(error):
                state.isPlanning = false
                state.planningError = error
                castellumLogger.error("Castellum planning failed: \(error)")
                return .none

            // MARK: User Interaction

            case let .toggleAction(actionID):
                if state.selectedActions.contains(actionID) {
                    state.selectedActions.remove(actionID)
                } else {
                    state.selectedActions.insert(actionID)
                }
                return .none

            case let .toggleActionDetail(actionID):
                if state.expandedActions.contains(actionID) {
                    state.expandedActions.remove(actionID)
                } else {
                    state.expandedActions.insert(actionID)
                }
                return .none

            case .executeSelected:
                guard let plan = state.currentPlan else { return .none }

                let selected = plan.actions.filter { state.selectedActions.contains($0.id) }
                guard !selected.isEmpty else { return .none }

                state.isExecuting = true

                return .run { send in
                    let tools = try await basinDB.fetchTools()
                    let toolMap = Dictionary(tools.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

                    // Group by channel for sequential execution, direct actions run concurrently
                    let directActions = selected.filter { $0.channelID == nil }
                    let channelGroups = Dictionary(grouping: selected.filter { $0.channelID != nil }) { $0.channelID! }

                    // Execute direct actions concurrently
                    await withTaskGroup(of: Void.self) { group in
                        for action in directActions {
                            guard let tool = toolMap[action.toolID] else { continue }
                            group.addTask {
                                await send(.actionStarted(action.id))
                                let result = await toolExecution.execute(action, tool)
                                await send(.actionCompleted(result))
                            }
                        }
                    }

                    // Execute channel pipelines sequentially
                    for (_, steps) in channelGroups {
                        let sorted = steps.sorted { ($0.stepIndex ?? 0) < ($1.stepIndex ?? 0) }
                        for action in sorted {
                            guard let tool = toolMap[action.toolID] else { continue }
                            await send(.actionStarted(action.id))
                            let result = await toolExecution.execute(action, tool)
                            await send(.actionCompleted(result))
                            // Stop pipeline on failure
                            if !result.success { break }
                        }
                    }

                    await send(.executionFinished)
                }

            case let .retryAction(actionID):
                guard var plan = state.currentPlan,
                      let index = plan.actions.firstIndex(where: { $0.id == actionID }) else {
                    return .none
                }

                plan.actions[index].status = .pending
                state.currentPlan = plan
                state.actionResults.removeValue(forKey: actionID)

                let action = plan.actions[index]
                return .run { send in
                    let tools = try await basinDB.fetchTools()
                    guard let tool = tools.first(where: { $0.id == action.toolID }) else {
                        await send(.actionCompleted(ActionResult(actionID: actionID, success: false, error: "Tool not found")))
                        return
                    }
                    await send(.actionStarted(actionID))
                    let result = await toolExecution.execute(action, tool)
                    await send(.actionCompleted(result))
                }

            case .dismissPlan:
                state.currentPlan = nil
                state.actionResults = [:]
                state.selectedActions = []
                state.expandedActions = []
                state.isPlanning = false
                state.isExecuting = false
                state.planningError = nil
                return .none

            // MARK: Execution

            case let .actionStarted(actionID):
                if var plan = state.currentPlan,
                   let index = plan.actions.firstIndex(where: { $0.id == actionID }) {
                    plan.actions[index].status = .executing
                    state.currentPlan = plan
                }
                return .none

            case let .actionCompleted(result):
                state.actionResults[result.actionID] = result
                if var plan = state.currentPlan,
                   let index = plan.actions.firstIndex(where: { $0.id == result.actionID }) {
                    plan.actions[index].status = result.success ? .succeeded : .failed
                    state.currentPlan = plan
                }
                return .none

            case .executionFinished:
                state.isExecuting = false
                return .none
            }
        }
    }
}
