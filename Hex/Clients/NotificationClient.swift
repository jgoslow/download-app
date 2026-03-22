//
//  NotificationClient.swift
//  Download
//
//  Schedules daily reminders for Download sessions.
//  Requires notification permission (prompted on first schedule).
//

import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import HexCore
import UserNotifications

private let notifLogger = HexLog.app

@DependencyClient
struct NotificationClient {
    var requestPermission: @Sendable () async -> Bool = { false }
    var scheduleDaily: @Sendable () async -> Void = {}
    var cancelAll: @Sendable () async -> Void = {}
}

extension NotificationClient: DependencyKey {
    static var liveValue: Self {
        .init(
            requestPermission: {
                do {
                    let granted = try await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])
                    notifLogger.info("Notification permission: \(granted ? "granted" : "denied")")
                    return granted
                } catch {
                    notifLogger.error("Notification permission error: \(error.localizedDescription)")
                    return false
                }
            },
            scheduleDaily: {
                let center = UNUserNotificationCenter.current()

                // Remove old scheduled notifications before re-scheduling
                center.removeAllPendingNotificationRequests()

                let schedules: [(id: String, title: String, body: String, hour: Int, minute: Int)] = [
                    ("morning-kickoff", "Morning Kickoff", "Before the day gets its hooks in you.", 7, 30),
                    ("mid-day-touchstone", "Mid-Day Touchstone", "Meetings done. How are you actually doing?", 12, 0),
                    ("days-end", "Day's End", "Close the loop before you close the laptop.", 17, 30),
                ]

                for schedule in schedules {
                    let content = UNMutableNotificationContent()
                    content.title = schedule.title
                    content.body = schedule.body
                    content.sound = .default
                    content.userInfo = ["download_type_id": schedule.id]
                    content.categoryIdentifier = "download-reminder"

                    // Weekdays only (Mon-Fri)
                    for weekday in 2...6 {
                        var dateComponents = DateComponents()
                        dateComponents.hour = schedule.hour
                        dateComponents.minute = schedule.minute
                        dateComponents.weekday = weekday

                        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                        let request = UNNotificationRequest(
                            identifier: "\(schedule.id)-\(weekday)",
                            content: content,
                            trigger: trigger
                        )

                        center.add(request) { error in
                            if let error {
                                notifLogger.error("Failed to schedule \(schedule.id)-\(weekday): \(error.localizedDescription)")
                            }
                        }
                    }

                    notifLogger.info("Scheduled \(schedule.id) at \(schedule.hour):\(String(format: "%02d", schedule.minute)) weekdays")
                }
            },
            cancelAll: {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                notifLogger.info("All scheduled notifications cancelled")
            }
        )
    }
}

extension DependencyValues {
    var notifications: NotificationClient {
        get { self[NotificationClient.self] }
        set { self[NotificationClient.self] = newValue }
    }
}
