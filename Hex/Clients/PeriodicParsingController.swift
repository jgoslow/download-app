//
//  PeriodicParsingController.swift
//  Basin
//
//  Periodically transcribes audio during recording to provide live feedback
//  on which prompts are being addressed. Works by taking snapshots of the
//  growing audio file and running partial transcription + lightweight analysis.
//

import AVFoundation
import Foundation
import HexCore

private let parseLogger = HexLog.app

/// Callback with partial transcript text and prompt indices addressed so far.
typealias PeriodicParseUpdate = (partialText: String, promptsAddressed: [Int])

actor PeriodicParsingController {

    static let shared = PeriodicParsingController()

    // Configuration
    private let intervalSeconds: TimeInterval = 5.0
    private let minimumAudioSeconds: TimeInterval = 2.0

    // State
    private var isActive = false
    private var parseTask: Task<Void, Never>?
    private var lastTranscriptLength = 0

    /// Start periodic parsing for an active recording.
    /// - Parameters:
    ///   - audioURL: The URL of the growing audio file being recorded
    ///   - promptTitles: The guided prompt titles for the current flow
    ///   - apiKey: Anthropic API key for lightweight analysis
    ///   - transcribe: Function to transcribe an audio file → text
    ///   - onUpdate: Called on each parse cycle with updated prompt coverage
    func start(
        audioURL: URL,
        promptTitles: [String],
        apiKey: String,
        transcribe: @escaping @Sendable (URL) async throws -> String,
        onUpdate: @escaping @Sendable (PeriodicParseUpdate) -> Void
    ) {
        guard !promptTitles.isEmpty else {
            parseLogger.info("Periodic parsing skipped — no prompts for this flow")
            return
        }

        guard !apiKey.isEmpty else {
            parseLogger.info("Periodic parsing skipped — no API key")
            return
        }

        stop()
        isActive = true
        lastTranscriptLength = 0

        let interval = intervalSeconds
        let minAudio = minimumAudioSeconds
        parseTask = Task { [weak self] in
            // Wait for initial audio to accumulate
            try? await Task.sleep(for: .seconds(interval))

            while !Task.isCancelled {
                guard let self, await self.isActive else { break }

                do {
                    // Check if audio file has enough content
                    let attrs = try FileManager.default.attributesOfItem(atPath: audioURL.path)
                    let fileSize = attrs[.size] as? UInt64 ?? 0
                    // Rough check: 16kHz * 4 bytes * minimumAudioSeconds
                    let minimumSize = UInt64(16_000 * 4 * minAudio)

                    if fileSize >= minimumSize {
                        // Copy the audio file to a temp location for transcription
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("basin-periodic-\(UUID().uuidString).wav")

                        try FileManager.default.copyItem(at: audioURL, to: tempURL)

                        defer { try? FileManager.default.removeItem(at: tempURL) }

                        // Transcribe the snapshot
                        let partialText = try await transcribe(tempURL)

                        // Only analyze if we got new text
                        let lastLength = await self.lastTranscriptLength
                        if partialText.count > lastLength + 10 {
                            await self.setLastTranscriptLength(partialText.count)

                            // Lightweight prompt analysis
                            let addressed = await self.analyzePromptCoverage(
                                text: partialText,
                                promptTitles: promptTitles,
                                apiKey: apiKey
                            )

                            onUpdate((partialText: partialText, promptsAddressed: addressed))
                            parseLogger.info("Periodic parse: \(partialText.count) chars, \(addressed.count) prompts addressed")
                        }
                    }
                } catch {
                    parseLogger.error("Periodic parse error: \(error.localizedDescription)")
                }

                try? await Task.sleep(for: .seconds(interval))
            }
        }

        parseLogger.info("Periodic parsing started (interval: \(interval)s)")
    }

    func stop() {
        isActive = false
        parseTask?.cancel()
        parseTask = nil
        lastTranscriptLength = 0
    }

    private func setLastTranscriptLength(_ length: Int) {
        lastTranscriptLength = length
    }

    // MARK: - Lightweight Prompt Analysis

    /// Quick Claude call that just checks which prompts have been addressed.
    /// Much cheaper than a full SessionAnalysis — returns only prompt indices.
    private func analyzePromptCoverage(
        text: String,
        promptTitles: [String],
        apiKey: String
    ) async -> [Int] {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return [] }

        let promptList = promptTitles.enumerated().map { "\($0.offset). \($0.element)" }.joined(separator: "\n")

        let prompt = """
        Given this partial voice transcript, which of these guided prompts has the speaker addressed so far?

        Prompts:
        \(promptList)

        Partial transcript:
        \(text.prefix(2000))

        Return ONLY a JSON array of prompt indices (0-based) that were addressed. Example: [0, 2]
        If none were addressed, return: []
        """

        let requestBody: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 64,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            let body = try JSONSerialization.data(withJSONObject: requestBody)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = body
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String else {
                return []
            }

            // Parse the JSON array
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let indices = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [Int] {
                return indices
            }

            return []
        } catch {
            return []
        }
    }
}
