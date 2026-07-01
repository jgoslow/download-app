---
type: planning
status: active
updated: 2026-07-01
tags: [planning, summary]
---

# Planning Summary
<!-- Maintained by /vault distill. Last distilled: 2026-07-01 -->

## Outstanding

- [ ] Test recording reliability during outdoor run (background audio + interruption recovery + Watch workout coexistence) — source: [session-ios-history-audio-pause](../captures/2026-07-01-session-ios-history-audio-pause.md)
- [ ] Pause/resume UI placement — toggle button is temporary; will move when Flow UI is redesigned — source: [session-ios-history-audio-pause](../captures/2026-07-01-session-ios-history-audio-pause.md)
- [ ] Stale changesets (.changeset/*.md ref `hex-app` old name) — recreate with `basn` before next release — source: [session-ios-history-audio-pause](../captures/2026-07-01-session-ios-history-audio-pause.md)
- [ ] Fix Castellum → Toggl tool_use bug (prose returned instead of tool_use block for multi-intent captures) — source: [REQ-castellum.md](REQ-castellum.md)
- [ ] Audio integration test layer — infra BUILT (WER, AudioPipelineTests, LFS corpus, CI); remaining: populate the diverse-speaker corpus — source: [REQ-testing.md](REQ-testing.md)
- [ ] Fix iOS tool connections (OAuth "no provider ID") — blocks Connect→Execute on device; deferred to tools overhaul — source: [REQ-castellum.md](REQ-castellum.md)
- [ ] Migrate macOS to capability routing (iOS is on it; macOS still tool-scoped) — source: [REQ-castellum.md](REQ-castellum.md)
- [ ] Per-flow capability→tool preference (resolver defaults to any connected provider) — source: [REQ-castellum.md](REQ-castellum.md)
- [ ] Implement action-level permissions tier 2 (action checkboxes after OAuth scope selection) — source: [REQ-castellum.md](REQ-castellum.md)
- [ ] Phone Call Mode — iOS-first feature (hold-to-ear social cover, TTS guide, smart interruption) — source: [reference/planning/2026-06-04-phone-call-mode.md](planning/2026-06-04-phone-call-mode.md)
- [ ] Setup Flow Onboarding + Flow Session Screen — source: [reference/planning/2026-05-31-setup-flow-onboarding.md](planning/2026-05-31-setup-flow-onboarding.md)
- [ ] Language support for input/output (model selection driven by language config) — source: [roadmap.md](roadmap.md)
- [ ] Integration master plan — tool marketplace, Apple native integrations, extended tools (Toggl/Atlassian/Google/Microsoft 365), server/infra — source: [reference/planning/2026-05-30-integration-master-plan.md](planning/2026-05-30-integration-master-plan.md)
- [x] Build full iOS capture pipeline — DONE 2026-06-30: heuristic+Castellum routing, native context, on-device execution, plan UI (capability-based, iOS-first) — source: [session-ios-native-pipeline](../captures/2026-06-30-session-ios-native-pipeline.md)
- [ ] Meeting note inputs (Google Gemini Notes or similar as capture source) — source: [roadmap.md](roadmap.md)

## Recent Plans

| Date | Plan | Status | Key Decisions |
|------|------|--------|---------------|
| 2026-07-01 | [ios-history-audio-pause](../captures/2026-07-01-session-ios-history-audio-pause.md) | complete | Plan persistence on CaptureRecord; history expand/collapse + inline plan; background audio + pause/resume |
| 2026-06-30 | [ios-native-pipeline](../captures/2026-06-30-session-ios-native-pipeline.md) | complete | Native serverless Castellum; BasinShared consolidation; capability routing (iOS); on-device execution + plan UI |
| 2026-06-27 | [debug-capture-archive](../captures/plans/2026-06-27-debug-capture-archive-and-audio-e2e-tests.md) | complete | Debug capture archive + grading + E2E audio test layer (executed; plan archived) |
| 2026-06-26 | [hex-basn-rename](../captures/2026-06-26-session-hex-basn-rename.md) | complete | Hex→Basn transition complete: dirs, API, strings, assets, pbxproj |
| 2026-06-26 | [fixture-pipeline](../captures/2026-06-26-session-fixture-pipeline.md) | complete | Duration parsing, text capture fix, iOS text input stub, 7 synthetic fixtures |
| 2026-06-25 | [vault-init](planning/init-cuddly-torvalds.md) | complete | Vault structure scaffolded; memory migrated to docs/reference/ |
| 2026-06-12 | [how-to-create-scenario-fixture](../captures/plans/2026-06-12-how-to-create-scenario-fixture.md) | complete | Fixture authoring SOP documented |
| 2026-06-09 | [fixture-based-capture-testing](../captures/plans/2026-06-09-fixture-based-capture-testing.md) | complete | JSON fixture layer built; synthetic fixtures for all current scenarios |
| 2026-06-04 | [phone-call-mode](planning/2026-06-04-phone-call-mode.md) | in-progress | Designed; not yet implemented |
| 2026-05-31 | [setup-flow-onboarding](planning/2026-05-31-setup-flow-onboarding.md) | in-progress | Designed; partially implemented |
| 2026-05-30 | [integration-master-plan](planning/2026-05-30-integration-master-plan.md) | in-progress | Execution-ready; covers marketplace, extended integrations, server/infra |
| 2026-05-28 | [ios-rebrand-plan](../captures/plans/2026-05-28-ios-rebrand-plan.md) | complete | App renamed Basn, iOS target started clean |
| 2026-05-27 | [architecture-system-model](planning/2026-05-27-architecture-system-model.md) | reference | Three-layer model (Flows/Castellum/Workflows/Tools) — stable |

## Key Decisions Log

- [2026-07-01] **Plan persistence** — `CaptureRecord.executionPlanData: Data?` stores JSON-encoded `ExecutionPlan`; both `routeCapture` and `rerunCapture` write it; History detail shows inline plan card; SessionRow expanded shows action chips — source: [session-ios-history-audio-pause](../captures/2026-07-01-session-ios-history-audio-pause.md)
- [2026-07-01] **Background audio recording** — `UIBackgroundModes: audio` added; `allowBluetooth`/`allowBluetoothA2DP` options on AVAudioSession; interruption + route-change notification observers with auto-resume; fixes recording stopping during outdoor activities — source: [session-ios-history-audio-pause](../captures/2026-07-01-session-ios-history-audio-pause.md)
- [2026-07-01] **Pause/resume** — `AVAudioRecorder.pause()`/`record()`; toggle button repurposed during recording; `accumulatedDuration` excludes paused time from session duration — source: [session-ios-history-audio-pause](../captures/2026-07-01-session-ios-history-audio-pause.md)
- [2026-07-01] **Word-boundary matching in CapabilityMatcher** — single-word keywords use `\b…\b` regex; multi-word use plain `contains`; "to do" removed from create_task (false positive on "want to do") — source: [session-ios-history-audio-pause](../captures/2026-07-01-session-ios-history-audio-pause.md)

- [2026-05-28] App renamed **Basn** (not Basin); bundle ID `com.lyra.basn`; "Workflow" replaces "Channel" — source: [architecture.md](architecture.md)
- [2026-05-22] Workflows are emergent from Castellum, never pre-configured by users — source: [REQ-global.md](REQ-global.md)
- [2026-05-22] HeuristicRouter fires only on exactly 1 unambiguous match; competing matches fall to Castellum — source: [REQ-castellum.md](REQ-castellum.md)
- [2026-05-22] Tool definitions are declarative JSON in `tool-definitions/*.json`, not per-tool Swift — source: [REQ-global.md](REQ-global.md)
- [2026-03-22] SwiftData + CloudKit private database for cross-device sync; on-device first — source: [architecture.md](architecture.md)
- [2026-06-25] basin-planning registered as `source` vault; server component question open (prototype exists in basin-planning/server/) — see Open Decisions in CLAUDE.md
- [2026-06-26] HeuristicRouter strips leading "for " from descriptions; adds `duration_minutes` param (defaults 30 min) — source: [session-fixture-pipeline](../captures/2026-06-26-session-fixture-pipeline.md)
- [2026-06-26] `saveTranscriptionHistory` gates audio file persistence only; text captures always reach history — source: [session-fixture-pipeline](../captures/2026-06-26-session-fixture-pipeline.md)
- [2026-06-26] **Hex → Basn rename complete**: `Hex/`→`Basn/`, `HexCore/`→`BasnCore/`, StoragePaths API (`hexMigratedFileURL`→`basnMigratedFileURL` etc.), all strings/assets updated. Legacy `hex_settings.json` filename retained intentionally for migration compatibility — source: [session-hex-basn-rename](../captures/2026-06-26-session-hex-basn-rename.md)
- [2026-06-26] "Built with inspiration from HEX (MIT)" wording chosen for About view attribution to `kitlangton/Hex` library — source: [session-hex-basn-rename](../captures/2026-06-26-session-hex-basn-rename.md)
- [2026-06-30] **Castellum is native + serverless for v1** — on-device routing/execution with user's Anthropic key; no server. Context follow-up is local-first (from on-device captures/analyses). Server deferred to v2 behind the `analyzeAndPlan`/`fetchContext` seam — source: [castellum-native-architecture.md](castellum-native-architecture.md)
- [2026-06-30] **Routing/plan types consolidated into `BasinShared`** (single source of truth for macOS/iOS/CarPlay/watch); `BasnCore` re-exports so macOS is unchanged; duplicate `Session` removed — source: [session-ios-native-pipeline](../captures/2026-06-30-session-ios-native-pipeline.md)
- [2026-06-30] **Capability-based routing** — fixed generic action vocabulary; hybrid prompt (connected real schemas + generic for uncovered) scales with connected set; generic actions are the pre-connection nudge (offline `CapabilityMatcher`), tool-specific takes over once connected; tools declare `capability` tags in JSON — source: [REQ-castellum.md](REQ-castellum.md)
- [2026-06-30] **iOS debug capture via hidden Developer-mode unlock** (tap version 7× + passphrase), inert in all builds; capture archive saves audio+JSON to dated folders for desktop assessment — source: [session-ios-native-pipeline](../captures/2026-06-30-session-ios-native-pipeline.md)

## Visual Identity Notes

Animation references for Basin's water/fluid identity (future sprints):
- 3D vessel pour — [CodePen](https://codepen.io/Umut501/pen/azmbrjG)
- Ripple interactions — [CodePen](https://codepen.io/B-O-V-I-C-E/pen/xxqoKYR)
- ASCII water particles — [CodePen](https://codepen.io/ddubs52/pen/PwPvEqg)
- Pixel-art animation frames — [Magnific](https://www.magnific.com/vectors/water-circle-animation/2#uuid=e4391128-0a87-4593-a42c-ee14ab1a3daa)
