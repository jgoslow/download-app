import SwiftData
import SwiftUI

@main
struct BasnAppIOS: App {
    @State private var appState = AppState()

    static let modelContainer: ModelContainer = {
        let schema = Schema([Tool.self, Workflow.self])
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
                }
                .fullScreenCover(isPresented: Binding(
                    get: { appState.showOnboarding },
                    set: { _ in }
                )) {
                    OnboardingView()
                        .environment(appState)
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
        if inserted > 0 { try? context.save() }
    }
}
