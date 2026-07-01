import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.lyra.basn", category: "tool-builder-feature")

@Reducer
struct AIToolBuilderFeature {

    @ObservableState
    struct State: Equatable {
        let apiKey: String
        var step: Step = .describe
        var description: String = ""
        var isGenerating = false
        var isSubmitting = false
        var generatedSpecRaw: String = ""
        var testResults: [String: Bool] = [:]
        var testMessages: [String: String] = [:]
        var testingIDs: Set<String> = []
        var submissionURL: String? = nil
        var errorMessage: String? = nil

        enum Step: Equatable, CaseIterable {
            case describe, generating, review, done
        }

        /// Parsed spec derived from the raw JSON. Nil if not yet generated or invalid.
        var generatedSpec: ToolDefinitionSpec? {
            guard !generatedSpecRaw.isEmpty,
                  let data = generatedSpecRaw.data(using: .utf8)
            else { return nil }
            return try? JSONDecoder().decode(ToolDefinitionSpec.self, from: data)
        }

        var anyTestsPassed: Bool { testResults.values.contains(true) }
        var allTestsPassed: Bool {
            guard let spec = generatedSpec, !spec.actions.isEmpty else { return false }
            return spec.actions.keys.allSatisfy { testResults[$0] == true }
        }
        var canSubmit: Bool { generatedSpec != nil && !isSubmitting }
    }

    enum Action {
        case descriptionChanged(String)
        case generateTapped
        case generationResponse(Result<String, Error>)
        case testActionTapped(String)
        case testCompleted(String, Bool, String)
        case submitTapped
        case submitResponse(Result<String, Error>)
        case retryDescription
        case dismissTapped
    }

    @Dependency(\.toolBuilderClient) var toolBuilderClient
    @Dependency(\.marketplaceSubmissionClient) var submissionClient
    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .descriptionChanged(let text):
                state.description = text
                return .none

            case .generateTapped:
                guard !state.description.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return .none
                }
                state.isGenerating = true
                state.step = .generating
                state.errorMessage = nil
                state.generatedSpecRaw = ""
                state.testResults = [:]
                state.testMessages = [:]
                let apiKey = state.apiKey
                let description = state.description
                return .run { send in
                    do {
                        let raw = try await toolBuilderClient.generate(description, apiKey)
                        await send(.generationResponse(.success(raw)))
                    } catch {
                        await send(.generationResponse(.failure(error)))
                    }
                }

            case .generationResponse(.success(let raw)):
                state.isGenerating = false
                guard let data = raw.data(using: .utf8),
                      (try? JSONDecoder().decode(ToolDefinitionSpec.self, from: data)) != nil
                else {
                    state.errorMessage = "The generated definition wasn't valid. Try describing the service more specifically, including what actions you want (e.g. 'create a task', 'log time')."
                    state.step = .describe
                    return .none
                }
                state.generatedSpecRaw = raw
                state.step = .review
                return .none

            case .generationResponse(.failure(let error)):
                state.isGenerating = false
                state.errorMessage = error.localizedDescription
                state.step = .describe
                return .none

            case .testActionTapped(let actionID):
                guard !state.testingIDs.contains(actionID) else { return .none }
                state.testingIDs.insert(actionID)
                let raw = state.generatedSpecRaw
                return .run { send in
                    guard let data = raw.data(using: .utf8),
                          let spec = try? JSONDecoder().decode(ToolDefinitionSpec.self, from: data),
                          let action = spec.actions[actionID]
                    else {
                        await send(.testCompleted(actionID, false, "Could not parse action"))
                        return
                    }
                    let result = ToolActionTestRunner.validate(
                        actionID: actionID,
                        action: action,
                        spec: spec
                    )
                    await send(.testCompleted(actionID, result.passed, result.message))
                }

            case .testCompleted(let actionID, let passed, let message):
                state.testingIDs.remove(actionID)
                state.testResults[actionID] = passed
                state.testMessages[actionID] = message
                return .none

            case .submitTapped:
                guard !state.generatedSpecRaw.isEmpty else { return .none }
                state.isSubmitting = true
                state.errorMessage = nil
                let raw = state.generatedSpecRaw
                let results = Array(state.testResults.map { id, passed in
                    ToolSubmissionRequest.ActionTestResult(
                        actionId: id,
                        statusCode: passed ? 200 : 422,
                        passed: passed,
                        errorSummary: state.testMessages[id]
                    )
                })
                return .run { send in
                    do {
                        guard let jsonData = raw.data(using: .utf8),
                              let jsonObj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                        else {
                            await send(.submitResponse(.failure(SubmitError.invalidJSON)))
                            return
                        }
                        let prURL = try await submissionClient.submit(jsonObj, results)
                        await send(.submitResponse(.success(prURL)))
                    } catch {
                        await send(.submitResponse(.failure(error)))
                    }
                }

            case .submitResponse(.success(let prURL)):
                state.isSubmitting = false
                state.submissionURL = prURL
                state.step = .done
                log.info("Tool submitted: \(prURL)")
                return .none

            case .submitResponse(.failure(let error)):
                state.isSubmitting = false
                state.errorMessage = error.localizedDescription
                return .none

            case .retryDescription:
                state.step = .describe
                state.errorMessage = nil
                state.generatedSpecRaw = ""
                state.testResults = [:]
                state.testMessages = [:]
                return .none

            case .dismissTapped:
                return .run { _ in await dismiss() }
            }
        }
    }

    private enum SubmitError: LocalizedError {
        case invalidJSON
        var errorDescription: String? { "Could not serialize the tool definition." }
    }
}
