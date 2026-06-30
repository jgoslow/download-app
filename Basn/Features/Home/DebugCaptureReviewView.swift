//
//  DebugCaptureReviewView.swift
//  Basn — #if DEBUG only
//
//  Master-detail review of archived captures. Sidebar: date-grouped list with
//  transcript previews. Detail: audio playback + a transcript / tabbed
//  (Summary-Actions | JSON) split, plus the test-value grading controls.
//  Reads the BasnCaptures archive folders directly; merges human feedback into
//  grade.json and recomputes the composite testValue.
//

import SwiftUI
import AVFoundation
import BasnCore

#if DEBUG
struct DebugCaptureReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var captures: [DebugCaptureArchive.ArchivedCapture] = []
    @State private var selection: String?
    @StateObject private var player = CapturePlayer()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Archived Captures").font(.headline)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { reload() }
                Button("Done") { dismiss() }
            }
            .padding(10)
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 280)
                Divider()
                Group {
                    if let id = selection, let idx = captures.firstIndex(where: { $0.id == id }) {
                        CaptureDetailView(capture: $captures[idx], player: player)
                            .id(id)  // rebuild (reload detail + reset grading) on selection change
                    } else {
                        ContentUnavailableView("Select a capture", systemImage: "waveform")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 1040, height: 680)
        .onAppear(perform: reload)
        .onDisappear { player.stop() }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            if captures.isEmpty {
                Text("No archived captures yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.day) { group in
                Section(group.day) {
                    ForEach(group.items) { cap in
                        sidebarRow(cap).tag(cap.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(_ cap: DebugCaptureArchive.ArchivedCapture) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(cap.metadata?.timestamp.formatted(date: .omitted, time: .standard)
                     ?? cap.folder.lastPathComponent)
                    .font(.subheadline.weight(.medium))
                if let p = cap.metadata?.platform {
                    Image(systemName: p == "ios" ? "iphone" : "desktopcomputer")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let v = cap.grade?.testValue {
                    Text("\(v)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(scoreColor(v).opacity(0.2), in: Capsule())
                }
            }
            Text(cap.transcript ?? "(no transcript)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private func scoreColor(_ v: Int) -> Color { v >= 70 ? .green : v >= 40 ? .orange : .red }

    /// Date-grouped, preserving the newest-first order.
    private var groups: [(day: String, items: [DebugCaptureArchive.ArchivedCapture])] {
        var order: [String] = []
        var map: [String: [DebugCaptureArchive.ArchivedCapture]] = [:]
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        for cap in captures {
            let day = cap.metadata.map { fmt.string(from: $0.timestamp) } ?? "Unknown date"
            if map[day] == nil { order.append(day) }
            map[day, default: []].append(cap)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func reload() {
        captures = DebugCaptureArchive.listArchivedCaptures()
        if selection == nil { selection = captures.first?.id }
    }
}

// MARK: - Detail

private struct CaptureDetailView: View {
    @Binding var capture: DebugCaptureArchive.ArchivedCapture
    @ObservedObject var player: CapturePlayer

    @State private var detail: DebugCaptureArchive.CaptureDetail?
    @State private var isRunning = false
    @State private var runError: String?

    // Grading
    @State private var accuracy: CaptureGrade.Accuracy?
    @State private var keepAsFixture = false
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let runError {
                Text(runError)
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal).padding(.bottom, 6)
            }
            Divider()
            if let detail {
                HSplitView {
                    transcriptPane(detail)
                        .frame(minWidth: 260)
                    rightTabs(detail)
                        .frame(minWidth: 300)
                }
            } else {
                Spacer()
            }
            Divider()
            gradingBar
        }
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(capture.metadata?.timestamp.formatted(date: .abbreviated, time: .standard)
                     ?? capture.folder.lastPathComponent)
                    .font(.headline)
                HStack(spacing: 10) {
                    if let m = capture.metadata {
                        Label("\(Int(m.durationSeconds))s", systemImage: "clock")
                        Label(m.whisperModel, systemImage: "waveform")
                    }
                    if let r = capture.grade?.routedVia ?? detail?.routedVia {
                        Label(r, systemImage: "arrow.triangle.branch")
                    }
                    Label("\(detail?.actions.count ?? capture.grade?.actionCount ?? 0) actions", systemImage: "bolt")
                    if let n = capture.grade?.audio?.noiseScore {
                        Label(String(format: "noise %.2f", n), systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let v = capture.grade?.testValue {
                Text("score \(v)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.blue.opacity(0.15), in: Capsule())
            }
            playButton
            if isRunning {
                ProgressView().controlSize(.small)
            } else {
                Button("Run pipeline", systemImage: "play.rectangle") { runPipeline() }
                    .help("Transcribe + route this capture on the desktop and rewrite its results")
            }
            Button("Reveal", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([capture.folder])
            }
        }
        .padding()
    }

    @ViewBuilder
    private var playButton: some View {
        if let url = capture.audioURL {
            let isPlaying = player.playingURL == url
            Button {
                player.toggle(url)
            } label: {
                Label(isPlaying ? "Stop" : "Play",
                      systemImage: isPlaying ? "stop.fill" : "play.fill")
            }
            .tint(isPlaying ? .red : .accentColor)
        } else {
            Label("No audio", systemImage: "speaker.slash").foregroundStyle(.tertiary)
        }
    }

    private func transcriptPane(_ d: DebugCaptureArchive.CaptureDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transcript").font(.subheadline.weight(.semibold))
            ScrollView {
                Text(d.transcript.isEmpty ? "(no transcript)" : d.transcript)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
    }

    private func rightTabs(_ d: DebugCaptureArchive.CaptureDetail) -> some View {
        TabView {
            summaryTab(d).tabItem { Label("Summary", systemImage: "list.bullet.rectangle") }
            jsonTab(d).tabItem { Label("JSON", systemImage: "curlybraces") }
        }
        .padding(8)
    }

    private func summaryTab(_ d: DebugCaptureArchive.CaptureDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let summary = d.summary, !summary.isEmpty {
                    section("Summary") { Text(summary).textSelection(.enabled) }
                }
                section("Actions (\(d.actions.count))") {
                    if d.actions.isEmpty {
                        Text("No actions").foregroundStyle(.secondary)
                    } else {
                        ForEach(d.actions) { a in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(a.toolID) · \(a.actionType)")
                                    .font(.callout.weight(.medium))
                                if !a.label.isEmpty {
                                    Text(a.label).font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(a.parameters.sorted(by: { $0.key < $1.key }), id: \.key) { k, val in
                                    Text("\(k): \(val)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @State private var jsonFile: JSONFile = .scenario
    private enum JSONFile: String, CaseIterable, Identifiable { case scenario, plan, analysis, metadata; var id: String { rawValue } }

    private func jsonTab(_ d: DebugCaptureArchive.CaptureDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $jsonFile) {
                ForEach(JSONFile.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            ScrollView([.horizontal, .vertical]) {
                Text(json(for: jsonFile, d) ?? "(none)")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func json(for file: JSONFile, _ d: DebugCaptureArchive.CaptureDetail) -> String? {
        switch file {
        case .scenario: return d.scenarioJSON
        case .plan:     return d.planJSON
        case .analysis: return d.analysisJSON
        case .metadata: return d.metadataJSON
        }
    }

    private var gradingBar: some View {
        HStack(spacing: 12) {
            Picker("Outcome", selection: $accuracy) {
                Text("Ungraded").tag(CaptureGrade.Accuracy?.none)
                ForEach(CaptureGrade.Accuracy.allCases, id: \.self) { acc in
                    Text(acc.rawValue.capitalized).tag(CaptureGrade.Accuracy?.some(acc))
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Toggle("Keep", isOn: $keepAsFixture).controlSize(.small)

            TextField("Notes", text: $notes)
                .textFieldStyle(.roundedBorder)

            Button("Save", systemImage: "checkmark") { save() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func load() {
        detail = DebugCaptureArchive.loadDetail(for: capture.folder)
        accuracy = capture.grade?.outcomeAccuracy
        keepAsFixture = capture.grade?.keepAsFixture ?? false
        notes = capture.grade?.notes ?? ""
    }

    private func runPipeline() {
        isRunning = true
        runError = nil
        let folder = capture.folder
        Task {
            let result = await CaptureIngestor.process(folder: folder)
            await MainActor.run {
                detail = DebugCaptureArchive.loadDetail(for: folder)
                capture.grade = DebugCaptureArchive.loadGrade(in: folder)
                accuracy = capture.grade?.outcomeAccuracy
                keepAsFixture = capture.grade?.keepAsFixture ?? false
                notes = capture.grade?.notes ?? ""
                runError = result.error
                isRunning = false
            }
        }
    }

    private func save() {
        var grade = capture.grade ?? CaptureGrade(
            actionCount: detail?.actions.count ?? 0,
            routedVia: detail?.routedVia ?? "none",
            castellumErrored: false,
            durationSeconds: capture.metadata?.durationSeconds ?? 0,
            wordCount: capture.metadata?.wordCount ?? 0,
            appVersion: capture.metadata?.appVersion ?? "unknown"
        )
        grade.outcomeAccuracy = accuracy
        grade.keepAsFixture = keepAsFixture
        grade.notes = notes.isEmpty ? nil : notes
        grade.gradedAt = Date()
        grade.recomputeTestValue()
        DebugCaptureArchive.writeGrade(grade, to: capture.folder)
        capture.grade = grade
    }
}

// MARK: - Audio player

private final class CapturePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingURL: URL?
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playingURL == url { stop(); return }
        player?.stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            playingURL = url
        } catch {
            playingURL = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playingURL = nil
    }
}
#endif
