import ComposableArchitecture
import SwiftUI

struct ToolDetailView: View {
    @Bindable var store: StoreOf<ToolDetailFeature>

    var body: some View {
        List {
            // Header
            Section {
                HStack(spacing: 16) {
                    Image(systemName: store.entry.icon)
                        .font(.largeTitle)
                        .frame(width: 56, height: 56)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(store.entry.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                            if store.entry.verified {
                                Label("Verified", systemImage: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .labelStyle(.iconOnly)
                            }
                        }
                        Text(store.entry.author)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
            }

            Section {
                Text(store.entry.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            // Install / installed state
            Section {
                if store.isInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        store.send(.installTapped)
                    } label: {
                        Label("Add to Basn", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .listRowBackground(Color.clear)

            // Actions
            if let spec = store.spec {
                let sortedActions = spec.actions.sorted(by: { $0.key < $1.key })
                Section("Actions") {
                    ForEach(sortedActions, id: \.key) { key, action in
                        ActionRowView(action: action)
                    }
                }
            } else if store.isLoadingSpec {
                Section("Actions") {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }

            // Metadata
            Section("Details") {
                LabeledContent("Version", value: store.entry.version)
                LabeledContent("Category", value: store.entry.category.capitalized)
                LabeledContent("Min. Basn", value: store.entry.minimumBasnVersion)
                if !store.entry.tags.isEmpty {
                    LabeledContent("Tags") {
                        Text(store.entry.tags.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(store.entry.name)
        .task { store.send(.task) }
    }
}

// MARK: - Action row

private struct ActionRowView: View {
    let action: ToolDefinitionSpec.ActionSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(action.displayName)
                .font(.body)
            Text(action.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let cap = action.capability {
                Text(cap)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}
