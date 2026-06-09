# Claude Touchpoint Analysis — Basn

**Status:** Reference analysis — feeds into `castellum/unified-client` branch work. Updated to reflect iOS real-time transcription architecture.

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

## How Real-Time iOS Transcription Changes the Approach

### What iOS has now

`FlowTranscriptionEngine` (`iOS/Flow/FlowTranscriptionEngine.swift`) uses `SFSpeechRecognizer` with `requiresOnDeviceRecognition: true`. It delivers two event streams:
- `onPartialUpdate` — raw in-progress text as speech is happening
- `onSentenceComplete` — finalized sentence segments, one at a time

`FlowSessionViewModel` tags each completed sentence to its active prompt (`promptIndex`, `promptTitle`) and stores it as a `TranscriptEntry`. The `onResult` callback at flow end delivers `[Int: Set<String>]` (chip selections per prompt) + `[String]` (ordered sentence list) — a structured, prompt-contextualized transcript, not a flat blob.

The "next" command detection is already a local pattern matcher (`isNextCommand`) — zero Anthropic involvement.

### The architectural implication

**The HeuristicRouter should not be post-session batch processing. It should be streaming, sentence-by-sentence, running during the recording.**

Right now the planned `HeuristicRouter` fires once after the recording ends, checks the full transcript, decides whether to bypass Claude. But by the time recording ends, the first sentence may have already contained the entire routing signal ("remind me to send the invoice tomorrow at 9am"). If the router had been running on the sentence stream, it would already have a `PlannedAction` ready — and the session ends with zero post-recording latency, no API call at all.

This is the model that makes sense:

```
sentence arrives (on-device) 
    → StreamingHeuristicRouter.process(sentence, promptContext)
        → pattern match → PlannedAction? (partial or confirmed)
    → accumulate routing signals
    
recording ends
    → if StreamingHeuristicRouter has high-confidence action(s): execute directly, skip Claude
    → else: send structured transcript + partial signals to Castellum (Haiku/Sonnet)
```

### What desktop needs

macOS Basn uses WhisperKit/Parakeet for final transcription — high quality, but batch. It doesn't have sentence-level callbacks during recording. The current `PeriodicParsingController` polls a growing audio file every 5s, but that's oriented around prompt coverage, not action routing.

**Option A — Dual-track (recommended for near term):** Run `SFSpeechRecognizer` on macOS alongside the WhisperKit recording. SFSpeechRecognizer is available on macOS 10.15+ and works identically to iOS. It provides the low-latency sentence stream for heuristic matching. WhisperKit provides the final high-quality transcript for Claude (if Claude is needed at all). The two run in parallel; the final Castellum input is always WhisperKit output, but by that point heuristics have already had first crack.

**Option B — Extend PeriodicParsingController:** Feed each periodic WhisperKit snapshot into the `StreamingHeuristicRouter` in addition to (or instead of) the prompt-coverage Claude call. Lower quality for fast patterns, but no new dependency.

Option A is cleaner and already proven — `FlowTranscriptionEngine` is the template.

### What this means for the structured transcript

A prompt response is not just voice/text — it's any combination of voice sentences, chip selections, or both. Both are co-equal signal sources for a given prompt. The structured input to Castellum should model this:

```
Prompt: "What blockers are you facing?"
  chips: []
  voice: ["Had a call with Diego. We need to fix the login crash."]

Prompt: "Which tools do you use?"
  chips: ["jira", "slack"]
  voice: ["We use Jira for everything, also Toggl for time."]

[no prompt — free capture, position 7 in stream]
  voice: ["Also need to send the updated brief to the client."]
```

This is significantly better input for Claude than a flat transcript — it tells Castellum which intent belongs to which context, with explicit confirmation signals from chip selections. A chip selection for a tool prompt is stronger than any inference from voice alone.

**Some sentences have no active prompt — that's fine.** The ordinal position in the stream still carries context. A sentence spoken before any prompts (preamble), between prompts, or after all prompts are done can still be routed — it just lacks the specificity of a prompt-tagged entry. The Castellum prompt should represent these as positioned entries without a prompt label, preserving their place in the sequence.

The structured format as a flat list for Claude's consumption:

```
[1] → Prompt "What blockers are you facing?"
      chips: (none)  |  "Had a call with Diego."

[2] → Prompt "Which tools do you use?"
      chips: jira, slack  |  "We use Jira for everything, also Toggl."

[3] → (no prompt)
      "Also need to send the updated brief to the client."
```

The `(no prompt)` entries should never be dropped — their position relative to the prompted entries is meaningful context.

**Desktop should produce this same structure.** The WhisperKit final transcript is a flat string today. Prompt advancement events during recording (timestamp when the user moved to the next prompt) can be used to segment which sentences belong to which prompt context.

### Revised model tier thinking

With sentence-streaming heuristics, the Haiku/Sonnet decision becomes more nuanced:

| Session type | New path | Claude needed? |
|-------------|----------|:--------------:|
| Single clear pattern ("remind me to X") | HeuristicRouter catches during recording | **No** |
| Multi-sentence with chips selected | Chips pre-route, Claude fills parameters | Haiku, reduced input |
| Complex with multiple tools, no clear pattern | Full Castellum call with structured transcript | Haiku or Sonnet |
| Long meeting/brainstorm, 4+ tools | Structured sentence-tagged transcript | Sonnet |

The net effect: the ~30% Claude bypass estimate from the master plan is likely conservative. With streaming heuristics catching intent earlier (rather than waiting for full transcript), and chip selections pre-routing a significant portion of flow sessions, the real bypass rate is probably closer to 40–50% for regular users.

---

## What Needs to Happen Before Adding More Integrations

In order of priority (blocks shipping to other users):

1. **Generalize system prompt** (`AnthropicClient.swift:93`) — remove hardcoded name and company. Replace with user profile fields from `BasnSettings`.
2. **Merge calls 1+2** into `CastellumClient.swift` — eliminates second round trip, halves latency.
3. **Add prompt caching** — `cache_control: ephemeral` on system block and last tool schema in the unified call.
4. **Add `SessionComplexityClassifier`** — gate Haiku/Sonnet selection before every call.
5. **`StreamingHeuristicRouter`** — runs during recording on sentence callbacks (iOS: `onSentenceComplete`; macOS: SFSpeechRecognizer dual-track or PeriodicParsingController feed). Not post-session batch.
6. **Structured transcript pipeline** — carry sentence-to-prompt tagging from `FlowSessionViewModel` through to Castellum input. Pass chip selections as confirmed routing hints.

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

The unified `CastellumClient` call signature needs to accept:
- `flowID` and `promptTitles` (already present in `AnthropicClient.analyze()`)
- `structuredEntries: [(sentence: String, promptIndex: Int?, promptTitle: String?, chips: Set<String>)]` — replaces the flat `rawText` string. `promptIndex` and `promptTitle` are optional because some sentences have no active prompt; their position in the ordered array still matters and should be preserved. `chips` is non-empty only for entries that represent a prompt response that included chip selections.
- Chip selections are **co-equal responses** to their prompt alongside voice/text — not a separate signal. They should be merged into the same entry so Castellum sees "for this prompt, the user said X and also tapped these chips."

The `PeriodicParsingController` (Touchpoint 3) serves a different purpose — live prompt coverage UI feedback during recording — and remains decoupled. It should NOT be conflated with the `StreamingHeuristicRouter`, which is about routing decisions, not UI feedback.

For desktop specifically: the macOS recording pipeline records to a file and transcribes post-recording. To get sentence-level streaming for heuristics, the cleanest path is to add a lightweight `SFSpeechRecognizer` instance that runs concurrently with the main recording (just like iOS `FlowTranscriptionEngine`) and feeds `StreamingHeuristicRouter`. WhisperKit output remains the source of truth for the final transcript sent to Claude.
