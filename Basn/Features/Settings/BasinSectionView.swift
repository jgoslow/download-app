//
//  BasinSectionView.swift
//  Basin
//
//  Settings section for Basin-specific behavior: AI key, paste mode, and advanced server config.
//

import ComposableArchitecture
import BasnCore
import SwiftUI

struct BasinSectionView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    private func basinBinding<T>(_ keyPath: WritableKeyPath<BasinSettings, T>) -> Binding<T> {
        Binding(
            get: { store.basnSettings.basinSettings[keyPath: keyPath] },
            set: { newValue in store.$basnSettings.withLock { $0.basinSettings[keyPath: keyPath] = newValue } }
        )
    }

    var body: some View {
        Section {
            // Anthropic API key (core Basin functionality)
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Anthropic API Key")
                    SecureField(
                        "sk-ant-...",
                        text: basinBinding(\.anthropicAPIKey)
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    Text("Enables AI analysis after each capture (summary, tasks, routing). Leave blank to skip.")
                        .settingsCaption()
                }
            } icon: {
                Image(systemName: "sparkles")
            }

            // Sessions folder link
            Label {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session storage")
                        Text("~/Library/Application Support/Basin/captures/")
                            .settingsCaption()
                            .font(.system(.caption, design: .monospaced))
                    }
                    Spacer()
                    Button("Open") {
                        openSessionsFolder()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                }
            } icon: {
                Image(systemName: "folder")
            }

            // Advanced: Server settings
            DisclosureGroup {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server URL")
                        TextField(
                            "http://localhost:3000",
                            text: basinBinding(\.serverURL)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        Text("POST /transcript endpoint. Leave blank to save locally only.")
                            .settingsCaption()
                    }
                } icon: {
                    Image(systemName: "server.rack")
                }

                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auth Token")
                        SecureField(
                            "Bearer token",
                            text: basinBinding(\.authToken)
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        Text("Sent as Authorization: Bearer <token>. Leave blank for unauthenticated.")
                            .settingsCaption()
                    }
                } icon: {
                    Image(systemName: "key")
                }
            } label: {
                Label("Advanced", systemImage: "gearshape.2")
            }

        } header: {
            Text("Basin")
        }
    }

    private func openSessionsFolder() {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        let sessionsFolder = appSupport.appendingPathComponent("Basin/captures")
        try? FileManager.default.createDirectory(at: sessionsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: sessionsFolder.path)
    }
}
