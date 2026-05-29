import SwiftUI

@main
struct BasnAppIOS: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task { await appState.load() }
                .fullScreenCover(isPresented: Binding(
                    get: { appState.showOnboarding },
                    set: { _ in }
                )) {
                    OnboardingView()
                        .environment(appState)
                }
        }
    }
}
