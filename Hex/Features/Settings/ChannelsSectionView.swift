//
//  ChannelsSectionView.swift
//  Basin
//
//  Settings section for channel automations (Write an email, Create a Jira card, etc.).
//  Each channel shows its required tools and can be enabled/disabled.
//

import ComposableArchitecture
import HexCore
import SwiftData
import SwiftUI

struct ChannelsSectionView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    @Query(sort: \ChannelDefinition.sortOrder) private var channels: [ChannelDefinition]
    @Query private var tools: [Tool]

    var body: some View {
        Section {
            ForEach(channels) { channel in
                channelRow(channel)
            }
        } header: {
            Text("Channels")
        }
    }

    @ViewBuilder
    private func channelRow(_ channel: ChannelDefinition) -> some View {
        let missingTools = channel.requiredToolIDs.filter { toolID in
            !tools.contains { $0.id == toolID && $0.isConnected }
        }
        let canEnable = missingTools.isEmpty

        Label {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                    if !canEnable, let firstMissing = missingTools.first {
                        let toolName = tools.first { $0.id == firstMissing }?.name ?? firstMissing
                        Text("Connect \(toolName) first")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if channel.requiredToolIDs.isEmpty {
                        Text("No tool required")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        let toolNames = channel.requiredToolIDs.compactMap { id in
                            tools.first { $0.id == id }?.name
                        }.joined(separator: ", ")
                        Text("Uses: \(toolNames)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                if canEnable {
                    Toggle("", isOn: Binding(
                        get: { channel.isEnabled },
                        set: { channel.isEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
        } icon: {
            Image(systemName: channel.iconSystemName)
                .foregroundStyle(canEnable ? .primary : .tertiary)
        }
    }
}
