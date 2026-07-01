import BasinShared
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var showDetail = false

    var body: some View {
        Group {
            if appState.sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 140)
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showDetail.toggle() }
                } label: {
                    Image(systemName: showDetail ? "text.justify" : "text.justify.left")
                        .symbolVariant(showDetail ? .fill : .none)
                }
                .accessibilityLabel(showDetail ? "Compact view" : "Detailed view")
            }
        }
        .refreshable {
            await appState.reloadSessions()
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
                NavigationLink(value: session) {
                    SessionRow(session: session, flows: appState.flows, showDetail: showDetail)
                }
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

// MARK: - Session Detail View

struct SessionDetailView: View {
    let session: Session
    @Environment(AppState.self) private var appState
    @AppStorage(DeveloperMode.unlockedKey) private var developerUnlocked = false
    @State private var isRouting = false
    @State private var didCopy = false

    @Query private var records: [CaptureRecord]

    init(session: Session) {
        self.session = session
        let id = session.id
        _records = Query(filter: #Predicate<CaptureRecord> { $0.id == id })
    }

    private var flowName: String {
        appState.flows.first(where: { $0.id == session.flowID })?.name ?? session.flowID
    }

    private var storedPlan: ExecutionPlan? {
        guard let data = records.first?.executionPlanData else { return nil }
        return try? JSONDecoder().decode(ExecutionPlan.self, from: data)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                metadataCard

                VStack(alignment: .leading, spacing: 8) {
                    Label("Transcript", systemImage: "text.quote")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(session.rawText.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                if let plan = storedPlan {
                    planCard(plan)
                } else if developerUnlocked {
                    noPlanCard
                }
            }
            .padding()
        }
        .navigationTitle(flowName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = session.rawText
                    didCopy = true
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                }
                .tint(didCopy ? .green : nil)
                .onChange(of: didCopy) { _, new in
                    if new {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
                    }
                }

                if developerUnlocked {
                    Button {
                        Task { await routeAndShow() }
                    } label: {
                        if isRouting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRouting)
                }
            }
        }
    }

    private func planCard(_ plan: ExecutionPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Capture Plan", systemImage: "list.bullet.rectangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let model = plan.modelUsed {
                    Text(modelLabel(model))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            ForEach(plan.actions) { action in
                HStack(spacing: 10) {
                    Image(systemName: planActionIcon(action))
                        .foregroundStyle(action.toolID.isEmpty ? .orange : .blue)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.label.isEmpty
                             ? action.actionType.replacingOccurrences(of: "_", with: " ").capitalized
                             : action.label)
                            .font(.subheadline)
                        Text(action.toolID.isEmpty
                             ? "No tool connected"
                             : action.toolID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Divider()

            Button {
                appState.lastPlan = plan
            } label: {
                Label("View & Execute", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var noPlanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No plan stored", systemImage: "bolt.slash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Re-run routing to generate a plan for this capture.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Generate Plan") {
                Task { await routeAndShow() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRouting)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var metadataCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(flowName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
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
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func routeAndShow() async {
        isRouting = true
        await appState.rerunCapture(session: session)
        isRouting = false
    }

    private func planActionIcon(_ action: PlannedAction) -> String {
        switch action.actionType {
        case "schedule_event", "create_event":   return "calendar"
        case "create_task", "create_reminder":   return "list.bullet.clipboard"
        case "capture_note", "create_note":      return "note.text"
        case "log_time":                         return "timer"
        case "send_message":                     return "bubble.left.fill"
        case "send_email", "compose_email":      return "envelope.fill"
        case "create_document":                  return "doc.text.fill"
        default:                                 return "bolt.fill"
        }
    }

    private func modelLabel(_ model: String) -> String {
        switch model {
        case "heuristic":   return "pattern matching"
        case "on-device":   return "on-device AI"
        case "lightweight": return "cloud AI"
        default:            return model
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: Session
    let flows: [Flow]
    let showDetail: Bool
    @Environment(AppState.self) private var appState
    @AppStorage(DeveloperMode.unlockedKey) private var developerUnlocked = false
    @State private var isRerunning = false
    @State private var didCopy = false

    @Query private var records: [CaptureRecord]

    init(session: Session, flows: [Flow], showDetail: Bool) {
        self.session = session
        self.flows = flows
        self.showDetail = showDetail
        let id = session.id
        _records = Query(filter: #Predicate<CaptureRecord> { $0.id == id })
    }

    private var storedPlan: ExecutionPlan? {
        guard let data = records.first?.executionPlanData else { return nil }
        return try? JSONDecoder().decode(ExecutionPlan.self, from: data)
    }

    private var flowName: String {
        flows.first(where: { $0.id == session.flowID })?.name ?? session.flowID
    }

    private var relativeTimestamp: String {
        let days = Calendar.current.dateComponents([.day], from: session.timestamp, to: Date()).day ?? 0
        if days >= 7 {
            return session.timestamp.formatted(date: .abbreviated, time: .omitted)
        }
        return session.timestamp.formatted(.relative(presentation: .named))
    }

    private func planActionIcon(_ action: PlannedAction) -> String {
        switch action.actionType {
        case "schedule_event", "create_event":   return "calendar"
        case "create_task", "create_reminder":   return "list.bullet.clipboard"
        case "capture_note", "create_note":      return "note.text"
        case "log_time":                         return "timer"
        case "send_message":                     return "bubble.left.fill"
        case "send_email", "compose_email":      return "envelope.fill"
        case "create_document":                  return "doc.text.fill"
        default:                                 return "bolt.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row
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

                Text(relativeTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Transcript (preview or full)
            if !session.rawText.isEmpty {
                Text(session.rawText.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(showDetail ? nil : 3)
            }

            // Stats row
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

                if isRerunning {
                    Spacer()
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.65)
                        Text("Routing…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Plan summary (only in expanded mode)
            if showDetail, let plan = storedPlan, !plan.actions.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Suggested actions")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(plan.actions.prefix(4)) { action in
                        HStack(spacing: 6) {
                            Image(systemName: planActionIcon(action))
                                .font(.caption2)
                                .foregroundStyle(action.toolID.isEmpty ? .orange : .blue)
                                .frame(width: 14)
                            Text(action.label.isEmpty
                                 ? action.actionType.replacingOccurrences(of: "_", with: " ").capitalized
                                 : action.label)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    if plan.actions.count > 4 {
                        Text("+ \(plan.actions.count - 4) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        appState.lastPlan = plan
                    } label: {
                        Label("Execute Plan", systemImage: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.blue)
                    .padding(.top, 2)
                }
                .padding(.top, 2)
            }

            // Detail actions (only in expanded mode)
            if showDetail {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = session.rawText
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
                    } label: {
                        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(didCopy ? .green : .secondary)

                    if developerUnlocked {
                        Button {
                            guard !isRerunning else { return }
                            Task {
                                isRerunning = true
                                await appState.rerunCapture(session: session)
                                isRerunning = false
                            }
                        } label: {
                            Label("Re-run", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isRerunning)
                        .tint(isRerunning ? .secondary : .blue)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        Task { await appState.deleteSession(session) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.red)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if developerUnlocked {
                Button {
                    guard !isRerunning else { return }
                    Task {
                        isRerunning = true
                        await appState.rerunCapture(session: session)
                        isRerunning = false
                    }
                } label: {
                    Label("Re-run", systemImage: "arrow.clockwise")
                }
            }
            Button {
                UIPasteboard.general.string = session.rawText
            } label: {
                Label("Copy Transcript", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                Task { await appState.deleteSession(session) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } preview: {
            VStack(alignment: .leading, spacing: 8) {
                Text(flowName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                Text(session.rawText)
                    .font(.subheadline)
                    .lineLimit(6)
                    .padding(.top, 2)
            }
            .padding()
            .frame(maxWidth: 300, alignment: .leading)
        }
    }
}
