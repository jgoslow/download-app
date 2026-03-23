//
//  NotificationClient.swift
//  Basin
//
//  Schedules daily reminders for capture sessions.
//  Requires notification permission (prompted on first schedule).
//

import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import HexCore
import SwiftData
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

                // Read flows with reminders enabled from SwiftData
                let context = ModelContext(HexApp.modelContainer)
                let descriptor = FetchDescriptor<FlowDefinition>(
                    predicate: #Predicate { $0.scheduleReminderEnabled }
                )
                let flows = (try? context.fetch(descriptor)) ?? []

                let weekdayMap: [String: Int] = [
                    "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7, "sun": 1
                ]

                for flow in flows {
                    guard let timeStr = flow.scheduleReminderTime else { continue }
                    let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                    guard parts.count == 2 else { continue }
                    let hour = parts[0]
                    let minute = parts[1]

                    let title = flow.scheduleNotificationTitle.isEmpty ? flow.name : flow.scheduleNotificationTitle
                    let body = flow.scheduleNotificationBody

                    let days = flow.scheduleDays.compactMap { weekdayMap[$0] }
                    // Default to weekdays if no days specified
                    let scheduleDays = days.isEmpty ? Array(2...6) : days

                    for weekday in scheduleDays {
                        let content = UNMutableNotificationContent()
                        content.title = title
                        content.body = body
                        content.sound = .default
                        content.userInfo = ["flow_id": flow.id]
                        content.categoryIdentifier = "basin-reminder"

                        var dateComponents = DateComponents()
                        dateComponents.hour = hour
                        dateComponents.minute = minute
                        dateComponents.weekday = weekday

                        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                        let request = UNNotificationRequest(
                            identifier: "\(flow.id)-\(weekday)",
                            content: content,
                            trigger: trigger
                        )

                        center.add(request) { error in
                            if let error {
                                notifLogger.error("Failed to schedule \(flow.id)-\(weekday): \(error.localizedDescription)")
                            }
                        }
                    }

                    notifLogger.info("Scheduled \(flow.id) at \(hour):\(String(format: "%02d", minute))")
                }

                if flows.isEmpty {
                    notifLogger.info("No flows with reminders enabled — no notifications scheduled")
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
