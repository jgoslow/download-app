# Basin System Model

## The Three Layers

### Flows
*When and how you capture.*

A Flow is a named capture context — Morning Kickoff, Day's End, Open. It sets the frame for what Castellum should pay attention to (e.g., in Morning Kickoff, surface action items and blockers; in Day's End, summarize and log hours). Users can create, customize, and schedule Flows. Flows are the only user-facing trigger concept.

### Tools
*What's possible.*

A Tool is an authenticated integration with an external service. Each tool has:
- Auth (OAuth or API key)
- A set of **actions** defined declaratively in JSON (create_event, send_email, create_issue, etc.)
- Optional **action-level permissions** — which actions the user has explicitly enabled

Tools are the only layer users configure ahead of time. A connected tool with enabled actions tells Castellum: "you are allowed to do these things."

Tool definitions live in `Hex/Resources/Data/tool-definitions/*.json`. Adding a new tool means adding a JSON file — no Swift code required for standard HTTP integrations.

### Channels / Workflows
*What happened.*

A Channel (also called a Workflow — nomenclature still evolving) is an **emergent outcome** produced by Castellum for a given capture. It is NOT predefined or user-configured. It arises organically from:
- The content of the capture transcript
- The Flow context
- The set of connected tools and their permitted actions

A single capture might produce multiple channel outcomes: a Jira card, a calendar event, and a Slack message. These are the channels for that capture. Castellum determines what's appropriate; the user confirms or auto-executes based on their tool settings.

**Channels map to outcomes, not settings.**

### Castellum
*The orchestration layer.*

Castellum reads the capture, constructs a plan of tool actions to execute, and runs them (with or without user confirmation depending on auto-execute settings). The "channel" is what emerges from Castellum's plan.

---

## What This Means for the UI

| Area | Current (wrong) | Target |
|---|---|---|
| Settings → Channels | User toggles predefined channels on/off | Replaced by: connected tools + their permitted actions |
| Channel list | Hardcoded: Write email, Create Jira card, etc. | Derived from Castellum's outcome history |
| "Connect X first" blocking | Channel availability gated on tool connection | Tools connect; Castellum uses what's available |
| Channel configuration | toolBinding, requiredToolIDs, isEnabled | Gone — outcomes are computed, not configured |

---

## Code Refactor Backlog

### Remove
- `ChannelDefinition.allDefaults` — no pre-seeded channel list
- Channel seeding in `HexAppDelegate.seedDefaultData()`
- `ChannelsSectionView` "configure channels" UI (or repurpose entirely)
- `ChannelDefinition.toolBinding`, `requiredToolIDs`, `isEnabled` — pre-config concepts

### Rename / Repurpose
- `ChannelDefinition` → `CaptureOutcome` (a historical record of what Castellum produced)
- `channels` key in tool definition JSON → `workflows` (what workflows this tool can execute)
- `ToolDefinitionSpec.channels` → `.workflows`

### Keep
- Tool definition JSON files — correct abstraction, just rename `channels` key
- `PlannedAction` and Castellum execution layer — this IS the channel concept, named correctly
- Tool auth, action definitions, action-level permissions plan

---

## Aspirational (v2+)

- **User-defined workflows**: Users describe a multi-step automation in natural language; Basin asks clarifying questions to formalize it into a reusable workflow template
- **Multi-tool workflows**: A single workflow invoking actions across Jira + Slack + Toggl
- **Workflow marketplace**: Community-contributed workflow templates, installable via the tool library
- **Tool library**: Users contribute custom integrations (any REST endpoint + auth scheme) conversationally
