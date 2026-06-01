# Plan: Setup Flow Onboarding + Flow Session Screen
**Date:** 2026-05-31

---

## Context

Basn's onboarding today ends after 2 steps (welcome+mic / language selection). Once the user reaches the home screen they have a fully transcribing app but no context about what tools to connect, what flows to run, or what Basn is really for. This plan adds a third onboarding step — a **setup flow** — that introduces the flow screen concept and gathers the configuration Basn needs to be useful from day one.

The setup flow is also the first exercise of the **flow session screen**, which is a net-new core UI feature: a full-screen capture experience with a live transcript area, a prompt carousel, dot navigation, and type/voice toggling. This plan specs and builds both.

**Applies to both macOS and iOS.**

---

## What We're Building

1. **Enriched `FlowPrompt` model** — adds `kind`, `timerSeconds`, `choices` so prompts can be timed, required, optional, or Castellum-generated
2. **Setup `FlowDefinition`** — a curated prompt sequence seeded on first launch; the first flow every user runs
3. **Onboarding bridge step** — a new Step 2 (macOS) / Page 2 (iOS) that explains flows and offers "Start Flow" or "Skip setup"
4. **`FlowSessionView`** — the mobile-first flow session screen: live transcript, prompt carousel, dot nav, timer animations
5. **Setup completion state + homepage checklist** — tracks which setup steps are done; shown on home if setup is incomplete

---

## Phase A: Enrich `FlowPrompt` Data Model

**File:** `Hex/Models/BasinModels.swift`

Replace the current minimal `FlowPrompt` struct:

```swift
// Current
struct FlowPrompt: Codable, Identifiable, Sendable, Equatable {
    var id: Int
    var title: String
    var detail: String
}
```

New version:

```swift
struct FlowPrompt: Codable, Identifiable, Sendable, Equatable {
    var id: Int
    var title: String
    var detail: String
    var isRequired: Bool           // true → must be answered or explicitly swiped past
    var timerSeconds: Double?      // if set, liquid-fill timer auto-advances when empty
    var choices: [PromptChoice]?   // optional tappable chips (multi-select if needed)
    var isCastellumGenerated: Bool // true → injected at runtime; shown with distinct dot style

    struct PromptChoice: Codable, Sendable, Equatable, Identifiable {
        var id: String
        var label: String
    }

    // Convenience initializer matching existing call sites
    init(id: Int, title: String, detail: String = "",
         isRequired: Bool = false, timerSeconds: Double? = nil,
         choices: [PromptChoice]? = nil,
         isCastellumGenerated: Bool = false) { ... }
}
```

**Why this shape:**
- `isRequired` and `timerSeconds` are orthogonal — a prompt can be optional-with-timer (common) or required-without-timer (common), etc.
- Castellum can inject any kind of prompt (required, timed, or plain optional); `isCastellumGenerated` is a display flag only — it drives dot styling and a subtle animation, not behavioral logic.
- `timerSeconds != nil` is the sole signal for timed behavior; no need for a separate enum case.

**Migration:** existing `FlowPrompt` JSON without these fields decodes safely via `decodeIfPresent` with defaults (`isRequired: false`, `timerSeconds: nil`, `isCastellumGenerated: false`).

---

## Phase B: Setup Flow Definition

The setup flow is a `FlowDefinition` with `id: "setup"`, seeded into the SwiftData store on first launch if it doesn't already exist. It runs once, post-onboarding.

**Seed location:** `Hex/App/BasnAppDelegate.swift` (macOS) and `iOS/App/AppState.swift` (iOS) — both call a shared `SeedData.seedSetupFlowIfNeeded(context:)` helper. The helper lives in a new shared file, or inline in each.

### Prompt sequence (v1 — static prompts, one API call at end)

| # | Required | Timer | Title | Choices |
|---|----------|-------|-------|---------|
| 1 | no | 2s | "Welcome to your first flow." | — |
| 2 | no | 6s | "Speaking out loud is the best way to use Basn — but you can always switch to text at any time." | — |
| 3 | **yes** | — | "What would you like to use Basn for?" | Work / Life / Growth / Something else |
| 4 | no | — | "What does a typical day or week look like for you? Share as much or as little as you like." | — |
| 5 | **yes** | — | "Which tools do you use?" | Jira / GitHub / Slack / Toggl / Google / Wave |
| 6 | no | 8s | "Basn creates workflows for you automatically — connect the tools and it figures out where your thoughts should go." | — |
| 7 | no | — | "What outcomes matter most to you? Tasks, messages, time logs, reminders, journal entries?" | — |
| 8 | no | — | "When do you usually want to capture your thoughts?" | Morning / Evening / Midday / Whenever |
| 9 | **yes** | — | "Anything else you want Basn to know about how you work or what you're trying to get out of it?" | — |

**Post-flow (one Anthropic API call):** full transcript → Claude Sonnet → returns JSON with: suggested tool connections, a first Flow name + schedule + cadence suggestion, 2–3 suggested Workflow descriptions. Cost: ~2k in + ~1k out ≈ $0.01/user. Not a recurring call.

After the API call:
- One-by-one tool connection screens (OAuth/API key) for each tool they mentioned
- Summary screen: "Here's what we've set up — flows, tools, and workflows"
- Done screen: "Well done. I've got a reminder scheduled for [cadence]. Do you want to do a quick flow now? [Open flow] [Morning Kickoff]"

---

## Phase C: Onboarding Bridge Step

Both platforms add one new step/page that bridges the existing model/mic steps into the setup flow.

### macOS — `Hex/Features/App/WelcomeView.swift`

Add `step == 2` to the existing `step` state variable. Step 2 is the bridge screen:

**Content:**
```
Basn works by capturing your thoughts as you speak (or type) and surfacing 
prompts for you to speak to during a flow session. Prompts can come from 
the flow, things you've said before, or even other sources.

Let's try it out by doing a setup flow.

[  ▶  Start Flow  ]    ← primary button using existing record-button lockup style

                  skip setup →   ← link, remains through all subsequent setup steps
```

The "Start Flow" button transitions to the `FlowSessionView` (Phase D) running the setup flow. "Skip setup" marks `hasCompletedSetupFlow = true` and opens the main app.

### iOS — `iOS/Onboarding/OnboardingView.swift`

Add `page == 2` to the existing `TabView`. Same content/behavior as above but in the full-screen dark video style (consistent with pages 0 and 1). "Start Flow" → pushes `FlowSessionView` as a full-screen sheet. "Skip setup" → `appState.completeSetupFlow()`.

### Completion state

**`iOS/App/AppState.swift`:**
```swift
var showSetupFlow: Bool = !UserDefaults.standard.bool(forKey: "hasCompletedSetupFlow")

func completeSetupFlow() {
    UserDefaults.standard.set(true, forKey: "hasCompletedSetupFlow")
    showSetupFlow = false
}
```

macOS: same pattern, read in `BasnAppDelegate.swift` after `hasCompletedOnboarding` is true.

---

## Phase D: `FlowSessionView` — Flow Screen UI (iOS-first)

New file: `iOS/Flow/FlowSessionView.swift`

### Layout

```
┌─────────────────────────────────────────┐
│ ↑  Live transcript — last ~3 sentences  │  ← 20% of screen height
│    (low-opacity, flows up as text grows)│    drag down → expands full-height
├─────────────────────────────────────────┤
│                                         │
│                                         │
│    [Prompt title text]                  │  ← center section
│    [Prompt detail, if any]              │
│                                         │
│    [Choice chip A]  [Choice chip B]     │  ← if prompt has choices
│    [Choice chip C]  [Choice chip D]     │
│                                         │
│                                         │
├─────────────────────────────────────────┤
│  ← ○ ○ ● ○ ○ →   dot nav               │  ← active dot center, animated
│  [🎤 mic]  [ Record button ]  [⌨ text]  │
└─────────────────────────────────────────┘
```

### Sub-components

**`LiveTranscriptView`**
- Shows last 3 sentences of running transcript
- Text color: `white.opacity(0.35)` (low contrast, readable but not distracting)
- New sentences push from bottom; old ones flow upward and fade
- Drag down gesture → `isExpanded = true`: scrollable full-transcript overlay
- Collapsed: fixed 20% height. Expanded: takes full screen minus bottom bar
- Up-arrow button (top-right) or swipe-up gesture collapses back

**`PromptCarouselView`**
- Displays active prompt title + detail
- `.transition(.opacity.combined(with: .move(edge: .trailing)))` between prompts
- "Beat" before new prompt: 0.5s blank gap after previous exits
- Wait for speech pause before advancing (detect via 1s silence in transcript)
- Choice chips as `HStack` of `Button` styled as outlined capsules; selecting one highlights it and marks the prompt as answered

**`PromptDotNavView`**
- Row of dots, active dot centered
- Scroll/swipe left-right to navigate
- Active dot: 18pt circle with state-driven animation:
  - has timer → liquid-fill ring draining: `Circle` stroke with `trim(from:to:)` animated 1.0 → 0.0
  - required + no timer → solid bright ring, gentle scale pulse (1.0 ↔ 1.05 every 2s)
  - optional + no timer → dim grey ring, no animation
  - Castellum-generated → any of the above + a faint glow/shimmer to indicate AI origin
- Inactive dots: 8pt, color varies: bright for required, grey for optional
- Castellum-injected prompts pop in with a spring animation when added to the timeline

**`FlowSessionViewModel` (or local `@State`)**

```swift
@Observable class FlowSessionViewModel {
    var prompts: [FlowPrompt]
    var activeIndex: Int = 0
    var transcriptSentences: [String] = []
    var isTranscriptExpanded: Bool = false
    var promptAnswers: [Int: String] = [:]    // promptID → answer text
    var selectedChoices: [Int: Set<String>] = [] // promptID → selected choice IDs
    var timerRemaining: Double = 0
    var isComplete: Bool = false
    
    // Advance to next prompt (with beat)
    func advance() async { ... }
    // Mark prompt answered and start short advance timer
    func markAnswered(promptID: Int) { ... }
}
```

### Timer behavior (`.timed` prompts)
- `timerRemaining` counts down from `prompt.timerSeconds`
- `Circle().trim(from: 0, to: timerRemaining / prompt.timerSeconds!)` renders the drain
- Uses `Task { while timerRemaining > 0 { try await Task.sleep(for: .seconds(0.05)); timerRemaining -= 0.05 } advance() }`

### Text/voice toggle
- Mic icon (left of record button) and keyboard icon (right) — same toggle pattern already noted for iOS home screen
- When "text" mode: bottom sheet with Slack-like text input field + submit button

### macOS flow screen
Defer to a follow-up plan. The macOS version will differ (less constrained layout, likely a floating panel or inline in the settings window). For now macOS shows the setup flow onboarding step but routes to the same `FlowSessionView` wrapped as an NSHostingView.

---

## Phase E: Post-Flow + Setup Completion

After all setup flow prompts are done:

1. **Castellum call** — `SetupFlowAnalyzer.analyze(transcript:choices:)` — one Anthropic call. System prompt includes: Basn tool list, Flow schema template. Returns a `SetupFlowResult` struct with suggested tools, first Flow, and 2-3 Workflows.

2. **Tool connection sequence** — for each suggested tool, present `ToolConnectView` (reuse `ToolsSectionView` connection logic from `Hex/Features/Settings/ToolsSectionView.swift`). User can connect or skip each.

3. **Setup summary screen** — lists what was set up: flows created, tools connected, workflows ready. "Everything looks good" or "here's what to do next."

4. **Done screen** — "Well done. I've got a reminder set for [cadence]." Two CTA buttons: `[Open flow]` and `[Morning Kickoff]` (or whatever first Flow was suggested).

5. **Call `completeSetupFlow()`** — sets `hasCompletedSetupFlow = true`.

---

## Phase F: Homepage Setup Checklist

**iOS:** `iOS/HomeView.swift` — if `!appState.hasCompletedSetupFlow`, show a `SetupProgressView` above the record button with 4 items:
1. ✅ Connect Microphone
2. ✅ Download Transcription Model  
3. ⬜ Run Setup Flow → taps into setup flow
4. ⬜ Perform Your First Flow → grayed until setup is done

**macOS:** Same component in `Hex/Features/Home/HomeView.swift`, shown below the flow picker if setup is incomplete.

---

## Decisions deferred to future plans

- **Real-time Castellum polling during flow** (v2): checking the transcript every 2-3s for prompt completion. v1 uses swipe or manual advancement for untimed prompts.
- **Dynamic prompt injection** (`.dynamic` kind): Castellum adds prompts to the timeline mid-flow. Spec'd above but not built in v1.
- **Desktop flow screen design**: macOS gets a proper flow screen layout after mobile is validated.
- **Spheres/domains**: the concept of tagging workflow outputs to life areas (Work / Life / Growth) is acknowledged in the setup flow prompt sequence ("What would you like to use Basn for?") and stored as domain tags on FlowDefinition, but the routing logic is not built here.
- **Flow scheduling + skip-counting**: `scheduleDays`, `scheduleReminderEnabled` already exist on `FlowDefinition`. Skip-count logic (3 skips → reschedule prompt) is a separate feature.
- **Privacy page**: content work, separate PR.
- **Audio retention setting**: add to Settings as a follow-up.

---

## Verification

1. **Model change**: run `swift test` in `HexCore/` to confirm `FlowPrompt` decoding/encoding roundtrips work with and without the `kind` field.
2. **Onboarding flow (iOS)**: reset `hasCompletedOnboarding` in simulator, run through all 3 pages, confirm "Skip setup" lands on home, confirm "Start Flow" opens the flow session screen.
3. **Onboarding flow (macOS)**: `defaults delete com.lyra.basn.debug hasCompletedOnboarding`, relaunch, confirm step 2 appears and both CTAs work.
4. **Setup flow prompts**: run through all 9 prompts — confirm timed prompts auto-advance, required prompts wait, choice chips highlight on tap and mark prompt answered.
5. **Transcript area**: speak during a flow, confirm sentences appear and scroll up, drag down to expand, up-arrow to collapse.
6. **Post-flow**: confirm API call fires after prompt 9, tool connection screens appear for mentioned tools, done screen shows correct CTA labels.
7. **Checklist**: after skipping setup, confirm checklist appears on home screen; after completing, confirm it disappears.

---

## Critical Files

| File | Change |
|------|--------|
| `Hex/Models/BasinModels.swift` | Enrich `FlowPrompt` |
| `Hex/Features/App/WelcomeView.swift` | Add step 2 |
| `iOS/Onboarding/OnboardingView.swift` | Add page 2 |
| `iOS/App/AppState.swift` | `hasCompletedSetupFlow` state + method |
| `iOS/Flow/FlowSessionView.swift` | **NEW** — full flow session screen |
| `iOS/HomeView.swift` | Add setup checklist |
| `Hex/Features/Home/HomeView.swift` | Add setup checklist |
| `Hex/App/BasnAppDelegate.swift` | Seed setup FlowDefinition on first launch |
