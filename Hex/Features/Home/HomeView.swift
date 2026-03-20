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
                "How are you feeling right now? Body, not thoughts.",
                "What would make today feel good — not productive, good?",
                "What needs to get done today that isn't captured?"
            ]
        ),
        DownloadTypeInfo(
            id: "mid-day-touchstone",
            name: "Mid-Day Touchstone",
            intro: "Meetings are done. Adjust the day's trajectory based on what's actually happened.",
            prompts: [
                "Quick body check — where are you holding tension?",
                "New priorities or things now urgent?",
                "Most important thing before you close the laptop?"
            ]
        ),
        DownloadTypeInfo(
            id: "days-end",
            name: "Day's End",
            intro: "Close the loop. What actually happened, what it felt like, what gets tracked.",
            prompts: [
                "Walk through the day — what did you work on?",
                "How did today feel? Not productivity — how did it feel?",
                "Anything unfinished pulling at you tonight? Name it and set it down."
            ]
        ),
        DownloadTypeInfo(
            id: "backlog-clean",
            name: "Backlog Clean",
            intro: "You're not doing the work right now. You're making sure the work is visible and assigned.",
            prompts: [
                "Which project needs the most attention?",
                "Any new work that needs a Jira card?",
                "Who owns PM review — Diego or Josh?"
            ]
        ),
        DownloadTypeInfo(
            id: "vision-alignment",
            name: "Vision Alignment",
            intro: "You don't have to have answers. You just have to be honest. Let's see what the quarter says.",
            prompts: [
                "Looking at the last quarter — what's the story?",
                "Concrete goal for the next 90 days?",
                "What do you actually want your life to look like?"
            ]
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                // Download type picker
                if !isRecording && !isTranscribing {
                    Picker("Type", selection: Binding(
                        get: { store.transcription.selectedDownloadTypeID },
                        set: { store.send(.transcription(.setDownloadType($0))) }
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

                // Guided prompts
                if !selectedType.prompts.isEmpty && !isTranscribing {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Things to cover")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                        ForEach(Array(selectedType.prompts.enumerated()), id: \.offset) { _, prompt in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(.tertiary)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(prompt)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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

// MARK: - Download Type Info

fileprivate struct DownloadTypeInfo: Identifiable {
    let id: String
    let name: String
    let intro: String
    let prompts: [String]
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
