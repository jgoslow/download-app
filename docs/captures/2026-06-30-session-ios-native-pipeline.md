---
type: log
subtype: session
status: reference
created: 2026-06-30
updated: 2026-06-30
distilled: true
tags: [session, ios, castellum, routing, capabilities]
---

# 2026-06-30 — Session: iOS native capture pipeline + capability routing

Long session spanning the debug capture archive, iOS device debugging, a shared-code
consolidation, and bringing the full capture→route→execute pipeline to iOS — all
serverless/native. Committed as 6 chunks on branch `feat/native-capture-pipeline`.

## What Was Decided

- **Castellum is native + serverless for v1.** No Castellum server; analysis/routing/
  execution run on-device with the user's own Anthropic key. Heavy server work (hooks,
  long-horizon memory, custom models, server-scheduled follow-ups) is deferred to v2.
  Decision recorded in `docs/reference/castellum-native-architecture.md`.
- **Context follow-up is local-first**, not server-dependent. `fetchContext(flowID)` now
  assembles `[SessionContext]` from recent on-device `CaptureRecord`/`CaptureAnalysis`;
  server is an optional override. Flow-scoped; with only the "Open" flow, all captures
  share context. Continuity only includes captures that produced an analysis (Castellum path).
- **Shared routing lives in `BasinShared`** (single source of truth for macOS + iOS +
  future CarPlay/watch). `BasnCore` re-exports it so macOS is untouched. The duplicate
  `Session` was removed.
- **Capability-based routing (iOS-first).** A fixed generic action vocabulary (7 caps)
  the router reasons over. Hybrid prompt: connected tools contribute real schemas
  (full fidelity), uncovered capabilities contribute a generic function (surface +
  nudge to connect). Prompt scales with the *connected* set, never the full catalog.
- **Generic actions are the pre-connection layer** and must work with no key/network —
  added an offline `CapabilityMatcher`. Once a tool is connected for a capability, its
  tool-specific action takes over. Per-flow tool preference for a capability is a future hook.
- **iOS debug capture via a hidden Developer-mode unlock** (tap version 7× + passphrase),
  shipping inert in all builds so it works on TestFlight/real-device.

## What Was Built or Changed

| Area | Change |
|------|--------|
| Debug archive | `DebugCaptureArchive` (audio+JSON dated folders), grading (`CaptureGrade`/`AudioQualityMetrics`), `WordErrorRate`, macOS Review master-detail UI, desktop `CaptureIngestor` |
| Test layer | `BasnTests/AudioPipelineTests` (live transcription → WER → routing), `AudioCorpus` (LFS), tools scripts, weekly CI |
| Shared refactor | Moved routing/plan types + `SessionContext` into `BasinShared`; `BasnCore` scoped re-exports + path dep; removed `BasnCore.Session` |
| Native context | `ModelContextClient.fetchRecentContext`; `DestinationRouterClient.fetchContext` local-first |
| Capabilities | `Capability` vocabulary + `CapabilityMatcher` (offline); declarative `capability` tags in tool-definition JSON; `CapabilityResolver` (iOS) |
| iOS pipeline | `IOSCastellumClient` (hybrid prompt), `AppState.routeCapture` (heuristic→Castellum + matcher + persist analysis), plan/confirmation UI with Connect links, on-device `GenericToolExecutor`, `DeveloperMode`, `IOSCaptureArchive`, audio-session fix (`.measurement`→`.default`), Files-app sharing |
| Build | `BasnTests` synchronized target + TEST_HOST/module-name fixes; iOS file memberships + bundled tool-defs; iOS app icon |

## Open Questions / Follow-ups

- [ ] **iOS tool connections (OAuth "no provider ID")** are still broken — Connect→Execute
      won't complete end-to-end until fixed. Deferred to the upcoming tools overhaul (user's call).
- [ ] **Migrate macOS to capability routing** (kept on tool-scoped routing for now).
- [ ] **Per-flow capability→tool preference** (resolver hook exists; defaults to any connected provider).
- [ ] **Tools-list filter by capability** (connect links cover the immediate need).
- [ ] Castellum+Toggl bug (no tool_use block) still open — see `castellum-toggl-bug.md`.

## Context to Carry Forward

- Verified green at session end: macOS Debug, iOS Debug, **iOS Release**, 173 BasnCore tests.
  (Pre-existing unrelated failure: missing `Fixtures/BasnSettings/v1.json`.)
- Work is on branch `feat/native-capture-pipeline` (6 commits), not yet merged to `main`.
- iOS dev workflow notes (pull captures, build/test, easter egg) are in `docs/reference/dev-commands.md`.
- The debug-archive implementation plan (`docs/plans/2026-06-27-…`) was fully executed this session.
