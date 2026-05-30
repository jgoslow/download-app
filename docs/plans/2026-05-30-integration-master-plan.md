# Basn — Integration Master Plan + Token Efficiency Architecture

**Status:** Execution-ready. Covers Apple native, extended core tools (Toggl/Atlassian/Google/Microsoft 365), server/infra, and non-native third-party apps. Includes token analysis, model tiering, and heuristic routing design. Each section is self-contained enough for a separate agent to implement.

---

## 1. Current Pipeline Analysis

**Two Claude calls per session today:**

```
[Transcript]
    ↓
AnthropicClient.analyze()         ← Call 1: Sonnet 4.6
  system: ~350 tok (hardcoded, "Jonas, Lyra Designs")
  user:   ~750 tok (flow + context + prompts + transcript)
  output: ~200 tok (SessionAnalysis JSON)
    ↓
CastellumPlannerClient.createPlan()  ← Call 2: Sonnet 4.6
  system: ~200 tok (planningSystemPrompt)
  tools:  ~1,500 tok (matched tool schemas)
  user:   ~400 tok (analysis summary + service context)
  output: ~400 tok (tool_use calls)
    ↓
[ExecutionPlan → GenericToolExecutor]
```

**Current token budget per average session:** ~3,875 tokens across 2 API calls.

**Issues to fix immediately (before adding more integrations):**
1. `AnthropicClient.swift` system prompt hardcodes "Jonas, a developer and founder of Lyra Designs" — must be generalized before shipping to users
2. No prompt caching in either call
3. Both calls use Sonnet — no Haiku fallback for simple sessions
4. Call 2's system prompt and tool schemas are rebuilt from scratch each time — no caching

---

## 2. Token Efficiency Architecture

> Goal: ≤1 Claude call per session for the majority of captures. Zero Claude calls for simple, pattern-matched intent. Minimize per-token cost via model tiering.

### 2A. Merge Two Calls into One (Unified CastellumClient)

**Current:** `AnthropicClient` (analyze) → `CastellumPlannerClient` (plan) — 2 round trips.
**Proposed:** Single `CastellumClient` that returns `SessionAnalysis` + `[PlannedAction]` in one call.

**How:** Claude can return both a `text` block (structured JSON) and `tool_use` blocks in the same response. The combined system prompt instructs Claude to:
1. Return a JSON analysis block as a text content block
2. Call the appropriate tool_use functions for each action

**Combined response shape Claude returns:**
```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"summary\": \"...\", \"tasks\": [...], \"routing\": [...], \"mood_tag\": null}"
    },
    { "type": "tool_use", "name": "jira_create_issue", "input": {...} },
    { "type": "tool_use", "name": "apple_reminders_create_reminder", "input": {...} }
  ]
}
```

**Files to change:**
- `Hex/Clients/AnthropicClient.swift` — generalize system prompt, expose as foundation
- `Hex/Clients/CastellumPlannerClient+Live.swift` — merge into unified single-call flow
- New: `Hex/Clients/CastellumClient.swift` — unified client that replaces both
- `HexCore/Sources/BasnCore/Models/ExecutionPlan.swift` — add `analysis: SessionAnalysis?` field to `ExecutionPlan`

**Token savings from merge:** ~600 tokens (eliminates second system prompt + duplicate prompt preamble). More importantly: halves API call count → halves latency.

**Generalized system prompt (replaces hardcoded "Jonas" version):**
```
You are Castellum, Basin's action planner. Basin is a voice capture app that turns spoken ideas, 
tasks, and notes into actions across connected tools.

Given a voice transcript, do two things:
1. Return a JSON analysis as a text block (summary, tasks, routing, integrations, mood_tag, prompts_addressed)
2. Call tool_use functions for each concrete action to take

Rules:
- Only call tools clearly warranted by the transcript content
- Fill parameters as specifically as possible from what was said
- Resolve person names to assignees/recipients when context allows
- For ambiguous routing, prefer the most specific tool available
- Do not speculate — if something is unclear, skip that action
- You may call multiple tools in one response
```

---

### 2B. Local Heuristic Router (Zero-Claude Path)

A `HeuristicRouter` runs **before** any Claude call. If it detects a pattern match with ≥90% confidence, it returns a `PlannedAction` directly without calling Claude.

**New file:** `Hex/Clients/HeuristicRouter.swift`

**Pattern rules (ordered by specificity):**

```swift
// Returns [PlannedAction] or nil (nil = defer to Claude)
struct HeuristicRouter {
    static func route(transcript: String, connectedToolIDs: Set<String>) -> [PlannedAction]? {
        let t = transcript.lowercased()
        
        // Reminder patterns
        if let reminder = extractReminder(t) {
            return [PlannedAction(toolID: "apple-reminders", actionType: "create_reminder", ...)]
        }
        // Quick note
        if t.hasPrefix("note:") || t.hasPrefix("write down") || t.hasPrefix("remember:") {
            return [PlannedAction(toolID: "apple-notes", actionType: "create_note", ...)]
        }
        // Play music
        if t.contains("play") && (t.contains("playlist") || t.contains("music") || t.contains("album")) {
            return [PlannedAction(toolID: "apple-music", actionType: "play_playlist", ...)]
        }
        // Text/message
        if let (recipient, body) = extractMessage(t) {
            return [PlannedAction(toolID: "apple-messages", actionType: "compose_message", ...)]
        }
        return nil  // Falls through to Claude
    }
}
```

**Pattern coverage (estimated bypass rate ~30% of sessions):**

| Pattern | Example | Bypass action |
|---------|---------|---------------|
| `remind me to X [time]` | "remind me to call back tomorrow at 3pm" | `apple-reminders/create_reminder` |
| `add X to [list] list` | "add oat milk to my grocery list" | `apple-reminders/create_reminder` |
| `note: X` / `write down X` | "note: blue header, white text" | `apple-notes/create_note` |
| `text/message [person] X` | "text mom I'm on my way" | `apple-messages/compose_message` |
| `call [person]` | "call Diego back" | `facetime/call_contact` |
| `play [X] playlist/music` | "play my focus playlist" | `apple-music/play_playlist` |
| `open [app]` | "open Xcode" | URL scheme open |
| `set timer for X minutes` | "set timer for 25 minutes" | System timer (URL scheme) |
| `directions to X` | "get directions to the client office" | `apple-maps/get_directions` |

---

### 2C. Model Tiering (Haiku vs Sonnet)

**New file:** `Hex/Clients/SessionComplexityClassifier.swift`

```swift
enum SessionComplexity {
    case simple     // → Haiku 4.5
    case standard   // → Haiku 4.5  
    case complex    // → Sonnet 4.6
}

struct SessionComplexityClassifier {
    static func classify(transcript: String, connectedToolCount: Int) -> SessionComplexity {
        let wordCount = transcript.split(separator: " ").count
        let hasMultiplePeople = // detect multiple person names
        let hasDateMath = // detect relative dates: "next Thursday", "in 3 weeks"
        let toolCount = connectedToolCount
        
        if wordCount < 100 && toolCount <= 2 { return .simple }
        if wordCount > 500 || hasMultiplePeople || hasDateMath || toolCount > 4 { return .complex }
        return .standard
    }
}
```

**Model mapping:**

| Complexity | Model | When |
|-----------|-------|------|
| Simple | `claude-haiku-4-5-20251001` | Short capture (<100 words), ≤2 tools, clear intent |
| Standard | `claude-haiku-4-5-20251001` | Most sessions — Haiku handles well |
| Complex | `claude-sonnet-4-6` | Long meeting recaps, multi-tool, ambiguous intent, date arithmetic |

**Routing heuristic:** Default to Haiku. Escalate to Sonnet only when:
- Transcript word count > 500
- 3+ distinct person names detected
- Contains relative dates requiring calculation
- 4+ connected tools match the session
- Haiku response fails to produce any tool_use (automatic retry on Sonnet)

**Cost difference:** Haiku input is 3.75x cheaper than Sonnet; output is 3.75x cheaper.

---

### 2D. Prompt Caching

Add Anthropic prompt caching (`cache_control: {type: "ephemeral"}`) to:
1. The static system prompt text block
2. All tool definition schemas (set `cache_control` on the last tool in the list)

**Cache TTL:** 5 minutes. Basn sessions are typically spaced >5 min apart, so cache WRITES are more common than cache READS for single users. However:
- Back-to-back captures within 5 min (common during brainstorm/meeting) → full cache read savings
- Cache write has 25% token premium → acceptable tradeoff
- Any multi-turn within a session → cache read saves 90%

**API request shape with caching:**
```json
{
  "system": [
    {
      "type": "text",
      "text": "<static Castellum system instructions>",
      "cache_control": {"type": "ephemeral"}
    }
  ],
  "tools": [
    { "name": "jira_create_issue", ... },
    { "name": "apple_reminders_create_reminder", ... },
    { "name": "google_send_email", ..., "cache_control": {"type": "ephemeral"} }
  ],
  "messages": [
    { "role": "user", "content": "<transcript + metadata — NOT cached>" }
  ]
}
```

**Files to modify:** `Hex/Clients/CastellumClient.swift` (new unified client)

---

### 2E. Selective Schema Loading

Already partially implemented: only tools matching `analysis.integrations` get schemas loaded. Refine this further:

1. **Flow-scoped tools:** Filter schemas to tools relevant to the active Flow. "Morning Kickoff" flow → Jira + Toggl + Slack. "Personal" flow → Notes + Reminders + Messages.
2. **Context window budget:** Cap total tool schemas at 4,000 tokens. If more tools are connected, rank by recency of use and trim to budget.
3. **Compressed schemas:** For parameter fields with long descriptions, send a shortened version to Claude (store full descriptions in JSON for UI display only).

---

## 3. Token Usage Estimates

### Per-Session Cost Table

Pricing basis (verify at shiptime):
- **Haiku 4.5:** $0.80/MTok input · $4.00/MTok output
- **Sonnet 4.6:** $3.00/MTok input · $15.00/MTok output
- **Cache write:** +25% on input price · **Cache read:** 10% of input price

| Session Type | Transcript | Input Tokens | Output Tokens | Model | API Calls | $/session |
|-------------|-----------|:------------:|:-------------:|-------|:---------:|:---------:|
| Heuristic bypass (simple reminder) | <50 words | 0 | 0 | None | 0 | **$0.000** |
| Quick note (30s) | ~75 tok | ~900 | ~250 | Haiku | 1 | **$0.0017** |
| Simple task / reminder (30s) | ~75 tok | ~1,000 | ~300 | Haiku | 1 | **$0.0020** |
| Calendar event (45s) | ~125 tok | ~1,200 | ~350 | Haiku | 1 | **$0.0023** |
| Multi-tool, clear intent (2min) | ~400 tok | ~2,200 | ~550 | Haiku | 1 | **$0.0040** |
| Meeting recap, 2 tools (5min) | ~1,000 tok | ~2,900 | ~700 | Sonnet | 1 | **$0.019** |
| Meeting recap, 4 tools (5min) | ~1,000 tok | ~3,800 | ~900 | Sonnet | 1 | **$0.025** |
| Complex brainstorm (10min) | ~2,500 tok | ~5,500 | ~1,200 | Sonnet | 1 | **$0.035** |
| Infra/code brief (2min) | ~400 tok | ~2,000 | ~800 | Haiku | 1 | **$0.0048** |

### Estimated Monthly Cost Per User

| Usage pattern | Sessions/day | Avg session type | Estimated $/month |
|---------------|:------------:|-----------------|:-----------------:|
| Light (reminder + notes) | 3-5 | Mostly Haiku + ~30% bypass | **$0.10 - $0.30** |
| Moderate (tasks + meetings) | 8-12 | ~60% Haiku, ~40% Sonnet | **$0.80 - $2.00** |
| Heavy (PM / founder) | 20-30 | ~40% Haiku, ~60% Sonnet | **$3.00 - $8.00** |

### Token Budget Per Tool (Schema Sizes)

Approximate tokens added to system context when a tool is loaded:

| Tool | Actions | Schema Tokens | Notes |
|------|---------|:-------------:|-------|
| `apple-reminders` | 2 | ~220 | Native, tiny schema |
| `apple-calendar` | 3 | ~330 | Native |
| `apple-notes` | 3 | ~300 | Native |
| `apple-files` | 5 | ~480 | Native |
| `apple-contacts` | 3 | ~300 | Native |
| `apple-messages` | 1 | ~120 | Native |
| `apple-mail` | 1 | ~150 | URL scheme |
| `apple-maps` | 3 | ~270 | URL scheme |
| Jira | 5 | ~650 | REST |
| Confluence | 3 | ~400 | REST |
| Google (Calendar+Gmail+Docs) | 6 | ~750 | REST |
| Google Sheets + Tasks | 4 | ~500 | REST |
| Toggl | 4 | ~420 | REST |
| Slack | 3 | ~380 | REST |
| GitHub | 3 | ~380 | REST |
| Microsoft 365 | 8 | ~950 | REST |
| Notion | 3 | ~400 | REST |
| Things 3 | 3 | ~300 | URL scheme |
| Day One | 2 | ~200 | URL scheme |
| Linear | 3 | ~420 | REST |
| Zoom | 3 | ~380 | REST |
| HubSpot | 5 | ~580 | REST |
| Vercel/Render/Infra | 3 | ~350 | REST + webhook |

**Budget implication:** A user with 6 connected tools sends ~2,200 schema tokens. With 12 connected tools, ~4,500 schema tokens. The 4,000-token cap in section 2E kicks in at ~10+ tools — trim by usage frequency.

---

## 4. Apple Native Integrations

### Architecture: NativeToolExecutor

**New file:** `Hex/Clients/ToolActions/NativeToolExecutor.swift`

Add to `GenericToolExecutor.execute()` before auth resolution:
```swift
if let handler = actionSpec.specialHandler, handler.hasPrefix("native_") {
    return await NativeToolExecutor.execute(handler: handler, action: action)
}
```

Add `"type": "native"` to `ToolDefinitionSpec` in `ToolDefinitionLoader.swift` — skip auth resolution for native tools.

---

### Branch: `apple-native/eventkit` — Reminders + Calendar

**Framework:** EventKit (shared permission, iOS + macOS 14+)
**Permission strings (Info.plist):** `NSRemindersUsageDescription`, `NSCalendarsUsageDescription`
**New files:**
- `Hex/Resources/Data/tool-definitions/apple-reminders.json`
- `Hex/Resources/Data/tool-definitions/apple-calendar.json`
- `Hex/Clients/ToolActions/EventKitActionClient.swift`
- Cases in `NativeToolExecutor.swift`

**Reminders JSON (`apple-reminders.json`):**
```json
{
  "id": "apple-reminders",
  "name": "Reminders",
  "icon": "checklist",
  "type": "native",
  "auth": { "methods": ["system"] },
  "actions": {
    "create_reminder": {
      "display_name": "Create Reminder",
      "description": "Add a reminder to Apple Reminders with optional due date, list, and priority",
      "special_handler": "native_reminders_create",
      "parameters": {
        "title": { "type": "string", "required": true, "description": "Reminder title" },
        "notes": { "type": "string", "required": false, "description": "Additional notes" },
        "due_date": { "type": "string", "required": false, "description": "Due date/time in ISO 8601 format" },
        "list_name": { "type": "string", "required": false, "description": "Name of the reminders list (default: Reminders)" },
        "priority": { "type": "string", "required": false, "description": "Priority: none, low, medium, high" }
      }
    },
    "create_reminder_list": {
      "display_name": "Create Reminder List",
      "description": "Create a new named list in Apple Reminders",
      "special_handler": "native_reminders_create_list",
      "parameters": {
        "list_name": { "type": "string", "required": true, "description": "Name for the new list" }
      }
    }
  }
}
```

**Calendar JSON (`apple-calendar.json`):**
```json
{
  "id": "apple-calendar",
  "name": "Calendar",
  "icon": "calendar",
  "type": "native",
  "auth": { "methods": ["system"] },
  "actions": {
    "create_event": {
      "display_name": "Create Event",
      "description": "Create an event in Apple Calendar",
      "special_handler": "native_calendar_create_event",
      "parameters": {
        "title": { "type": "string", "required": true },
        "start_time": { "type": "string", "required": true, "description": "ISO 8601 datetime" },
        "end_time": { "type": "string", "required": true, "description": "ISO 8601 datetime" },
        "notes": { "type": "string", "required": false },
        "location": { "type": "string", "required": false },
        "calendar_name": { "type": "string", "required": false, "description": "Calendar name (default: primary)" }
      }
    },
    "create_all_day_event": {
      "display_name": "Create All-Day Event",
      "description": "Create an all-day event (deadline, OOO, anniversary)",
      "special_handler": "native_calendar_create_allday",
      "parameters": {
        "title": { "type": "string", "required": true },
        "date": { "type": "string", "required": true, "description": "Date in YYYY-MM-DD format" },
        "notes": { "type": "string", "required": false }
      }
    },
    "find_free_time": {
      "display_name": "Find Free Time",
      "description": "Find available time slots on a given date",
      "special_handler": "native_calendar_find_free",
      "parameters": {
        "date": { "type": "string", "required": true, "description": "Date in YYYY-MM-DD" },
        "duration_minutes": { "type": "string", "required": true, "description": "Required duration in minutes" }
      }
    }
  }
}
```

**`EventKitActionClient.swift` implementation outline:**
```swift
import EventKit

enum EventKitActionClient {
    private static let store = EKEventStore()
    
    static func requestAccess() async throws {
        try await store.requestFullAccessToReminders()
        try await store.requestFullAccessToEvents()
    }
    
    static func createReminder(title: String, notes: String?, dueDate: Date?, listName: String?, priority: EKReminderPriority) async throws -> String {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = findCalendar(named: listName, type: .reminder) ?? store.defaultCalendarForNewReminders()
        if let due = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        }
        reminder.priority = Int(priority.rawValue)
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }
    
    static func createEvent(title: String, start: Date, end: Date, notes: String?, location: String?, calendarName: String?) async throws -> String {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.location = location
        event.calendar = findCalendar(named: calendarName, type: .event) ?? store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }
    
    private static func findCalendar(named name: String?, type: EKEntityType) -> EKCalendar? {
        guard let name else { return nil }
        return store.calendars(for: type).first { $0.title.lowercased() == name.lowercased() }
    }
}
```

**`NativeToolExecutor.swift` dispatch:**
```swift
enum NativeToolExecutor {
    static func execute(handler: String, action: PlannedAction) async -> ActionResult {
        switch handler {
        case "native_reminders_create":
            return await handleRemindersCreate(action)
        case "native_reminders_create_list":
            return await handleRemindersCreateList(action)
        case "native_calendar_create_event":
            return await handleCalendarCreateEvent(action)
        case "native_calendar_create_allday":
            return await handleCalendarCreateAllDay(action)
        case "native_calendar_find_free":
            return await handleCalendarFindFree(action)
        // ... other native handlers
        default:
            return ActionResult(actionID: action.id, success: false, error: "Unknown native handler: \(handler)")
        }
    }
}
```

**Date parsing for parameters:** The `due_date` / `start_time` parameters from Claude will be ISO 8601 strings. Use `ISO8601DateFormatter` to parse. Claude will always produce ISO 8601 when instructed (the system prompt says "ISO 8601 format").

---

### Branch: `apple-native/notes` — Notes (macOS)

**Method:** `NSAppleScript` (macOS 14+ sandbox-compatible via Automation entitlement)
**Permission:** macOS Automation permission for Notes.app — auto-prompted on first run
**New files:**
- `Hex/Resources/Data/tool-definitions/apple-notes.json`
- `Hex/Clients/ToolActions/NotesAppleScriptClient.swift`
- Cases in `NativeToolExecutor.swift`

**iOS fallback:** `UIActivityViewController` with Notes as primary suggested destination. Cannot create a Note in the background on iOS.

**`NotesAppleScriptClient.swift`:**
```swift
import Foundation

enum NotesAppleScriptClient {
    static func createNote(title: String, body: String, folderName: String = "Notes", accountName: String = "iCloud") throws {
        let safeTitle = title.appleScriptEscaped
        let safeBody = body.appleScriptEscaped
        let safeFolderName = folderName.appleScriptEscaped
        
        let script = """
        tell application "Notes"
            tell account "\(accountName)"
                if not (exists folder "\(safeFolderName)") then
                    make new folder with properties {name: "\(safeFolderName)"}
                end if
                set targetFolder to folder "\(safeFolderName)"
                make new note at targetFolder with properties {name: "\(safeTitle)", body: "\(safeTitle)\\n\\n\(safeBody)"}
            end tell
        end tell
        """
        try runAppleScript(script)
    }
    
    static func appendToNote(noteTitle: String, content: String, accountName: String = "iCloud") throws {
        let script = """
        tell application "Notes"
            tell account "\(accountName)"
                set matchedNote to first note whose name is "\(noteTitle.appleScriptEscaped)"
                set body of matchedNote to (body of matchedNote) & "\\n\\n\(content.appleScriptEscaped)"
            end tell
        end tell
        """
        try runAppleScript(script)
    }
    
    private static func runAppleScript(_ source: String) throws {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&error)
        if let err = error {
            throw NotesError.applescriptFailed(err.description)
        }
    }
}

private extension String {
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
```

**Actions:**

| Action | Handler | Parameters |
|--------|---------|------------|
| `create_note` | `native_notes_create` | `title` (req), `body` (req), `folder_name` |
| `append_to_note` | `native_notes_append` | `note_title` (req), `content` (req) |
| `create_note_in_folder` | `native_notes_create_in_folder` | `title` (req), `body` (req), `folder_name` (req) |

---

### Branch: `apple-native/files` — Files + iCloud Drive

**Method:** `FileManager` + ubiquitous container (both platforms)
**Permission:** iCloud entitlement already in project (`com.apple.developer.ubiquity-container-identifiers`)
**New files:**
- `Hex/Resources/Data/tool-definitions/apple-files.json`
- `Hex/Clients/ToolActions/FilesActionClient.swift`
- Cases in `NativeToolExecutor.swift`

**Folder resolution map:**
```swift
static func resolveFolder(_ name: String?) -> URL {
    switch name?.lowercased() {
    case "desktop": return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    case "downloads": return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    case "icloud", "icloud drive": return iCloudDriveURL?.appendingPathComponent("Basn") ?? documentsURL
    default: return documentsURL.appendingPathComponent(name ?? "")
    }
}
```

**Actions:**

| Action | Handler | Parameters |
|--------|---------|------------|
| `create_text_file` | `native_files_create_text` | `filename` (req), `content` (req), `folder` (default: Documents), `format` (txt/md/rtf) |
| `append_to_file` | `native_files_append` | `filename` (req), `content` (req), `folder` |
| `create_folder` | `native_files_create_folder` | `folder_name` (req), `parent_folder` |
| `save_to_icloud_drive` | `native_files_save_icloud` | `filename` (req), `content` (req), `subfolder` |

**RTF writing:** Use `NSAttributedString(string: content).data(from: .init(location: 0, length: content.count), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])` to produce `.rtf` bytes.

**Markdown default:** Unless otherwise specified, Basn saves transcript outputs as `.md` files with a YAML front matter block (date, flow, session ID).

---

### Branch: `apple-native/contacts` — Contacts (Action + Context Resolver)

**Framework:** Contacts (`import Contacts`) — iOS + macOS
**Permission:** `NSContactsUsageDescription` in Info.plist
**New files:**
- `Hex/Resources/Data/tool-definitions/apple-contacts.json`
- `Hex/Clients/ContactsContextClient.swift` — dual-use: action executor + Castellum context provider
- Cases in `NativeToolExecutor.swift`

**Dual-use architecture:**

```swift
// ContactsContextClient.swift
struct ContactsContextClient {
    // Used by Castellum system prompt builder — inject compact contact list for name resolution
    var loadSummaries: @Sendable () async -> [ContactSummary]  // [{name, email, phone}]
    // Used by NativeToolExecutor — find matching contact
    var findContact: @Sendable (String) async -> CNContact?    // name query
    // Used by NativeToolExecutor — create new contact
    var createContact: @Sendable (ContactCreateRequest) async throws -> Void
}

struct ContactSummary: Codable {
    let displayName: String
    let email: String?
    let phone: String?
}
```

**Castellum context injection:** The unified `CastellumClient` loads contact summaries before the Claude call and injects them into the user message:
```
Contacts available for name resolution:
- Diego Martínez <diego@example.com> +1 (555) 234-5678
- Sarah Chen <sarah@agency.com>
...
```
Limit to 50 most recently contacted (via `CNContactSortOrder.userDefault`, sort by last name). Cap at ~1,500 tokens.

**Actions:**

| Action | Handler | Parameters |
|--------|---------|------------|
| `create_contact` | `native_contacts_create` | `first_name` (req), `last_name`, `email`, `phone`, `company`, `notes` |
| `update_contact` | `native_contacts_update` | `name_query` (req), `add_note`, `add_email`, `add_phone` |
| `find_contact` | `native_contacts_find` | `name_query` (req) — returns result to Castellum as context |

---

### Branch: `apple-native/clipboard-spotlight` — Clipboard + Spotlight

**No permissions required.**
**New files:**
- Cases in `NativeToolExecutor.swift`
- `Hex/Clients/SpotlightIndexClient.swift`

**Clipboard actions:**

| Action | Handler | Parameters |
|--------|---------|------------|
| `copy_to_clipboard` | `native_clipboard_copy` | `content` (req), `label` (optional, shown in notification) |

**Spotlight:** `SpotlightIndexClient` runs automatically after every session completes (no user trigger):
```swift
import CoreSpotlight

struct SpotlightIndexClient {
    func index(session: Session, summary: String) {
        let item = CSSearchableItem(
            uniqueIdentifier: session.id,
            domainIdentifier: "com.lyra.basn.sessions",
            attributeSet: {
                let attrs = CSSearchableItemAttributeSet(contentType: .text)
                attrs.title = summary
                attrs.contentDescription = session.rawText.prefix(200).description
                attrs.keywords = ["basn", session.flowID]
                return attrs
            }()
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }
}
```

---

### Branch: `apple-native/url-schemes` — Mail, Messages, Maps, Safari

**Zero permission. Both platforms.**
**New files:**
- `Hex/Resources/Data/tool-definitions/apple-mail.json`
- `Hex/Resources/Data/tool-definitions/apple-messages.json`
- `Hex/Resources/Data/tool-definitions/apple-maps.json`
- `Hex/Resources/Data/tool-definitions/apple-safari.json`
- `Hex/Clients/ToolActions/URLSchemeActionClient.swift`

**URL scheme executor:**
```swift
enum URLSchemeActionClient {
    static func open(_ url: URL) async -> ActionResult {
        #if os(iOS)
        await UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
    
    static func mailtoURL(to: String, subject: String, body: String, cc: String?) -> URL {
        var components = URLComponents(string: "mailto:\(to)")!
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        if let cc { components.queryItems?.append(URLQueryItem(name: "cc", value: cc)) }
        return components.url!
    }
    
    static func mapsURL(destination: String, transportType: String) -> URL {
        var components = URLComponents(string: "maps://")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: destination),
            URLQueryItem(name: "dirflg", value: transportType == "transit" ? "r" : transportType == "walking" ? "w" : "d")
        ]
        return components.url!
    }
}
```

**Actions summary:**

| Tool | Action | Handler | URL scheme |
|------|--------|---------|-----------|
| Mail | `compose_email` | `native_mail_compose` | `mailto:to?subject=&body=&cc=` |
| Messages | `compose_message` | `native_messages_compose` | `sms:recipient&body=` |
| Maps | `get_directions` | `native_maps_directions` | `maps://?daddr=&dirflg=d` |
| Maps | `search_nearby` | `native_maps_search` | `maps://?q=query` |
| Maps | `open_location` | `native_maps_open` | `maps://?address=` |
| Safari | `add_to_reading_list` | `native_safari_reading_list` | `SSReadingList.add(url:title:previewText:)` |
| Safari | `open_url` | `native_safari_open` | `https://url` (opens in default browser) |

---

### Branch: `apple-native/app-intents` — Shortcuts + Siri + Focus Filter

**Framework:** App Intents (iOS 16+ / macOS 13+)
**New directory:** `Hex/AppIntents/`
**New files:**
- `Hex/AppIntents/StartCaptureIntent.swift`
- `Hex/AppIntents/StopCaptureIntent.swift`
- `Hex/AppIntents/GetTranscriptIntent.swift`
- `Hex/AppIntents/CreateNoteFromCaptureIntent.swift`
- `Hex/AppIntents/BasnFocusFilter.swift`
- `Hex/AppIntents/BasnShortcutsProvider.swift`

**Intents:**

```swift
struct StartCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Basn Capture"
    static var description = IntentDescription("Start recording a voice capture in Basn")
    
    @Parameter(title: "Flow") var flowID: String?
    
    func perform() async throws -> some IntentResult & ProvidesStringRepresentationResult {
        // Dispatch to TCA store via dependency
        await BasnIntentBridge.startCapture(flowID: flowID)
        return .result(value: "Recording started")
    }
}

struct BasnFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Set Basn Routing for Focus"
    
    @Parameter(title: "Default routing") var routingPreference: RoutingPreference?
    
    func perform() async throws -> some IntentResult {
        // Store routing preference that CastellumClient reads during sessions
        UserDefaults.standard.set(routingPreference?.rawValue, forKey: "focusRoutingPreference")
        return .result()
    }
}
```

**Shortcuts App Intents to expose:**
1. `StartCapture(flowID:)` — "Hey Siri, start a Basn capture"
2. `StopCapture` — "Stop Basn"  
3. `GetLastTranscript` — returns transcript text (useful in Shortcuts automations)
4. `CreateNoteFromCapture(folderName:)` — save last transcript as a Note
5. `SendCaptureToTool(toolID:)` — route last capture to a specific tool

---

### Branch: `apple-native/widgets` — WidgetKit

**New Xcode target:** `BasnWidget` (Widget Extension)
**New files:**
- `BasnWidget/BasnWidgetBundle.swift`
- `BasnWidget/RecentCaptureWidget.swift`
- `BasnWidget/QuickRecordWidget.swift`
- `BasnWidget/SharedWidgetModels.swift`
- `BasnWidget/AppGroup.swift` — `com.lyra.basn.widget-data` App Group for data sharing

**Widget types:**

| Widget | Sizes | Data source | iOS 17+ interactive? |
|--------|-------|------------|:--------------------:|
| Recent Capture | Small, Medium | Last session from App Group | No |
| Daily Summary | Medium | Sessions today count + top workflow | No |
| Quick Record | Small | Tap-to-record | Yes (interactive) |

**App Group data sharing:** Session data is written to `UserDefaults(suiteName: "group.com.lyra.basn")` after each session completes. Widget reads from this App Group. No SwiftData sharing needed — just summary data (title, timestamp, action count).

---

### Branch: `apple-native/photos` — Photos

**Framework:** PHPhotoLibrary
**Permission:** `NSPhotoLibraryAddUsageDescription` (write-only; no read permission needed for creating albums)
**New files:**
- `Hex/Resources/Data/tool-definitions/apple-photos.json`
- Cases in `NativeToolExecutor.swift`

| Action | Handler | Parameters |
|--------|---------|------------|
| `create_album` | `native_photos_create_album` | `album_name` (req) |
| `save_image` | `native_photos_save_image` | `image_data` (base64, req), `album_name` |

---

### Branch: `apple-native/music` — Music (macOS AppleScript)

**Method:** AppleScript on macOS (no entitlement required)
**New files:**
- `Hex/Resources/Data/tool-definitions/apple-music.json`
- `Hex/Clients/ToolActions/MusicAppleScriptClient.swift`
- Cases in `NativeToolExecutor.swift`

| Action | Handler | Parameters |
|--------|---------|------------|
| `play_playlist` | `native_music_play_playlist` | `playlist_name` (req) |
| `pause_playback` | `native_music_pause` | — |
| `skip_track` | `native_music_skip` | — |
| `add_to_playlist` | `native_music_add_to_playlist` | `playlist_name` (req), `track_query` (req) |

---

## 5. Core Third-Party Integrations (Extend Existing)

### Toggl (Extend `toggl.json`)

**Existing:** `create_time_entry` in `ToolActionRegistry.swift` (hardcoded) + `toggl.json`
**Extend `toggl.json` with:**

| New Action | `special_handler` | Parameters | Notes |
|-----------|-------------------|------------|-------|
| `start_timer` | `toggl_start_timer` | `description` (req), `project_name` | Stops existing running timer first |
| `stop_current_timer` | `toggl_stop_timer` | — | Stops whatever is running |
| `get_current_entry` | `toggl_get_current` | — | Returns running entry for context |
| `edit_last_entry` | `toggl_edit_last` | `description`, `project_name` | Patch the last completed entry |

**Extend `TogglActionClient.swift`** with these four handlers.

**Extend `buildServiceContext()`** in `CastellumPlannerClient+Live.swift` to include active Toggl timer (if running) in the user message context — helps Castellum decide whether to start a new timer or stop the current one.

**Discovery:** Cache the user's workspace projects (name + ID) from `/api/v9/me/workspaces/{wid}/projects`. Already partially in place — complete the caching.

---

### Jira / Atlassian (Extend + Add Confluence)

**Existing:** `jira.json` with `create_issue`
**Extend `jira.json` with:**

| New Action | Endpoint | Parameters |
|-----------|----------|------------|
| `update_issue` | `PUT {base_url}/rest/api/3/issue/{issue_key}` | `issue_key` (req), `status`, `assignee_email`, `add_label` |
| `add_comment` | `POST {base_url}/rest/api/3/issue/{issue_key}/comment` | `issue_key` (req), `body` (req) |
| `log_work` | `POST {base_url}/rest/api/3/issue/{issue_key}/worklog` | `issue_key` (req), `time_spent` (e.g. "2h 30m"), `comment` |
| `search_issues` | `GET {base_url}/rest/api/3/search?jql=` | `jql` (req) — results fed back to Castellum as context |
| `get_issue` | `GET {base_url}/rest/api/3/issue/{issue_key}` | `issue_key` (req) — for context/status checks |

**New: `confluence.json`** (same OAuth token as Jira — Atlassian unified):
```json
{
  "id": "confluence",
  "name": "Confluence",
  "icon": "doc.richtext",
  "auth": { "methods": ["oauth"], "oauth_provider": "atlassian" },
  "base_url": { "oauth": "https://api.atlassian.com/ex/confluence/{cloud_id}" },
  "discovery": {
    "spaces": {
      "endpoint": "{base_url}/rest/api/space?limit=50",
      "method": "GET",
      "extract": "$.results[*].{key, name}",
      "description": "Confluence spaces",
      "refresh_interval_hours": 168
    }
  },
  "actions": {
    "create_page": {
      "display_name": "Create Confluence Page",
      "description": "Create a new page in a Confluence space",
      "endpoint": "{base_url}/rest/api/content",
      "method": "POST",
      "parameters": {
        "space_key": { "type": "string", "required": true, "description": "Space key from discovery" },
        "title": { "type": "string", "required": true },
        "body": { "type": "string", "required": true, "description": "Page content in plain text" },
        "parent_page_title": { "type": "string", "required": false }
      }
    },
    "add_comment": {
      "display_name": "Comment on Page",
      "description": "Add a comment to an existing Confluence page",
      "endpoint": "{base_url}/rest/api/content/{page_id}/child/comment",
      "method": "POST",
      "parameters": {
        "page_title": { "type": "string", "required": true, "description": "Page title to search for" },
        "comment": { "type": "string", "required": true }
      }
    },
    "search": {
      "display_name": "Search Confluence",
      "description": "Search Confluence for pages matching a query",
      "endpoint": "{base_url}/rest/api/content/search?cql=text~\"{query}\"&limit=5",
      "method": "GET",
      "parameters": {
        "query": { "type": "string", "required": true }
      }
    }
  }
}
```

**`integrationToToolID` mapping** in `CastellumPlannerClient+Live.swift` — add:
```swift
"confluence": "confluence",
"atlassian": "jira",  // alias
```

---

### Google Apps (Extend `google.json`)

**Existing:** `create_event`, `send_email`, `create_document`
**New actions to add to `google.json`:**

| Action | Endpoint | Scope needed | Parameters |
|--------|----------|-------------|------------|
| `create_draft` | `/gmail/v1/users/me/drafts` | `gmail.compose` | `to`, `subject`, `body`, `cc` |
| `append_to_document` | `/docs/v1/documents/{documentId}:batchUpdate` | `documents` | `document_title` (search by title), `content` |
| `create_spreadsheet` | `/sheets/v4/spreadsheets` | `spreadsheets` | `title`, `sheet_name` |
| `append_sheet_row` | `/sheets/v4/spreadsheets/{id}/values/{range}:append` | `spreadsheets` | `spreadsheet_title`, `values` (comma-sep) |
| `create_task` | `https://tasks.googleapis.com/tasks/v1/lists/@default/tasks` | `tasks` | `title`, `notes`, `due` (RFC 3339) |
| `complete_task` | PATCH `tasks/v1/lists/@default/tasks/{taskId}` | `tasks` | `task_title` (search) |
| `create_drive_folder` | `/drive/v3/files` (type: folder) | `drive.file` | `folder_name`, `parent_folder_name` |
| `send_chat_message` | Webhook URL | None (webhook) | `webhook_url`, `text` |

**New OAuth scopes** to add to `google.json`:
```json
"tasks": { "label": "Google Tasks", "scope": "https://www.googleapis.com/auth/tasks", "default": false },
"sheets": { "label": "Sheets access", "scope": "https://www.googleapis.com/auth/spreadsheets", "default": false },
"drive": { "label": "Drive full access", "scope": "https://www.googleapis.com/auth/drive.file", "default": true }
```

**Discovery: document list** — cache a list of recent Docs/Sheets titles so Claude can match "append to the project brief" to the correct document ID without a search round-trip.

**`append_to_document` implementation:** Because Google Docs requires knowing the document ID and the end-of-document index for `batchUpdate`, this action needs a `special_handler: "google_docs_append"` in `google.json`. `GenericToolExecutor` calls `buildGoogleDocsAppendRequest()` which:
1. Searches Drive for the document by title: `GET /drive/v3/files?q=name='{title}' and mimeType='application/vnd.google-apps.document'`
2. Gets the document end index: `GET /docs/v1/documents/{id}`
3. Inserts text at end index

---

### Microsoft 365 (New Integration)

**New file:** `Hex/Resources/Data/tool-definitions/microsoft365.json`
**OAuth provider:** Microsoft Identity Platform (`https://login.microsoftonline.com/common/oauth2/v2.0/`)
**Base URL:** `https://graph.microsoft.com/v1.0`
**Single OAuth token covers all M365 apps** — users connect once, get access to Calendar, Mail, To Do, Teams, OneNote, Planner.

**New OAuth provider entry in auth system:** `"oauth_provider": "microsoft"` — requires adding Microsoft OAuth flow alongside existing Google/Atlassian flows in `OAuthClient.swift`.

**`microsoft365.json` (abridged structure):**
```json
{
  "id": "microsoft365",
  "name": "Microsoft 365",
  "icon": "square.grid.3x3.fill",
  "auth": {
    "methods": ["oauth"],
    "oauth_provider": "microsoft",
    "scopes_selectable": true,
    "available_scopes": {
      "calendar":    { "label": "Outlook Calendar", "scope": "Calendars.ReadWrite", "default": true },
      "mail":        { "label": "Outlook Mail", "scope": "Mail.Send Mail.ReadWrite", "default": true },
      "todo":        { "label": "Microsoft To Do", "scope": "Tasks.ReadWrite", "default": true },
      "teams":       { "label": "Microsoft Teams", "scope": "ChannelMessage.Send Chat.ReadWrite", "default": false },
      "onenote":     { "label": "OneNote", "scope": "Notes.ReadWrite.All", "default": false },
      "planner":     { "label": "Planner", "scope": "Group.ReadWrite.All", "default": false }
    }
  },
  "base_url": { "oauth": "https://graph.microsoft.com/v1.0" },
  "discovery": {
    "calendars": { "endpoint": "{base_url}/me/calendars", "extract": "$.value[*].{id, name}" },
    "todo_lists": { "endpoint": "{base_url}/me/todo/lists", "extract": "$.value[*].{id, displayName}" },
    "teams": { "endpoint": "{base_url}/me/joinedTeams", "extract": "$.value[*].{id, displayName}" }
  }
}
```

**Actions:**

| Action | Endpoint | Parameters |
|--------|----------|------------|
| `create_calendar_event` | `POST /me/events` | `title` (req), `start_time`, `end_time`, `attendees`, `body`, `location` |
| `send_email` | `POST /me/sendMail` | `to` (req), `subject` (req), `body` (req), `cc` |
| `create_draft` | `POST /me/messages` | `to`, `subject`, `body` |
| `create_todo_task` | `POST /me/todo/lists/{listId}/tasks` | `title` (req), `notes`, `due_date`, `list_name` |
| `complete_todo_task` | `PATCH /me/todo/lists/{listId}/tasks/{taskId}` | `task_title` (req), `list_name` |
| `create_todo_list` | `POST /me/todo/lists` | `list_name` (req) |
| `send_teams_message` | `POST /teams/{teamId}/channels/{channelId}/messages` | `team_name` (req), `channel_name`, `message` (req) |
| `create_teams_meeting` | `POST /me/onlineMeetings` | `subject` (req), `start_time`, `end_time` |
| `create_onenote_page` | `POST /me/onenote/sections/{sectionId}/pages` | `title` (req), `content` (req), `section_name` |
| `create_planner_task` | `POST /planner/tasks` | `title` (req), `plan_id`, `bucket_id`, `assignee_ids` |

**`integrationToToolID` mapping additions:**
```swift
"outlook": "microsoft365",
"teams": "microsoft365",
"onenote": "microsoft365",
"todo": "microsoft365",
"microsoftteams": "microsoft365"
```

**Token budget note:** Microsoft 365 tool schema is ~950 tokens (8 actions). Only load it if user has connected M365. Never load alongside Google for the same intent (Castellum should pick one per action type based on which is connected).

---

## 6. Server / Infra Platforms

> **Basn's role here is capture and brief-generation, not execution.** The primary output is a structured spec file (Markdown/JSON) that Claude Code or another agent can act on. Secondary: trigger deploy hooks, create repos, or spin up cloud resources when the action is clear.

**New tool definition:** `Hex/Resources/Data/tool-definitions/infra.json` (grouped under one tool ID for simplicity, sub-actions map to different platforms)

### Deployment Platforms

| Platform | Auth | Action | What it does |
|----------|------|--------|-------------|
| **Vercel** | API token | `trigger_deploy` | POST to project deploy hook URL |
| **Vercel** | API token | `create_project` | Creates a Vercel project linked to a GitHub repo |
| **Netlify** | API token | `trigger_build` | POST to Netlify build hook |
| **Render** | API token | `trigger_deploy` | POST to Render deploy hook |
| **Railway** | API token | `create_project` | Railway REST API — new project |
| **Fly.io** | API token | `deploy_app` | Fly Machines API — deploy existing app |
| **Cloudflare** | API token | `deploy_worker` | Cloudflare Workers API |
| **Cloudflare** | API token | `purge_cache` | Cache purge by zone/URL pattern |

### Database / Backend

| Platform | Auth | Action | What it does |
|----------|------|--------|-------------|
| **Supabase** | Management API key | `create_project` | New Supabase project via Management API |
| **Supabase** | Service role key | `run_sql` | Execute SQL via REST (for quick table creation) |
| **Neon** | API key | `create_database` | Neon Management API — new Postgres database |
| **PlanetScale** | API key | `create_database` | PlanetScale API — new MySQL database |

### CI/CD Triggers

| Platform | Auth | Action | What it does |
|----------|------|--------|-------------|
| **GitHub Actions** | Token (extends GitHub tool) | `trigger_workflow` | `POST /repos/{owner}/{repo}/actions/workflows/{id}/dispatches` |
| **CircleCI** | API token | `trigger_pipeline` | CircleCI API v2 — trigger a named pipeline |

### Infra-as-Brief (Primary Use Case)

**New action type: `create_project_brief`**

This is the highest-value infra action — Castellum captures the voice idea and Basn generates a structured spec file:

```markdown
# Project Brief: [title]
Generated: 2026-05-30 from Basn voice capture

## Concept
[Castellum-generated description]

## Tech Stack
- Frontend: [detected from transcript]
- Backend: [detected]
- Database: [detected]
- Hosting: [detected]

## Core Features
1. [Feature 1]
2. [Feature 2]

## MVP Scope
[What to build first]

## Next Steps
- [ ] Create GitHub repo
- [ ] Initialize project scaffold
- [ ] Set up CI/CD

## Raw Transcript
[original transcript]
```

This file is saved to iCloud Drive (`/Basn/Briefs/[project-name].md`) and can be opened directly in Claude Code.

**`create_project_brief` action:**
- Handler: `native_files_create_markdown` (reuses the files tool)
- Castellum generates the structured content
- No external API call — pure local file creation

**Token estimate for infra brief:** ~400-token transcript → ~800-token Castellum output (structured spec). Low cost, high value. Always Haiku.

---

## 7. Non-Native Third-Party Apps — Full List

### Notes / PKM

**Day One** — `dayone2://post?entry=&journal=&date=&starred=true`
- `create_entry` — full journal entry with date, body, journal name, tags, starred
- **Highest-value non-native integration for Basn** — voice-to-journal is the canonical use case
- Zero auth, URL scheme only

**Obsidian** — `obsidian://`
- `create_note` — `obsidian://new?vault=Vault&name=Title&content=Body&tags=tag1,tag2`
- `append` — `obsidian://append?vault=Vault&file=File&content=Content`
- Zero auth, file-system based
- Recommend `format=markdown` so Basn output lands cleanly in Obsidian's markdown vault

**Bear** — `bear://x-callback-url/`
- `create_note` — `bear://x-callback-url/create?title=&text=&tags=&pin=yes`
- `append` — `bear://x-callback-url/add-text?id=&text=` (requires note ID — lookup first)
- Zero auth (Bear 2: free to write; reading requires a Bear Pro subscription for callback URL)

**Notion** — REST API, `notion_integration_token`
- `create_page` — title, content (Notion block structure), parent page or database
- `append_blocks` — add paragraph/todo/heading blocks to existing page
- `create_database_entry` — add a row to a Notion database with properties
- Discovery: cache list of databases (name + ID)

**Craft** — `craftdocs://` URL scheme + Craft API (OAuth)
- `create_document` — new document in a space
- `add_block` — append content to document

**Evernote** — REST API (legacy)
- `create_note` — ENML body, notebook assignment

### Task Managers

**Things 3** — `things:///` URL scheme (extremely rich)
- `add_task` — title, notes, `when` (today/tomorrow/evening/anytime/someday/YYYY-MM-DD), deadline, tags, list (project/area)
- `add_project` — create a new project in an area
- `add_multiple_tasks` — JSON array of tasks in one URL (Things 3.14+)
- Zero auth

**OmniFocus** — `omnifocus:///` URL scheme
- `add_task` — name, note, project, tag, due, defer, flag
- Zero auth

**Todoist** — REST API
- `create_task` — content, description, project_id, due_string ("tomorrow at 3pm"), priority (1-4), labels
- `complete_task` — mark done by title search
- Discovery: projects list

**TickTick** — REST API
- `create_task` — title, content, project, due date, priority, tags
- `create_list` — new list

**Linear** — GraphQL API
- `create_issue` — title, description, team, status, assignee, priority, labels
- `update_issue` — change status, add comment
- `create_project` — new project in a team
- Discovery: teams + projects

**Asana** — REST API
- `create_task` — name, notes, project, assignee, due_on, tags, followers
- `create_subtask` — parent task ID + subtask properties
- `add_comment` — on a task
- Discovery: projects + workspaces

**Trello** — REST API (API key + token)
- `create_card` — name, description, idList (board list), due, labels, checklist items
- `create_checklist_item` — add to existing card's checklist

**Monday.com** — GraphQL API
- `create_item` — board item with column values
- `update_status` — change a status column

**ClickUp** — REST API
- `create_task` — name, description, list_id, assignees, due_date, tags, priority
- `add_comment` — on a task

### Communication / Video

**Zoom** — REST API + URI `zoommtg://`
- `create_meeting` — topic, start_time, duration, agenda, password
- `join_meeting` — open Zoom to a meeting ID
- `get_recordings` — list recent recordings (for Castellum context)

**Microsoft Teams** — Microsoft Graph API (covered under Microsoft 365)

**Discord** — REST API (Bot token) or Incoming Webhook
- `send_message` — channel message via webhook or Bot API
- Most practical: Webhook URL stored as tool config (no OAuth needed)

**Telegram** — Bot API
- `send_message` — send to a chat ID via Bot token
- Config: Bot token + chat ID per "recipient"

**Loom** — REST API
- `get_recent_videos` — list recent recordings with share links
- `add_to_space` — organize a video into a workspace folder

### CRM / Business

**HubSpot** — REST API (private app token)
- `create_contact` — first/last name, email, phone, company, lifecycle stage
- `create_deal` — name, stage, amount, close date, associated contact
- `create_task` — task with owner, due date, linked to contact/deal
- `add_note` — note on contact or deal timeline
- `create_company` — company record with domain, industry
- Discovery: pipelines + stages + owners

**Salesforce** — REST API (OAuth2 + instance URL)
- `create_lead` — name, company, email, phone, lead source, description
- `create_opportunity` — name, stage, amount, close date, account
- `log_activity` — call/meeting log on any record
- `create_case` — support case

**Pipedrive** — REST API (API token)
- `create_deal` — title, stage, value, currency, close date, person ID
- `create_person` — name, email, phone, organization
- `add_activity` — call, meeting, task linked to deal/person
- Discovery: stages + pipelines + users

**Attio** — REST API (API key)
- `create_record` — in any object (People, Companies, Deals)
- `add_note` — timeline note on any record
- Discovery: object types + attributes

### Finance

**Stripe** — REST API (secret key)
- `create_payment_link` — price, product name, quantity
- `create_invoice` — customer, line items, due date
- `create_customer` — name, email

**QuickBooks Online** — REST API (OAuth2)
- `create_invoice` — customer, line items (description, qty, rate), due date
- `create_expense` — payee, amount, account, category
- `create_customer` — display name, email, phone

**Harvest** — REST API (personal access token)
- `log_time` — project, task, hours, notes, spent_date
- `start_timer` — start a running timer on a project/task

### Scheduling

**Fantastical** — `x-fantastical3://parse?sentence=` (NLP event creation)
- `create_event` — any natural language string ("Meeting with John tomorrow 2pm for 1 hour")
- `create_reminder` — same NLP approach
- Zero auth — Fantastical's NLP handles parsing

**Calendly** — REST API (OAuth2)
- `create_one_off_link` — single-use scheduling link for a specific meeting type
- `get_availability` — available time slots in a date range

### Reading / Knowledge

**Readwise Reader** — REST API (token)
- `save_article` — save URL to reading list with tags
- `add_highlight` — highlight text with optional note

**Raindrop.io** — REST API (OAuth2)
- `create_bookmark` — URL, title, description, tags, collection

**Instapaper** — REST API (OAuth)
- `add_url` — save URL to reading list

### Automation

**Zapier** — Webhook URL
- `trigger_zap` — POST JSON payload to a catch hook URL
- Universal adapter — any Basn capture can trigger any Zapier zap
- No central auth — each "Zapier" tool instance stores its own webhook URL

**Make (formerly Integromat)** — Webhook URL
- Same webhook pattern as Zapier

**n8n** — Webhook URL
- Self-hosted — same webhook pattern

### Music

**Spotify** — URI scheme + Web API (OAuth)
- `play_playlist` — `spotify:playlist:{id}` via `spotify:` URI scheme (no auth) or Web API playback
- `create_playlist` — new playlist via Web API
- `add_to_playlist` — add track(s) to a named playlist
- `search_and_queue` — search + add to queue

---

## 8. Integration Matrices (Full)

### App × Action Type Matrix

| Integration | Create | Append | Send | Log | Read | Open | Remind | Control | Index | Schema Tokens |
|-------------|:------:|:------:|:----:|:---:|:----:|:----:|:------:|:-------:|:-----:|:-------------:|
| **Apple Reminders** | ✓ | ✓ | – | – | ✓ | – | ✓ | – | – | ~220 |
| **Apple Calendar** | ✓ | ✓ | – | – | ✓ | – | ✓ | – | – | ~330 |
| **Apple Notes** | ✓ | ✓ | – | – | (✓) | ✓ | – | – | – | ~300 |
| **Files / iCloud** | ✓ | ✓ | – | – | ✓ | ✓ | – | – | – | ~480 |
| **Contacts** | ✓ | ✓ | – | – | ✓ | – | – | – | – | ~300 |
| **Clipboard** | – | – | – | – | ✓ | – | – | – | – | ~80 |
| **Spotlight** | – | – | – | – | – | – | – | – | ✓ | ~80 |
| **Mail (compose)** | ✓ | – | ✓ | – | – | ✓ | – | – | – | ~150 |
| **Messages** | – | – | ✓ | – | – | ✓ | – | – | – | ~120 |
| **Maps** | – | – | – | – | ✓ | ✓ | – | – | – | ~270 |
| **Safari** | – | ✓ | – | – | (✓) | ✓ | – | – | – | ~180 |
| **Photos** | ✓ | ✓ | – | – | ✓ | – | – | – | – | ~200 |
| **Music** | ✓ | ✓ | – | – | ✓ | – | – | ✓ | – | ~250 |
| **App Intents / Siri** | – | – | – | – | – | ✓ | ✓ | ✓ | – | – |
| **Widgets** | – | – | – | – | ✓ | ✓ | – | – | – | – |
| **Jira** | ✓ | ✓ | – | ✓ | ✓ | – | – | – | – | ~650 |
| **Confluence** | ✓ | ✓ | – | – | ✓ | – | – | – | – | ~400 |
| **Google Calendar** | ✓ | ✓ | – | – | ✓ | – | – | – | – | ~350 |
| **Gmail** | ✓ | – | ✓ | – | ✓ | – | – | – | – | ~300 |
| **Google Docs** | ✓ | ✓ | – | – | ✓ | – | – | – | – | ~300 |
| **Google Sheets** | ✓ | ✓ | – | ✓ | ✓ | – | – | – | – | ~280 |
| **Google Tasks** | ✓ | – | – | – | ✓ | – | ✓ | – | – | ~220 |
| **Toggl** | – | – | – | ✓ | ✓ | – | – | ✓ | – | ~420 |
| **Slack** | – | – | ✓ | – | ✓ | – | – | – | – | ~380 |
| **GitHub** | ✓ | ✓ | – | – | ✓ | – | – | – | – | ~380 |
| **Microsoft 365** | ✓ | ✓ | ✓ | – | ✓ | – | ✓ | – | – | ~950 |
| **Day One** | ✓ | ✓ | – | ✓ | – | ✓ | – | – | – | ~200 |
| **Obsidian** | ✓ | ✓ | – | – | – | ✓ | – | – | – | ~200 |
| **Things 3** | ✓ | ✓ | – | – | – | ✓ | ✓ | – | – | ~300 |
| **OmniFocus** | ✓ | ✓ | – | – | – | ✓ | ✓ | – | – | ~280 |
| **Notion** | ✓ | ✓ | – | – | ✓ | ✓ | – | – | – | ~400 |
| **Todoist** | ✓ | ✓ | – | – | ✓ | – | ✓ | – | – | ~380 |
| **Linear** | ✓ | ✓ | – | – | ✓ | – | – | – | – | ~420 |
| **HubSpot** | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | – | – | ~580 |
| **Zoom** | ✓ | – | ✓ | – | ✓ | ✓ | – | – | – | ~380 |
| **Fantastical** | ✓ | – | – | – | – | ✓ | ✓ | – | – | ~200 |
| **Spotify** | ✓ | ✓ | – | – | ✓ | – | – | ✓ | – | ~300 |
| **Infra / Deploy** | ✓ | – | ✓ | – | ✓ | – | – | – | – | ~350 |

---

### Workflow × App Matrix (Cross-Platform)

| Workflow | Reminders | Calendar | Notes | Files | Contacts | Mail | Messages | Jira | Slack | Google | M365 | Toggl | Things/OF | Notion | Day One | Zoom | Infra |
|----------|:---------:|:--------:|:-----:|:-----:|:--------:|:----:|:--------:|:----:|:-----:|:------:|:----:|:-----:|:---------:|:------:|:-------:|:----:|:-----:|
| **Voice → Note** | – | – | ✓ | (✓) | – | – | – | – | – | (✓) | (✓) | – | – | (✓) | (✓) | – | – |
| **Meeting recap** | ✓ | (✓) | (✓) | (✓) | ✓ | (✓) | – | (✓) | (✓) | (✓) | (✓) | ✓ | (✓) | – | – | – | – |
| **Brain dump → Tasks** | ✓ | – | (✓) | – | – | – | – | (✓) | – | (✓) | (✓) | – | ✓ | (✓) | – | – | – |
| **Daily standup** | (✓) | ✓ | (✓) | – | – | – | – | ✓ | ✓ | – | (✓) | ✓ | – | – | – | – | – |
| **New contact** | – | – | (✓) | – | ✓ | – | – | – | – | – | – | – | – | (✓) | – | – | – |
| **Quick text** | – | – | – | – | ✓ | – | ✓ | – | – | – | (✓) | – | – | – | – | – | – |
| **Draft email** | – | – | – | – | ✓ | ✓ | – | – | – | ✓ | ✓ | – | – | – | – | – | – |
| **Idea → File** | – | – | (✓) | ✓ | – | – | – | – | – | (✓) | (✓) | – | – | ✓ | – | – | – |
| **Travel planning** | (✓) | ✓ | (✓) | – | – | – | – | – | – | ✓ | (✓) | – | – | – | – | – | – |
| **End-of-day wrap** | ✓ | (✓) | ✓ | (✓) | – | – | – | (✓) | (✓) | – | – | ✓ | – | – | ✓ | – | – |
| **Research capture** | – | – | ✓ | ✓ | – | – | – | – | – | – | – | – | – | ✓ | – | – | – |
| **Focus session** | – | (✓) | – | – | – | – | – | – | – | – | – | – | – | – | – | – | – |
| **Sales call log** | – | – | – | – | ✓ | (✓) | – | – | – | – | – | – | – | – | – | – | – |
| **Journal entry** | – | – | ✓ | (✓) | – | – | – | – | – | – | – | – | – | – | ✓ | – | – |
| **Invoice / finance** | – | – | – | – | ✓ | (✓) | – | – | – | – | – | – | – | – | – | – | – |
| **Schedule meeting** | – | ✓ | – | – | ✓ | (✓) | – | – | – | ✓ | ✓ | – | – | – | – | ✓ | – |
| **Log time** | – | – | – | – | – | – | – | – | – | – | – | ✓ | – | – | – | – | – |
| **Project brief** | – | – | – | ✓ | – | – | – | (✓) | – | – | – | – | – | – | – | – | ✓ |
| **Siri trigger** | (✓) | (✓) | (✓) | (✓) | – | – | – | – | – | – | – | – | – | – | – | – | – |

---

## 9. Execution Branch Plan (Ordered)

Branches are ordered by value/effort ratio. Each branch is a PR; test and merge before starting the next.

### Pre-work (must ship first — blocks everything)

**Branch: `castellum/unified-client`**
1. Generalize `AnthropicClient.swift` system prompt (remove "Jonas, Lyra Designs" hardcode)
2. Create `Hex/Clients/CastellumClient.swift` — unified single-call client replacing both `AnthropicClient` and `CastellumPlannerClient+Live.swift`
3. Add prompt caching headers (`cache_control: ephemeral`) to system block and last tool schema
4. Add `SessionComplexityClassifier.swift` — Haiku/Sonnet routing
5. Update `CastellumFeature.swift` to use new unified client
6. Verify: one Claude call per session, token usage logged to console

**Branch: `castellum/heuristic-router`** (can follow immediately after unified-client)
1. Create `HeuristicRouter.swift` with ~9 pattern rules
2. Wire into session processing pipeline — runs before `CastellumClient`
3. Verify: "remind me to call John tomorrow" → skips Claude, creates Reminders entry directly

**Branch: `castellum/model-tiering`** (follow after heuristic-router)
1. Classify transcript complexity → route to Haiku vs Sonnet
2. Add automatic retry: if Haiku returns 0 tool_use blocks → escalate to Sonnet
3. Add `modelUsed: String` to `ExecutionPlan` for diagnostics

---

### Apple Native (order by value)

**Branch: `apple-native/eventkit`** — Reminders + Calendar
- Creates `NativeToolExecutor.swift` (foundation for all native branches)
- Estimated: ~400 lines new code

**Branch: `apple-native/clipboard-spotlight`** — trivial, zero permission
- 50 lines of new code

**Branch: `apple-native/url-schemes`** — Mail, Messages, Maps, Safari
- URL scheme actions, all zero permission, ~150 lines

**Branch: `apple-native/files`** — Files + iCloud Drive
- Creates `FilesActionClient.swift`
- Markdown default format with YAML front matter

**Branch: `apple-native/notes`** — Notes (macOS AppleScript)
- Creates `NotesAppleScriptClient.swift`
- macOS-only guard blocks

**Branch: `apple-native/contacts`** — Contacts (action + context resolver)
- Creates `ContactsContextClient.swift` (used by `CastellumClient` for name resolution)
- Injects top-50 contacts into user message context

**Branch: `apple-native/app-intents`** — Shortcuts + Siri + Focus Filter
- New `Hex/AppIntents/` directory
- Requires Xcode configuration (App Intents extension or inline Intents)

**Branch: `apple-native/widgets`** — WidgetKit
- New `BasnWidget` Xcode target
- Requires App Group entitlement addition

**Branch: `apple-native/photos`** — Photos
- 80 lines, permission string addition

**Branch: `apple-native/music`** — Music AppleScript
- macOS only, 80 lines AppleScript

---

### Core Tools (extend existing + add Microsoft 365)

**Branch: `tools/toggl-extend`**
- Extend `toggl.json` with start_timer, stop_timer, get_current, edit_last
- Extend `TogglActionClient.swift`
- Add active timer to Castellum service context

**Branch: `tools/jira-extend`**
- Extend `jira.json` with update_issue, add_comment, log_work, search_issues, get_issue
- New `confluence.json`
- Extend `JiraActionClient.swift` or `GenericToolExecutor` to handle new actions

**Branch: `tools/google-extend`**
- Extend `google.json` with append_to_document, create_draft, create_spreadsheet, append_sheet_row, create_task, create_drive_folder
- New `special_handler: "google_docs_append"` with two-step (search → append) executor
- New OAuth scope additions (tasks, sheets)

**Branch: `tools/microsoft365`**
- New `microsoft365.json`
- New `MicrosoftOAuthProvider.swift` (PKCE flow via Microsoft Identity)
- New `Microsoft365ActionClient.swift` for actions requiring multi-step lookup (Teams channel ID resolution, OneNote section lookup)
- Wire into `integrationToToolID` mapping

---

### Non-Native Apps (Tier A first)

**Branch: `tools/day-one`** — URL scheme, 30 lines
**Branch: `tools/things3`** — URL scheme, 50 lines
**Branch: `tools/obsidian`** — URL scheme / file, 40 lines
**Branch: `tools/omnifocus`** — URL scheme, 40 lines
**Branch: `tools/notion`** — REST API
**Branch: `tools/todoist`** — REST API
**Branch: `tools/linear`** — GraphQL API (new `GraphQLToolExecutor` or special_handler)
**Branch: `tools/zoom`** — REST + URI
**Branch: `tools/hubspot`** — REST API
**Branch: `tools/spotify`** — URI + Web API
**Branch: `tools/fantastical`** — URL scheme, 30 lines

---

### Infra

**Branch: `tools/infra-briefs`** — Reuses Files tool; `create_project_brief` action
**Branch: `tools/infra-deploy`** — Vercel, Netlify, Render webhooks; GitHub Actions dispatch

---

## 10. Files To Create / Modify Summary

### New Swift files
```
Hex/Clients/CastellumClient.swift                     (new — replaces two existing)
Hex/Clients/HeuristicRouter.swift                     (new)
Hex/Clients/SessionComplexityClassifier.swift         (new)
Hex/Clients/ContactsContextClient.swift               (new)
Hex/Clients/SpotlightIndexClient.swift                (new)
Hex/Clients/ToolActions/NativeToolExecutor.swift      (new — dispatch hub)
Hex/Clients/ToolActions/EventKitActionClient.swift    (new)
Hex/Clients/ToolActions/NotesAppleScriptClient.swift  (new)
Hex/Clients/ToolActions/FilesActionClient.swift       (new)
Hex/Clients/ToolActions/URLSchemeActionClient.swift   (new)
Hex/Clients/ToolActions/MusicAppleScriptClient.swift  (new)
Hex/Clients/ToolActions/Microsoft365ActionClient.swift (new)
Hex/AppIntents/StartCaptureIntent.swift               (new)
Hex/AppIntents/StopCaptureIntent.swift                (new)
Hex/AppIntents/GetTranscriptIntent.swift              (new)
Hex/AppIntents/BasnFocusFilter.swift                  (new)
Hex/AppIntents/BasnShortcutsProvider.swift            (new)
BasnWidget/BasnWidgetBundle.swift                     (new Xcode target)
BasnWidget/RecentCaptureWidget.swift                  (new)
BasnWidget/QuickRecordWidget.swift                    (new)
```

### Modified Swift files
```
Hex/Clients/AnthropicClient.swift                     (generalize system prompt)
Hex/Clients/CastellumPlannerClient+Live.swift         (deprecate → delegate to CastellumClient)
Hex/Clients/ToolActions/GenericToolExecutor.swift     (add native_ prefix routing)
Hex/Clients/ToolActions/ToolDefinitionLoader.swift    (add "type": "native" field)
Hex/Clients/ToolActions/ToolActionRegistry.swift      (add Toggl start/stop/get)
Hex/Clients/ToolActions/TogglActionClient.swift       (extend with 4 new actions)
Hex/Clients/ToolActions/JiraActionClient.swift        (extend with 5 new actions)
Hex/Features/Castellum/CastellumFeature.swift        (wire to unified CastellumClient)
HexCore/Sources/BasnCore/Settings/BasinSettings.swift (add selectedModel preference)
```

### New JSON tool definitions
```
Hex/Resources/Data/tool-definitions/apple-reminders.json
Hex/Resources/Data/tool-definitions/apple-calendar.json
Hex/Resources/Data/tool-definitions/apple-notes.json
Hex/Resources/Data/tool-definitions/apple-files.json
Hex/Resources/Data/tool-definitions/apple-contacts.json
Hex/Resources/Data/tool-definitions/apple-mail.json
Hex/Resources/Data/tool-definitions/apple-messages.json
Hex/Resources/Data/tool-definitions/apple-maps.json
Hex/Resources/Data/tool-definitions/apple-safari.json
Hex/Resources/Data/tool-definitions/apple-photos.json
Hex/Resources/Data/tool-definitions/apple-music.json
Hex/Resources/Data/tool-definitions/confluence.json
Hex/Resources/Data/tool-definitions/microsoft365.json
Hex/Resources/Data/tool-definitions/day-one.json
Hex/Resources/Data/tool-definitions/things3.json
Hex/Resources/Data/tool-definitions/omnifocus.json
Hex/Resources/Data/tool-definitions/obsidian.json
Hex/Resources/Data/tool-definitions/notion.json
Hex/Resources/Data/tool-definitions/todoist.json
Hex/Resources/Data/tool-definitions/linear.json
Hex/Resources/Data/tool-definitions/zoom.json
Hex/Resources/Data/tool-definitions/hubspot.json
Hex/Resources/Data/tool-definitions/spotify.json
Hex/Resources/Data/tool-definitions/fantastical.json
Hex/Resources/Data/tool-definitions/infra.json
```

---

## 11. Verification Checklist

For each branch, verify:

- [ ] **Build:** Project compiles without warnings on both macOS and iOS targets
- [ ] **Permission prompt:** First use shows the correct system permission dialog (EventKit, Contacts, Photos as applicable)
- [ ] **Castellum routing:** Voice capture with clear intent routes to the correct tool and action
- [ ] **Token logging:** Console shows model used (haiku/sonnet), input token count, output token count per session
- [ ] **Heuristic bypass:** Simple reminder phrase triggers the heuristic router (logged as "heuristic_bypass", no Claude call)
- [ ] **Single Claude call:** Console confirms only one API call per session (no second planning call)
- [ ] **Action execution:** The planned action actually executes and produces the correct result in the target app
- [ ] **Success notification:** User sees a confirmation notification with the action taken
- [ ] **Error handling:** Graceful failure if permission denied, network error, or action fails — no crash
- [ ] **Spotlight:** After session, search `⌘ Space → "Basn"` surfaces recent sessions

### Per-tool spot tests

| Tool | Test phrase | Expected outcome |
|------|------------|-----------------|
| Apple Reminders | "remind me to send the invoice tomorrow at 9am" | Reminder in Reminders.app, due tomorrow 9am |
| Apple Calendar | "schedule a team sync for next Monday at 2pm for an hour" | Event in Calendar.app |
| Apple Notes | "take a note: the client wants blue headers and white text" | New note in Notes.app |
| Files | "save this as a markdown file in my documents folder" | `.md` file in ~/Documents/Basn/ |
| Contacts | "create a contact for Sarah Chen, email sarah@agency.com" | New contact in Contacts.app |
| Messages | "text mom I'm running 10 minutes late" | Messages compose view pre-filled |
| Maps | "get directions to 123 Main Street" | Maps opens with directions |
| Toggl | "start a timer for the TACA project" | Running timer in Toggl |
| Jira | "create a bug ticket for the login crash in the mobile app" | Issue in Jira (correct project) |
| Google Docs | "create a Google Doc for the project brief" | New Doc in Drive |
| Notion | "add a note to my Notion inbox" | Page created in Notion |
| Things 3 | "add finish the proposal to my today list in Things" | Task in Things Today |
| Day One | "journal entry: feeling good about today's progress" | Journal entry in Day One |
| Microsoft 365 | "schedule a Teams meeting with the design team for Thursday" | Meeting in Outlook Calendar |
