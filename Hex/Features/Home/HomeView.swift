//
//  HomeView.swift
//  Basin (macOS)
//
//  The app's home screen. One big button. Click to record, click to stop.
//  The hotkey still works alongside this — both paths hit the same TCA actions.
//

import ComposableArchitecture
import HexCore
import Inject
import SwiftData
import SwiftUI

struct HomeView: View {
    @Bindable var store: StoreOf<AppFeature>
    @ObserveInjection var inject
    @Query(filter: #Predicate<FlowDefinition> { !$0.isTemplate },
           sort: \FlowDefinition.sortOrder)
    private var flows: [FlowDefinition]
    @State private var showHistory = false
    @State private var selectedPromptID: Int? = nil

    var isRecording: Bool { store.transcription.isRecording }
    var isTranscribing: Bool { store.transcription.isTranscribing }
    var isModelReady: Bool { store.modelBootstrapState.isModelReady }
    var lastAnalysis: SessionAnalysis? { store.transcription.lastAnalysis }
    var history: [Transcript] { store.transcription.transcriptionHistory.history }
    fileprivate var selectedFlow: FlowDefinition? {
        flows.first { $0.id == store.transcription.selectedFlowID }
            ?? flows.first
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main content
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 40)

                // Flow picker
                if !isRecording && !isTranscribing {
                    Picker("Type", selection: Binding(
                        get: { store.transcription.selectedFlowID },
                        set: { newID in
                        let flow = flows.first { $0.id == newID }
                        let promptTitles = flow?.prompts.map(\.title) ?? []
                        store.send(.transcription(.setFlow(newID, promptTitles: promptTitles)))
                    }
                    )) {
                        if flows.isEmpty {
                            Text("Open Flow").tag("open")
                        }
                        ForEach(flows) { flow in
                            Text(flow.name).tag(flow.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                    .padding(.bottom, 8)

                    // Intro text
                    if let flow = selectedFlow {
                        Text(flow.intro)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                            .padding(.bottom, 16)
                    }
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
                   let prompt = selectedFlow?.prompts.first(where: { $0.id == promptID }) {
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

                            // Castellum execution plan (appears when actions are identified)
                            ExecutionPlanView(
                                store: store.scope(state: \.castellum, action: \.castellum)
                            )
                            .padding(.top, 8)
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
            if let flow = selectedFlow, !flow.prompts.isEmpty {
                Divider()
                PromptSidebar(
                    prompts: flow.prompts,
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
    let prompts: [FlowPrompt]
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
