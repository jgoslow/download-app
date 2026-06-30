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
                                Text("Routed via \(model).")
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
        !toolID.isEmpty && tools.contains { $0.id == toolID && $0.isConnected }
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
                guard let tool = tools.first(where: { $0.id == action.toolID && $0.isConnected }) else { continue }
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

    private var isGeneric: Bool { action.toolID.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusIcon
                Text(action.label.isEmpty ? "\(action.toolID) · \(action.actionType)" : action.label)
                    .font(.body.weight(.medium))
                    .foregroundStyle(connected ? .primary : .secondary)
                Spacer()
            }
            Text(isGeneric ? "Suggested · \(action.actionType)" : "\(action.toolID) · \(action.actionType)")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(action.parameters.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(alignment: .top, spacing: 6) {
                    Text(key).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(value).font(.caption)
                }
            }

            if !connected {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isGeneric
                         ? "No tool connected for this yet — connect one to run it:"
                         : "Connect \(action.toolID.capitalized) to run this action:")
                        .font(.caption2).foregroundStyle(.orange)
                    if providers.isEmpty {
                        Text("No tool available for this action.")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            ForEach(providers, id: \.self) { toolID in
                                Button { onConnect(toolID) } label: {
                                    Label("Connect \(toolID.capitalized)", systemImage: "link").font(.caption2)
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

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .pending:   Image(systemName: isGeneric ? "sparkles" : icon(for: action.toolID)).foregroundStyle(isGeneric ? .orange : .blue)
        case .executing: ProgressView().controlSize(.small)
        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private func icon(for toolID: String) -> String {
        switch toolID {
        case "jira": return "checklist"
        case "slack": return "number"
        case "toggl": return "timer"
        case "google": return "doc.text"
        case "github": return "chevron.left.forwardslash.chevron.right"
        default: return "bolt"
        }
    }
}
