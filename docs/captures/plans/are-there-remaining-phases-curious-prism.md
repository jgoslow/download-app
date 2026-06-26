# Remaining Hex → Basn Transition

## Context

The app was originally named "Hex" and has been substantially renamed to "Basn" (targets, bundle IDs, schemes, Swift module names). However, the two source directories (`Hex/`, `HexCore/`), several user-visible strings, internal API names, and Xcode build settings still reference the old name. This plan completes the transition.

**Explicitly out of scope:**
- `hex_settings.json` / `transcription_history.json` file names on disk — intentional backwards-compat migration paths
- Historical CHANGELOG.md entries — these are historical records

---

## Phase 1 — User-visible & runtime strings (no structural risk)

**Files to edit:**

- [Localizable.xcstrings](Localizable.xcstrings) — entries to update:
  - `"Built on Hex (MIT)"` → `"Built with inspiration from HEX (MIT)"`
  - `"Ensure Hex can access your microphone..."` → `"Ensure Basn can access..."`
  - `"Hex is open source"` → `"Basn is open source"`
  - German translation `"Hex ist Open Source"` → `"Basn ist Open Source"`
  - `"Hex on GitHub"` — the link label for `github.com/kitlangton/Hex` — leave as-is

- [Hex/Features/Settings/AboutView.swift](Hex/Features/Settings/AboutView.swift):
  - `Label("Built on Hex (MIT)", ...)` → `Label("Built with inspiration from HEX (MIT)", ...)`
  - `Link("Hex on GitHub", ...)` pointing to `github.com/kitlangton/Hex` — leave as-is (correct attribution URL)

- [Hex/Features/Transcription/TranscriptionFeature.swift](Hex/Features/Transcription/TranscriptionFeature.swift):
  - `preventSleep(reason: "Hex Voice Recording")` → `"Basn Voice Recording"`
  - `fault("Force quit voice command recognized; terminating Hex.")` → `"terminating Basn."`

- [package.json](package.json):
  - `"description": "Release metadata + changelog automation for the Hex macOS app."` → `"...for the Basn macOS app."`

---

## Phase 2 — Internal API renaming (BasnCore StoragePaths)

**File:** [HexCore/Sources/BasnCore/StoragePaths.swift](HexCore/Sources/BasnCore/StoragePaths.swift)

Rename three public members:
- `URL.hexApplicationSupport` → `URL.basnApplicationSupport`
- `URL.hexMigratedFileURL(named:)` → `URL.basnMigratedFileURL(named:)` (the underlying migration logic stays the same — it reads legacy `hex_settings.json` paths to migrate them)
- `URL.hexModelsDirectory` → `URL.basnModelsDirectory`

Then update all callsites — `grep -r "hexApplicationSupport\|hexMigratedFileURL\|hexModelsDirectory"` across the project. Known callsites:
- `Hex/Models/AppBasnSettings.swift` — `hexMigratedFileURL(named: "hex_settings.json")`
- `Hex/Features/History/HistoryFeature.swift` — `hexMigratedFileURL(named: "transcription_history.json")`

Also update the comment on `AppBasnSettings.swift:6` from `"without HexCore prefixes"` → `"without BasnCore prefixes"`.

---

## Phase 3 — Directory rename: `Hex/` → `Basn/`

This is the largest structural change. It requires coordinated git and Xcode edits.

**Steps:**
1. `git mv Hex Basn` — renames the directory and its contents in git history
2. Rename `Basn/Hex.entitlements` → `Basn/Basn.entitlements`
3. Edit [Basn.xcodeproj/project.pbxproj](Basn.xcodeproj/project.pbxproj) — update the following build settings (all currently reference `Hex/...`):
   - `CODE_SIGN_ENTITLEMENTS` → `Basn/Basn.entitlements`
   - `DEVELOPMENT_ASSET_PATHS` → `"Basn/Preview Content"`
   - `INFOPLIST_FILE` → `Basn/Info.plist`
   - `PBXFileSystemSynchronizedRootGroup` name → `Basn`
4. Remove the orphaned `<key>Hex.xcscheme_^#shared#^_</key>` entry from [Basn.xcodeproj/xcuserdata/jonasgoslow.xcuserdatad/xcschemes/xcschememanagement.plist](Basn.xcodeproj/xcuserdata/jonasgoslow.xcuserdatad/xcschemes/xcschememanagement.plist)

**Verify:** `xcodebuild -scheme Basn -configuration Debug build` succeeds after these changes.

---

## Phase 4 — Directory rename: `HexCore/` → `BasnCore/`

1. `git mv HexCore BasnCore`
2. Edit [Basn.xcodeproj/project.pbxproj](Basn.xcodeproj/project.pbxproj):
   - `XCLocalSwiftPackageReference "HexCore"` → `"BasnCore"`
   - Update the `path` value for the local package reference from `HexCore` to `BasnCore`
3. Remove the orphaned `<key>HexCore.xcscheme_^#shared#^_</key>` entry from [BasnCore/.swiftpm/xcode/xcuserdata/jonasgoslow.xcuserdatad/xcschemes/xcschememanagement.plist](BasnCore/.swiftpm/xcode/xcuserdata/jonasgoslow.xcuserdatad/xcschemes/xcschememanagement.plist)
4. Update [docs/reference/](docs/reference/) or any REQ-*.md files that refer to the `HexCore/` path

**Verify:** `cd BasnCore && swift test` passes.

---

## Phase 5 — Asset file cleanup

In `Basn/Assets.xcassets/BasnIcon.imageset/` (after Phase 3 rename):
- Rename `hex 1.svg` and `hex 2.svg` to `basn-icon-1.svg` / `basn-icon-2.svg`
- Update the `Contents.json` in that imageset to reference the new filenames

---

## Recommended execution order

Do Phases 1–2 first (no build risk, easy to verify). Then Phase 3 and 4 together in a single commit since they're structurally related. Phase 5 is cosmetic and can be done any time.

## Verification

- `xcodebuild -scheme Basn -configuration Debug build` — no errors
- `cd BasnCore && swift test` — all tests pass
- `grep -r "Hex" . --include="*.swift" --include="*.xcstrings" --include="*.json" --include="*.plist" -l` — only returns historical files (CHANGELOG.md, legacy filenames)
- `grep -r "HexCore\|Hex/" . --include="*.pbxproj"` — zero results
