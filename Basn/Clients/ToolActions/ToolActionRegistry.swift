//
//  ToolActionRegistry.swift
//  Basin
//
//  Defines the available OOB actions per tool and their parameter schemas.
//  Used by the CastellumPlanner to build Claude tool_use requests,
//  and by the ToolExecutionClient to validate parameters before dispatch.
//

import Foundation

// MARK: - Action Definition

struct ToolActionDefinition: Sendable {
    let toolID: String
    let actionType: String
    let displayName: String
    let description: String
    let parameters: [ActionParameter]

    struct ActionParameter: Sendable {
        let name: String
        let type: String          // "string", "integer", "array"
        let description: String
        let required: Bool
        let enumValues: [String]?

        init(name: String, type: String = "string", description: String, required: Bool = false, enumValues: [String]? = nil) {
            self.name = name
            self.type = type
            self.description = description
            self.required = required
            self.enumValues = enumValues
        }
    }
}

// MARK: - Registry

enum ToolActionRegistry {

    /// All registered tool actions. Each tool can have multiple actions.
    static let actions: [ToolActionDefinition] = [

        // MARK: Jira

        ToolActionDefinition(
            toolID: "jira",
            actionType: "create_issue",
            displayName: "Create Issue",
            description: "Create a Jira issue from a task or note",
            parameters: [
                .init(name: "project_key", description: "Jira project key (e.g. LYRA)", required: true),
                .init(name: "summary", description: "Issue title/summary", required: true),
                .init(name: "description", description: "Detailed description"),
                .init(name: "issue_type", description: "Issue type", enumValues: ["Task", "Bug", "Story"]),
                .init(name: "assignee", description: "Assignee username or email"),
                .init(name: "priority", description: "Priority level", enumValues: ["Highest", "High", "Medium", "Low", "Lowest"]),
            ]
        ),

        // MARK: GitHub

        ToolActionDefinition(
            toolID: "github",
            actionType: "create_issue",
            displayName: "Create Issue",
            description: "Create a GitHub issue in a repository",
            parameters: [
                .init(name: "owner", description: "Repository owner", required: true),
                .init(name: "repo", description: "Repository name", required: true),
                .init(name: "title", description: "Issue title", required: true),
                .init(name: "body", description: "Issue body/description"),
                .init(name: "labels", type: "array", description: "Labels to apply"),
            ]
        ),

        // MARK: Slack

        ToolActionDefinition(
            toolID: "slack",
            actionType: "send_message",
            displayName: "Send Message",
            description: "Send a message to a Slack channel or user",
            parameters: [
                .init(name: "channel", description: "#channel or @username", required: true),
                .init(name: "text", description: "Message text", required: true),
                .init(name: "thread_ts", description: "Thread timestamp to reply to"),
            ]
        ),

        // MARK: Google Calendar

        ToolActionDefinition(
            toolID: "calendar",
            actionType: "create_event",
            displayName: "Create Event",
            description: "Create a Google Calendar event",
            parameters: [
                .init(name: "summary", description: "Event title", required: true),
                .init(name: "description", description: "Event description"),
                .init(name: "start_time", description: "Start time (ISO 8601)", required: true),
                .init(name: "end_time", description: "End time (ISO 8601)", required: true),
                .init(name: "attendees", type: "array", description: "Attendee email addresses"),
            ]
        ),

        // MARK: Toggl

        ToolActionDefinition(
            toolID: "toggl",
            actionType: "create_time_entry",
            displayName: "Log Time",
            description: "Create a time entry in Toggl Track",
            parameters: [
                .init(name: "description", description: "What you worked on", required: true),
                // Optional to match toggl.json — Toggl logs time without a project fine.
                // (Was required:true, which dropped time-log actions that had no project.)
                .init(name: "project_name", description: "Project name"),
                .init(name: "duration_minutes", type: "integer", description: "Duration in minutes", required: true),
                .init(name: "tags", type: "array", description: "Tags to apply"),
            ]
        ),

        // MARK: Email (Gmail)

        ToolActionDefinition(
            toolID: "email",
            actionType: "send_email",
            displayName: "Send Email",
            description: "Send an email via Gmail",
            parameters: [
                .init(name: "to", description: "Recipient email address", required: true),
                .init(name: "subject", description: "Email subject", required: true),
                .init(name: "body", description: "Email body text", required: true),
                .init(name: "cc", description: "CC recipients"),
            ]
        ),

        // MARK: Wave

        ToolActionDefinition(
            toolID: "wave",
            actionType: "create_invoice",
            displayName: "Create Invoice",
            description: "Create an invoice in Wave accounting",
            parameters: [
                .init(name: "customer_name", description: "Customer/client name", required: true),
                .init(name: "items", type: "array", description: "Line items (description, quantity, unit price)", required: true),
                .init(name: "due_date", description: "Payment due date (YYYY-MM-DD)"),
            ]
        ),
    ]

    /// Look up actions for a specific tool.
    static func actions(for toolID: String) -> [ToolActionDefinition] {
        actions.filter { $0.toolID == toolID }
    }

    /// Look up a specific action by tool + action type.
    static func action(toolID: String, actionType: String) -> ToolActionDefinition? {
        actions.first { $0.toolID == toolID && $0.actionType == actionType }
    }

    /// Build Claude tool_use JSON schema for a set of tool IDs.
    /// Returns an array of tool definitions ready for the Anthropic API `tools` parameter.
    static func claudeToolSchemas(for toolIDs: Set<String>) -> [[String: Any]] {
        actions
            .filter { toolIDs.contains($0.toolID) }
            .map { action in
                var properties: [String: Any] = [:]
                var required: [String] = []

                for param in action.parameters {
                    var prop: [String: Any] = [
                        "type": param.type,
                        "description": param.description,
                    ]
                    if let enums = param.enumValues {
                        prop["enum"] = enums
                    }
                    properties[param.name] = prop
                    if param.required {
                        required.append(param.name)
                    }
                }

                return [
                    "name": "\(action.toolID)_\(action.actionType)",
                    "description": action.description,
                    "input_schema": [
                        "type": "object",
                        "properties": properties,
                        "required": required,
                    ] as [String: Any],
                ]
            }
    }
}
