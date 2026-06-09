import Foundation

// MARK: - Execution Plan

/// A set of proposed actions the Castellum has planned based on a capture's analysis.
/// Presented to the user for confirmation before execution.
public struct ExecutionPlan: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let captureID: String
    public var actions: [PlannedAction]
    public let createdAt: Date
    /// Which model produced this plan. "heuristic" = no API call; nil = legacy path.
    public let modelUsed: String?

    public init(
        id: String = UUID().uuidString,
        captureID: String,
        actions: [PlannedAction],
        createdAt: Date = Date(),
        modelUsed: String? = nil
    ) {
        self.id = id
        self.captureID = captureID
        self.actions = actions
        self.createdAt = createdAt
        self.modelUsed = modelUsed
    }

    public var hasActionableItems: Bool {
        !actions.isEmpty
    }
}

// MARK: - Planned Action

/// A single action within an execution plan — e.g., "Create Jira card: 'Auth bug fix'".
/// May be a direct tool action (OOB) or part of a channel pipeline.
public struct PlannedAction: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let toolID: String
    public let actionType: String
    public let label: String
    public let parameters: [String: String]
    public var status: ActionStatus
    public let channelID: String?
    public let stepIndex: Int?

    public init(
        id: String = UUID().uuidString,
        toolID: String,
        actionType: String,
        label: String,
        parameters: [String: String] = [:],
        status: ActionStatus = .pending,
        channelID: String? = nil,
        stepIndex: Int? = nil
    ) {
        self.id = id
        self.toolID = toolID
        self.actionType = actionType
        self.label = label
        self.parameters = parameters
        self.status = status
        self.channelID = channelID
        self.stepIndex = stepIndex
    }
}

// MARK: - Action Status

public enum ActionStatus: String, Codable, Sendable, Equatable {
    case pending
    case executing
    case succeeded
    case failed
}

// MARK: - Action Result

/// The outcome of executing a single planned action.
public struct ActionResult: Sendable, Equatable {
    public let actionID: String
    public let success: Bool
    public let message: String?
    public let error: String?

    public init(actionID: String, success: Bool, message: String? = nil, error: String? = nil) {
        self.actionID = actionID
        self.success = success
        self.message = message
        self.error = error
    }
}
