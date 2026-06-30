//
//  CaptureIngestor.swift
//  Basn — #if DEBUG only (macOS)
//
//  Desktop assessment of captures recorded elsewhere (e.g. pulled off an iPhone
//  via the Files app). Given an audio file — or a phone capture folder that
//  contains audio.wav + metadata.json — this runs the REAL desktop pipeline:
//  transcribe → route (heuristic, then Castellum if an API key is set) → and
//  writes a full archive folder (audio + scenario + metadata + plan + auto-grade)
//  that shows up in the DebugBar Review sheet for grading and promotion.
//
//  Nothing here runs on the phone; the phone only records (see IOSCaptureArchive).
//

import Foundation
import ComposableArchitecture
import BasnCore

#if DEBUG
enum CaptureIngestor {

    struct Result: Identifiable {
        let id = UUID()
        let source: URL
        var folder: URL?
        var transcript: String?
        var routedVia: String?
        var actionCount: Int = 0
        var error: String?
    }

    /// Expand a user selection into individual ingestible items. Handles:
    ///  - a `.wav` file → itself
    ///  - a capture folder containing `audio.wav` → itself
    ///  - a parent folder of capture subfolders (e.g. a pulled `2026-06-29/`) →
    ///    every subfolder that contains `audio.wav`, plus any loose `.wav` files
    /// So selecting the date folder imports all captures inside it.
    static func expand(_ url: URL) -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            return url.pathExtension.lowercased() == "wav" ? [url] : []
        }
        if fm.fileExists(atPath: url.appendingPathComponent("audio.wav").path) {
            return [url]  // a single capture folder
        }
        // Parent folder: collect child capture folders + loose wavs.
        let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var items: [URL] = []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var childIsDir: ObjCBool = false
            fm.fileExists(atPath: child.path, isDirectory: &childIsDir)
            if childIsDir.boolValue {
                if fm.fileExists(atPath: child.appendingPathComponent("audio.wav").path) { items.append(child) }
            } else if child.pathExtension.lowercased() == "wav" {
                items.append(child)
            }
        }
        return items
    }

    /// Ingest one audio file (or a folder containing audio.wav) into a NEW archive
    /// folder. Never throws so a batch import keeps going.
    static func ingest(_ inputURL: URL) async -> Result {
        var result = Result(source: inputURL)
        let (audioURL, pulledMeta) = resolveAudio(inputURL)
        guard let audioURL else {
            result.error = "No audio.wav found"
            return result
        }
        let captureID = pulledMeta?.captureID ?? UUID().uuidString
        let timestamp = pulledMeta?.timestamp ?? Date()
        guard let folder = DebugCaptureArchive.ingestFolderURL(captureID: captureID, timestamp: timestamp) else {
            result.error = "Could not create archive folder"
            return result
        }
        DebugCaptureArchive.copyAudio(from: audioURL, to: folder)
        return await run(audioURL: folder.appendingPathComponent("audio.wav"),
                         into: folder, pulledMeta: pulledMeta,
                         captureID: captureID, timestamp: timestamp,
                         sourceLabel: inputURL.lastPathComponent, result: result)
    }

    /// Re-run the pipeline on an EXISTING capture folder in place — transcribe its
    /// audio.wav and (re)write scenario/plan/analysis/metadata/grade. Used by the
    /// Review screen's "Run pipeline" button on raw phone captures.
    static func process(folder: URL) async -> Result {
        var result = Result(source: folder)
        let audioURL = folder.appendingPathComponent("audio.wav")
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            result.error = "No audio.wav in folder"
            return result
        }
        let pulledMeta: CaptureArchiveMetadata? = {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("metadata.json")) else { return nil }
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return try? dec.decode(CaptureArchiveMetadata.self, from: data)
        }()
        let captureID = pulledMeta?.captureID ?? UUID().uuidString
        let timestamp = pulledMeta?.timestamp ?? Date()
        return await run(audioURL: audioURL, into: folder, pulledMeta: pulledMeta,
                         captureID: captureID, timestamp: timestamp,
                         sourceLabel: folder.lastPathComponent, result: result)
    }

    /// Shared core: transcribe → route → write artifacts into `folder`.
    private static func run(
        audioURL: URL, into folder: URL, pulledMeta: CaptureArchiveMetadata?,
        captureID: String, timestamp: Date, sourceLabel: String, result: Result
    ) async -> Result {
        var result = result
        result.folder = folder

        @Shared(.basnSettings) var basnSettings: BasnSettings
        let settings = basnSettings.basinSettings
        let model = basnSettings.selectedModel

        guard await AudioTestPipeline.isModelDownloaded(model) else {
            result.error = "Model '\(model)' not downloaded — download it in Settings first."
            return result
        }

        // 1. Transcribe on the desktop model.
        let transcript: String
        do {
            transcript = try await AudioTestPipeline.transcribe(
                audioURL: audioURL, model: model, language: basnSettings.outputLanguage
            )
        } catch {
            result.error = "Transcription failed: \(error.localizedDescription)"
            return result
        }
        guard !transcript.isEmpty else {
            result.error = "Empty transcript"
            return result
        }
        result.transcript = transcript

        let flowID = pulledMeta?.flowID ?? "open"
        let duration = pulledMeta?.durationSeconds ?? 0
        let wordCount = transcript.split(whereSeparator: \.isWhitespace).count

        // 2. Route — heuristic first, Castellum fallback if a key is configured.
        let tools = (try? await ModelContextClient.liveValue.fetchTools()) ?? []
        let connectedTools = tools.filter(\.isConnected)
        let connectedToolIDs = Set(connectedTools.map(\.id))

        var routedVia = "none"
        var castellumErrored = false
        var plan = ExecutionPlan(captureID: captureID, actions: [], modelUsed: nil)

        if let heuristic = HeuristicRouter.route(transcript: transcript, connectedToolIDs: connectedToolIDs) {
            routedVia = "heuristic"
            plan = ExecutionPlan(captureID: captureID, actions: heuristic, modelUsed: "heuristic")
        } else if !settings.anthropicAPIKey.isEmpty {
            routedVia = "castellum"
            let workflows = ((try? await ModelContextClient.liveValue.fetchWorkflows()) ?? []).filter(\.isEnabled)
            let capture = StructuredCapture(
                captureID: captureID, flowID: flowID, timestamp: timestamp,
                durationSeconds: duration, entries: [CaptureEntry(sentence: transcript)]
            )
            do {
                let (analysis, castellumPlan) = try await CastellumClient.liveValue.analyzeAndPlan(
                    capture, [], [], tools, workflows, settings.anthropicAPIKey
                )
                plan = castellumPlan
                DebugCaptureArchive.writeArtifact(analysis, named: "analysis.json", to: folder)
            } catch {
                castellumErrored = true
                result.error = "Castellum failed: \(error.localizedDescription)"
            }
        }
        result.routedVia = routedVia
        result.actionCount = plan.actions.count

        // 3. Write scenario.json (corpus-ready) + plan.json + metadata.json.
        let scenario = CaptureScenario(
            name: "Ingested \(captureID.prefix(8))",
            description: "Assessed from \(sourceLabel) on the desktop pipeline.",
            rawText: transcript,
            connectedToolIDs: Array(connectedToolIDs).sorted(),
            routedVia: routedVia == "castellum" ? .castellum : .heuristic,
            rawContentBlocks: nil,
            expected: .init(actions: plan.actions.map {
                .init(toolID: $0.toolID, actionType: $0.actionType, parameters: $0.parameters)
            }),
            audioFile: "audio.wav",
            expectedTranscript: transcript
        )
        DebugCaptureArchive.writeArtifact(scenario, named: "scenario.json", to: folder)
        DebugCaptureArchive.writeArtifact(plan, named: "plan.json", to: folder)

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let metadata = CaptureArchiveMetadata(
            captureID: captureID, timestamp: timestamp,
            device: pulledMeta?.device ?? Host.current().localizedName ?? "mac",
            flowID: flowID, durationSeconds: duration, wordCount: wordCount,
            whisperModel: model, language: basnSettings.outputLanguage,
            sourceAppBundleID: nil, sourceAppName: nil, appVersion: appVersion,
            connectedToolIDs: Array(connectedToolIDs).sorted(),
            platform: pulledMeta?.platform ?? "ingested",
            onDeviceTranscript: pulledMeta?.onDeviceTranscript
        )
        DebugCaptureArchive.writeArtifact(metadata, named: "metadata.json", to: folder)

        // 4. Auto-grade (preserve any prior human feedback if a grade exists).
        let audioMetrics = DebugCaptureAudio.metrics(forFileAt: audioURL)
        var grade = CaptureGrade(
            actionCount: plan.actions.count, routedVia: routedVia,
            castellumErrored: castellumErrored, durationSeconds: duration,
            wordCount: wordCount, appVersion: appVersion, audio: audioMetrics
        )
        if let prior = DebugCaptureArchive.loadGrade(captureID: captureID, timestamp: timestamp) {
            grade.outcomeAccuracy = prior.outcomeAccuracy
            grade.keepAsFixture = prior.keepAsFixture
            grade.notes = prior.notes
            grade.recomputeTestValue()
        }
        DebugCaptureArchive.writeArtifact(grade, named: "grade.json", to: folder)

        return result
    }

    /// If given a folder, find audio.wav + metadata.json inside it. If given a
    /// .wav directly, use it (and look for a sibling metadata.json).
    private static func resolveAudio(_ url: URL) -> (audio: URL?, meta: CaptureArchiveMetadata?) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        let audio: URL?
        let metaURL: URL
        if isDir.boolValue {
            audio = fm.fileExists(atPath: url.appendingPathComponent("audio.wav").path)
                ? url.appendingPathComponent("audio.wav") : nil
            metaURL = url.appendingPathComponent("metadata.json")
        } else {
            audio = url.pathExtension.lowercased() == "wav" ? url : nil
            metaURL = url.deletingLastPathComponent().appendingPathComponent("metadata.json")
        }

        var meta: CaptureArchiveMetadata?
        if let data = try? Data(contentsOf: metaURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            meta = try? decoder.decode(CaptureArchiveMetadata.self, from: data)
        }
        return (audio, meta)
    }
}
#endif
