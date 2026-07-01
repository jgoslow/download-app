import SwiftData
import SwiftUI

@main
struct BasnAppIOS: App {
    @State private var appState = AppState()

    static let modelContainer: ModelContainer = {
        let schema = Schema([Tool.self, Workflow.self, CaptureRecord.self, CaptureAnalysis.self])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: false)])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .modelContainer(Self.modelContainer)
                .task {
                    await appState.load()
                    seedDefaultTools()
                    await MarketplaceSeeder.seedIfNeeded(modelContext: Self.modelContainer.mainContext)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { appState.showOnboarding },
                    set: { _ in }
                )) {
                    OnboardingView()
                        .environment(appState)
                        .modelContainer(Self.modelContainer)
                }
        }
    }

    private func seedDefaultTools() {
        let context = Self.modelContainer.mainContext
        guard let existing = try? context.fetch(FetchDescriptor<Tool>()) else { return }
        let existingIDs = Set(existing.map(\.id))
        var inserted = 0
        for tool in Tool.allDefaults where !existingIDs.contains(tool.id) {
            context.insert(tool)
            inserted += 1
        }
        // System-auth tools never need a credential — mark any existing ones as connected.
        for tool in existing where tool.effectiveAuthMethod == "system" && !tool.isConnected {
            tool.isConnected = true
            inserted += 1
        }
        // One-time migration: disable existing system tools so users opt in consciously.
        let disableMigrationKey = "BasnApplied_SystemToolsDisableMigration_v1"
        if !UserDefaults.standard.bool(forKey: disableMigrationKey) {
            for tool in existing where tool.effectiveAuthMethod == "system" {
                tool.isEnabled = false
            }
            UserDefaults.standard.set(true, forKey: disableMigrationKey)
        }
        if inserted > 0 { try? context.save() }
    }
}
