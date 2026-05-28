```
                                                        /\
                                                 /\    /  \
                                          /\    /  \  /    \
  .             B A S N            .     /  \  /    \/      \
 / \                              / \   /    \/              \
/   \.                           /   \_/     /\               \
     '==.                       /           /  \               \
         '==.                  /     .====='    \               \
             '==.             / .===' || ||      \               \
                 '==.     .===' () ()=() ()       \               \
=||====.=||==.=====||'===' ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ \~ ~ ~ ~ ~ ~ ~ ~
 () ~ ~ ~() ~ ~ ~ ~() ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
```

# Basin
Basn is an AI-powered capture and productivity app for iOS, macOS and Apple Watch.

Pour your thoughts into Basn with daily ritual flows, and build channels for your ideas to go to work. Capture your thoughts by voice, let AI analyze them, and route workflows to the tools you connect. Create channels to support your personal and work life goals. Basn helps you build practical pathways for your ideas and empty your mind on a daily basis.

Basn - Let your thoughts flow.


Built on [Parakeet TDT v3](https://github.com/FluidInference/FluidAudio) (default) and [WhisperKit](https://github.com/argmaxinc/WhisperKit) for on-device transcription, [Swift Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) for state management, and SwiftData + CloudKit for persistence and sync.

> **Note:** Basin requires an **Apple Silicon** Mac running macOS 14+.

---

## The Waterworks

Basin is modeled after a Roman waterworks system. Each layer has a role:

```

       .  *  .                              .  *  .
    *  . ~~ .  *                         *  .    .  *
   . ~~~~ ~~~~ .     THE BASIN            . ~~~~ .
  ~~~~  MIND  ~~~~    WATERWORKS         ~~~~  ~~~~
 ~~~~~~~~~~~~~~~~     ~~~~~~~~~~        ~~~~~~~~~~~
/|||  ~~~~~~~~  |||\                   /|||  ~~~~  |||\
/||||~~~~~~~~~~~~||||\   *   *   *    /||||~~~~~~~~||||\
 ^^^^ MOUNTAINS ^^^^    ~ ~ ~ ~ ~     ^^^^^^^^^^^^ ^^^^
        \   /          ~ springs ~           \   /
         \ /            ~ ~ ~ ~               \ /
          |               \ /                  |
          v                v                   v
         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ~ ~ ~
        ~  ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~  ~
       ~                                           ~
      ~               THE  BASIN                    ~
     ~        Water collects here by gravity.        ~
      ~       No force. No friction. Just speak.    ~
       ~                                           ~
        ~ ~ ~ ~ ~ ~ ~ ~ ~|~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
                          |
            .~~~~~~~~~~~~~|~~~~~~~~~~~~~~.
           /    F   L   O   W   S         \
          /  Guided rituals shape the      \
         /   water into directed streams.   \
        /  Morning Kickoff  |  Day's End     \
       /   Backlog Clean    |  Vision         \
      /_______________________________________ \
                          |
                    ______|______
                   /              \
                  | CASTELLUM     |    The distribution hub.
                  | ~ ~ ~ ~ ~ ~  |    On-device AI receives the
                  | (the brain)   |    water and decides: what is
                  |  ~ ~ ~ ~ ~   |    it? Where should it go?
                   \______________/    Who needs it?
                          |
        __________________|__________________
       |         |         |        |        |
       v         v         v        v        v
    |==|==|   |==|==|   |==|==|  |==|==|  |==|==|
    |card |   | msg |   |hours|  |issue|  |event|   WORKFLOWS
    |==|==|   |==|==|   |==|==|  |==|==|  |==|==|   (previously Channels)
       |         |         |        |        |
       |         |         |        |        |       The paths that
       |         |         |        |        |       carry water to
       |         |         |        |        |       its destination.
       v         v         v        v        v
    [Jira]    [Slack]   [Toggl]  [ GH  ]  [ Cal ]
     ~~~       ~~~       ~~~       ~~~      ~~~
      ~         ~         ~         ~        ~       TOOLS

    Like mechanisms along an aqueduct —
    fountains, baths, water clocks. A single
    workflow may use many tools on its way.

       ~    .    ~    .    ~    .    ~
      . ~ evaporation ~ . ~ . ~ . ~        The water cycle completes.
     ~  .  ~  .  ~  .  ~  .  ~  .  ~       Outputs become context for
    .  ~  .  ~  .  ~  .  ~  .  ~  .  ~     the next capture. Closed
     ~ . ~ . ~ . ~ . ~ . ~ . ~ . ~ .      Jira cards, logged hours,
      .   rising back to the mountains     sent messages — all feed
       ~    .    ~    .    ~    .    ~      back into tomorrow's flows.
```

---

## Terminology

| Term | Metaphor | Definition |
|------|----------|------------|
| **Basn** | The basin itself | The app. Voice capture that feels effortless. |
| **Capture** | Water entering the basin | A single voice recording session with its transcript. |
| **Flow** | A directed stream from the basin | A named capture ritual with guided prompts, schedule, and routing. E.g., "Morning Kickoff" or "Day's End". |
| **Castellum** | The distribution hub | On-device AI orchestration. Receives water from the basin, analyzes it, and decides where it should go. In Roman waterworks, the castellum sat where the aqueduct entered the city and divided the water. |
| **Workflow** (previously Channel) | A channel to a specific outcome — like an aqueduct bringing water to a specific destination, through specific tools, creating a specific result. E.g., "Created Jira card", "Sent email", "Logged time". Not predefined — arises organically from the capture content and connected tools. |
| **Tool** | Mechanisms along the aqueduct | A connected external service (Jira, Slack, Toggl, etc.) with various actions it can perform. Like fountains, baths, and water clocks — a single workflow may use many tools along its path. |
| **Evaporation** | The water cycle or possible "Backflow" | Feedback loop. Outputs (closed cards, logged hours, sent messages) become pre-session context for the next capture. The cycle completes. |

---

## How It Works

1. **Press-and-hold** a hotkey to record, release to transcribe
2. **Double-tap** to lock recording, tap again to stop
3. **Choose a flow** for guided prompts (or use Open for freeform)
4. **AI analyzes** the capture: extracts tasks, routing, mood, delegations
5. **Workflows emerge**: Castellum routes to connected tools — creates Jira cards, logs time, sends messages

---

## Setup

Once you open Basin, grant microphone and accessibility permissions so it can record your voice and paste transcribed text into any application.

### Onboarding order:
1. **Flows** — choose or create your capture rituals
2. **Tools** — connect the services you use (Jira, Slack, Toggl, Google, etc.)
3. **Workflows emerge** — Castellum produces outcomes automatically based on your captures and connected tools. Users can tune the specifics of a workflow by editing natural language descriptions or asking Basn to adjust a workflow directly through an open flow.

---

## Development

See [CLAUDE.md](CLAUDE.md) for build commands, architecture details, and contribution guidelines.

### Changelog workflow

- **For AI agents:** Run `bun run changeset:add-ai <type> "summary"` to create a changeset non-interactively.
- **For humans:** Run `bunx changeset` when your PR needs release notes.
- The release tool consumes fragments, bumps versions, and publishes to GitHub + Sparkle.

## License

This project is licensed under the MIT License. See `LICENSE` for details.
