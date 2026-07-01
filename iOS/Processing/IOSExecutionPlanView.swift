//
//  IOSExecutionPlanView.swift
//  Basn iOS
//
//  Presents the routing result (ExecutionPlan) for a capture and lets the user
//  execute the planned tool actions on-device, against their connected tools
//  (via GenericToolExecutor + Keychain auth). Per-action status + results shown.
//

import SwiftUI
import SwiftData
import BasinShared

struct IOSExecutionPlanView: View {
    let plan: ExecutionPlan
    @Environment(\.dismiss) private var dismiss
    @Query private var tools: [Tool]

    @State private var statuses: [String: ActionStatus] = [:]
    @State private var results: [String: String] = [:]
    @State private var isExecuting = false
    @State private var connectingTool: Tool?

    private var executableActions: [PlannedAction] {
        plan.actions.filter { isConnected($0.toolID) }
    }
    private var allDone: Bool {
        !executableActions.isEmpty && executableActions.allSatisfy { statuses[$0.id] == .succeeded }
    }

    var body: some View {
        NavigationStack {
            Group {
                if plan.actions.isEmpty {
                    ContentUnavailableView(
                        "No actions",
                        systemImage: "tray",
                        description: Text("This capture didn't map to any tool actions.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(plan.actions) { action in
                                ActionRow(
                                    action: action,
                                    status: statuses[action.id] ?? .pending,
                                    result: results[action.id],
                                    connected: isConnected(action.toolID),
                                    providers: providerCandidates(for: action),
                                    onConnect: { toolID in connectingTool = tools.first { $0.id == toolID } }
                                )
                            }
                        } footer: {
                            if let model = plan.modelUsed {
                                let label: String = switch model {
                                case "heuristic":    "Routed via local pattern matching."
                                case "on-device":    "Routed via on-device AI (Apple Intelligence)."
                                case "lightweight":  "Routed via lightweight cloud AI (Claude Haiku)."
                                default:             "Routed via \(model)."
                                }
                                Text(label)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Capture Plan")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $connectingTool) { tool in
                ToolConnectSheet(tool: tool, onDismiss: { connectingTool = nil })
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(allDone ? "Done" : "Close") { dismiss() }
                }
                if !executableActions.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        if isExecuting {
                            ProgressView()
                        } else {
                            Button(allDone ? "Re-run" : "Execute") { executeAll() }
                        }
                    }
                }
            }
        }
    }

    private func isConnected(_ toolID: String) -> Bool {
        !toolID.isEmpty && tools.contains { $0.id == toolID && $0.isAvailableForRouting }
    }

    /// Tools to offer connecting for an action. Tool-scoped action → that tool;
    /// generic capability action (empty toolID) → all tools that provide it.
    private func providerCandidates(for action: PlannedAction) -> [String] {
        action.toolID.isEmpty
            ? CapabilityResolver.providers(for: action.actionType)
            : [action.toolID]
    }

    private func executeAll() {
        isExecuting = true
        Task {
            for action in plan.actions {
                // Skip generic/unconnected actions — they show a connect link instead.
                guard let tool = tools.first(where: { $0.id == action.toolID && $0.isAvailableForRouting }) else { continue }
                await MainActor.run { statuses[action.id] = .executing }
                let result = await GenericToolExecutor.execute(action: action, tool: tool)
                await MainActor.run {
                    if let result {
                        statuses[action.id] = result.success ? .succeeded : .failed
                        results[action.id] = result.success ? (result.message ?? "Done") : (result.error ?? "Failed")
                    } else {
                        statuses[action.id] = .failed
                        results[action.id] = "No executor available for \(action.toolID)"
                    }
                }
            }
            await MainActor.run { isExecuting = false }
        }
    }
}

private struct ActionRow: View {
    let action: PlannedAction
    let status: ActionStatus
    let result: String?
    let connected: Bool
    let providers: [String]
    let onConnect: (String) -> Void

    @State private var showThirdPartyPicker = false

    private var isGeneric: Bool { action.toolID.isEmpty }

    /// Native system tools (apple-*) available for this action — quick enable via ToolConnectSheet.
    private var nativeProviders: [String] { providers.filter { $0.hasPrefix("apple-") } }
    /// Third-party tools — surfaced via a picker so specific apps aren't listed inline.
    private var thirdPartyProviders: [String] { providers.filter { !$0.hasPrefix("apple-") } }

    /// Parameters that need special-case display (time range shown as a single formatted line).
    private var timeRangeDisplay: String? {
        guard let startISO = action.parameters["start_time"] else { return nil }
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFmt2 = ISO8601DateFormatter()
        let timeFmt = DateFormatter()
        timeFmt.dateStyle = .none
        timeFmt.timeStyle = .short
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "EEE, MMM d"
        let cal = Calendar.current

        func parse(_ s: String) -> Date? { isoFmt.date(from: s) ?? isoFmt2.date(from: s) }

        guard let start = parse(startISO) else { return nil }

        let dayLabel: String
        if cal.isDateInToday(start)     { dayLabel = "Today" }
        else if cal.isDateInTomorrow(start) { dayLabel = "Tomorrow" }
        else                            { dayLabel = dateFmt.string(from: start) }

        var range = timeFmt.string(from: start)
        if let endISO = action.parameters["end_time"], let end = parse(endISO) {
            range += " – " + timeFmt.string(from: end)
        }
        return "\(range) · \(dayLabel)"
    }

    /// Keys rendered as a single time range (hidden from the generic param loop).
    private let timeKeys: Set<String> = ["start_time", "end_time"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusIcon
                Text(action.label.isEmpty ? friendlyActionLabel : action.label)
                    .font(.body.weight(.medium))
                    .foregroundStyle(connected ? .primary : .secondary)
                Spacer()
            }
            Text(isGeneric ? "Suggested · \(friendlyActionType)" : "\(action.toolID) · \(friendlyActionType)")
                .font(.caption).foregroundStyle(.secondary)

            // Show time range as a human-readable formatted line
            if let timeDisplay = timeRangeDisplay {
                HStack(alignment: .top, spacing: 6) {
                    Text("time").font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(timeDisplay).font(.caption)
                }
            }
            // All other parameters (excluding raw ISO time keys)
            ForEach(action.parameters.sorted(by: { $0.key < $1.key }).filter { !timeKeys.contains($0.key) }, id: \.key) { key, value in
                HStack(alignment: .top, spacing: 6) {
                    Text(friendlyParamKey(key)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(value).font(.caption)
                }
            }

            if !connected {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isGeneric ? "Connect \(capabilityNoun) to run this action:" : "Connect a tool to run this action:")
                        .font(.caption2).foregroundStyle(.orange)
                        .padding(.top, 4)

                    HStack(spacing: 8) {
                        if isGeneric {
                            // 1. Native (built-in) tools first — one tap to enable
                            ForEach(nativeProviders, id: \.self) { toolID in
                                Button { onConnect(toolID) } label: {
                                    Label(toolDisplayName(toolID), systemImage: toolIcon(toolID))
                                        .font(.caption2)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .tint(.orange)
                            }

                            // 2. Generic "connect another" for third-party options
                            if !thirdPartyProviders.isEmpty {
                                Button { showThirdPartyPicker = true } label: {
                                    Label("Connect another app", systemImage: "plus.circle")
                                        .font(.caption2)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .tint(.secondary)
                                .confirmationDialog(
                                    "Connect \(capabilityNounBare) app",
                                    isPresented: $showThirdPartyPicker,
                                    titleVisibility: .visible
                                ) {
                                    ForEach(thirdPartyProviders, id: \.self) { toolID in
                                        Button(toolDisplayName(toolID)) { onConnect(toolID) }
                                    }
                                }
                            } else if nativeProviders.isEmpty {
                                Text("Go to Settings → Tools to add one.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        } else {
                            // Specific tool — show its dedicated connect button
                            ForEach(providers, id: \.self) { toolID in
                                Button { onConnect(toolID) } label: {
                                    Label(toolDisplayName(toolID), systemImage: toolIcon(toolID))
                                        .font(.caption2)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .tint(.orange)
                            }
                        }
                    }
                }
            }

            if let result {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(status == .succeeded ? .green : .red)
            }
        }
        .padding(.vertical, 2)
        .opacity(connected ? 1 : 0.9)
    }

    /// Human-readable display name for a tool ID.
    private func toolDisplayName(_ toolID: String) -> String {
        switch toolID {
        case "apple-calendar":  return "Apple Calendar"
        case "apple-reminders": return "Reminders"
        case "apple-notes":     return "Apple Notes"
        case "apple-mail":      return "Mail"
        case "apple-messages":  return "Messages"
        case "apple-files":     return "Files"
        case "toggl":           return "Toggl"
        case "jira":            return "Jira"
        case "slack":           return "Slack"
        case "google":          return "Google"
        case "github":          return "GitHub"
        default:                return toolID.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }
    }

    /// SF Symbol name for a tool ID.
    private func toolIcon(_ toolID: String) -> String {
        switch toolID {
        case "apple-calendar":  return "calendar"
        case "apple-reminders": return "list.bullet.clipboard"
        case "apple-notes":     return "note.text"
        case "apple-mail":      return "envelope.fill"
        case "apple-messages":  return "bubble.left.and.bubble.right.fill"
        case "apple-files":     return "folder.fill"
        case "toggl":           return "timer"
        case "jira":            return "checklist"
        case "slack":           return "bubble.left.fill"
        case "google":          return "doc.text.fill"
        case "github":          return "chevron.left.forwardslash.chevron.right"
        default:                return "bolt.fill"
        }
    }

    /// "a notes app", "a calendar app", etc. — used in the generic connect CTA.
    private var capabilityNoun: String {
        switch action.actionType {
        case "capture_note", "create_note":      return "a notes app"
        case "schedule_event", "create_event":   return "a calendar app"
        case "create_task", "create_reminder":   return "a task manager"
        case "log_time":                         return "a time tracker"
        case "send_message":                     return "a messaging app"
        case "send_email", "compose_email":      return "an email app"
        case "create_document":                  return "a docs app"
        case "save_text", "save_file":           return "a storage app"
        default:                                 return "an app"
        }
    }

    /// Bare noun for dialog title (no article): "notes app", "calendar app", etc.
    private var capabilityNounBare: String { capabilityNoun.replacingOccurrences(of: "a ", with: "").replacingOccurrences(of: "an ", with: "") }

    /// Human-readable action type label.
    private var friendlyActionType: String {
        switch action.actionType {
        case "capture_note", "create_note":      return "Create Note"
        case "schedule_event", "create_event":   return "Create Event"
        case "create_task":                      return "Create Task"
        case "create_reminder":                  return "Create Reminder"
        case "log_time":                         return "Log Time"
        case "send_message":                     return "Send Message"
        case "send_email", "compose_email":      return "Compose Email"
        case "create_document":                  return "Create Document"
        case "save_text", "save_file":           return "Save File"
        default:                                 return action.actionType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Fall-through label when action.label is empty.
    private var friendlyActionLabel: String {
        if !action.toolID.isEmpty {
            return "\(toolDisplayName(action.toolID)): \(friendlyActionType)"
        }
        return friendlyActionType
    }

    /// Human-readable parameter key labels.
    private func friendlyParamKey(_ key: String) -> String {
        switch key {
        case "body":       return "body"
        case "title":      return "title"
        case "subject":    return "subject"
        case "to":         return "to"
        case "recipient":  return "recipient"
        case "notes":      return "notes"
        case "folder":     return "folder"
        case "filename":   return "filename"
        case "content":    return "content"
        case "priority":   return "priority"
        case "duration":   return "duration"
        case "project":    return "project"
        case "channel":    return "channel"
        default:           return key
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .pending:   Image(systemName: isGeneric ? "sparkles" : toolIcon(action.toolID)).foregroundStyle(isGeneric ? .orange : .blue)
        case .executing: ProgressView().controlSize(.small)
        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
