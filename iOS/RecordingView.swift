import BasinShared
import SwiftUI

// MARK: - RecordView (Flow Screen)
// Shown when the user navigates to the record tab.
// Recording is started by tapping the center button in the tab bar — this screen
// shows the live flow state and lets the user stop the current capture.

struct RecordView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                flowHeader
                    .padding(.top, 48)

                Spacer()

                if appState.isTranscribing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Processing…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else if !appState.isRecording {
                    VStack(spacing: 12) {
                        Image(systemName: "mic.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)

                        Text("Tap the mic to capture")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                if appState.isRecording { Spacer() }

                if appState.flows.count > 1 {
                    flowSelector
                        .padding(.bottom, appState.isRecording ? 0 : 16)
                }

                if appState.isRecording {
                    HStack(spacing: 6) {
                        if appState.isPaused {
                            Image(systemName: "pause.circle.fill")
                                .foregroundStyle(.orange)
                        }
                        Text(durationText)
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundStyle(appState.isPaused ? .orange : .secondary)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 140)
                    .animation(.easeInOut(duration: 0.2), value: appState.isPaused)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.isRecording)
        .animation(.easeInOut(duration: 0.25), value: appState.isTranscribing)
    }

    // MARK: - Flow Header

    private var flowHeader: some View {
        VStack(spacing: 10) {
            Text(appState.activeFlow.name)
                .font(.system(size: 28, weight: .semibold, design: .rounded))

            if !appState.activeFlow.domains.isEmpty {
                HStack(spacing: 6) {
                    ForEach(appState.activeFlow.domains.prefix(4), id: \.self) { domain in
                        Text(domain)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Flow Selector

    private var flowSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(appState.flows) { flow in
                    Button {
                        appState.selectFlow(flow)
                    } label: {
                        Text(flow.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                appState.activeFlow.id == flow.id
                                    ? Color.blue
                                    : Color(.tertiarySystemBackground)
                            )
                            .foregroundStyle(appState.activeFlow.id == flow.id ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isRecording)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Duration

    private var durationText: String {
        let total = Int(appState.recordingDuration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
