//
//  ModelContextClient.swift
//  Basin
//
//  TCA dependency wrapping SwiftData operations.
//  All SwiftData reads and writes go through this client.
//

import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import BasnCore
import SwiftData

private let dbLogger = BasnLog.app

@DependencyClient
struct ModelContextClient {
    // Captures
    var saveCapture: @Sendable (CaptureRecord) async throws -> Void
    var saveAnalysis: @Sendable (CaptureAnalysis, CaptureRecord) async throws -> Void
    var fetchCaptures: @Sendable (_ limit: Int?) async throws -> [CaptureRecord]
    var deleteCapture: @Sendable (_ id: String) async throws -> Void

    // Flows
    var fetchFlows: @Sendable () async throws -> [FlowDefinition]
    var saveFlow: @Sendable (FlowDefinition) async throws -> Void
    var deleteFlow: @Sendable (_ id: String) async throws -> Void

    // Tools
    var fetchTools: @Sendable () async throws -> [Tool]
    var updateTool: @Sendable (Tool) async throws -> Void

    // Workflows (formerly Channels)
    var fetchWorkflows: @Sendable () async throws -> [Workflow]
    var saveWorkflow: @Sendable (Workflow) async throws -> Void
    var deleteWorkflow: @Sendable (_ id: String) async throws -> Void
}

extension ModelContextClient: DependencyKey {
    @MainActor
    static var liveValue: Self {
        let context = ModelContext(BasnApp.modelContainer)

        return .init(
            saveCapture: { capture in
                await MainActor.run {
                    context.insert(capture)
                    try? context.save()
                    dbLogger.info("Saved capture \(capture.id)")
                }
            },
            saveAnalysis: { analysis, capture in
                await MainActor.run {
                    analysis.capture = capture
                    capture.analysis = analysis
                    context.insert(analysis)
                    try? context.save()
                    dbLogger.info("Saved analysis for capture \(capture.id)")
                }
            },
            fetchCaptures: { limit in
                try await MainActor.run {
                    var descriptor = FetchDescriptor<CaptureRecord>(
                        sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                    )
                    if let limit { descriptor.fetchLimit = limit }
                    return try context.fetch(descriptor)
                }
            },
            deleteCapture: { id in
                try await MainActor.run {
                    var descriptor = FetchDescriptor<CaptureRecord>(
                        predicate: #Predicate { $0.id == id }
                    )
                    descriptor.fetchLimit = 1
                    if let capture = try context.fetch(descriptor).first {
                        // Delete audio file if it exists
                        if let audioPath = capture.audioPath {
                            try? FileManager.default.removeItem(atPath: audioPath)
                        }
                        context.delete(capture)
                        try context.save()
                        dbLogger.info("Deleted capture \(id)")
                    }
                }
            },
            fetchFlows: {
                try await MainActor.run {
                    let descriptor = FetchDescriptor<FlowDefinition>(
                        predicate: #Predicate { !$0.isTemplate },
                        sortBy: [SortDescriptor(\.sortOrder)]
                    )
                    return try context.fetch(descriptor)
                }
            },
            saveFlow: { flow in
                await MainActor.run {
                    context.insert(flow)
                    try? context.save()
                    dbLogger.info("Saved flow \(flow.id)")
                }
            },
            deleteFlow: { id in
                try await MainActor.run {
                    var descriptor = FetchDescriptor<FlowDefinition>(
                        predicate: #Predicate { $0.id == id }
                    )
                    descriptor.fetchLimit = 1
                    if let flow = try context.fetch(descriptor).first {
                        context.delete(flow)
                        try context.save()
                        dbLogger.info("Deleted flow \(id)")
                    }
                }
            },
            fetchTools: {
                try await MainActor.run {
                    let descriptor = FetchDescriptor<Tool>(
                        sortBy: [SortDescriptor(\.name)]
                    )
                    return try context.fetch(descriptor)
                }
            },
            updateTool: { _ in
                await MainActor.run {
                    try? context.save()
                    dbLogger.info("Updated tool")
                }
            },
            fetchWorkflows: {
                try await MainActor.run {
                    let descriptor = FetchDescriptor<Workflow>(
                        sortBy: [SortDescriptor(\.sortOrder)]
                    )
                    return try context.fetch(descriptor)
                }
            },
            saveWorkflow: { workflow in
                await MainActor.run {
                    context.insert(workflow)
                    try? context.save()
                    dbLogger.info("Saved workflow \(workflow.id)")
                }
            },
            deleteWorkflow: { id in
                try await MainActor.run {
                    var descriptor = FetchDescriptor<Workflow>(
                        predicate: #Predicate { $0.id == id }
                    )
                    descriptor.fetchLimit = 1
                    if let workflow = try context.fetch(descriptor).first {
                        context.delete(workflow)
                        try context.save()
                        dbLogger.info("Deleted workflow \(id)")
                    }
                }
            }
        )
    }
}

extension DependencyValues {
    var modelContext: ModelContextClient {
        get { self[ModelContextClient.self] }
        set { self[ModelContextClient.self] = newValue }
    }
}
