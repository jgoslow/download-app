import ComposableArchitecture
import Foundation
import SwiftData

@Reducer
struct MarketplaceFeature {
    @ObservableState
    struct State: Equatable {
        var manifest: MarketplaceManifest?
        var isLoading = false
        var errorMessage: String?
        var selectedCategory: String?
        var searchText = ""
        var installingIDs: Set<String> = []
        var installedIDs: Set<String> = []
        /// The tool whose detail sheet is presented (nil = no sheet).
        var detailEntry: ToolDetailFeature.State?

        var filteredTools: [MarketplaceToolEntry] {
            guard let manifest else { return [] }
            return manifest.tools.filter { entry in
                let matchesCategory = selectedCategory == nil || entry.category == selectedCategory
                let matchesSearch = searchText.isEmpty
                    || entry.name.localizedCaseInsensitiveContains(searchText)
                    || entry.description.localizedCaseInsensitiveContains(searchText)
                    || entry.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
                return matchesCategory && matchesSearch
            }
        }

        var categories: [MarketplaceCategory] { manifest?.categories ?? [] }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task
        case manifestLoaded(Result<MarketplaceManifest, Error>)
        case installTool(MarketplaceToolEntry)
        case toolInstalled(Result<(String, ToolDefinitionSpec), Error>)
        case selectTool(MarketplaceToolEntry)
        case dismiss
    }

    @Dependency(\.marketplaceClient) var marketplace
    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .task:
                state.isLoading = true
                state.errorMessage = nil
                let installedDir = MarketplaceClient.installedToolsDirectory()
                if let files = try? FileManager.default.contentsOfDirectory(
                    at: installedDir, includingPropertiesForKeys: nil
                ).filter({ $0.pathExtension == "json" }) {
                    state.installedIDs = Set(files.map { $0.deletingPathExtension().lastPathComponent })
                }
                return .run { send in
                    await send(.manifestLoaded(Result { try await marketplace.fetchManifest() }))
                }

            case let .manifestLoaded(.success(manifest)):
                state.isLoading = false
                state.manifest = manifest
                return .none

            case let .manifestLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            case let .installTool(entry):
                state.installingIDs.insert(entry.id)
                return .run { send in
                    await send(.toolInstalled(Result {
                        let spec = try await marketplace.installTool(entry)
                        return (entry.id, spec)
                    }))
                }

            case let .toolInstalled(.success((toolID, _))):
                state.installingIDs.remove(toolID)
                state.installedIDs.insert(toolID)
                ToolDefinitionLoader.invalidateCache()
                return .none

            case let .toolInstalled(.failure(error)):
                state.installingIDs = []
                state.errorMessage = error.localizedDescription
                return .none

            case let .selectTool(entry):
                state.detailEntry = ToolDetailFeature.State(
                    entry: entry,
                    isInstalled: state.installedIDs.contains(entry.id)
                )
                return .none

            case .dismiss:
                return .run { _ in await dismiss() }

            case .binding:
                return .none
            }
        }
    }
}

// MARK: - Tool detail sub-feature

@Reducer
struct ToolDetailFeature {
    @ObservableState
    struct State: Equatable {
        let entry: MarketplaceToolEntry
        var isInstalled: Bool
        var spec: ToolDefinitionSpec?
        var isLoadingSpec = false

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.entry == rhs.entry
                && lhs.isInstalled == rhs.isInstalled
                && lhs.isLoadingSpec == rhs.isLoadingSpec
                && (lhs.spec == nil) == (rhs.spec == nil)
        }
    }

    enum Action {
        case task
        case specLoaded(Result<ToolDefinitionSpec, Error>)
        case installTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isLoadingSpec = true
                let url = URL(string: state.entry.definitionUrl)!
                return .run { send in
                    await send(.specLoaded(Result {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        return try JSONDecoder().decode(ToolDefinitionSpec.self, from: data)
                    }))
                }

            case let .specLoaded(.success(spec)):
                state.isLoadingSpec = false
                state.spec = spec
                return .none

            case .specLoaded(.failure):
                state.isLoadingSpec = false
                return .none

            case .installTapped:
                return .none
            }
        }
    }
}
