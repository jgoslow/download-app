import BasinShared
import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("History")
            .refreshable {
                await appState.reloadSessions()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No captures yet")
                .font(.title3)
                .fontWeight(.medium)
            Text("Tap the Record tab to start your first capture.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionList: some View {
        List {
            ForEach(appState.sessions) { session in
                SessionRow(session: session, flows: appState.flows)
            }
            .onDelete { offsets in
                Task {
                    for index in offsets {
                        await appState.deleteSession(appState.sessions[index])
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct SessionRow: View {
    let session: Session
    let flows: [Flow]

    private var flowName: String {
        flows.first(where: { $0.id == session.flowID })?.name ?? session.flowID
    }

    private var preview: String {
        let text = session.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 100 else { return text }
        return String(text.prefix(100)) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(flowName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())

                Spacer()

                Text(session.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !session.rawText.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                Label("\(session.wordCount) words", systemImage: "text.word.spacing")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if session.durationSeconds > 0 {
                    let mins = Int(session.durationSeconds) / 60
                    let secs = Int(session.durationSeconds) % 60
                    Label(mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
