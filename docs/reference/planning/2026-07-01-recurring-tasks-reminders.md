# Recurring Tasks & Reminders

**Status:** Planning only — no implementation yet  
**Context:** Discussed 2026-07-01 after noticing "weekly reminder" was created without recurrence

## Problem

When a user says "set a weekly reminder to check the garden", Basn creates a one-time reminder with no recurrence rule. The repeat intent is not captured, parsed, or supported in the action parameters.

## Requirements

### 1. Parameter support

The `create_reminder` action needs a `recurrence_rule` parameter. The schema should accept:

| Value | Meaning |
|---|---|
| `daily` | Repeats every day |
| `weekly` | Repeats every week (same day of week as start date) |
| `weekdays` | Mon–Fri |
| `monthly` | Same day of month |
| `"RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"` | Full iCalendar RRULE (for complex schedules) |

For `create_event`, add `recurrence_rule` as well (e.g., "block every Monday at 9am").

### 2. EventKit support

`EventKitActionClient.create_reminder` currently uses `EKReminder`. Add `reminder.recurrenceRules` when `recurrence_rule` is set:

```swift
if let rule = params["recurrence_rule"] {
    let freq: EKRecurrenceFrequency
    switch rule {
    case "daily":    freq = .daily
    case "weekly":   freq = .weekly
    case "monthly":  freq = .monthly
    default:         freq = .weekly
    }
    reminder.recurrenceRules = [EKRecurrenceRule(recurrenceWith: freq, interval: 1, end: nil)]
}
```

### 3. Clarification prompt

`create_reminder` should add `recurrence_rule` to its "nice to have" prompt set. If the transcript says "every day", "weekly", "every morning", etc., extract it automatically. If unclear, ask: "Should this repeat? If so, how often?"

### 4. Castellum / router updates

Add to the system prompt rule list:
- When "every [day/week/month]", "daily", "recurring", "every morning", or "routine" are mentioned in context with a reminder, set `recurrence_rule` accordingly.
- Natural language mappings: "every day" → `daily`, "every week" → `weekly`, "every morning" → `daily`, "every [weekday]" → `weekly`.

## Related

- [[2026-07-01-action-clarification-prompts]] — recurrence should be a clarification prompt field for `create_reminder`
- `EventKitActionClient.swift` — implementation location
- `apple-reminders.json` — add `recurrence_rule` to parameters schema
