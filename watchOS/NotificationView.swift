//
//  NotificationView.swift
//  Download (watchOS)
//
//  Shown when a scheduled reminder fires on Apple Watch.
//  Displays the DownloadType name and notification body, with 5 action buttons:
//  Start / +5m / +10m / +1h / Skip
//
//  Tapping "Start" opens the iPhone app to the selected DownloadType via deep link.
//  Snooze buttons reschedule the notification after the selected delay.
//  Skip dismisses and logs the session as skipped.
//
//  STATUS: Stub — watchOS target not yet added to Xcode project.
//  See SETUP.md for Xcode configuration steps.
//

// import SwiftUI
// import UserNotifications
// import WatchKit
//
// struct NotificationView: View {
//     let downloadTypeName: String
//     let notificationBody: String
//     let snoozeOptionsMinutes: [Int]
//
//     var body: some View {
//         VStack(alignment: .leading, spacing: 8) {
//             Text(downloadTypeName)
//                 .font(.headline)
//             Text(notificationBody)
//                 .font(.body)
//                 .foregroundStyle(.secondary)
//         }
//     }
// }
//
// // MARK: - Notification category registration
// //
// // Call this on app launch to register the action buttons.
// // The "download-reminder" category must match the category ID set by NotificationScheduler.
// //
// // func registerNotificationCategory() {
// //     let start = UNNotificationAction(identifier: "start", title: "Start", options: .foreground)
// //     let snooze5 = UNNotificationAction(identifier: "snooze5", title: "+5m", options: [])
// //     let snooze10 = UNNotificationAction(identifier: "snooze10", title: "+10m", options: [])
// //     let snooze60 = UNNotificationAction(identifier: "snooze60", title: "+1h", options: [])
// //     let skip = UNNotificationAction(identifier: "skip", title: "Skip", options: .destructive)
// //
// //     let category = UNNotificationCategory(
// //         identifier: "download-reminder",
// //         actions: [start, snooze5, snooze10, snooze60, skip],
// //         intentIdentifiers: []
// //     )
// //     UNUserNotificationCenter.current().setNotificationCategories([category])
// // }
