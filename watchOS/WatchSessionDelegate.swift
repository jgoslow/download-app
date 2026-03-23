//
//  WatchSessionDelegate.swift
//  Basin (watchOS)
//
//  WatchConnectivity bridge between the iPhone app and the Watch.
//  Responsibilities:
//  - Receive Flow schedule from iPhone → write to shared container
//  - Forward "Start" taps from Watch to iPhone via WatchConnectivity message
//  - Relay snooze/skip actions back to iPhone for logging
//
//  STATUS: Stub — watchOS target not yet added to Xcode project.
//  See SETUP.md for Xcode configuration steps.
//

// import Foundation
// import WatchConnectivity
//
// final class WatchSessionDelegate: NSObject, WCSessionDelegate, Sendable {
//     static let shared = WatchSessionDelegate()
//
//     func activate() {
//         guard WCSession.isSupported() else { return }
//         WCSession.default.delegate = self
//         WCSession.default.activate()
//     }
//
//     // MARK: - WCSessionDelegate
//
//     func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
//
//     func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
//         // iPhone sent updated flows.json → save to shared container
//         // The NotificationScheduler reads from here to schedule reminders
//     }
//
//     func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
//         // Handle deep-link relay: "openType" → forward to iPhone app
//     }
// }
