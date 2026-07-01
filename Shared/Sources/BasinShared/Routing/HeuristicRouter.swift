import Foundation

/// Local pattern-matching router that runs before any Claude call.
///
/// For clear single-intent captures with a connected tool match, returns
/// pre-built actions so the Anthropic call is skipped entirely.
/// Returns nil for anything ambiguous — falls through to CastellumClient.
///
/// On iOS, this is called on each `onSentenceComplete` callback during recording.
/// On macOS (current), it runs once on the full transcript at recording end.
/// Both paths use the same API; only the timing differs.
public struct HeuristicRouter {

    public static func route(transcript: String, connectedToolIDs: Set<String>) -> [PlannedAction]? {
        let lower = transcript.lowercased()
        var actions: [PlannedAction] = []

        if connectedToolIDs.contains("toggl") {
            if let action = checkToggl(lower, original: transcript) { actions.append(action) }
        }
        if connectedToolIDs.contains("apple-reminders") {
            if let action = checkAppleReminders(lower, original: transcript) { actions.append(action) }
        }
        if connectedToolIDs.contains("apple-calendar") {
            if let action = checkAppleCalendar(lower, original: transcript) { actions.append(action) }
        }
        if connectedToolIDs.contains("apple-notes") {
            if let action = checkAppleNotes(lower, original: transcript) { actions.append(action) }
        }
        if connectedToolIDs.contains("apple-mail") {
            if let action = checkAppleMail(lower, original: transcript) { actions.append(action) }
        }
        if connectedToolIDs.contains("apple-messages") {
            if let action = checkAppleMessages(lower, original: transcript) { actions.append(action) }
        }
        if connectedToolIDs.contains("apple-maps") {
            if let action = checkAppleMaps(lower, original: transcript) { actions.append(action) }
        }

        // Only bypass Claude when exactly one clear action is found.
        // Multi-intent or ambiguous captures go through Castellum.
        guard actions.count == 1 else { return nil }
        return actions
    }

    // MARK: - Pattern matchers (extend as native tools are added)

    private static func checkToggl(_ lower: String, original: String) -> PlannedAction? {
        let triggers = ["start timer", "start a timer", "log time for", "track time for", "track time on"]
        guard let trigger = triggers.first(where: { lower.contains($0) }) else { return nil }

        var description = original
        if let range = lower.range(of: trigger) {
            var after = String(original[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            // Strip a leading "for" left over from triggers that don't include it (e.g. "start timer for X")
            if after.lowercased().hasPrefix("for ") {
                after = String(after.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            }
            if !after.isEmpty { description = after }
        }

        let minutes = parseDurationMinutes(from: lower)

        return PlannedAction(
            toolID: "toggl",
            actionType: "create_time_entry",
            label: "Log time: \(description.prefix(60))",
            parameters: [
                "description": String(description.prefix(200)),
                "duration_minutes": "\(minutes)"
            ]
        )
    }

    // MARK: - Apple-native matchers

    private static func checkAppleReminders(_ lower: String, original: String) -> PlannedAction? {
        let triggers = [
            "remind me to", "remind me about", "remind me",
            "add a reminder to", "add a reminder for", "add a reminder",
            "add reminder to", "add reminder for",
            "set a reminder to", "set a reminder for", "set a reminder",
            "create a reminder to", "create a reminder for", "create a reminder",
            "don't let me forget", "don't forget to",
        ]
        guard let trigger = triggers.first(where: { lower.contains($0) }) else { return nil }

        var title = original
        if let range = lower.range(of: trigger) {
            let after = String(original[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !after.isEmpty { title = after }
        }

        return PlannedAction(
            toolID: "apple-reminders",
            actionType: "create_reminder",
            label: "Remind: \(title.prefix(60))",
            parameters: ["title": String(title.prefix(200))]
        )
    }

    private static func checkAppleCalendar(_ lower: String, original: String) -> PlannedAction? {
        let triggers = [
            // Specific-form first (avoids overly broad matches consuming too-short phrases)
            "schedule a meeting", "schedule a call", "schedule a session", "schedule a lunch",
            "schedule a dinner", "schedule a coffee", "schedule a catch-up", "schedule a 1:1",
            "schedule time", "schedule an appointment",
            "add an event", "add a meeting", "add a call", "add a calendar event",
            "create an event", "create a meeting", "create a calendar event",
            "put on my calendar", "add to my calendar", "add to the calendar",
            "block time for", "block off time for", "block some time for",
            "put a hold on", "hold on my calendar",
            // Broad "schedule [something]" — only when "schedule" is followed by meaningful content
            "let's schedule", "we should schedule", "can you schedule", "i need to schedule",
        ]
        guard let trigger = triggers.first(where: { lower.contains($0) }) else { return nil }

        var eventText = original
        if let range = lower.range(of: trigger) {
            var after = String(original[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if after.lowercased().hasPrefix("for ") { after = String(after.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
            if after.lowercased().hasPrefix("with ") { after = String(after) } // keep "with X"
            if !after.isEmpty { eventText = after }
        }

        // Extract dates and derive a clean title by stripping the time phrase
        let (startDate, endDate, dateRange) = parseEventDates(from: eventText)
        var title = eventText
        if let range = dateRange {
            var after = String(eventText[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if after.lowercased().hasPrefix("to ") { after = String(after.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            let before = String(eventText[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            title = after.isEmpty ? before : after
            if title.isEmpty { title = eventText }
        }

        let formatter = ISO8601DateFormatter()
        return PlannedAction(
            toolID: "apple-calendar",
            actionType: "create_event",
            label: "Event: \(title.prefix(60))",
            parameters: [
                "title": String(title.prefix(200)),
                "start_time": formatter.string(from: startDate),
                "end_time": formatter.string(from: endDate)
            ]
        )
    }

    /// Extracts start/end dates from a natural-language event description.
    /// Returns (start, end, matchRange) where matchRange covers the full date-time
    /// expression in `text` so callers can strip it cleanly from the event title.
    /// Tries regex patterns first (most reliable for range expressions), then falls
    /// back to NSDataDetector, then a default of tomorrow at 9 AM.
    private static func parseEventDates(from text: String) -> (start: Date, end: Date, matchRange: Range<String.Index>?) {
        let cal = Calendar.current
        let now = Date()

        // --- 1. "between N and N" with optional date prefix ---
        // e.g. "tomorrow between 3 and 5", "between 2pm and 4pm"
        let betweenPat = #"(?:(tomorrow|today)\s+)?between\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s+and\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        if let regex = try? NSRegularExpression(pattern: betweenPat, options: .caseInsensitive),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let fullRange = Range(m.range, in: text) {

            let dateRef = rangeString(m, at: 1, in: text)?.lowercased()
            let base = dateRef == "today" ? now : (cal.date(byAdding: .day, value: 1, to: now) ?? now)

            let startH  = Int(rangeString(m, at: 2, in: text) ?? "9") ?? 9
            let startMin = Int(rangeString(m, at: 3, in: text) ?? "0") ?? 0
            let startAP  = rangeString(m, at: 4, in: text)?.lowercased()
            let endH    = Int(rangeString(m, at: 5, in: text) ?? "10") ?? 10
            let endMin   = Int(rangeString(m, at: 6, in: text) ?? "0") ?? 0
            let endAP    = rangeString(m, at: 7, in: text)?.lowercased()

            var sh = resolveHour(startH, ampm: startAP)
            var eh = resolveHour(endH,   ampm: endAP ?? startAP)
            if eh <= sh { eh += 12 } // "between 11 and 1" → 11 AM – 1 PM

            let start = cal.date(bySettingHour: sh, minute: startMin, second: 0, of: base) ?? base
            let end   = cal.date(bySettingHour: eh, minute: endMin,   second: 0, of: base) ?? base
            return (start, end, fullRange)
        }

        // --- 2. "at N" or "at N:MM am/pm" with optional date prefix ---
        let atPat = #"(?:(tomorrow|today)\s+)?at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        if let regex = try? NSRegularExpression(pattern: atPat, options: .caseInsensitive),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let fullRange = Range(m.range, in: text) {

            let dateRef = rangeString(m, at: 1, in: text)?.lowercased()
            let base = dateRef == "today" ? now : (cal.date(byAdding: .day, value: 1, to: now) ?? now)
            let h   = Int(rangeString(m, at: 2, in: text) ?? "9") ?? 9
            let min = Int(rangeString(m, at: 3, in: text) ?? "0") ?? 0
            let ap  = rangeString(m, at: 4, in: text)?.lowercased()
            let sh  = resolveHour(h, ampm: ap)
            let start = cal.date(bySettingHour: sh, minute: min, second: 0, of: base) ?? base
            return (start, start.addingTimeInterval(3600), fullRange)
        }

        // --- 3. NSDataDetector fallback (handles named days, relative dates, etc.) ---
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = detector.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            if matches.count >= 2,
               let d1 = matches[0].date, let d2 = matches[1].date,
               let r1 = Range(matches[0].range, in: text), let r2 = Range(matches[1].range, in: text),
               d1 != d2 {
                return (min(d1, d2), max(d1, d2), r1.lowerBound..<r2.upperBound)
            }
            if let match = matches.first, let date = match.date {
                let duration = match.duration > 0 ? match.duration : 3600
                return (date, date.addingTimeInterval(duration), Range(match.range, in: text))
            }
        }

        // --- 4. Default: tomorrow at 9 AM ---
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.day = (comps.day ?? 0) + 1
        comps.hour = 9; comps.minute = 0; comps.second = 0
        let start = cal.date(from: comps) ?? now.addingTimeInterval(86400)
        return (start, start.addingTimeInterval(3600), nil)
    }

    /// Extract a capture group string from an NSTextCheckingResult.
    private static func rangeString(_ match: NSTextCheckingResult, at group: Int, in text: String) -> String? {
        guard match.numberOfRanges > group,
              match.range(at: group).location != NSNotFound,
              let range = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[range])
    }

    /// Apply AM/PM rules: explicit qualifier wins; otherwise 7–12 = AM, 1–6 = PM.
    private static func resolveHour(_ h: Int, ampm: String?) -> Int {
        if let ap = ampm {
            if ap == "pm" && h < 12 { return h + 12 }
            if ap == "am" && h == 12 { return 0 }
            return h
        }
        if h >= 1 && h <= 6 { return h + 12 } // default PM
        return h
    }

    private static func checkAppleNotes(_ lower: String, original: String) -> PlannedAction? {
        let triggers = ["take a note", "jot this down", "jot down", "write a note", "note that", "make a note"]
        guard let trigger = triggers.first(where: { lower.contains($0) }) else { return nil }

        var body = original
        if let range = lower.range(of: trigger) {
            var after = String(original[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if after.lowercased().hasPrefix("about ") { after = String(after.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            if !after.isEmpty { body = after }
        }

        // Use first sentence or first 60 chars as title
        let sentences = body.components(separatedBy: ". ")
        let title = String((sentences.first ?? body).prefix(60))

        return PlannedAction(
            toolID: "apple-notes",
            actionType: "create_note",
            label: "Note: \(title.prefix(60))",
            parameters: [
                "title": title,
                "body": String(body.prefix(2000))
            ]
        )
    }

    private static func checkAppleMail(_ lower: String, original: String) -> PlannedAction? {
        // Only match when there's a clear recipient — avoids false positives on
        // "send an update" or "email the team" without a specific address/name.
        let triggers = ["send an email to", "send email to", "email to", "compose an email to"]
        guard let trigger = triggers.first(where: { lower.contains($0) }) else { return nil }

        var recipient = ""
        if let range = lower.range(of: trigger) {
            let after = String(original[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            // Take everything up to "about" or "saying" as the recipient
            let stopWords = [" about ", " saying ", " with subject ", " that "]
            var end = after.endIndex
            for stop in stopWords {
                if let r = after.lowercased().range(of: stop) { end = min(end, r.lowerBound) }
            }
            recipient = String(after[..<end]).trimmingCharacters(in: .whitespaces)
        }

        guard !recipient.isEmpty else { return nil }

        return PlannedAction(
            toolID: "apple-mail",
            actionType: "compose_email",
            label: "Email to: \(recipient.prefix(60))",
            parameters: [
                "to": String(recipient.prefix(200)),
                "subject": "",
                "body": original
            ]
        )
    }

    private static func checkAppleMessages(_ lower: String, original: String) -> PlannedAction? {
        let triggers = ["send a text to ", "send a message to ", "text ", "message ", "imessage "]
        // Require "to" or a name immediately after — avoids matching "text me back"
        guard let trigger = triggers.first(where: { lower.hasPrefix($0) || lower.contains(" \($0)") }) else { return nil }

        let stopWords = [" about ", " saying ", " that ", " to tell ", " asking "]
        let triggerEnd = original.range(of: trigger, options: .caseInsensitive)?.upperBound ?? original.startIndex
        let afterTrigger = String(original[triggerEnd...]).trimmingCharacters(in: .whitespaces)

        var recipientEnd = afterTrigger.endIndex
        for stop in stopWords {
            if let r = afterTrigger.lowercased().range(of: stop) { recipientEnd = min(recipientEnd, r.lowerBound) }
        }
        let recipient = String(afterTrigger[..<recipientEnd]).trimmingCharacters(in: .whitespaces)

        guard !recipient.isEmpty, recipient.split(separator: " ").count <= 4 else { return nil }

        let messageBody: String = {
            var after = afterTrigger
            for stop in stopWords {
                if let r = after.lowercased().range(of: stop) {
                    after = String(after[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            return after.isEmpty ? original : after
        }()

        return PlannedAction(
            toolID: "apple-messages",
            actionType: "send_message",
            label: "Message \(recipient.prefix(40))",
            parameters: [
                "recipient": String(recipient.prefix(200)),
                "body": String(messageBody.prefix(1000))
            ]
        )
    }

    private static func checkAppleMaps(_ lower: String, original: String) -> PlannedAction? {
        let triggers = ["navigate to ", "navigation to ", "get directions to ",
                        "directions to ", "how do i get to ", "take me to "]
        guard let trigger = triggers.first(where: { lower.contains($0) }) else { return nil }

        var destination = original
        if let range = lower.range(of: trigger) {
            let after = String(original[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !after.isEmpty { destination = after }
        }

        return PlannedAction(
            toolID: "apple-maps",
            actionType: "open_location",
            label: "Navigate to \(destination.prefix(60))",
            parameters: ["directions_to": String(destination.prefix(500))]
        )
    }

    /// Extract a duration in minutes from natural-language text.
    /// Falls back to 30 if no duration is found.
    private static func parseDurationMinutes(from lower: String) -> Int {
        // "half an hour" / "half hour"
        if lower.contains("half an hour") || lower.contains("half hour") { return 30 }
        // "an hour" / "a hour" / "one hour"
        if lower.contains("an hour") || lower.contains("a hour") || lower.contains("one hour") { return 60 }

        // "[N] hour(s)" — supports integers and simple decimals like 1.5
        let hourPattern = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*hours?"#)
        if let m = hourPattern?.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let r = Range(m.range(at: 1), in: lower),
           let value = Double(lower[r]) {
            return Int((value * 60).rounded())
        }

        // "[N] minute(s) / min(s)"
        let minPattern = try? NSRegularExpression(pattern: #"(\d+)\s*(?:minutes?|mins?)"#)
        if let m = minPattern?.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let r = Range(m.range(at: 1), in: lower),
           let value = Int(lower[r]) {
            return value
        }

        return 30 // default when no duration mentioned
    }
}
