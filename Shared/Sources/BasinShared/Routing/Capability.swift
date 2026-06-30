import Foundation

/// A generic, tool-agnostic action type. The fixed vocabulary the router reasons
/// over BEFORE tools are connected — it identifies what a capture wants to do and
/// nudges the user to connect a tool that provides it. Once a tool IS connected
/// for a capability, that tool's specific (higher-fidelity) action is used
/// instead. Keeping this list small + fixed means the prompt scales with the
/// CONNECTED tool set, never the full catalog.
public struct Capability: Sendable, Identifiable {
    public let id: String          // e.g. "create_task"
    public let title: String       // human label, e.g. "Create a task"
    public let summary: String     // one-line for Claude + the connect prompt
    public let parameters: [Param]

    public struct Param: Sendable {
        public let name: String
        public let description: String
        public let required: Bool
        public init(_ name: String, _ description: String, required: Bool = false) {
            self.name = name; self.description = description; self.required = required
        }
    }

    public init(id: String, title: String, summary: String, parameters: [Param]) {
        self.id = id; self.title = title; self.summary = summary; self.parameters = parameters
    }
}

public enum Capabilities {
    /// Prefix for generic capability tool_use function names, so they're
    /// distinguishable from tool-scoped (`toolID_actionType`) ones.
    public static let functionPrefix = "cap_"

    public static let all: [Capability] = [
        Capability(id: "create_task", title: "Create a task", summary: "Create a task or ticket to track work",
                   parameters: [.init("title", "Short task title", required: true),
                                .init("description", "Optional detail"),
                                .init("project", "Project or area, if mentioned")]),
        Capability(id: "log_time", title: "Log time", summary: "Record time spent on something",
                   parameters: [.init("description", "What was worked on", required: true),
                                .init("duration_minutes", "Minutes spent")]),
        Capability(id: "send_message", title: "Send a message", summary: "Send a chat message to a person or channel",
                   parameters: [.init("message", "The message text", required: true),
                                .init("channel", "Channel or recipient, if mentioned")]),
        Capability(id: "schedule_event", title: "Schedule an event", summary: "Put an event on a calendar",
                   parameters: [.init("title", "Event title", required: true),
                                .init("start", "Start time, if mentioned"),
                                .init("attendees", "People to invite, if mentioned")]),
        Capability(id: "send_email", title: "Send an email", summary: "Compose and send an email",
                   parameters: [.init("to", "Recipient"),
                                .init("subject", "Subject"),
                                .init("body", "Body text")]),
        Capability(id: "create_document", title: "Create a document", summary: "Create a document or doc page",
                   parameters: [.init("title", "Document title", required: true),
                                .init("content", "Body content, if any")]),
        Capability(id: "capture_note", title: "Capture a note", summary: "Save a freeform note",
                   parameters: [.init("text", "The note text", required: true)]),
    ]

    public static func byID(_ id: String) -> Capability? { all.first { $0.id == id } }

    /// Strip the `cap_` prefix to recover the capability id from a function name.
    public static func capabilityID(fromFunctionName name: String) -> String? {
        name.hasPrefix(functionPrefix) ? String(name.dropFirst(functionPrefix.count)) : nil
    }

    /// Claude tool_use schemas for the given generic capabilities (function name = `cap_<id>`).
    public static func claudeSchemas(for ids: [String]) -> [[String: Any]] {
        ids.compactMap(byID).map { cap in
            var properties: [String: Any] = [:]
            var required: [String] = []
            for p in cap.parameters {
                properties[p.name] = ["type": "string", "description": p.description]
                if p.required { required.append(p.name) }
            }
            return [
                "name": functionPrefix + cap.id,
                "description": cap.summary + " (generic — no specific tool is connected for this yet).",
                "input_schema": ["type": "object", "properties": properties, "required": required],
            ]
        }
    }
}
