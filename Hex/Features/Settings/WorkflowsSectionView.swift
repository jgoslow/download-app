//
//  WorkflowsSectionView.swift
//  Basin
//
//  Settings section for workflows — emergent automations produced by Castellum
//  from capture content and connected tools. Workflows are defined by a plain-English
//  instruction rather than pre-configured action mappings.
//
//  Formerly ChannelsSectionView (the old "Channels" concept).
//

import ComposableArchitecture
import HexCore
import SwiftData
import SwiftUI

struct WorkflowsSectionView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    @Query(sort: \Workflow.sortOrder) private var workflows: [Workflow]

    var body: some View {
        Section {
            if workflows.isEmpty {
                emptyState
            } else {
                ForEach(workflows) { workflow in
                    workflowRow(workflow)
                }
            }
        } header: {
            Text("Workflows")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No workflows yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Workflows are created during onboarding or when Castellum detects a repeating pattern in your captures.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Row

    @ViewBuilder
    private func workflowRow(_ workflow: Workflow) -> some View {
        Label {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workflow.name)
                    Text(workflow.instruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { workflow.isEnabled },
                    set: { workflow.isEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        } icon: {
            Image(systemName: workflow.iconSystemName)
                .foregroundStyle(workflow.isEnabled ? .primary : .tertiary)
        }
    }
}
