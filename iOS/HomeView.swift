import AVFoundation
import BasinShared
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5 ..< 12: return "Good morning"
        case 12 ..< 17: return "Good afternoon"
        case 17 ..< 21: return "Good evening"
        default: return "Good night"
        }
    }

    // Most recently used unique flows, padded with other flows up to 3.
    private var recentFlows: [Flow] {
        var seen = Set<String>()
        var result: [Flow] = []
        for session in appState.sessions.sorted(by: { $0.timestamp > $1.timestamp }) {
            guard !seen.contains(session.flowID),
                  let flow = appState.flows.first(where: { $0.id == session.flowID })
            else { continue }
            seen.insert(session.flowID)
            result.append(flow)
            if result.count == 3 { break }
        }
        for flow in appState.flows where !seen.contains(flow.id) && result.count < 3 {
            result.append(flow)
        }
        return result
    }

    private var mostRecentSession: Session? {
        appState.sessions.max(by: { $0.timestamp < $1.timestamp })
    }

    private var needsSetup: Bool {
        !appState.micPermissionGranted || !appState.isModelDownloaded
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header
                    if needsSetup { setupCard }
                    if !appState.isLoadingFlows { recentFlowsSection }
                    if let session = mostRecentSession { lastCaptureCard(session) }
                    if !appState.sessions.isEmpty { weekStatsCard }
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Basn")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Let your thoughts flow.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Setup Checklist

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Get set up")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if !appState.isModelDownloaded {
                SetupRow(
                    icon: "arrow.down.circle.fill",
                    title: "Download transcription model",
                    subtitle: appState.isDownloadingModel
                        ? "Downloading… \(Int(appState.modelDownloadProgress * 100))%"
                        : "Required for on-device voice transcription",
                    done: false,
                    inProgress: appState.isDownloadingModel,
                    progressValue: appState.isDownloadingModel ? appState.modelDownloadProgress : nil
                )
            }

            if !appState.micPermissionGranted {
                SetupRow(
                    icon: "mic.fill",
                    title: "Allow microphone access",
                    subtitle: "Required to capture your voice",
                    done: false
                )
            }

            if appState.isModelDownloaded && appState.micPermissionGranted {
                SetupRow(
                    icon: "checkmark.circle.fill",
                    title: "You're all set",
                    subtitle: "Tap Record to start your first capture",
                    done: true
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Recent Flows

    private var recentFlowsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Flows")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recentFlows) { flow in
                        FlowCard(
                            flow: flow,
                            isActive: appState.activeFlow.id == flow.id
                        ) {
                            appState.selectFlow(flow)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Last Capture

    private func lastCaptureCard(_ session: Session) -> some View {
        let flowName = appState.flows.first(where: { $0.id == session.flowID })?.name ?? session.flowID
        let preview = session.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = preview.count > 200 ? String(preview.prefix(200)) + "…" : preview

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last capture")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(session.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(flowName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())

                if !truncated.isEmpty {
                    Text(truncated)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(5)
                }

                HStack(spacing: 14) {
                    Label("\(session.wordCount) words", systemImage: "text.word.spacing")
                    if session.durationSeconds > 0 {
                        let m = Int(session.durationSeconds) / 60
                        let s = Int(session.durationSeconds) % 60
                        Label(m > 0 ? "\(m)m \(s)s" : "\(s)s", systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Week Stats

    private var weekStatsCard: some View {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
        let thisWeek = appState.sessions.filter { $0.timestamp >= weekStart }
        let totalWords = thisWeek.reduce(0) { $0 + $1.wordCount }
        let totalMins = Int(thisWeek.reduce(0.0) { $0 + $1.durationSeconds }) / 60

        return VStack(alignment: .leading, spacing: 10) {
            Text("This week")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            HStack(spacing: 0) {
                StatCell(value: "\(thisWeek.count)", label: "captures")
                Divider().frame(height: 32)
                StatCell(value: "\(totalWords)", label: "words")
                Divider().frame(height: 32)
                StatCell(value: totalMins > 0 ? "\(totalMins)m" : "<1m", label: "recorded")
            }
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }
}

// MARK: - FlowCard

private struct FlowCard: View {
    let flow: Flow
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(flow.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isActive ? .white : .primary)

                if !flow.domains.isEmpty {
                    Text(flow.domains.prefix(2).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(isActive ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minWidth: 100, alignment: .leading)
            .background(isActive ? Color.blue : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color.clear : Color(.separator).opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SetupRow

private struct SetupRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let done: Bool
    var inProgress: Bool = false
    var progressValue: Double? = nil

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if inProgress {
                    Image(systemName: icon).foregroundStyle(.blue)
                } else {
                    Image(systemName: icon).foregroundStyle(.blue)
                }
            }
            .font(.title3)
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(done ? .secondary : .primary)
                    .strikethrough(done)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let p = progressValue, inProgress {
                    ProgressView(value: p)
                        .tint(.blue)
                        .padding(.top, 4)
                        .frame(maxWidth: 220)
                }
            }

            Spacer()

            if !done {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - StatCell

private struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
