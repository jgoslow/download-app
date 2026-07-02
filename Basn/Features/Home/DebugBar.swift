//
//  DebugBar.swift
//  Basn — #if DEBUG only
//
//  Shown at the bottom of HomeView in debug builds. Toggles the capture archive,
//  which saves each capture's audio + JSON into a dated per-capture folder.
//  Writing the flag here (via @AppStorage) goes to the correct sandbox container
//  UserDefaults — `defaults write` from Terminal does not.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BasnCore

#if DEBUG
struct DebugBar: View {
    @AppStorage(DebugCaptureArchive.toggleKey) private var archiveCaptures = false
    @State private var showReview = false
    @State private var isImporting = false
    @State private var importStatus: String?

    var body: some View {
        HStack(spacing: 8) {
            Text("DEBUG")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.orange, in: Capsule())

            Toggle("Archive captures (audio + JSON)", isOn: $archiveCaptures)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                .foregroundStyle(.secondary)

            if archiveCaptures {
                Text("→ Documents/BasnCaptures/")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.orange.opacity(0.8))

                Button {
                    revealArchive()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Show captures folder in Finder")
            }

            Button("Review") { showReview = true }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .font(.caption)
                .help("Grade archived captures")

            if isImporting {
                ProgressView().controlSize(.mini)
            } else {
                Button("Import…") { importCaptures() }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .font(.caption)
                    .help("Transcribe, route, and grade audio captured elsewhere (e.g. pulled from iPhone)")
            }

            if let importStatus {
                Text(importStatus)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.orange.opacity(0.25), lineWidth: 1))
        .sheet(isPresented: $showReview) {
            DebugCaptureReviewView()
        }
    }

    private func revealArchive() {
        guard let root = DebugCaptureArchive.rootURL else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    /// Pick audio files / phone capture folders and run the desktop pipeline on
    /// each (transcribe → route → archive + grade). New folders appear in Review.
    private func importCaptures() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.wav, .folder]
        panel.message = "Choose audio files or capture folders pulled from another device."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        // Expand any selected parent folders into their capture subfolders so
        // selecting a date folder imports everything inside it.
        let items = panel.urls.flatMap { CaptureIngestor.expand($0) }
        isImporting = true
        importStatus = "importing \(items.count)…"
        Task {
            var ok = 0, failed = 0, duplicates = 0
            for url in items {
                let result = await CaptureIngestor.ingest(url)
                if result.skippedDuplicate {
                    duplicates += 1
                } else if result.folder != nil, result.error == nil {
                    ok += 1
                } else {
                    failed += 1
                }
            }
            await MainActor.run {
                isImporting = false
                importStatus = "imported \(ok)"
                    + (duplicates > 0 ? ", \(duplicates) dupes skipped" : "")
                    + (failed > 0 ? ", \(failed) failed" : "")
            }
        }
    }
}
#endif
