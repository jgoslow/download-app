import Foundation
import Testing
import BasnCore

// MARK: - Fixture loading

extension CaptureScenario {
    /// Load a named scenario from `Fixtures/Scenarios/<name>.json` in the test bundle.
    static func load(named name: String) throws -> CaptureScenario {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/Scenarios"
        ) else {
            throw FixtureError.notFound(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CaptureScenario.self, from: data)
    }
}

enum FixtureError: Error {
    case notFound(String)
}

// MARK: - Assertion helper

/// Assert that `actual` actions match the `expected` partial specs.
/// Only parameter keys listed in `expected` are checked — other params are ignored.
func assertActions(
    _ actual: [PlannedAction],
    match expected: [CaptureScenario.ExpectedAction],
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    if actual.count != expected.count {
        Issue.record(
            "Expected \(expected.count) action(s), got \(actual.count)",
            sourceLocation: sourceLocation
        )
        return
    }
    for (i, (act, exp)) in zip(actual, expected).enumerated() {
        if act.toolID != exp.toolID {
            Issue.record("Action[\(i)] toolID: expected '\(exp.toolID)', got '\(act.toolID)'", sourceLocation: sourceLocation)
        }
        if act.actionType != exp.actionType {
            Issue.record("Action[\(i)] actionType: expected '\(exp.actionType)', got '\(act.actionType)'", sourceLocation: sourceLocation)
        }
        for (key, expectedValue) in exp.parameters {
            guard let actualValue = act.parameters[key] else {
                Issue.record("Action[\(i)] parameters['\(key)']: expected '\(expectedValue)', key missing", sourceLocation: sourceLocation)
                continue
            }
            if actualValue != expectedValue {
                Issue.record("Action[\(i)] parameters['\(key)']: expected '\(expectedValue)', got '\(actualValue)'", sourceLocation: sourceLocation)
            }
        }
    }
}
