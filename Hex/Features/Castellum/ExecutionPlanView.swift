//
//  ExecutionPlanView.swift
//  Basin
//
//  Inline card shown in HomeView after analysis identifies actionable tasks.
//  Displays proposed actions with checkboxes, status indicators, and execute/retry controls.
//

import ComposableArchitecture
import HexCore
import SwiftUI

struct ExecutionPlanView: View {
    let store: StoreOf<CastellumFeature>

    var body: some View {
        if store.isPlanning {
            planningIndicator
        } else if let error = store.planningError {
            errorCard(error)
        } else if let plan = store.currentPlan {
            planCard(plan)
        }
    }

    // MARK: - Planning Indicator

    private var planningIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Planning actions...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Error Card

    private func errorCard(_ error: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("Planning failed")
                    .font(.headline)
                Spacer()
                Button { store.send(.dismissPlan) } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(error)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Plan Card

    private func planCard(_ plan: ExecutionPlan) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bolt.circle.fill")
                    .foregroundStyle(.blue)
                Text("Proposed Actions")
                    .font(.headline)
                Spacer()

                if !store.isExecuting {
                    Button { store.send(.dismissPlan) } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Action rows
            let channelGroups = groupedActions(plan.actions)

            VStack(spacing: 0) {
                // Direct actions
                if let direct = channelGroups[nil], !direct.isEmpty {
                    ForEach(direct) { action in
                        actionRow(action)
                        if action.id != plan.actions.last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }

                // Channel-grouped actions
                let channelEntries = channelGroups.compactMap { k, v -> (String, [PlannedAction])? in
                    guard let k else { return nil }
                    return (k, v)
                }
                ForEach(channelEntries, id: \.0) { channelID, actions in
                    channelHeader(channelID)
                    ForEach(actions) { action in
                        actionRow(action, indented: true)
                        if action.id != actions.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }

            Divider()

            // Footer with execute button
            HStack {
                let selectedCount = store.selectedActions.count
                let totalCount = plan.actions.count
                Text("\(selectedCount) of \(totalCount) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if store.isExecuting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Executing...")
                            .font(.callout)
                    }
                } else if plan.actions.contains(where: { $0.status == .failed }) {
                    // Some actions failed — show status
                    let succeeded = plan.actions.filter { $0.status == .succeeded }.count
                    let failed = plan.actions.filter { $0.status == .failed }.count
                    Text("\(succeeded) done, \(failed) failed")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if plan.actions.allSatisfy({ $0.status == .succeeded }) {
                    // All done
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("All actions completed")
                            .font(.callout)
                    }
                } else {
                    Button {
                        store.send(.executeSelected)
                    } label: {
                        Text("Execute")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.selectedActions.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Action Row

    private func actionRow(_ action: PlannedAction, indented: Bool = false) -> some View {
        HStack(spacing: 8) {
            // Checkbox (only when pending)
            if action.status == .pending {
                Button {
                    store.send(.toggleAction(action.id))
                } label: {
                    Image(systemName: store.selectedActions.contains(action.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.selectedActions.contains(action.id) ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                statusIcon(action.status)
            }

            // Tool icon
            Image(systemName: toolIcon(action.toolID))
                .frame(width: 16)
                .foregroundStyle(.secondary)

            // Label
            Text(action.label)
                .font(.callout)
                .lineLimit(2)

            Spacer()

            // Retry button for failed actions
            if action.status == .failed {
                Button {
                    store.send(.retryAction(action.id))
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .help("Retry this action")
            }
        }
        .padding(.horizontal, indented ? 24 : 12)
        .padding(.vertical, 8)
    }

    // MARK: - Channel Header

    private func channelHeader(_ channelID: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2)
            Text(channelID.replacingOccurrences(of: "-", with: " ").capitalized)
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    private func statusIcon(_ status: ActionStatus) -> some View {
        Group {
            switch status {
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            case .executing:
                ProgressView()
                    .controlSize(.mini)
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func toolIcon(_ toolID: String) -> String {
        switch toolID {
        case "jira": return "ticket"
        case "github": return "chevron.left.forwardslash.chevron.right"
        case "slack": return "bubble.left.and.bubble.right"
        case "toggl": return "clock"
        case "calendar": return "calendar"
        case "email": return "envelope"
        case "wave": return "dollarsign.circle"
        default: return "wrench"
        }
    }

    private func groupedActions(_ actions: [PlannedAction]) -> [String?: [PlannedAction]] {
        Dictionary(grouping: actions) { $0.channelID }
    }
}
