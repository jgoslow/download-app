import Foundation

/// A named session configuration — defines the ritual, prompts, and routing for a class of recording.
///
/// Loaded from `download-types.json` (generated from `context/download-types/*.md` in the
/// jonas-pathways repo). The app bundles the JSON file and re-reads it on launch so changes
/// take effect without an app update.
public struct Flow: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let cadence: Cadence
    public let domains: [String]
    public let schedule: Schedule

    /// The "Open" type is always present and cannot be removed — it's the app's ground state.
    public static let openID = "open"

    public enum Cadence: String, Codable, Sendable {
        case onDemand = "on-demand"
        case daily
        case weekly
        case monthly
        case quarterly
    }

    public init(
        id: String,
        name: String,
        cadence: Cadence = .onDemand,
        domains: [String] = [],
        schedule: Schedule = Schedule()
    ) {
        self.id = id
        self.name = name
        self.cadence = cadence
        self.domains = domains
        self.schedule = schedule
    }
}

extension Flow {
    /// Fallback used when no types have been loaded from disk yet.
    public static let openDefault = Flow(
        id: openID,
        name: "Open",
        cadence: .onDemand,
        domains: ["anything"],
        schedule: Schedule(
            days: [],
            reminderEnabled: false,
            suggestedDurationMinutes: 5,
            notificationTitle: "Open",
            notificationBody: "Something on your mind?",
            snoozeOptionsMinutes: [5, 10, 60]
        )
    )
}
