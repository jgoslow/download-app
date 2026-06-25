# Create all scenario fixtures and wire up tests

## Context

Speech-to-text quality makes voice-recording fixtures unreliable right now. All fixtures will be created as hand-authored JSON (synthetic) so tests can run immediately. Heuristic fixtures are fully deterministic. Castellum fixtures use realistic synthetic `rawContentBlocks` to test the parser layer — not Claude's live output, but the exact format Claude produces (verified against the real recorded response from the earlier session). Wave is excluded (not connected).

## Parser format (from CastellumResponseParser)

- Tool name convention: `<toolID>_<actionType>` — split on first `_` only
- Text block: prose + JSON blob (`summary`, `mood_tag`, `tasks`, `routing`, `delegations`, `integrations`, `prompts_addressed`)
- tool_use block: `{ "type": "tool_use", "name": "jira_create_issue", "input": { ... } }`
- Multiple tool_use blocks = multiple PlannedActions

## Files to create

### Heuristic fixtures (new)

**`toggl-start-timer.json`**
```json
rawText: "start timer for Basn iOS work"
connectedToolIDs: ["toggl"]
routedVia: heuristic
expected: create_time_entry, description: "Basn iOS work", duration_minutes: "30"
```

### Castellum fixtures (synthetic, parser-testing)

**`jira-only-ticket.json`**
```
rawText: "Create a ticket for the login screen crash on iOS"
connectedToolIDs: ["jira"]
rawContentBlocks: text(SessionAnalysis) + tool_use(jira_create_issue)
expected: jira/create_issue, summary: "Login screen crash on iOS", issue_type: "Bug"
```

**`jira-slack-standup.json`**
```
rawText: "Create a Jira ticket for the auth refactor and post a standup update to Slack"
connectedToolIDs: ["jira", "slack"]
rawContentBlocks: text(SessionAnalysis) + tool_use(jira_create_issue) + tool_use(slack_send_message)
expected: jira/create_issue + slack/send_message
```

**`toggl-jira-multi-intent.json`**
```
rawText: "Log 1 hour on the auth bug fix and create a Jira ticket to track it"
connectedToolIDs: ["jira", "toggl"]
routedVia: castellum  (HeuristicRouter returns nil — 2 intents)
rawContentBlocks: text(SessionAnalysis) + tool_use(toggl_create_time_entry) + tool_use(jira_create_issue)
expected: toggl/create_time_entry + jira/create_issue
```

**`no-actions-journal.json`**
```
rawText: "Today was a good day, finished the iOS pipeline design, feeling good about the direction"
connectedToolIDs: ["jira", "toggl", "slack"]
rawContentBlocks: text(SessionAnalysis only, no tool_use)
expected: [] (empty — tests graceful no-op)
```

**`google-calendar-event.json`**
```
rawText: "Schedule a 30 minute call with Diego tomorrow afternoon"
connectedToolIDs: ["google"]
rawContentBlocks: text(SessionAnalysis) + tool_use(google_create_event)
expected: google/create_event, summary: "Call with Diego"
```

## Files to modify

**`HexCore/Tests/BasnCoreTests/CaptureScenarioTests.swift`**
- Add active `@Test` for each fixture above
- Pattern for heuristic: call `HeuristicRouter.route`, assert actions
- Pattern for Castellum: call `CastellumResponseParser.parse(scenario.toContentBlocks(), captureID: "test")`, assert analysis non-empty + actions
- `waveExpense` stays commented (not connected)

## Verification

```bash
cd HexCore && swift test
```

All 7 tests should pass (1 existing + 1 new heuristic + 5 Castellum).
