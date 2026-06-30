---
type: capture
date: 2026-06-29
source: ios-device (real iPhone) → pulled via USB
status: unactioned
tags: [capture, ios, bugs, ideas, tools]
---

# iOS Device Captures — 2026-06-29

Six captures recorded on the real iPhone (Developer-mode capture archive),
pulled off via USB and preserved. Transcripts below are the **on-device**
WhisperKit output (`metadata.onDeviceTranscript`). Audio + metadata also copied
to the Mac container (`~/Library/Containers/com.lyra.basn.debug/Data/Documents/BasnCaptures/2026-06-29/`)
so they survive a phone reinstall and appear in DebugBar → Review.

Not actioned yet — **tool/connection items are for the separate tools thread.**

## 🛠 For the tools thread

### #2 — Tool connections fail on iOS + sync + missing live transcript (63s, 18:29)
> So just check in to write some notes about basin, how it's working. It seems
> that none of the tools can connect because they don't have a provider ID or
> something on iPhone. I feel like it did work on the computer so there must be
> something different with how it connects to an iPhone. The other question is
> how can we sync what I'm testing on the iPhone with what happens on the Mac.
> They should be the same accounts in theory. So how do we make that happen? And
> then in the iPhone experience, I don't see the transcript of what I'm saying
> show up at the top, but I should. I did see it in the onboarding experience, so
> I'm not sure what happened here in this one.

Three distinct items:
1. **Tool connect broken on iOS** — "no provider ID or something." Works on Mac. iOS OAuth/provider wiring likely missing.
2. **iPhone ↔ Mac sync** — same accounts should share tool connections / data. How?
3. **Live transcript not shown** during capture on iOS (top of screen) — but it *did* show during onboarding. Regression/inconsistency.

### #3 — Need a dev endpoint to connect a Basin instance (24s, 18:39)
> I'd love to just put in a note about: I need a new card to develop an endpoint
> for [auth/API] and development that I can connect my Basin instance to.

(Transcript a little garbled — gist: stand up a dev endpoint that a Basin instance can connect to.)

### #4 — Widget error + widget should start recording (21s, 18:42)
> Need to just record that the Basin widgets have an error — I'll include a
> screenshot of [it] — and also that picking the widget should start recording in
> Basin, as opposed to just opening Basin.

## 💡 Product ideas

### #5 — Tooltips + flow-aware tool hints (27s, 18:45)
> A future idea: we need to have tooltips because there's going to be a lot of
> hints that help people use [it] better. In particular, when you're creating a
> flow, it identifies the tools that are probably going to be used for that flow,
> and people may want to call out specific terms or words that instigate
> different tools at the end of the flow — that way we don't need to use AI.

(Term/keyword → tool triggers as a deterministic alternative to the AI router.)

### #6 — "Third spaces" / listening flows / run + music ducking (66s, 18:47)
> …there's different third spaces that are good for doing a flow, and running is
> one — but probably more for a *listening* flow. Maybe situations where you want
> a recap of a bunch of things, even in a creative manner like a podcast or a
> story, something that prepares your brain for processing things. Something like
> a run could be a situation where you're listening to music but the mic is on as
> well — when you have something to say, the music ducks down and it captures
> your words as you go. Lots of circumstances where that would be profoundly useful.

## Test capture

### #1 — Test check-in (20s, 18:19)
> Just doing a test check-in to write a note that I'm trying out Basin on my phone
> and seeing how it goes. So that's about it.

---

## Earlier desktop test captures (3, 14:49–14:51)

Recorded/imported on the Mac earlier the same day (platform unset). Less
substantive:
- Journal check-in ("working on Basin and it's fun") → Google doc.
- "track one hour of time worked on the basin app today" → **0 actions** (known Castellum-Toggl bug).
- A 48s loose intelligibility test → Google doc.
