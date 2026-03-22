//
//  HomeView.swift
//  Download (macOS)
//
//  The app's home screen. One big button. Click to record, click to stop.
//  The hotkey still works alongside this — both paths hit the same TCA actions.
//

import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct HomeView: View {
    @Bindable var store: StoreOf<AppFeature>
    @ObserveInjection var inject
    @State private var showHistory = false
    @State private var selectedPromptID: Int? = nil

    var isRecording: Bool { store.transcription.isRecording }
    var isTranscribing: Bool { store.transcription.isTranscribing }
    var isModelReady: Bool { store.modelBootstrapState.isModelReady }
    var lastAnalysis: SessionAnalysis? { store.transcription.lastAnalysis }
    var history: [Transcript] { store.transcription.transcriptionHistory.history }
    fileprivate var selectedType: DownloadTypeInfo {
        Self.downloadTypes.first { $0.id == store.transcription.selectedDownloadTypeID }
            ?? Self.downloadTypes[0]
    }

    private static let downloadTypes: [DownloadTypeInfo] = [
        DownloadTypeInfo(
            id: "open",
            name: "Open",
            intro: "No structure. No prompts. Press record, speak, press stop.",
            prompts: []
        ),
        DownloadTypeInfo(
            id: "morning-kickoff",
            name: "Morning Kickoff",
            intro: "Before the day gets its hooks in you. Start with how you're actually doing, then build your day.",
            prompts: [
                PromptItem(id: 0, title: "Body check-in",
                           detail: "How are you feeling right now? Not what you think — what you actually feel. Sensations in your body, energy level, tension."),
                PromptItem(id: 1, title: "What's weighing on you",
                           detail: "What's bigger than your work that you're carrying into today? Personal stuff, worries, things on your mind. Let it be named."),
                PromptItem(id: 2, title: "What would make today good",
                           detail: "Not productive — good. What would make you feel like today was a day well spent?"),
                PromptItem(id: 3, title: "Yesterday's follow-ups",
                           detail: "Any follow-ups from yesterday that need to happen before you start new work?"),
                PromptItem(id: 4, title: "Today's work",
                           detail: "What needs to get done today that isn't already captured? Say it now — tasks, calls, deliverables."),
                PromptItem(id: 5, title: "Delegations",
                           detail: "Anything you want to delegate to Diego or Josh today? Be specific about what they need to know."),
                PromptItem(id: 6, title: "Drafts",
                           detail: "Any emails or Slack messages you want to draft while you're thinking about it?"),
            ]
        ),
        DownloadTypeInfo(
            id: "mid-day-touchstone",
            name: "Mid-Day Touchstone",
            intro: "Meetings are done. Adjust the day's trajectory based on what's actually happened.",
            prompts: [
                PromptItem(id: 0, title: "Body check",
                           detail: "Where are you holding tension right now? Neck, shoulders, jaw, gut? Water? Food?"),
                PromptItem(id: 1, title: "What just happened",
                           detail: "New priorities from this morning? Things that shifted or became urgent? Anything from a meeting you need to capture before you forget?"),
                PromptItem(id: 2, title: "Delegation",
                           detail: "From this morning and what just came up — what needs to go to Diego or Josh?"),
                PromptItem(id: 3, title: "End-of-day target",
                           detail: "What's the single most important thing to have done before you close your laptop? Anything to consciously drop?"),
                PromptItem(id: 4, title: "Evening bridge",
                           detail: "Need to check in about tonight? Dinner, family, coordination? What time do you want to stop working?"),
            ]
        ),
        DownloadTypeInfo(
            id: "days-end",
            name: "Day's End",
            intro: "Close the loop. What actually happened, what it felt like, what gets tracked.",
            prompts: [
                PromptItem(id: 0, title: "Hour accounting",
                           detail: "Walk through the day in roughly the order it happened. What did you work on? What's not in Toggl?"),
                PromptItem(id: 1, title: "Task close-out",
                           detail: "What got done? What didn't? Anything you did that wasn't on the list? It counts."),
                PromptItem(id: 2, title: "Emotional close",
                           detail: "How did today feel? Not how productive — how did it feel? One thing you want to remember from today."),
                PromptItem(id: 3, title: "Unfinished business",
                           detail: "Anything unfinished that's going to pull at you tonight? Name it and set it down."),
                PromptItem(id: 4, title: "Tomorrow's seed",
                           detail: "Anything the morning download should know about? Say it now and let it go."),
            ]
        ),
        DownloadTypeInfo(
            id: "backlog-clean",
            name: "Backlog Clean",
            intro: "You're not doing the work right now. You're making sure the work is visible and assigned.",
            prompts: [
                PromptItem(id: 0, title: "Project overview",
                           detail: "Which projects need the most attention? Which is furthest behind on scope vs. contract?"),
                PromptItem(id: 1, title: "Scope drift",
                           detail: "Any projects where the scope has changed but the cards haven't caught up?"),
                PromptItem(id: 2, title: "Stale cards",
                           detail: "Cards that haven't moved in a while — still valid? Close, update, or deprioritize?"),
                PromptItem(id: 3, title: "New cards",
                           detail: "Any new work that needs a Jira card? Walk through each one: what, why, roughly how long."),
                PromptItem(id: 4, title: "PM handoff",
                           detail: "Who owns PM review today — Diego or Josh? Any cards that need a sync call?"),
            ]
        ),
        DownloadTypeInfo(
            id: "vision-alignment",
            name: "Vision Alignment",
            intro: "You don't have to have answers. You just have to be honest. Let's see what the quarter says.",
            prompts: [
                PromptItem(id: 0, title: "The mirror",
                           detail: "Looking at the last quarter — what's the story? What were you actually doing with your time and attention?"),
                PromptItem(id: 1, title: "Short-term goals",
                           detail: "What's a concrete goal for the next 90 days? Be specific."),
                PromptItem(id: 2, title: "Long-term vision",
                           detail: "What's a longer-term goal (1-3 years) to keep in view?"),
                PromptItem(id: 3, title: "Letting go",
                           detail: "Any goal from 90 days ago you're ready to let go of? Personal life goals that belong on this list?"),
                PromptItem(id: 4, title: "The real question",
                           detail: "What do you actually want your life to look like? Not as a founder — as a person. What do you keep saying you'll do that never happens?"),
            ]
        ),
    ]

    var body: some View {
        HStack(spacing: 0) {
            // Main content
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 40)

                // Download type picker
                if !isRecording && !isTranscribing {
                    Picker("Type", selection: Binding(
                        get: { store.transcription.selectedDownloadTypeID },
                        set: { newID in
                        let type = Self.downloadTypes.first { $0.id == newID } ?? Self.downloadTypes[0]
                        store.send(.transcription(.setDownloadType(newID, promptTitles: type.prompts.map(\.title))))
                    }
                    )) {
                        ForEach(Self.downloadTypes, id: \.id) { type in
                            Text(type.name).tag(type.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                    .padding(.bottom, 8)

                    // Intro text
                    Text(selectedType.intro)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                        .padding(.bottom, 16)
                }

                // Record button
                Button(action: handleRecordButton) {
                    ZStack {
                        Circle()
                            .fill(buttonBackground)
                            .frame(width: 88, height: 88)
                            .shadow(color: shadowColor, radius: isRecording ? 16 : 4, x: 0, y: 2)

                        Image(systemName: buttonIcon)
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .buttonStyle(.plain)
                .symbolEffect(.pulse, isActive: isRecording)
                .animation(.easeInOut(duration: 0.2), value: isRecording)
                .animation(.easeInOut(duration: 0.2), value: isTranscribing)
                .disabled(isTranscribing || !isModelReady)

                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                    .animation(.easeInOut, value: isRecording)
                    .animation(.easeInOut, value: isTranscribing)

                // Shortcut hint
                if !isRecording && !isTranscribing {
                    Text("or use the keyboard shortcut")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }

                // Prompt detail (when a prompt is selected from sidebar)
                if let promptID = selectedPromptID,
                   let prompt = selectedType.prompts.first(where: { $0.id == promptID }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(prompt.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button {
                                selectedPromptID = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(prompt.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                // Last transcript + analysis
                if !isRecording && !isTranscribing, let lastTranscript = history.first {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Transcript")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                            Text(lastTranscript.text)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }

                        if let analysis = lastAnalysis {
                            Divider()
                            AnalysisCard(analysis: analysis)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Session history
                if !isRecording && !isTranscribing && history.count > 1 {
                    DisclosureGroup("Previous sessions", isExpanded: $showHistory) {
                        VStack(spacing: 8) {
                            ForEach(history.dropFirst().prefix(10)) { transcript in
                                SessionRow(transcript: transcript)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                Spacer().frame(height: 20)
            }
            .frame(maxWidth: .infinity)
        }

            // Prompt sidebar
            if !selectedType.prompts.isEmpty {
                Divider()
                PromptSidebar(
                    prompts: selectedType.prompts,
                    selectedID: $selectedPromptID,
                    addressedIDs: Set(lastAnalysis?.promptsAddressed ?? [])
                )
                .frame(width: 200)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: lastAnalysis != nil)
        .enableInjection()
    }

    // MARK: - Helpers

    private var buttonBackground: some ShapeStyle {
        if isRecording {
            return AnyShapeStyle(Color.red.gradient)
        } else if isTranscribing {
            return AnyShapeStyle(Color.orange.gradient)
        }
        return AnyShapeStyle(Color.accentColor.gradient)
    }

    private var shadowColor: Color {
        if isRecording { return .red.opacity(0.4) }
        return .black.opacity(0.15)
    }

    private var buttonIcon: String {
        if isTranscribing { return "waveform" }
        if isRecording { return "stop.fill" }
        return "mic.fill"
    }

    private var statusText: String {
        if isTranscribing { return "Transcribing…" }
        if isRecording { return "Recording — click to stop" }
        if !isModelReady { return "Loading model…" }
        return "Click to record"
    }

    private func handleRecordButton() {
        if isRecording {
            store.send(.transcription(.stopRecording))
        } else {
            store.send(.transcription(.startRecording))
        }
    }
}

// MARK: - Prompt Sidebar

private struct PromptSidebar: View {
    let prompts: [PromptItem]
    @Binding var selectedID: Int?
    let addressedIDs: Set<Int>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("Prompts")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                ForEach(prompts) { prompt in
                    Button {
                        selectedID = selectedID == prompt.id ? nil : prompt.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: addressedIDs.contains(prompt.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(addressedIDs.contains(prompt.id) ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                            Text(prompt.title)
                                .font(.caption)
                                .foregroundStyle(selectedID == prompt.id ? .primary : .secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedID == prompt.id
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .background(.regularMaterial)
    }
}

// MARK: - Download Type Info

fileprivate struct DownloadTypeInfo: Identifiable {
    let id: String
    let name: String
    let intro: String
    let prompts: [PromptItem]
}

fileprivate struct PromptItem: Identifiable {
    let id: Int
    let title: String
    let detail: String
}

// MARK: - Analysis Card

private struct AnalysisCard: View {
    let analysis: SessionAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Summary
            HStack(alignment: .top, spacing: 6) {
                if let mood = analysis.moodTag {
                    Text(mood)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
                Text(analysis.summary)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Tasks
            if !analysis.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(analysis.tasks, id: \.self) { task in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .padding(.top, 1)
                            Text(task)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            // Routing destinations
            if !analysis.routing.isEmpty {
                HStack(spacing: 6) {
                    ForEach(analysis.routing, id: \.self) { dest in
                        Text(dest.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Integration tags
            if !analysis.integrations.isEmpty {
                HStack(spacing: 6) {
                    Text("Integrations")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(analysis.integrations, id: \.self) { integration in
                        HStack(spacing: 3) {
                            Image(systemName: integrationIcon(integration))
                                .font(.system(size: 8))
                            Text(integration.rawValue)
                        }
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func integrationIcon(_ integration: SessionAnalysis.Integration) -> String {
        switch integration {
        case .jira: return "ticket"
        case .toggl: return "clock"
        case .slack: return "bubble.left"
        case .email: return "envelope"
        case .calendar: return "calendar"
        case .wave: return "dollarsign.circle"
        case .github: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let transcript: Transcript

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.timeFormatter.string(from: transcript.timestamp))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(transcript.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}
