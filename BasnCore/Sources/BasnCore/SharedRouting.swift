// The routing + plan types now live in BasinShared (shared by macOS, iOS, and
// future CarPlay/watch targets — single source of truth). These scoped
// re-exports let existing `import BasnCore` call sites keep working unchanged on
// macOS without importing BasinShared everywhere. New cross-platform code should
// `import BasinShared` directly.
//
// We re-export only these specific symbols (not the whole module) to avoid
// clashing with app-target types of the same name (e.g. FlowPrompt, PromptChoice).

@_exported import struct BasinShared.Session
@_exported import struct BasinShared.SessionContext
@_exported import struct BasinShared.HeuristicRouter
@_exported import struct BasinShared.CastellumResponseParser
@_exported import struct BasinShared.SessionComplexityClassifier
@_exported import enum BasinShared.SessionComplexity
@_exported import struct BasinShared.ExecutionPlan
@_exported import struct BasinShared.PlannedAction
@_exported import enum BasinShared.ActionStatus
@_exported import struct BasinShared.ActionResult
@_exported import struct BasinShared.StructuredCapture
@_exported import struct BasinShared.CaptureEntry
@_exported import struct BasinShared.SessionAnalysis
