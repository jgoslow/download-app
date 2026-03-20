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

    var isRecording: Bool { store.transcription.isRecording }
    var isTranscribing: Bool { store.transcription.isTranscribing }
    var isModelReady: Bool { store.modelBootstrapState.isModelReady }
    var lastAnalysis: SessionAnalysis? { store.transcription.lastAnalysis }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

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

            Spacer().frame(height: 20)

            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .animation(.easeInOut, value: isRecording)
                .animation(.easeInOut, value: isTranscribing)

            Spacer()

            // Last transcript + analysis
            if !isRecording && !isTranscribing, let lastTranscript = store.transcription.transcriptionHistory.history.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Raw transcript
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

                        // Analysis
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
                }
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Shortcut hint
            if !isRecording && !isTranscribing {
                Text("or use the keyboard shortcut")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
