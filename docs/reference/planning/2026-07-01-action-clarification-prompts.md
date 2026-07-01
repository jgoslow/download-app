# Action Clarification Prompts

**Status:** Planned — not yet implemented  
**Priority:** High — blocks reliable action execution

## Problem

When Castellum or HeuristicRouter identifies an action (e.g. schedule_event), it may not have enough information to execute it correctly. Currently, the app proceeds with defaults (tomorrow at 9 AM, no invitees) or uses the raw transcript as the event title. This leads to incorrect actions being created silently.

## Requirement

Before executing any action, Basn should check whether the minimum required parameters are present and, if not, surface a clarification prompt to the user. The user responds (ideally by voice or text), and execution proceeds with the confirmed details.

## Minimum Required Details Per Capability

| Capability | Required | Optional |
|---|---|---|
| `schedule_event` | date, time range (start + end), title | invitees (default: user only), location, calendar |
| `create_task` | title | due date, priority, list |
| `log_time` | description, duration | project, billable flag |
| `send_message` | recipient, message body | — |
| `send_email` | recipient (to), subject, body | cc, attachments |
| `capture_note` | body | title |
| `create_document` | title | content, folder |

## UX Flow

1. Routing produces a `PlannedAction` with available parameters
2. Before showing the execution plan, check if any required params are missing
3. If missing: show a clarification sheet with pre-filled values (from what was extracted) and blank fields for what's missing
4. User fills in / confirms / edits
5. Plan is updated and execution sheet shown (or auto-executed if all confirmed)

## Clarification UI

The sheet should feel like a quick-fill form, not a modal. Each field should have a clear label and a voice-input affordance (tap to speak a correction). For scheduling:

- Title: short text field (pre-filled with extracted title if available)
- Date: date picker (pre-filled with detected date if available, otherwise "today / tomorrow / pick")
- Time range: two time pickers — Start and End (pre-filled if detected, else defaults to next hour for 1hr)
- Invitees: people picker (default = "Just me") 

The sheet is dismissable (skip confirmation → execute with current params) but should encourage completion.

## Integration Points

- `IOSExecutionPlanView` — show clarification sheet before the main plan view if params are missing
- `PlannedAction` — may need a `missingParams: [String]` field or a `validate()` method
- `CapabilityMatcher` / routers — can set `highConfidence: false` when params are clearly missing

## Context

Discussed session 2026-07-01. User noted that the current scheduling AM/PM and "tomorrow" logic produces wrong times silently. Clarification prompts would catch this before the action is committed. The FoundationModels and LightweightRouter system prompts have been updated with AM/PM rules (7–12 = AM, 1–6 = PM, today-after-now constraint) as a partial fix, but the definitive solution is user confirmation.

Clarification prompts are also important for:
- Events with invitees (who to add?)
- Reminders with relative due dates ("next week" → which day?)
- Messages/emails where the recipient is ambiguous ("my team" → which people?)
