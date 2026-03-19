// NotificationScheduler is platform-specific (UserNotifications framework).
// The macOS and iOS implementations live in their respective targets.
// This file defines the shared protocol and data types.

import Foundation

/// A scheduled reminder that should fire at a specific time.
public struct ScheduledReminder: Sendable {
    public let downloadTypeID: String
    public let downloadTypeName: String
    public let notificationTitle: String
    public let notificationBody: String
    public let snoozeOptionsMinutes: [Int]
    /// Weekday + time the reminder should fire. Nil = no schedule.
    public let weekday: Schedule.Weekday?
    public let reminderTime: String?  // "07:30" local time

    public init(
        downloadTypeID: String,
        downloadTypeName: String,
        notificationTitle: String,
        notificationBody: String,
        snoozeOptionsMinutes: [Int],
        weekday: Schedule.Weekday? = nil,
        reminderTime: String? = nil
    ) {
        self.downloadTypeID = downloadTypeID
        self.downloadTypeName = downloadTypeName
        self.notificationTitle = notificationTitle
        self.notificationBody = notificationBody
        self.snoozeOptionsMinutes = snoozeOptionsMinutes
        self.weekday = weekday
        self.reminderTime = reminderTime
    }
}

/// Derives the set of ScheduledReminders from a list of DownloadTypes.
///
/// Called when the app launches or when types are updated. The result is passed
/// to the platform-specific notification scheduling implementation.
public enum NotificationScheduler {
    public static func reminders(from types: [DownloadType]) -> [ScheduledReminder] {
        var reminders: [ScheduledReminder] = []
        for type_ in types {
            let schedule = type_.schedule
            guard schedule.reminderEnabled, let time = schedule.reminderTime else { continue }
            for day in schedule.days {
                reminders.append(ScheduledReminder(
                    downloadTypeID: type_.id,
                    downloadTypeName: type_.name,
                    notificationTitle: schedule.notificationTitle,
                    notificationBody: schedule.notificationBody,
                    snoozeOptionsMinutes: schedule.snoozeOptionsMinutes,
                    weekday: day,
                    reminderTime: time
                ))
            }
        }
        return reminders
    }
}
