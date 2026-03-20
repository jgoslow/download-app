import Foundation

/// The structured output from the post-session AI call (Phase 2).
///
/// Claude reads the transcript and returns this — one sentence summary,
/// extracted tasks, routing hints, delegations, and an optional mood tag.
public struct SessionAnalysis: Codable, Sendable, Equatable {
    /// One sentence capturing the main point of the session.
    public let summary: String
    /// One word describing the emotional tone. Nil if neutral/work-focused.
    public let moodTag: String?
    /// Actionable items mentioned in the transcript.
    public let tasks: [String]
    /// Suggested destinations for this content.
    public let routing: [RoutingDestination]
    /// Things to delegate, with who. E.g. "Diego: review the Rivera design".
    public let delegations: [String]

    public enum RoutingDestination: String, Codable, Sendable {
        case jira
        case calendar
        case notes
        case slack
        case email
        case cns  // Full Pathways system
    }

    public init(
        summary: String,
        moodTag: String? = nil,
        tasks: [String] = [],
        routing: [RoutingDestination] = [],
        delegations: [String] = []
    ) {
        self.summary = summary
        self.moodTag = moodTag
        self.tasks = tasks
        self.routing = routing
        self.delegations = delegations
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case moodTag = "mood_tag"
        case tasks
        case routing
        case delegations
    }
}
