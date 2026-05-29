import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            RecordView()
                .tabItem { Label("Record", systemImage: "mic.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
