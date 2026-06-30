import Foundation

/// A recorded capture scenario used as a fixture for pipeline tests.
///
/// Each scenario stores the inputs to the routing pipeline, an optional raw
/// Anthropic API response (for parse-layer tests), and the expected outputs.
/// Serialized to JSON — one file per scenario in `Fixtures/Scenarios/`.
public struct CaptureScenario: Codable {

    // MARK: - Metadata

    public let name: String
    public let description: String

    // MARK: - Pipeline inputs

    /// Human-readable transcript text. Passed to `HeuristicRouter.route` for
    /// heuristic-path scenarios; used as a reference label for castellum scenarios.
    public let rawText: String
    public let connectedToolIDs: [String]

    // MARK: - Routing path

    /// Which routing path this scenario takes.
    public let routedVia: RoutingPath

    public enum RoutingPath: String, Codable, Sendable {
        case heuristic  // HeuristicRouter matched → no API call
        case castellum  // Full Castellum (Claude) API call
    }

    // MARK: - Raw Castellum response

    /// The `content` array from the raw Anthropic API response body.
    /// `nil` for heuristic-path scenarios (no API call was made).
    public let rawContentBlocks: [RawBlock]?

    // MARK: - Expected outputs

    public let expected: Expected

    // MARK: - Audio corpus fields (optional)
    //
    // Present when this scenario was promoted into the end-to-end audio test
    // corpus. All optional so existing JSON fixtures decode unchanged.

    /// Audio file name relative to the scenario folder, e.g. "audio.wav".
    public let audioFile: String?
    /// Reference transcript used for WER scoring against live transcription.
    public let expectedTranscript: String?
    /// Maximum acceptable word-error-rate. Callers default to 0.15 when nil.
    public let werThreshold: Double?
    /// Speaker / environment metadata, used to track diversity-matrix coverage.
    public let speaker: SpeakerProfile?

    // MARK: - Nested types

    /// Speaker and recording-environment metadata for an audio corpus entry.
    public struct SpeakerProfile: Codable, Sendable {
        public let accent: String?
        public let nativeEnglish: Bool?
        public let environment: String?  // "quiet", "café", "street", …
        public let mic: String?          // "built-in", "AirPods", "external", …

        public init(
            accent: String? = nil,
            nativeEnglish: Bool? = nil,
            environment: String? = nil,
            mic: String? = nil
        ) {
            self.accent = accent
            self.nativeEnglish = nativeEnglish
            self.environment = environment
            self.mic = mic
        }
    }

    /// A single content block from the Anthropic response, stored in a
    /// Codable-friendly form so it can survive JSON serialization.
    public struct RawBlock: Codable {
        public let type: String
        /// Present when `type == "text"`.
        public let text: String?
        /// Present when `type == "tool_use"`.
        public let name: String?
        /// Present when `type == "tool_use"`. Values use `RawValue` to
        /// handle the heterogeneous types Claude returns (strings, numbers, arrays).
        public let input: [String: RawValue]?

        public init(type: String, text: String? = nil, name: String? = nil, input: [String: RawValue]? = nil) {
            self.type = type
            self.text = text
            self.name = name
            self.input = input
        }
    }

    public struct Expected: Codable {
        /// Expected actions — partial match (only listed parameter keys are asserted).
        public let actions: [ExpectedAction]

        public init(actions: [ExpectedAction]) {
            self.actions = actions
        }
    }

    public struct ExpectedAction: Codable {
        public let toolID: String
        public let actionType: String
        /// Partial parameter expectations — only keys listed here are checked.
        public let parameters: [String: String]

        public init(toolID: String, actionType: String, parameters: [String: String] = [:]) {
            self.toolID = toolID
            self.actionType = actionType
            self.parameters = parameters
        }
    }

    // MARK: - Memberwise init

    public init(
        name: String,
        description: String,
        rawText: String,
        connectedToolIDs: [String],
        routedVia: RoutingPath,
        rawContentBlocks: [RawBlock]?,
        expected: Expected,
        audioFile: String? = nil,
        expectedTranscript: String? = nil,
        werThreshold: Double? = nil,
        speaker: SpeakerProfile? = nil
    ) {
        self.name = name
        self.description = description
        self.rawText = rawText
        self.connectedToolIDs = connectedToolIDs
        self.routedVia = routedVia
        self.rawContentBlocks = rawContentBlocks
        self.expected = expected
        self.audioFile = audioFile
        self.expectedTranscript = expectedTranscript
        self.werThreshold = werThreshold
        self.speaker = speaker
    }
}

// MARK: - RawValue

/// A minimal Codable union type for heterogeneous JSON values in tool_use inputs.
/// Handles the types Claude actually returns: Bool, Int, Double, String,
/// arrays of RawValue, and string-keyed dictionaries of RawValue.
public enum RawValue: Codable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([RawValue])
    case object([String: RawValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self)             { self = .bool(v);   return }
        if let v = try? c.decode(Int.self)              { self = .int(v);    return }
        if let v = try? c.decode(Double.self)           { self = .double(v); return }
        if let v = try? c.decode(String.self)           { self = .string(v); return }
        if let v = try? c.decode([RawValue].self)       { self = .array(v);  return }
        if let v = try? c.decode([String: RawValue].self){ self = .object(v); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let v):   try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null:          try c.encodeNil()
        }
    }

    /// Convert to the `Any` type used by `CastellumResponseParser.parse`.
    public var anyValue: Any {
        switch self {
        case .bool(let v):   return v
        case .int(let v):    return NSNumber(value: v)
        case .double(let v): return NSNumber(value: v)
        case .string(let v): return v
        case .array(let v):  return v.map { $0.anyValue }
        case .object(let v): return v.mapValues { $0.anyValue }
        case .null:          return NSNull()
        }
    }
}

// MARK: - Convenience conversion

extension CaptureScenario {
    /// Convert `rawContentBlocks` to the `[[String: Any]]` format expected by
    /// `CastellumResponseParser.parse`.
    public func toContentBlocks() -> [[String: Any]] {
        guard let blocks = rawContentBlocks else { return [] }
        return blocks.map { block in
            var dict: [String: Any] = ["type": block.type]
            if let text = block.text   { dict["text"] = text }
            if let name = block.name   { dict["name"] = name }
            if let input = block.input { dict["input"] = input.mapValues { $0.anyValue } }
            return dict
        }
    }
}
