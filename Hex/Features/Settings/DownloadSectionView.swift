//
//  DownloadSectionView.swift
//  Download
//
//  Settings section for Download-specific behavior: server endpoint, auth, routing mode.
//

import ComposableArchitecture
import HexCore
import SwiftUI

struct DownloadSectionView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        Section {
            // Server URL
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server URL")
                    TextField(
                        "http://localhost:3000",
                        text: $store.hexSettings.downloadSettings.serverURL
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    Text("POST /transcript endpoint. Leave blank to save locally only.")
                        .settingsCaption()
                }
            } icon: {
                Image(systemName: "server.rack")
            }

            // Auth token
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auth Token")
                    SecureField(
                        "Bearer token",
                        text: $store.hexSettings.downloadSettings.authToken
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    Text("Sent as Authorization: Bearer <token>. Leave blank for unauthenticated.")
                        .settingsCaption()
                }
            } icon: {
                Image(systemName: "key")
            }

            // Anthropic API key
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Anthropic API Key")
                    SecureField(
                        "sk-ant-...",
                        text: $store.hexSettings.downloadSettings.anthropicAPIKey
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    Text("Enables AI analysis after each session (summary, tasks, routing). Leave blank to skip.")
                        .settingsCaption()
                }
            } icon: {
                Image(systemName: "sparkles")
            }

            // Paste after session toggle
            Label {
                Toggle(
                    "Paste transcript to cursor",
                    isOn: $store.hexSettings.downloadSettings.pasteAfterSession
                )
                Text("Enable to keep Hex's original paste-to-cursor behavior alongside session routing.")
                    .settingsCaption()
            } icon: {
                Image(systemName: "doc.on.clipboard")
            }

            // Sessions folder link
            Label {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session storage")
                        Text("~/Library/Application Support/Download/sessions/")
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

        } header: {
            Text("Download")
        }
    }

    private func openSessionsFolder() {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        let sessionsFolder = appSupport.appendingPathComponent("Download/sessions")
        // Create if needed, then reveal in Finder
        try? FileManager.default.createDirectory(at: sessionsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: sessionsFolder.path)
    }
}
