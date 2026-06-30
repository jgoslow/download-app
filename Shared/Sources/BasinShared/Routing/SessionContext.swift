import Foundation

/// A summary of a previous session, used as pre-session continuity context.
/// Shared across platforms; assembled from the local capture store (native) or
/// fetched from a Castellum server when configured.
public struct SessionContext: Codable, Sendable {
    public let timestamp: String?
    public let summary: String?
    public let moodTag: String?
    public let tasks: [String]?
    public let routing: [String]?
    public let delegations: [String]?

    public init(
        timestamp: String? = nil,
        summary: String? = nil,
        moodTag: String? = nil,
        tasks: [String]? = nil,
        routing: [String]? = nil,
        delegations: [String]? = nil
    ) {
        self.timestamp = timestamp
        self.summary = summary
        self.moodTag = moodTag
        self.tasks = tasks
        self.routing = routing
        self.delegations = delegations
    }

    enum CodingKeys: String, CodingKey {
        case timestamp, summary, tasks, routing, delegations
        case moodTag = "mood_tag"
    }
}
