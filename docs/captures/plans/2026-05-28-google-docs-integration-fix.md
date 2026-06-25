# Fix Google Docs integration pipeline + improve action display

## Context

When a user says "create a new doc in Google", the Castellum planner silently returns an empty plan because the "docs" integration is not wired anywhere in the pipeline — even though `google.json` has a `create_document` action and Google is connected. The screenshot shows a "notes" routing tag but no executed actions, which is the symptom.

There are three root causes in the pipeline plus a missing entry in `google.json`, and separately the action display in `ExecutionPlanView` needs clearer tool attribution and expandable detail.

---

## Bugs to fix

### 1. `docs` missing from `SessionAnalysis.Integration` enum
**File**: `HexCore/Sources/HexCore/Models/SessionAnalysis.swift:32-40`

Add `.docs` case. Without it, Claude can never return `"docs"` in the integrations array — the type simply doesn't exist.

```swift
public enum Integration: String, Codable, Sendable, CaseIterable {
    case jira
    case toggl
    case slack
    case email
    case calendar
    case docs      // ← add
    case wave
    case github
}
```

### 2. System prompt doesn't mention "docs" as a possible integration
**File**: `Hex/Clients/AnthropicClient.swift:105`

Update the integrations list in the system prompt so Claude knows to emit `"docs"` when a Google Doc action is requested:

```
"integrations": ["jira", "toggl", "slack", "email", "calendar", "docs", "wave", "github"],
```

Also update the free-text guidance line (around line 112) to mention docs explicitly:
> `"docs" if a Google Doc needs to be created or edited`

### 3. `integrationToToolID` map missing `"docs"` entry
**File**: `Hex/Clients/CastellumPlannerClient+Live.swift:25-29`

Add `"docs": "google"` so the planner routes docs-tagged sessions to the Google tool definition:

```swift
let integrationToToolID: [String: String] = [
    "calendar": "google", "email": "google", "docs": "google",
    "jira": "jira", "slack": "slack", "toggl": "toggl",
    "github": "github", "wave": "wave"
]
```

### 4. `create_document` (and `append_text`) missing from `workflows` in `google.json`
**File**: `Hex/Resources/Data/tool-definitions/google.json:185-188`

```json
"workflows": {
    "create-event": "create_event",
    "write-email": "send_email",
    "create-doc": "create_document",
    "append-doc": "append_text"
}
```

---

## UI enhancements

### 5. Add `docs` integration icon in HomeView
**File**: `Hex/Features/Home/HomeView.swift:467-477`

Add `.docs` case to `integrationIcon()`:
```swift
case .docs: return "doc.text"
```

### 6. Fix `toolIcon()` for "google" in ExecutionPlanView
**File**: `Hex/Features/Castellum/ExecutionPlanView.swift:279-290`

Currently `toolIcon("google")` falls through to `"wrench"`. Add:
```swift
case "google": return "doc.text"
```
(or differentiate by `actionType` if needed: `create_event` → `calendar`, `send_email` → `envelope`, otherwise `doc.text`)

### 7. Show tool service name + expandable parameter detail in action rows
**File**: `Hex/Features/Castellum/ExecutionPlanView.swift`

Each `actionRow` currently shows just the action label. Changes:

- Below the label, show a caption with the tool's display name (load from `ToolDefinitionSpec.name` via `ToolDefinitionLoader.load(action.toolID)?.name ?? action.toolID.capitalized`).
- Wrap each action row in a `DisclosureGroup` so tapping reveals a parameter list (key: value pairs from `action.parameters`). This satisfies the "clicking it should reveal more detail" requirement.

The disclosure should be collapsed by default and only shown when there are parameters.

---

## Verification

1. Say into Basin: "Create a new doc in Google, put it in the accounts folder for Lyra, and note that I'm developing Basin."
2. After transcription, analysis should show `integrations: ["docs"]` and `routing: ["notes"]`.
3. Castellum should plan one action: `google / create_document` with `title` parameter filled.
4. `ExecutionPlanView` should show the row with "Google" as a service caption; tapping should reveal `title: "..."`.
5. Executing should call `https://docs.googleapis.com/v1/documents` and create the doc.
