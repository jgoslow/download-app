import ComposableArchitecture
import SwiftUI

struct MarketplaceView: View {
    @Bindable var store: StoreOf<MarketplaceFeature>

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading {
                    ProgressView("Loading marketplace...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't load marketplace", systemImage: "wifi.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { store.send(.task) }
                    }
                } else {
                    toolList
                }
            }
            .navigationTitle("Browse Tools")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { store.send(.dismiss) }
                }
            }
            .searchable(text: $store.searchText, prompt: "Search tools")
            .navigationDestination(item: $store.detailEntry) { detailState in
                let detailStore = Store(initialState: detailState) { ToolDetailFeature() }
                ToolDetailView(store: detailStore)
                    .onReceive(detailStore.publisher.map(\.isInstalled).removeDuplicates()) { isInstalled in
                        if isInstalled, let id = store.detailEntry?.entry.id {
                            store.installedIDs.insert(id)
                        }
                    }
            }
        }
        .task { store.send(.task) }
    }

    @ViewBuilder
    private var toolList: some View {
        List {
            // Category filter chips
            if !store.categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryChip(id: nil, label: "All", icon: "square.grid.2x2")
                        ForEach(store.categories) { cat in
                            categoryChip(id: cat.id, label: cat.label, icon: cat.icon)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(store.filteredTools) { entry in
                MarketplaceToolRow(
                    entry: entry,
                    isInstalled: store.installedIDs.contains(entry.id),
                    isInstalling: store.installingIDs.contains(entry.id)
                ) {
                    store.send(.selectTool(entry))
                } onInstall: {
                    store.send(.installTool(entry))
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if store.filteredTools.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            }
        }
    }

    private func categoryChip(id: String?, label: String, icon: String) -> some View {
        let selected = store.selectedCategory == id
        return Button {
            store.selectedCategory = id
        } label: {
            Label(label, systemImage: icon)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tool row

private struct MarketplaceToolRow: View {
    let entry: MarketplaceToolEntry
    let isInstalled: Bool
    let isInstalling: Bool
    let onTap: () -> Void
    let onInstall: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: entry.icon)
                    .font(.title2)
                    .frame(width: 36, height: 36)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(.body)
                            .fontWeight(.medium)
                        if entry.verified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                    Text(entry.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                installButton
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var installButton: some View {
        if isInstalled {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if isInstalling {
            ProgressView()
                .controlSize(.small)
        } else {
            Button("Add", action: onInstall)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
