# Plan: Three Flow Session Fixes
**Date:** 2026-06-01

---

## Context

Three issues observed during hands-on testing of the setup flow:

1. **Transcript not segmented by prompt** — sentences pile up as a flat stream with no indication of which prompt each response belongs to. When the user reviews it (expanded view) or when Castellum processes it, context is lost.

2. **"What outcomes matter most to you?" has no chips** — prompt 7 asks an open-ended question but the plan always called for tappable chips. The `detail` field currently hints at options in text form; those should become selectable chips.

3. **Tool onboarding phases skipped entirely** — after finishing the flow, the wizard jumps straight to "All Set" without showing any tool connection screens. Root cause: `OnboardingView` is presented as a `fullScreenCover` from `ContentView`, but the `modelContainer` environment is not explicitly forwarded to the cover's content. `@Query` in `SetupFlowBridgePage` finds no tools, `toolsToConnect` is always empty, and `case .connectTool(index: 0)` immediately falls through to `SetupDoneView`.

---

## Fix 1 — Prompt-tagged transcript

**Files:** `iOS/Flow/FlowSessionView.swift`

Add a `TranscriptEntry` struct (nested or private) alongside `FlowSessionViewModel`:

```swift
struct TranscriptEntry: Identifiable {
    let id = UUID()
    let sentence: String
    let promptIndex: Int
    let promptTitle: String
}
```

Change `transcriptSentences: [String]` → `transcriptEntries: [TranscriptEntry]` in `FlowSessionViewModel`.

Update `appendTranscriptSentence` to tag entries with `activeIndex` and `activePrompt?.title ?? ""`.

Update `submitTextInput` and the `onSentenceComplete` closure — both call `appendTranscriptSentence`.

Update `LiveTranscriptView` to accept `[TranscriptEntry]` instead of `[String]`. Group entries by `promptIndex` with a small prompt label header above each group:

```
[prompt title, dim/small]
  sentence 1
  sentence 2
[next prompt title]
  sentence 3
```

Collapsed mode (last 3): show the trailing 3 entries regardless of group, but include the header for the group they belong to.

Update the `onResult` call in `completionView` to pass `model.transcriptEntries.map(\.sentence)` — no change to the `onResult` signature.

---

## Fix 2 — Outcomes chips

**File:** `Shared/Sources/BasinShared/Models/FlowPrompt.swift`

Prompt ID 7 currently:
```swift
FlowPrompt(
    id: 7,
    title: "What outcomes matter most to you?",
    detail: "Tasks, messages, time logs, reminders, journal entries?"
)
```

Change to:
```swift
FlowPrompt(
    id: 7,
    title: "What outcomes matter most to you?",
    choices: [
        PromptChoice(id: "tasks",     label: "Tasks"),
        PromptChoice(id: "messages",  label: "Messages"),
        PromptChoice(id: "time_logs", label: "Time logs"),
        PromptChoice(id: "reminders", label: "Reminders"),
        PromptChoice(id: "journal",   label: "Journal"),
    ]
)
```

Remove the `detail` (it restated the choices in prose form). No other changes needed — `ChoiceChipsView` is already rendered for any prompt with `choices`.

---

## Fix 3 — Forward model container to onboarding cover

**File:** `iOS/App/BasnAppIOS.swift`

The `fullScreenCover` content needs an explicit `.modelContainer()` because SwiftUI doesn't reliably propagate it across presentation boundaries:

```swift
.fullScreenCover(isPresented: ...) {
    OnboardingView()
        .environment(appState)
        .modelContainer(Self.modelContainer)   // ← add this
}
```

This lets `@Query(sort: \Tool.name) private var allTools: [Tool]` in `SetupFlowBridgePage` resolve against the shared container and return the 6 default tools, so `toolsToConnect` is populated and the wizard flows through each tool screen.

---

## Verification

1. **Transcript grouping** — start a flow, speak to 2–3 different prompts, expand the transcript; entries should be grouped under their respective prompt title headers.
2. **Outcomes chips** — navigate to prompt 7; chips should appear and be tappable/multi-selectable (same style as prompt 3 and 5).
3. **Tool screens** — complete the setup flow; after "Finish Setup", the Jira connection screen should appear first (or whichever tools were chip-selected on prompt 5), followed by each subsequent tool, then workflows → suggested flow → done. No longer jumps straight to "All Set".

---

## Critical Files

| File | Change |
|------|--------|
| `iOS/Flow/FlowSessionView.swift` | Add `TranscriptEntry`; tag entries with prompt index; update `LiveTranscriptView` to group by prompt |
| `Shared/Sources/BasinShared/Models/FlowPrompt.swift` | Add choices to prompt 7; remove its `detail` |
| `iOS/App/BasnAppIOS.swift` | Add `.modelContainer(Self.modelContainer)` to the onboarding `fullScreenCover` |
