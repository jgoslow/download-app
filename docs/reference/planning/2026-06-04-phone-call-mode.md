# Phone Call Mode

## Context

Talking out loud is socially awkward in most of modern life — open offices, public spaces, shared homes. Holding your phone to your ear is a universally legible signal ("they're on a call") that creates social cover. Phone Call Mode exploits this: it reframes capture as a phone conversation with a persona (best friend, boss, etc.), lowers the activation energy of speaking, and scaffolds the session with a conversational guide that listens, prompts, and knows when to talk vs. listen.

This is iOS-first — the "hold to ear" metaphor only makes sense on a handheld device.

---

## Voices: What's Available and What's Good

**Apple AVSpeechSynthesizer (recommended for MVP)**
- iOS 16+: "Enhanced" neural voices (~50MB download). Noticeably natural — proper intonation, not robot cadence.
- iOS 17+: "Premium" voices (e.g. Zoe, Nicky, Reed) — ~150MB, competitive with early OpenAI TTS. These are the target.
- Free, offline, <50ms latency. Filter with `AVSpeechSynthesisVoice.speechVoices().filter { $0.quality >= .enhanced }`.
- Greeting phrases can be pre-baked as short `.caf` audio files bundled with the app for instant zero-latency playback.

**OpenAI TTS (optional upgrade path)**
- `nova` / `shimmer` voices via `POST /v1/audio/speech` are excellent — warm, conversational.
- ~500ms first-chunk latency (can stream for faster perceived start).
- Gated behind user providing OpenAI key. Not in MVP scope, but the `TTSClient` protocol should make this a drop-in later.

**ElevenLabs / others**: Best quality, most friction. Out of scope for now.

**Verdict**: Ship with Apple premium voices. They're good enough that most users won't notice the difference from a cloud TTS in a casual "phone call" context, and they work offline with no API key.

---

## Feature Design

### Entry point
A "Call" button or card on the iOS home screen (alongside existing flows). Tapping it opens the setup sheet, not a flow session. After setup, it launches `PhoneCallSessionView` in `fullScreenCover`.

### Setup screen (chip sheet)
Two chip rows presented before the call begins:
1. **Where are you?** → `.atDesk`, `.walking`, `.publicSpace`, `.commuting`, `.home`
2. **Who should I be?** → `.bestFriend`, `.boss`, `.therapist`, `.coach`, `.journal`

Space selection drives:
- An optional spoken suggestion before recording starts (e.g. "You're in public — want to find a quiet corner first? Even a stairwell works." / "Walking is great for this — let's go.")
- Session tone (bestFriend = casual, low-pressure; boss = structured, outcome-oriented; therapist = open-ended, reflective)

### Call session
The session is audio-first: the guide speaks prompts rather than displaying them. The UI is minimal and phone-like:
- Large avatar / persona icon centered
- Waveform strip (user's voice level) at bottom
- Collapsed transcript strip (hidden by default, expandable)
- "End call" button (hangs up, sends capture to Castellum)

The guide works through the active flow's prompts conversationally, adapting language to the persona. Example (bestFriend, MorningKickoff flow):

> "Hey! So what's the deal today — what's on your plate?"
> [user talks]
> *[silence detected → chime → guide speaks]*
> "Got it. Anything that's been nagging at you that you haven't dealt with yet?"

### Smart Interruption
The most technically novel piece. When the guide wants to speak:
1. Monitor audio level (via AVAudioRecorder metering, already set up in `RecordingClientLiveIOS`)
2. Wait for **1.2s of silence** (configurable)
3. Play a soft chime (`interruptionChime.caf`) — signals "I'm about to say something"
4. Begin TTS playback
5. If user starts speaking during playback → `stop()` immediately, resume listening
6. If the guide finishes before user speaks → resume listening normally

This makes the turn-taking feel natural rather than aggressive. The chime is the key social cue — it mirrors how people signal they want to speak in a real conversation.

---

## Implementation Plan

### 1. `TTSClient` — new dependency (`Hex/Clients/TTSClient.swift`)

```swift
protocol TTSClientProtocol {
    var isSpeaking: AnyPublisher<Bool, Never> { get }
    func speak(_ text: String) async
    func stop()
    func preferredVoice() -> AVSpeechSynthesisVoice?
}
```

Live implementation:
- `AVSpeechSynthesizer` with delegate
- Voice selection: filter `speechVoices()` for `.premium` first, fall back to `.enhanced`, then default `en-US`
- Async `speak()` suspends until utterance completes or `stop()` is called
- Register as a `DependencyKey` in TCA's dependency system

### 2. `SmartInterruptionEngine` — new file (`Hex/Clients/SmartInterruptionEngine.swift`)

```swift
actor SmartInterruptionEngine {
    func waitForSilence(threshold: TimeInterval = 1.2) async
    func speakWhenReady(_ text: String) async // waits → chimes → speaks
    func monitorUserSpeech() -> AsyncStream<Bool> // true when user is talking
}
```

- Audio level monitoring via `AVAudioRecorder.averagePower(forChannel:)` polled at 10Hz
- Silence window: consecutive samples below –35 dBFS threshold for `threshold` seconds
- Chime: play `interruptionChime.caf` via `SoundEffectsClient` (add new case `.interruptionChime`)
- Add `interruptionChime.caf` to `Resources/Audio/` — a short, soft two-tone bell (~300ms)

### 3. `PhoneCallSessionViewModel` — iOS only (`iOS/PhoneCall/PhoneCallSessionViewModel.swift`)

`@Observable` class (same pattern as `FlowSessionViewModel`):

```swift
@Observable class PhoneCallSessionViewModel {
    var persona: CallPersona
    var space: CallSpace
    var phase: CallPhase // .setup | .suggestingSpace | .greeting | .flowing | .wrappingUp
    var isUserSpeaking: Bool
    var isGuideSpeaking: Bool
    var transcript: [String]
    var currentPromptIndex: Int
    
    func startCall(flow: Flow) async
    func endCall() -> StructuredCapture
    func handleUserSilence() async
}
```

Prompt script generation: build a string like `"You are a \(persona.label) helping with \(flow.name). Keep it casual and short. Ask: \(prompt.text)"` and pass to a lightweight Claude call (Haiku, cached system prompt) to get a spoken version of the prompt. Cache per `(persona, prompt.id)`.

### 4. `PhoneCallSetupView` (`iOS/PhoneCall/PhoneCallSetupView.swift`)

- Bottom sheet presented from home
- Two `ChoiceChipsView` rows (reuse existing `FlowLayout` + chip styling from `FlowSessionView`)
- Space chip → optional spoken suggestion line shown as italic caption
- "Start call" button enabled once both rows have a selection
- "Skip" option defaults to `.atDesk` + `.bestFriend`

### 5. `PhoneCallSessionView` (`iOS/PhoneCall/PhoneCallSessionView.swift`)

- Dark full-screen view (`fullScreenCover`)
- Centered persona avatar (SF Symbol or generated emoji-style icon per persona)
- Guide speaking: subtle pulsing ring around avatar
- User speaking: waveform strip animates
- Chime pending: brief visual flash on avatar border
- Expandable transcript strip at top (same `LiveTranscriptView` reused from `FlowSessionView`)
- "End call" (red phone icon, bottom center)
- Status label: "Listening…" / "On it…" / "Thinking…"

### 6. Integration into iOS App

- `iOS/HomeView.swift`: Add "Call" card alongside recent flows. Shows last persona used.
- `iOS/App/AppState.swift` / `ContentView.swift`: Add `isPhoneCallActive: Bool` + `phoneCallViewModel: PhoneCallSessionViewModel?`; present `PhoneCallSessionView` via `.fullScreenCover`
- When call ends: pass `StructuredCapture` to `CastellumClient` same as normal flow completion — no new routing needed

---

## Files to Create
- `Hex/Clients/TTSClient.swift`
- `Hex/Clients/SmartInterruptionEngine.swift`
- `iOS/PhoneCall/PhoneCallSessionViewModel.swift`
- `iOS/PhoneCall/PhoneCallSetupView.swift`
- `iOS/PhoneCall/PhoneCallSessionView.swift`
- `Resources/Audio/interruptionChime.caf`

## Files to Modify
- `Hex/Clients/SoundEffect.swift` — add `.interruptionChime` case
- `iOS/HomeView.swift` — add Call entry point card
- `iOS/App/AppState.swift` — add phone call state
- `iOS/App/ContentView.swift` — wire `fullScreenCover` for call session

## Files to Reuse (no changes needed)
- `iOS/Flow/FlowSessionView.swift` → borrow `ChoiceChipsView`, `LiveTranscriptView`, `FlowLayout`
- `Hex/Clients/SoundEffect.swift` → reuse `AVAudioEngine` plumbing for chime
- `iOS/Clients/RecordingClientLiveIOS.swift` → reuse `AVAudioRecorder` for level metering
- `HexCore/Sources/BasnCore/Models/StructuredCapture.swift` → output format unchanged

---

## Verification

1. Build and run on iOS simulator / device
2. Open Home → tap "Call" → confirm setup sheet appears with both chip rows
3. Select chips → tap "Start call" → confirm greeting plays (voice heard, avatar pulses)
4. Speak naturally → confirm transcript strip updates in real time
5. Go silent → confirm 1.2s delay → chime plays → guide speaks next prompt
6. Start speaking while guide is talking → confirm guide stops immediately
7. Tap "End call" → confirm capture routes to Castellum and result appears in history
8. Test with no premium voice installed → confirm graceful fallback to enhanced voice

---

## Open Questions for Later

- Should the guide adapt dynamically mid-call based on what it hears (e.g. detect user is stressed and slow down), or is a fixed script-per-prompt enough for v1? → Fixed script for now.
- Walk suggestion: actively prompt user to go somewhere before starting? → Show as a dismissable banner in setup, not a blocker.
- Should "smart interruption" silence threshold be user-configurable? → Hardcoded 1.2s for now; add to Settings if users ask.
