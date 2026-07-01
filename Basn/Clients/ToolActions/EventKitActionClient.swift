import EventKit
import Foundation
import BasinShared
import os

private let log = Logger(subsystem: "com.lyra.basn", category: "eventkit")

/// Executes Apple Calendar and Reminders actions via EventKit.
/// Only available on macOS (EventKit is present on iOS too, but this app targets macOS first).
enum EventKitActionClient {
    private static let store = EKEventStore()

    // MARK: - Entry point

    static func execute(
        action: PlannedAction,
        handler: String
    ) async -> ActionResult {
        switch handler {
        case "eventkit_create_reminder":
            return await createReminder(action: action)
        case "eventkit_create_event":
            return await createEvent(action: action)
        default:
            return ActionResult(actionID: action.id, success: false, error: "Unknown EventKit handler: \(handler)")
        }
    }

    // MARK: - Authorization

    private static func requestAccess(to entityType: EKEntityType) async -> Bool {
        do {
            if entityType == .reminder {
                return try await store.requestFullAccessToReminders()
            } else {
                // Write-only is sufficient — we only create events, never read them.
                return try await store.requestWriteOnlyAccessToEvents()
            }
        } catch {
            log.error("EventKit access denied: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Reminders

    private static func createReminder(action: PlannedAction) async -> ActionResult {
        guard await requestAccess(to: .reminder) else {
            return ActionResult(actionID: action.id, success: false,
                                error: "Reminders access denied. Allow Basn in System Settings → Privacy & Security → Reminders.")
        }

        let params = action.parameters
        guard let title = params["title"] as? String, !title.isEmpty else {
            return ActionResult(actionID: action.id, success: false, error: "Reminder title is required")
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title

        if let notes = params["notes"] as? String { reminder.notes = notes }

        // Due date
        if let dueDateStr = params["due_date"] as? String,
           let dueDate = ISO8601DateFormatter().date(from: dueDateStr) {
            var components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.dueDateComponents = components
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }

        // Priority
        switch (params["priority"] as? String ?? "none") {
        case "high":   reminder.priority = 1
        case "medium": reminder.priority = 5
        case "low":    reminder.priority = 9
        default:       reminder.priority = 0
        }

        // Calendar (list)
        if let listName = params["list_name"] as? String {
            reminder.calendar = store.calendars(for: .reminder)
                .first(where: { $0.title.caseInsensitiveCompare(listName) == .orderedSame })
                ?? store.defaultCalendarForNewReminders()
        } else {
            reminder.calendar = store.defaultCalendarForNewReminders()
        }

        do {
            try store.save(reminder, commit: true)
            log.info("Created reminder: \(reminder.title ?? "")")
            return ActionResult(actionID: action.id, success: true,
                                message: "Reminder '\(title)' created in Reminders")
        } catch {
            log.error("Failed to save reminder: \(error.localizedDescription)")
            return ActionResult(actionID: action.id, success: false, error: error.localizedDescription)
        }
    }

    // MARK: - Calendar events

    private static func createEvent(action: PlannedAction) async -> ActionResult {
        guard await requestAccess(to: .event) else {
            return ActionResult(actionID: action.id, success: false,
                                error: "Calendar access denied. Allow Basn in System Settings → Privacy & Security → Calendars.")
        }

        let params = action.parameters
        guard let title = params["title"] as? String, !title.isEmpty else {
            return ActionResult(actionID: action.id, success: false, error: "Event title is required")
        }
        let formatter = ISO8601DateFormatter()

        let startDate: Date
        if let startStr = params["start_time"], let parsed = formatter.date(from: startStr) {
            startDate = parsed
        } else {
            // Default: tomorrow at 9am local time
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.day = (comps.day ?? 0) + 1
            comps.hour = 9; comps.minute = 0; comps.second = 0
            startDate = Calendar.current.date(from: comps) ?? Date().addingTimeInterval(86400)
        }

        let endDate: Date
        if let endStr = params["end_time"], let parsed = formatter.date(from: endStr) {
            endDate = parsed
        } else {
            endDate = startDate.addingTimeInterval(3600)
        }

        let event = EKEvent(eventStore: store)
        event.title     = title
        event.startDate = startDate
        event.endDate   = endDate
        if let notes = params["notes"] as? String { event.notes = notes }
        if let location = params["location"] as? String { event.location = location }
        if let urlStr = params["url"] as? String, let url = URL(string: urlStr) { event.url = url }

        // Calendar
        if let calName = params["calendar_name"] as? String {
            event.calendar = store.calendars(for: .event)
                .first(where: { $0.title.caseInsensitiveCompare(calName) == .orderedSame })
                ?? store.defaultCalendarForNewEvents
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
            log.info("Created calendar event: \(event.title ?? "")")
            return ActionResult(actionID: action.id, success: true,
                                message: "Event '\(title)' created in Calendar")
        } catch {
            log.error("Failed to save calendar event: \(error.localizedDescription)")
            return ActionResult(actionID: action.id, success: false, error: error.localizedDescription)
        }
    }
}
