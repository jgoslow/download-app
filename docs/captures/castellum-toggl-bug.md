---
type: log
subtype: capture
status: reference
created: 2026-06-25
updated: 2026-06-25
source: session
distilled: true
tags: [capture, castellum, toggl, bug]
---

## Castellum → Toggl tool_use bug

**Symptom:** When a capture reaches Castellum (bypassing HeuristicRouter) and Toggl is the intended tool, Claude returns a text explanation ("I don't have a direct Toggl integration tool available in my current toolkit") rather than a `tool_use` block. No PlannedAction is produced, so nothing executes.

**Observed:** 2026-06-25 during fixture capture. Capture text: "Log 1 hour of work time on Basn project from the past hour". Castellum responded with a text-only block including manual instructions for the user.

**Root cause:** Unknown. Two candidates:
1. Toggl tool schema is not being passed correctly to Claude in the `analyzeAndPlan` prompt
2. Haiku (the model used) is declining to call the Toggl tool for time-logging requests

**Why this matters:** Any multi-intent capture involving Toggl + another tool (e.g. Toggl + Jira) goes to Castellum (HeuristicRouter returns nil for 2 matches). If Castellum can't call Toggl, the time-logging half silently fails.

**Workaround:** HeuristicRouter handles single-intent Toggl captures (log time for X, start timer for X) and correctly bypasses Castellum entirely. Multi-intent captures are broken.

**How to apply:** Before adding new Castellum path test cases involving Toggl, investigate and fix this bug. The `toggl-jira-multi-intent` fixture uses a synthetic rawContentBlock that assumes Toggl tool_use works — it tests the parser, not Claude's live behavior.
