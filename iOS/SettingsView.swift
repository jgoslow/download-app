import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    NavigationLink {
                        Text("Flows — coming soon")
                            .navigationTitle("Flows")
                    } label: {
                        Label("Flows", systemImage: "wind")
                    }

                    NavigationLink {
                        Text("Transcription model — coming soon")
                            .navigationTitle("Model")
                    } label: {
                        Label("Transcription Model", systemImage: "waveform")
                    }
                }

                Section("Connections") {
                    NavigationLink {
                        Text("Tools — coming soon")
                            .navigationTitle("Tools")
                    } label: {
                        Label("Tools", systemImage: "wrench.and.screwdriver")
                    }

                    NavigationLink {
                        Text("Workflows — coming soon")
                            .navigationTitle("Workflows")
                    } label: {
                        Label("Workflows", systemImage: "arrow.triangle.branch")
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://getbasin.ai")!) {
                        Label("getbasin.ai", systemImage: "globe")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
