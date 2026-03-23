import Foundation

/// The notification and reminder schedule for a Flow.
///
/// Drives the watchOS notification system and the NotificationScheduler service.
/// All fields are optional/nullable to support the "Open" type which has no schedule.
public struct Schedule: Codable, Sendable, Equatable {
    /// Days of the week this type should fire a reminder.
    public let days: [Weekday]
    /// Local time for the reminder, e.g. "07:30". Nil if not scheduled.
    public let reminderTime: String?
    /// Whether the reminder notification is enabled.
    public let reminderEnabled: Bool
    /// Suggested session duration in minutes, shown as a hint in the UI.
    public let suggestedDurationMinutes: Int
    /// Title for the watch/lock screen notification, e.g. "Morning Kickoff".
    public let notificationTitle: String
    /// Body line shown in the notification, e.g. "Before the day gets its hooks in you."
    public let notificationBody: String
    /// Snooze duration options in minutes, shown as buttons in the watch notification.
    public let snoozeOptionsMinutes: [Int]
    /// For monthly/quarterly types: which week of the month (1-based). Nil for weekly/daily.
    public let weekOfMonth: Int?
    /// For quarterly types: which month of the quarter (1-based). Nil for weekly/monthly.
    public let monthOfQuarter: Int?

    public enum Weekday: String, Codable, Sendable, CaseIterable {
        case mon, tue, wed, thu, fri, sat, sun
    }

    public init(
        days: [Weekday] = [],
        reminderTime: String? = nil,
        reminderEnabled: Bool = false,
        suggestedDurationMinutes: Int = 10,
        notificationTitle: String = "",
        notificationBody: String = "",
        snoozeOptionsMinutes: [Int] = [5, 10, 60],
        weekOfMonth: Int? = nil,
        monthOfQuarter: Int? = nil
    ) {
        self.days = days
        self.reminderTime = reminderTime
        self.reminderEnabled = reminderEnabled
        self.suggestedDurationMinutes = suggestedDurationMinutes
        self.notificationTitle = notificationTitle
        self.notificationBody = notificationBody
        self.snoozeOptionsMinutes = snoozeOptionsMinutes
        self.weekOfMonth = weekOfMonth
        self.monthOfQuarter = monthOfQuarter
    }

    enum CodingKeys: String, CodingKey {
        case days
        case reminderTime = "reminder_time"
        case reminderEnabled = "reminder_enabled"
        case suggestedDurationMinutes = "suggested_duration_minutes"
        case notificationTitle = "notification_title"
        case notificationBody = "notification_body"
        case snoozeOptionsMinutes = "snooze_options_minutes"
        case weekOfMonth = "week_of_month"
        case monthOfQuarter = "month_of_quarter"
    }
}
