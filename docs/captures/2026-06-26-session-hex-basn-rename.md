---
type: log
subtype: session
status: reference
created: 2026-06-26
updated: 2026-06-26
distilled: true
tags: [session, rename, branding]
---

# 2026-06-26 — Session: Complete Hex → Basn Transition

## What Was Decided

- **"Built with inspiration from HEX (MIT)"** chosen as the wording for the About view credit to `github.com/kitlangton/Hex` (external library attribution, not self-reference). The `Link("Hex on GitHub")` label and URL are intentionally left unchanged.
- **No re-registration required** for Google OAuth or Apple Developer — bundle ID (`com.lyra.basn`), URL scheme (`basin://`), and entitlement keychain groups were already using Basn naming. The rename was purely internal/structural.
- **Tests deferred to Xcode (Cmd+U)** — `swift test` and `xcodebuild test` both fail on this machine due to a pre-existing `safe.bareRepository=explicit` environment issue where Xcode/SwiftPM pass this flag on the command line when invoking git, preventing use of their own bare-repo package cache. Not introduced by this session. Fix: open in Xcode and run with Cmd+U.
- **`.gitignore` updated** — `HexCore/.build` and `Hex/Config/Secrets.xcconfig` entries updated to `BasnCore/.build` and `Basn/Config/Secrets.xcconfig`. Critical: without this, `Basn/Config/Secrets.xcconfig` would be exposed to accidental commits.

## What Was Built or Changed

| File / Area | Change |
|-------------|--------|
| `Hex/` → `Basn/` (90 files) | Directory renamed via `git mv`; all source, assets, resources moved |
| `HexCore/` → `BasnCore/` (60 files) | Package directory renamed via `git mv` |
| `Hex/Hex.entitlements` → `Basn/Basn.entitlements` | Entitlements file renamed |
| `Basn.xcodeproj/project.pbxproj` | `CODE_SIGN_ENTITLEMENTS`, `INFOPLIST_FILE`, `DEVELOPMENT_ASSET_PATHS`, `FileSystemSynchronizedRootGroup` path, `XCLocalSwiftPackageReference`, all `Hex/` file path references updated |
| `xcschememanagement.plist` (×2) | Orphaned `Hex.xcscheme` and `HexCore.xcscheme` entries removed |
| `BasnCore/Sources/BasnCore/StoragePaths.swift` | `hexApplicationSupport`, `hexMigratedFileURL`, `hexModelsDirectory` → `basn*`; 7 callsites updated |
| `Localizable.xcstrings` | "Built on Hex (MIT)" → "Built with inspiration from HEX (MIT)"; "Ensure Hex can access…" → "Ensure Basn can access…"; "Hex is open source" → "Basn is open source"; German translations updated |
| `Basn/Features/Settings/AboutView.swift` | Label updated to match xcstrings |
| `Basn/Features/Transcription/TranscriptionFeature.swift` | `"Hex Voice Recording"` → `"Basn Voice Recording"`; fault log updated |
| `BasnIcon.imageset/` | `hex 1.svg` / `hex 2.svg` → `basn-icon-1.svg` / `basn-icon-2.svg`; `Contents.json` updated |
| Code comments (5 files) | `HexCore` / `Hex app` references updated to `BasnCore` / `Basn` in `Logging.swift`, `ParakeetModel.swift`, `Session.swift`, `CaptureScenarioTests.swift`, `ParakeetClient.swift` |
| `package.json` | Description updated from "Hex macOS app" → "Basn macOS app" |
| `.gitignore` | `HexCore/.build` → `BasnCore/.build`; `Hex/Config/Secrets.xcconfig` → `Basn/Config/Secrets.xcconfig` |

## Commit

`76de985` — rename: complete Hex → Basn transition (150 files, 343 insertions, 77 deletions)

## Plan

Archived plan: [are-there-remaining-phases-curious-prism.md](plans/are-there-remaining-phases-curious-prism.md)

## Open Questions

- [ ] Run full test suite via Xcode (Cmd+U) to confirm no compilation regressions from the rename
- [ ] `git config --global safe.bareRepository all` doesn't fix the `swift test` CLI — Xcode/SwiftPM hardcode `explicit` on the command line. May resolve in a future Xcode update.

## Context to Carry Forward

- `Hex/` and `HexCore/` are gone — always reference `Basn/` and `BasnCore/` going forward
- The StoragePaths migration functions still read legacy `hex_settings.json` on disk — this is intentional for upgrade compatibility. The function names are now `basnMigratedFileURL` etc. but the file names they look for remain `hex_*` for the migration path.
- `docs/reference/planning-summary.md` has a stale reference: "move `CastellumClient` to HexCore" — should be updated to say `BasnCore`
