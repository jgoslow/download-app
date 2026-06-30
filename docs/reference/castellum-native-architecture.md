---
type: reference
subtype: architecture-decision
status: active
created: 2026-06-30
tags: [reference, castellum, architecture, privacy, context]
---

# Castellum: native-first, serverless for v1

<!-- Decision record. The "Castellum server" (heavy pre/post-processing) is deferred; v1 runs natively. -->

## Decision

Ship v1 **without a Castellum server.** Capture analysis, routing, context
follow-up, and execution run **natively** on each device, using the user's own
Anthropic key for the one AI call. The heavyweight server (processing hooks,
cross-session evaluation at scale, long-horizon memory, custom models) is a
**v2 graduation**, not a v1 dependency.

This is mostly the architecture we already have — the AI path is `app → Claude`
directly (`CastellumClient.analyzeAndPlan`), no custom backend. The one piece
wired to the server is **context follow-up**, which we make local-first.

## The native loop

```
Capture (on-device, private)
  → Context assembly (on-device: recent flow sessions + open follow-ups)
  → Plan: heuristic (offline) OR Claude call (BYO key, context injected)
  → Execute (on-device, via connected tools)
  → Persist analysis + open items locally  ──┐
        ↑                                     │ feeds next capture's context
        └─────────────────────────────────────┘
```

## What's native (v1) vs deferred (server v2)

| Native, now | Deferred to a Castellum server |
|---|---|
| On-device transcription (WhisperKit/Parakeet) | Processing hooks / async pipelines / webhooks |
| Offline heuristic routing (no network) | Long-horizon memory: RAG/embeddings/clustering over months |
| Local session history + flow-scoped context | Custom / fine-tuned models |
| Per-capture analysis + routing via direct Claude call | Server-scheduled follow-ups (fire while app closed) |
| On-device execution against connected tools | Cross-device sync of *derived* state |
| Locally-tracked open follow-ups → next capture | Server-side heavy evaluation / dedup |

**Privacy nuance:** "native/private" means *no backend we operate holds the
data*. The Claude call still sends transcript + assembled context to Anthropic.
Fully-on-device requires a local LLM (a "custom models" v2 item). The heuristic
path is 100% local.

## Current state + the gap

- `CastellumClient.analyzeAndPlan(capture, promptTitles, sessionContext, tools, workflows, apiKey)`
  already calls Claude directly. ✅ serverless.
- macOS already **persists** each analysis locally (`CaptureAnalysis` @Model) and
  each capture (`CaptureRecord`). ✅
- **Gap:** `DestinationRouterClient.fetchContext(flowID)` and `postAnalysis` are
  **server-only** — `fetchContext` returns `[]` with no `serverURL`. So today,
  with no server, captures have **no cross-session continuity**.

## Native fix: local-first context assembly

Make `fetchContext(flowID)` build `[SessionContext]` from the **on-device store**
(recent `CaptureRecord` + `CaptureAnalysis` for that flow), with the server as an
optional override when `serverURL` is set. The data already exists locally; we
just need to read it back and shape it.

`postAnalysis` likewise becomes "persist locally" first (already happens via the
SwiftData save), server POST optional.

### Data model

- **Context unit:** existing `SessionContext` (`Basn/Clients/DestinationRouterClient.swift`)
  — summary/tasks/etc. per prior session. Reuse as-is.
- **Open follow-ups:** derived from prior `CaptureAnalysis.tasks` / `.delegations`
  not yet marked done. v1: surface the last N flow sessions' tasks/delegations as
  context (no separate completion tracking yet); a `done` flag on follow-ups is a
  small later add.
- **iOS:** currently persists only `Session` (JSON via `SessionStore`), not
  analyses. Needs a local analysis store (SwiftData `CaptureAnalysis`, mirroring
  macOS) so iOS can assemble context too.

## The swap seam (server-ready without rework)

Three injection points stay stable; only their *implementations* change when a
server arrives:

1. `analyzeAndPlan(...)` — swap "Claude direct + local context" for "call our server."
2. `fetchContext(flowID)` — swap "local store" for "server context endpoint."
3. `postAnalysis(...)` — swap "local persist" for "local + server push."

Callers (`TranscriptionFeature`, iOS `AppState`) don't change. Native-first does
**not** lock us out of the server later.

## Next implementation steps (ordered)

1. **Local-first `fetchContext`** (macOS): assemble `[SessionContext]` from recent
   `CaptureRecord`/`CaptureAnalysis` for the flow; server optional. Immediate
   native continuity on macOS.
2. **iOS analysis store + context assembly:** persist `CaptureAnalysis` on iOS;
   mirror local `fetchContext`.
3. **Phase 2 — iOS Castellum:** share `CastellumClient` + `ToolDefinitionLoader`/
   `ToolActionRegistry` into iOS (imports → `BasinShared`); copy `tool-definitions/*.json`
   into the iOS bundle; wire the Claude fallback (with context) in `AppState.routeCapture`.
4. **Phase 3 — execution:** share `GenericToolExecutor` + Keychain auth; run plan
   actions against connected tools.
5. **Phase 4 — plan UI:** select / confirm / execute / show results.
6. **Open-follow-up `done` tracking** (small): mark prior tasks resolved so context
   reflects what's outstanding.
