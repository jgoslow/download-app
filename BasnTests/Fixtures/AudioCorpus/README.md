# Audio Test Corpus

The end-to-end audio integration layer ([`AudioPipelineTests`](../../Integration/AudioPipelineTests.swift))
runs real recordings through transcription and asserts a fuzzy **WER** threshold,
then routes the transcript and asserts the resulting `ExecutionPlan`.

## Layout

```
AudioCorpus/
├── manifest.json     # committed — array of corpus entries (CaptureScenario shape)
├── README.md         # committed
└── *.wav             # git-LFS tracked, NOT in normal repo history
```

Audio files are large and varied, so they live in **git-LFS** (see `.gitattributes`)
and are excluded from normal clones via `.gitignore`. The committed `manifest.json`
is the source of truth for what the corpus *should* contain. CI pulls audio with
`git lfs pull` before running the heavy job.

## Manifest entry

Each entry is a `CaptureScenario` (see `BasnCore/Sources/BasnCore/Logic/CaptureScenario.swift`)
with the optional audio fields populated:

```jsonc
{
  "name": "Toggl timer — Indian English, café noise",
  "description": "…",
  "rawText": "log time for two hours on the iOS pipeline",
  "expectedTranscript": "log time for two hours on the iOS pipeline",
  "werThreshold": 0.20,
  "audioFile": "toggl-timer-in-cafe.wav",
  "connectedToolIDs": ["toggl"],
  "routedVia": "heuristic",
  "expected": { "actions": [ { "toolID": "toggl", "actionType": "create_time_entry", "parameters": {} } ] },
  "speaker": { "accent": "Indian English", "nativeEnglish": false, "environment": "café", "mic": "AirPods" },
  "grade": { "...": "carried over from the capture archive (optional)" }
}
```

## Adding entries

1. Record a real capture with **Archive captures** enabled (DebugBar, debug build).
   Each capture lands in `~/Library/Containers/com.lyra.basn.debug/Data/Documents/BasnCaptures/<date>/<time-id>/`.
2. Grade it in the DebugBar **Review** sheet and mark **Keep as fixture**.
3. Promote it:
   ```bash
   bun run tools/src/archive-to-fixture.ts <archive-folder> --corpus
   ```
   This copies `audio.wav` here (renamed) and appends the entry to `manifest.json`.

## Diversity matrix (non-negotiable — REQ-testing)

A single speaker misses real failure modes. Track coverage across:

| Axis            | Target values                                   |
|-----------------|-------------------------------------------------|
| Accent          | native US/UK, Indian, European, East Asian, …   |
| Native English  | yes / no                                        |
| Environment     | quiet room, café/background, street, music      |
| Mic             | built-in Mac mic, AirPods, external/USB         |

Run `bun run tools/src/capture-grades.ts` for current coverage + grade trends.

## Running

```bash
# Pull audio (CI / first run)
git lfs pull

# Pick a downloaded model, then run only the audio layer
BASN_TEST_MODEL=parakeet \
  xcodebuild test -scheme Basn -only-testing:BasnTests/AudioPipelineTests
```

With no corpus present the suite **skips** rather than fails.
