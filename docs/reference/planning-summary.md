---
type: planning
status: active
updated: 2026-06-25
tags: [planning, summary]
---

# Planning Summary
<!-- Maintained by /vault distill. Last distilled: 2026-06-25 -->

## Outstanding

- [ ] Fix Castellum → Toggl tool_use bug (prose returned instead of tool_use block for multi-intent captures) — source: [REQ-castellum.md](REQ-castellum.md)
- [ ] Build audio integration test layer (S3 corpus, WER fuzzy assertions, diverse speakers) — HIGH PRIORITY — source: [REQ-testing.md](REQ-testing.md)
- [ ] Implement action-level permissions tier 2 (action checkboxes after OAuth scope selection) — source: [REQ-castellum.md](REQ-castellum.md)
- [ ] Phone Call Mode — iOS-first feature (hold-to-ear social cover, TTS guide, smart interruption) — source: [reference/planning/2026-06-04-phone-call-mode.md](planning/2026-06-04-phone-call-mode.md)
- [ ] Setup Flow Onboarding + Flow Session Screen — source: [reference/planning/2026-05-31-setup-flow-onboarding.md](planning/2026-05-31-setup-flow-onboarding.md)
- [ ] Language support for input/output (model selection driven by language config) — source: [roadmap.md](roadmap.md)
- [ ] Integration master plan — tool marketplace, Apple native integrations, extended tools (Toggl/Atlassian/Google/Microsoft 365), server/infra — source: [reference/planning/2026-05-30-integration-master-plan.md](planning/2026-05-30-integration-master-plan.md)
- [ ] Meeting note inputs (Google Gemini Notes or similar as capture source) — source: [roadmap.md](roadmap.md)

## Recent Plans

| Date | Plan | Status | Key Decisions |
|------|------|--------|---------------|
| 2026-06-25 | [vault-init](planning/init-cuddly-torvalds.md) | complete | Vault structure scaffolded; memory migrated to docs/reference/ |
| 2026-06-12 | [how-to-create-scenario-fixture](../captures/plans/2026-06-12-how-to-create-scenario-fixture.md) | complete | Fixture authoring SOP documented |
| 2026-06-09 | [fixture-based-capture-testing](../captures/plans/2026-06-09-fixture-based-capture-testing.md) | complete | JSON fixture layer built; synthetic fixtures for all current scenarios |
| 2026-06-04 | [phone-call-mode](planning/2026-06-04-phone-call-mode.md) | in-progress | Designed; not yet implemented |
| 2026-05-31 | [setup-flow-onboarding](planning/2026-05-31-setup-flow-onboarding.md) | in-progress | Designed; partially implemented |
| 2026-05-30 | [integration-master-plan](planning/2026-05-30-integration-master-plan.md) | in-progress | Execution-ready; covers marketplace, extended integrations, server/infra |
| 2026-05-28 | [ios-rebrand-plan](../captures/plans/2026-05-28-ios-rebrand-plan.md) | complete | App renamed Basn, iOS target started clean |
| 2026-05-27 | [architecture-system-model](planning/2026-05-27-architecture-system-model.md) | reference | Three-layer model (Flows/Castellum/Workflows/Tools) — stable |

## Key Decisions Log

- [2026-05-28] App renamed **Basn** (not Basin); bundle ID `com.lyra.basn`; "Workflow" replaces "Channel" — source: [architecture.md](architecture.md)
- [2026-05-22] Workflows are emergent from Castellum, never pre-configured by users — source: [REQ-global.md](REQ-global.md)
- [2026-05-22] HeuristicRouter fires only on exactly 1 unambiguous match; competing matches fall to Castellum — source: [REQ-castellum.md](REQ-castellum.md)
- [2026-05-22] Tool definitions are declarative JSON in `tool-definitions/*.json`, not per-tool Swift — source: [REQ-global.md](REQ-global.md)
- [2026-03-22] SwiftData + CloudKit private database for cross-device sync; on-device first — source: [architecture.md](architecture.md)
- [2026-06-25] basin-planning registered as `source` vault; server component question open (prototype exists in basin-planning/server/) — see Open Decisions in CLAUDE.md

## Visual Identity Notes

Animation references for Basin's water/fluid identity (future sprints):
- 3D vessel pour — [CodePen](https://codepen.io/Umut501/pen/azmbrjG)
- Ripple interactions — [CodePen](https://codepen.io/B-O-V-I-C-E/pen/xxqoKYR)
- ASCII water particles — [CodePen](https://codepen.io/ddubs52/pen/PwPvEqg)
- Pixel-art animation frames — [Magnific](https://www.magnific.com/vectors/water-circle-animation/2#uuid=e4391128-0a87-4593-a42c-ee14ab1a3daa)
