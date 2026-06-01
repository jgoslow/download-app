import Foundation

/// A single guided prompt within a flow session.
///
/// Prompts are orthogonal along two axes:
/// - `isRequired`: must be answered or explicitly swiped past (vs. passable)
/// - `timerSeconds`: if non-nil, the prompt auto-advances when the timer expires
///
/// `isCastellumGenerated` is a display-only flag — it drives a shimmer dot style
/// indicating the prompt was injected by Castellum at runtime.
public struct FlowPrompt: Codable, Identifiable, Sendable, Equatable {
    public var id: Int
    public var title: String
    public var detail: String
    public var isRequired: Bool
    public var timerSeconds: Double?
    public var choices: [PromptChoice]?
    public var isCastellumGenerated: Bool

    public struct PromptChoice: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var label: String

        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }
    }

    public init(
        id: Int,
        title: String,
        detail: String = "",
        isRequired: Bool = false,
        timerSeconds: Double? = nil,
        choices: [PromptChoice]? = nil,
        isCastellumGenerated: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isRequired = isRequired
        self.timerSeconds = timerSeconds
        self.choices = choices
        self.isCastellumGenerated = isCastellumGenerated
    }

    enum CodingKeys: String, CodingKey {
        case id, title, detail, isRequired, timerSeconds, choices, isCastellumGenerated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        isRequired = try c.decodeIfPresent(Bool.self, forKey: .isRequired) ?? false
        timerSeconds = try c.decodeIfPresent(Double.self, forKey: .timerSeconds)
        choices = try c.decodeIfPresent([PromptChoice].self, forKey: .choices)
        isCastellumGenerated = try c.decodeIfPresent(Bool.self, forKey: .isCastellumGenerated) ?? false
    }
}

// MARK: - Setup Flow

extension FlowPrompt {
    /// The prompt sequence for the onboarding setup flow.
    /// Static v1 — no Castellum processing during the flow; one API call fires at the end.
    public static let setupFlowPrompts: [FlowPrompt] = [
        FlowPrompt(
            id: 1,
            title: "Welcome to your first flow.",
            timerSeconds: 2
        ),
        FlowPrompt(
            id: 2,
            title: "Speaking out loud is the best way to use Basn — but you can always switch to text at any time.",
            timerSeconds: 6
        ),
        FlowPrompt(
            id: 3,
            title: "What would you like to use Basn for?",
            isRequired: true,
            choices: [
                PromptChoice(id: "work", label: "Work"),
                PromptChoice(id: "life", label: "Life"),
                PromptChoice(id: "growth", label: "Growth"),
                PromptChoice(id: "other", label: "Something else"),
            ]
        ),
        FlowPrompt(
            id: 4,
            title: "What does a typical day or week look like for you?",
            detail: "Share as much or as little as you like."
        ),
        FlowPrompt(
            id: 5,
            title: "Which tools do you use?",
            isRequired: true,
            choices: [
                PromptChoice(id: "jira", label: "Jira"),
                PromptChoice(id: "github", label: "GitHub"),
                PromptChoice(id: "slack", label: "Slack"),
                PromptChoice(id: "toggl", label: "Toggl"),
                PromptChoice(id: "google", label: "Google"),
                PromptChoice(id: "wave", label: "Wave"),
            ]
        ),
        FlowPrompt(
            id: 6,
            title: "Basn creates workflows for you automatically — connect the tools and it figures out where your thoughts should go.",
            timerSeconds: 8
        ),
        FlowPrompt(
            id: 7,
            title: "What outcomes matter most to you?",
            detail: "Tasks, messages, time logs, reminders, journal entries?"
        ),
        FlowPrompt(
            id: 8,
            title: "When do you usually want to capture your thoughts?",
            choices: [
                PromptChoice(id: "morning", label: "Morning"),
                PromptChoice(id: "evening", label: "Evening"),
                PromptChoice(id: "midday", label: "Midday"),
                PromptChoice(id: "whenever", label: "Whenever"),
            ]
        ),
        FlowPrompt(
            id: 9,
            title: "Anything else you want Basn to know about how you work — or what you're hoping to get out of it?",
            isRequired: true
        ),
    ]
}
