# Basn Brand Guide

## The Name

The app is called **Basn** — not "Basin." This is intentional.

**Basn** is the technical identity of the product: app name, App Store listing, bundle ID prefix, Swift symbol prefix. It's a proper noun — always capitalized as-is, never "BASN" or "basin" when referring to the app.

**"basin"** (lowercase, common noun) remains available for natural language use when describing the water metaphor. *"Pour your thoughts into Basn — let them collect in the basin before they flow to their destination."* In copy, diagrams, and the README's waterworks metaphor, the word "basin" describes the physical thing the app is named after. The two coexist without conflict.

---

## Names at a Glance

| Context | Use |
|---|---|
| App name | **Basn** |
| Referring to the app in prose | Basn |
| Bundle identifier (macOS) | `com.lyra.basn` |
| Bundle identifier (iOS) | `com.lyra.basn.ios` |
| URL scheme | `basin://` (OAuth callbacks — unchanged from prior registration) |
| S3 / artifact prefix | `basn-` |
| Swift module (formerly HexCore) | `BasnCore` (package folder still named `HexCore/` on disk) |
| Swift symbol prefix | `Basn` (BasnLog, BasnSettings, BasnApp) |
| Lowercase file/folder names | `basn` |
| The water-collection metaphor in copy | basin (common noun, lowercase) |
| Talking about Roman waterworks | basin, aqueduct, castellum — all natural prose |

---

## Bundle Identifiers

| Target | Bundle ID |
|---|---|
| macOS app (release) | `com.lyra.basn` |
| macOS app (debug) | `com.lyra.basn.debug` |
| iOS app | `com.lyra.basn.ios` |
| iOS widget extension | `com.lyra.basn.ios.widget` |
| watchOS app | `com.lyra.basn.watchos` |
| Tests | `com.lyra.basn.tests` |
| Keychain service (OAuth tokens) | `com.lyra.basn.oauth` |
| App Group (if needed) | `group.com.lyra.basn` |

---

## Voice & Tone

Basn's copy follows the water metaphor without overdoing it. A few principles:

- **Calm, unhurried.** Water doesn't rush. Neither does Basn. Avoid urgency language.
- **Physical, grounded.** Use concrete metaphors from the waterworks model — flows, channels, the castellum distributing water — when it serves clarity. Drop it when it gets forced.
- **No productivity theater.** Basn doesn't "supercharge" or "10x" anything. It captures what you say and routes it. The work happens naturally.
- **Short.** Prompts, confirmations, and onboarding copy should be as short as water flowing downhill.

### Taglines in use
- *Basn — Let your thoughts flow.*
- *Pour your thoughts in. Let them find their way.*

---

## The Waterworks Metaphor

The app is modeled after a Roman waterworks system. The full metaphor is in [README.md](README.md). Key terms:

| Term | Metaphor | Meaning |
|---|---|---|
| Basn | The basin itself | The app. Voice capture that feels effortless. |
| Capture | Water entering the basin | A single voice recording session + transcript. |
| Flow | A directed stream | A named capture ritual with guided prompts, schedule, routing. |
| Castellum | The distribution hub | On-device AI. Receives the transcript, decides where it goes. |
| Workflow | A channel to a specific outcome | What Castellum produces: a Jira card, a Slack message, a calendar event. Not predefined — emergent. |
| Tool | Mechanisms along the aqueduct | A connected external service (Jira, Slack, Toggl, etc.). |
| Evaporation | The water cycle | Feedback loop. Outputs become context for the next capture. |

---

## Visual Identity

The primary visual motif is **the water circle** — a circular animation suggesting water collecting in a basin, then draining outward. This appears as:

- The macOS menu bar icon (at rest: static circle; recording: animated)
- The iOS record button (centered, prominent — the main interaction surface)
- The iOS Live Activity / Dynamic Island indicator (spinning drain animation while recording)
- Loading states and processing indicators throughout the app

### The drain animation
The recording state uses a **spinning water drain** effect — a vortex that suggests water being drawn down into the system for processing. The animation should feel calm and deliberate, not frantic. Think of looking down at a bathtub draining: a slow, inevitable spiral.

---

## Developer Notes

- All Swift symbols use `Basn` prefix: `BasnLog`, `BasnSettings`, `BasnApp`, `BasnAppDelegate`
- The package formerly known as `HexCore` is now `BasnCore` (folder on disk is still `HexCore/` — rename pending)
- The shared settings key in TCA is `.basnSettings`
- The logging subsystem is `"com.lyra.basn"`
- Sparkle update feed: `https://basn-updates.s3.amazonaws.com/appcast.xml`
- OAuth redirect URI stays `basin://oauth/callback` (already registered with providers — no change needed)
- Avoid `Hex` in new code. If you see it, rename it.
