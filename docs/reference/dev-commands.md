---
type: reference
title: Dev Commands Cheat-Sheet
updated: 2026-06-29
tags: [reference, commands, debug, captures, build]
---

# Dev Commands Cheat-Sheet

Copy-paste reference for the common Basn dev/debug actions. Run from the repo
root (`/Users/jonasgoslow/localhost/basin`) unless noted.

> Tip: many `swift`/`xcodebuild` commands need this prefix in some shells to work
> around a git setting — it's harmless to always include:
> `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all`

## Pull capture recordings off the iPhone (USB)

Pulls the app's archived captures straight from the device. **Aim at `/tmp`, not
`~/Downloads`** (Downloads is privacy-protected and tools can't read it):

```bash
xcrun devicectl device copy from --device "Jonas's iPhone" \
  --domain-type appDataContainer --domain-identifier com.lyra.basn.ios \
  --source Documents/BasnCaptures --destination /tmp/ios-captures
```

If you already AirDropped/saved them into `~/Downloads`, move them somewhere
readable:

```bash
cp -R ~/Downloads/BasnCaptures /tmp/ios-captures
```

List connected devices (to confirm the name / that it's seen):

```bash
xcrun devicectl list devices
```

## Where captures live

```bash
# Mac debug-app capture archive (live captures + desktop "Import"):
open ~/Library/Containers/com.lyra.basn.debug/Data/Documents/BasnCaptures

# Booted iOS Simulator's app container:
open "$(xcrun simctl get_app_container booted com.lyra.basn.ios data)/Documents/BasnCaptures"
```

## Build

```bash
# macOS app (Debug)
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild build -scheme Basn -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# iOS app (Debug, generic device)
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild build -scheme "Basn iOS" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

## Test

```bash
# Fast offline unit tests (BasnCore — WER, audio metrics, grading, routing fixtures)
cd BasnCore && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all swift test; cd ..

# End-to-end audio tests (skip cleanly if no corpus/model)
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild test -scheme Basn -only-testing:BasnTests/AudioPipelineTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## Capture → fixture tooling

```bash
# Promote an archived capture folder into a parse-layer fixture or the audio corpus
bun run tools/scripts/archive-to-fixture.ts <capture-folder> --scenario
bun run tools/scripts/archive-to-fixture.ts <capture-folder> --corpus

# Test-value / accuracy trend report across the corpus (or an archive folder)
bun run tools/scripts/capture-grades.ts
```

## In-app debug actions (Mac debug build)

DebugBar at the bottom of Home:
- **Archive captures** — toggle on to save audio + JSON per capture.
- **folder icon** — reveal the captures folder in Finder.
- **Review** — grade captures (accuracy / keep-as-fixture / notes).
- **Import…** — transcribe + route + grade audio captured elsewhere (e.g. the phone).

## iOS easter egg (unlock debug on a real device)

Settings → About → tap the **Version** row 7× → enter the passphrase (set in
`iOS/App/DeveloperMode.swift`) → the **Developer** section appears with the
capture-archive toggle.
