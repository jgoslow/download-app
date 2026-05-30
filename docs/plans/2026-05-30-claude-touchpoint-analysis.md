# Claude Touchpoint Analysis — Basn

**Status:** Reference analysis — feeds into `castellum/unified-client` branch work.

---

## Current Touchpoints (live today)

### Touchpoint 1 — Session Analysis
**File:** `Hex/Clients/AnthropicClient.swift`  
**Trigger:** After recording ends, once per session  
**Model:** `claude-sonnet-4-6` (hardcoded)  
**Token profile:** ~350 system + ~750 user → ~200 output  
**Purpose:** Read raw transcript, return structured `SessionAnalysis` JSON: summary, tasks, routing, integrations, mood_tag, prompts_addressed  

**Model verdict: Haiku for most sessions.**  
This is a structured extraction task — read transcript, fill JSON fields. Haiku handles this well for sessions ≤~500 words with clear intent. Escalate to Sonnet only for: long meeting recaps (>500 words), multiple person names that need resolution, or relative date arithmetic.

**Blocking issue:** System prompt hardcodes `"Jonas, a developer and founder of Lyra Designs"` — must be generalized before this ships to any other user. Should become `"Basin is a personal voice capture app. The user's name is {name} and their context is {context}."` pulled from user profile settings.

---

### Touchpoint 2 — Action Planning (Castellum)
**File:** `Hex/Clients/CastellumPlannerClient+Live.swift`  
**Trigger:** After Touchpoint 1 completes (sequential, separate HTTP round trip)  
**Model:** `claude-sonnet-4-6` (hardcoded)  
**Token profile:** ~200 system + ~1,500 tools + ~400 user → ~400 output (tool_use blocks)  
**Purpose:** Given SessionAnalysis, select and parameterize `tool_use` calls for connected tools (Jira, Slack, Toggl, Google, etc.)  

**Model verdict: Haiku for most sessions.**  
Tool selection + parameter fill from a structured analysis is straightforward. Haiku degrades gracefully: if it returns 0 `tool_use` blocks, auto-retry on Sonnet as a fallback. The master plan (section 2C) targets Haiku as default, Sonnet only when: transcript >500 words, 3+ person names, 4+ matched tools, or Haiku retry triggered.

**Key issue:** This is a second sequential HTTP call — adds full round-trip latency. The Claude API supports returning both a `text` block (analysis JSON) and `tool_use` blocks in the same response, so these two calls can and should be merged into one.

---

### Touchpoint 3 — Live Prompt Coverage (Periodic)
**File:** `Hex/Clients/PeriodicParsingController.swift`  
**Trigger:** Every 5 seconds *during* recording, only when the flow has guided prompts  
**Model:** `claude-haiku-4-5-20251001` ✓ (already correct)  
**Token profile:** ~prompt list + ~2,000 transcript chars → 64 output (JSON int array)  
**Purpose:** Check which guided prompts the user has addressed so far in the partial transcript; updates UI in real-time  

**Model verdict: Haiku is correct here. No change needed.**  
This is a lightweight classification call with a tiny output cap. It already uses Haiku. The main thing to watch as flows expand: if guided prompt lists grow long, the input token cost accumulates across multiple 5s intervals — may want to debounce or only re-analyze when transcript length changes significantly (already partially implemented via `lastTranscriptLength`).

---

## Planned Touchpoints

### Planned — Unified Castellum Call
**Planned file:** `Hex/Clients/CastellumClient.swift` (replaces both Touchpoint 1 and 2)  
**Defined in:** Master plan, section 2A + Branch `castellum/unified-client`  
**What changes:** Single API call that returns both the analysis text block AND tool_use blocks in one response. Claude already supports mixed content responses.  
**Model:** Haiku default, Sonnet escalation path via `SessionComplexityClassifier`  
**Caching:** System prompt block + last tool schema get `cache_control: {type: "ephemeral"}` — 5-min TTL, most useful for back-to-back captures in a session  
**Token savings:** ~600 tokens eliminated (second system prompt + duplicate preamble). More importantly: half the latency.

---

### Planned — Contact Context Injection
**Planned file:** `Hex/Clients/ContactsContextClient.swift`  
**Defined in:** Master plan, section 4 (Apple Contacts branch)  
**What it adds:** Before the unified Castellum call, load top-50 contacts and inject into user message as `"Contacts available for name resolution: Diego Martínez <diego@example.com>..."`  
**Model impact:** This is NOT a separate Claude call — it's extra context added to the existing Touchpoint 1+2 (unified) user message. Adds ~1,500 tokens to input. No new call. Helps Claude resolve person names ("Diego" → jira assignee email) without hallucinating.  
**When to include:** Only when session has person mentions or delegation content; skip for pure note/task captures.

---

### Planned — HeuristicRouter (Zero-Claude Path)
**Planned file:** `Hex/Clients/HeuristicRouter.swift`  
**Defined in:** Master plan, section 2B  
**What it does:** Runs regex/pattern matching on the transcript BEFORE any Claude call. If match confidence ≥90%, produces a `PlannedAction` directly without touching the API.  
**Model impact:** **Eliminates Claude entirely** for ~30% of sessions (simple reminders, quick notes, "text mom", "play my playlist").  
**Patterns:** See master plan section 2B table — 9 pattern families covering reminders, notes, messages, calls, music, timers, directions.

---

### Planned — SessionComplexityClassifier
**Planned file:** `Hex/Clients/SessionComplexityClassifier.swift`  
**Defined in:** Master plan, section 2C  
**What it does:** Classifies session into simple/standard/complex before the Claude call, picks model accordingly.  
**No separate Claude call** — pure local Swift logic (word count, person name detection, date math heuristics, connected tool count).

---

## Model Tiering Summary

| Touchpoint | Current Model | Target Model | Rationale |
|-----------|:-------------:|:------------:|-----------|
| Session Analysis (Call 1) | Sonnet 4.6 | **Haiku 4.5** (default) | Structured extraction; Sonnet only for >500w / complex |
| Action Planning (Call 2) | Sonnet 4.6 | **Haiku 4.5** (default) | Tool selection; Sonnet on retry or >4 tools |
| Live Prompt Coverage | **Haiku 4.5** ✓ | No change | Already correct |
| Unified Call (planned) | — | **Haiku 4.5** default, Sonnet escalation | Merges 1+2 with classifier gating |
| HeuristicRouter bypass | — | **No model** | Local pattern matching, ~30% of sessions |
| Contact context injection | — | **No model** | Local lookup, injected into existing call |

---

## What Needs to Happen Before Adding More Integrations

In order of priority (blocks shipping to other users):

1. **Generalize system prompt** (`AnthropicClient.swift:93`) — remove hardcoded name and company. Replace with user profile fields from `BasnSettings`.
2. **Merge calls 1+2** into `CastellumClient.swift` — eliminates second round trip, halves latency.
3. **Add prompt caching** — `cache_control: ephemeral` on system block and last tool schema in the unified call.
4. **Add `SessionComplexityClassifier`** — gate Haiku/Sonnet selection before every call.
5. **HeuristicRouter** — bypass Claude entirely for simple patterns.

Items 2–5 are ordered dependencies: unified client first, then caching inside it, then model tiering, then the heuristic bypass layer in front of it.

---

## Files Requiring Change (Pre-work phase only)

| File | Change |
|------|--------|
| `Hex/Clients/AnthropicClient.swift` | Generalize system prompt; expose user profile injection point |
| `Hex/Clients/CastellumPlannerClient+Live.swift` | Deprecate; delegate to new unified client |
| `Hex/Clients/CastellumClient.swift` | **New** — unified single-call client with caching + model tiering |
| `Hex/Clients/SessionComplexityClassifier.swift` | **New** — local model routing logic |
| `Hex/Clients/HeuristicRouter.swift` | **New** — pattern-based bypass |
| `Hex/Features/Castellum/CastellumFeature.swift` | Wire `planExecution` to new unified client |
| `HexCore/Sources/BasnCore/Settings/BasinSettings.swift` | Add user name/context fields for system prompt |

---

## Notes on Flows Refactoring Impact

Per your note that flows work is in progress: the unified `CastellumClient` needs to accept Flow context as an input parameter (flow name, guided prompts, any flow-specific routing hints) so Castellum's combined prompt can incorporate it. The current `AnthropicClient.analyze()` already accepts `promptTitles` and the session's `flowID` — those need to be preserved in the unified call signature.

The `PeriodicParsingController` (Touchpoint 3) reads flow prompts independently and can remain decoupled from the unified client — it's a separate live-feedback concern, not part of the post-session pipeline.
