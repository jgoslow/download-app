---
name: basin-architecture-decisions
description: "Three-layer system (Flows/Channels/Tools) built on SwiftData + CloudKit, with Castellum orchestration — channels are emergent workflows, not predefined configs"
metadata: 
  node_type: memory
  type: project
  originSessionId: 3f3bf9d1-edae-44c8-847e-cacd6174dc98
---

Basin has a three-layer system modeled after Roman waterworks:

1. **Flows** — capture rituals (Morning Kickoff, Day's End, etc.). When and how you record.
2. **Channels** — emergent workflows produced by Castellum from a capture. NOT predefined by the user; they arise organically from the Flow context + connected Tools. A Channel maps to an outcome (a Jira card, a calendar event, an email draft). The user doesn't configure channels ahead of time — they configure tools, and Castellum figures out what workflows are possible.
3. **Tools** (mechanisms) — external services that do the work. Jira, Slack, Google, Toggl, etc. Each tool has declarative actions defined in JSON. Tools are the only layer users configure ahead of time (auth + which actions to permit).

**Nomenclature:** "Workflow" is the chosen term (confirmed 2026-05-22). Historically called "Channel" — if you see "channel" in old code, git history, or docs, it means workflow. In Shopify terms, think "automation" but implemented via English-language LLM instruction rather than trigger/condition/action UI.

**Castellum = CNS.** On-device AI orchestration via Anthropic API. Castellum reads the capture transcript, knows which tools are connected and what actions they expose, and generates a plan of actions to execute. The "channel" is what emerges from that plan.

**Evaporation = feedback loop.** Channel outputs (closed cards, logged hours, sent messages) become pre-session context for the next capture.

**What channels are NOT:**
- Not a pre-configured list the user toggles on/off in Settings
- Not a 1:1 mapping to a single tool action
- Not user-defined workflows (yet — this is aspirational for v2)

**What channels ARE:**
- An emergent outcome produced by Castellum for a given capture
- Potentially multi-step and cross-tool (send Slack message + create Jira card + log time)
- A record of what happened (history), not a prediction of what might happen
- Named by the system based on what was produced ("Logged time in Toggl", "Created Jira card TACA-42")

**Data architecture (decided 2026-03-22, revised 2026-05-22):**
- SwiftData + CloudKit private database for cross-device sync
- On-device first; server may return for heavier processing
- Tool actions configurable per tool (auto-execute vs. confirm)
- UserDefaults via @Shared stays for HexSettings/BasinSettings
- Audio files stay on disk; SwiftData stores path only
- `ChannelDefinition` model has been replaced by `Workflow` — a SwiftData model with `name`, `instruction` (English-language LLM prompt), `isEnabled`, `flowID?`. No pre-seeded defaults.
- Tool definition JSON files use `"workflows"` key to declare which workflow IDs a tool can execute and via which action

**Error & Usage Pipeline (planned, 2026-03-28):**
- Opt-in setting: "Send usage and error logs to help improve Basin"
- Tool execution errors auto-create tickets in BASN Jira project

**How to apply:** Tools = the only configurable layer. Channels/workflows = emergent outcomes Castellum produces. Never build a pre-configured channel list that users must maintain.
