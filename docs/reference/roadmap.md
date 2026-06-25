---
name: project_roadmap
description: Basin/Hex roadmap items — language support, meeting note inputs, and future feature ideas
type: project
---

## Roadmap Items

### Language support for input/output
- Need to specify input and output languages in the tool/flow configuration
- Language selection affects which speech-to-text model is used (e.g., Parakeet multilingual vs Whisper English-only Distil variants)
- **Why:** Users need multilingual workflows; model selection should be driven by language config, not manual choice
- **How to apply:** When designing tool definitions or flow configs, include language fields. Model selection logic should consult these fields.

### Phone Call Mode (onboarding / activation energy)
- A capture mode designed for people who can't easily speak out loud at their desk
- Reframes capture as a phone call — holding the phone to your ear is a universally legible social signal
- Pre-session setup: two chip rows ("Where are you?" + "Who should I be?") to set space and persona
- Guide speaks prompts conversationally via TTS (Apple premium voices, iOS 17+); adapts tone to persona (best friend, boss, therapist, coach)
- **Smart interruption**: monitors audio levels, waits 1.2s of silence, plays a soft chime, then speaks — stops immediately if user starts talking
- Space-aware suggestions: "You're in public — want to find a quiet corner first?" / "Walking is great for this"
- iOS-first (hold-to-ear metaphor); feeds into existing Castellum pipeline at the end
- Plan doc: `docs/plans/2026-06-04-phone-call-mode.md`
- **Why:** Talking out loud is socially awkward in most contexts; phone call mode provides social cover and a scaffolded structure that lowers the barrier to voice capture
- **How to apply:** When designing onboarding or activation flows, consider this as the primary "first capture" experience for new iOS users who feel resistance to speaking aloud

### Meeting summary inputs
- Accept meeting summaries from Google Gemini Notes or other note-taking services as inputs to Basin flows
- **Why:** Voice capture is one input modality; meeting notes are another high-value source of structured context
- **How to apply:** When designing the input/channel system, plan for ingesting external meeting summaries alongside voice transcripts
