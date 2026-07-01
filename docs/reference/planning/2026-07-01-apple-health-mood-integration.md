# Apple Health Mood Integration

**Status:** Idea — no implementation yet  
**Context:** User mentioned during 2026-07-01 midday check-in capture

## Concept

Basin check-ins could push the user's current mood/feelings directly to Apple Health as a "mindful session" or custom health metric — creating a daily "How are you feeling?" log that lives alongside other health data.

## User's Vision

- Somatic body check-ins as part of a meditation-style flow
- Basin captures mood/feeling statements → writes to Apple Health
- Apple Health is one potential endpoint; other mental health tracking services could also be explored

## Technical Path

Apple Health supports:
- `HKCategoryTypeIdentifier.mindfulSession` — for time-based mindfulness records
- Custom `HKQuantityType` samples if the app has HealthKit entitlements

The mood capture could:
1. Extract a mood score (1–5 or a label) from the `mood_tag` field already present in `SessionAnalysis`
2. Create an `HKCategorySample` or `HKQuantitySample` for the session duration
3. Write via `HKHealthStore.save(_:withCompletion:)`

Requires HealthKit entitlement: `com.apple.developer.healthkit`.

## Potential Action Type

New tool: `apple-health` with action `log_mood` (or `log_mindful_session`):
```json
{
  "toolID": "apple-health",
  "actionType": "log_mood",
  "parameters": {
    "mood_label": "optimistic",
    "duration_seconds": "180"
  }
}
```

This fits the existing tool architecture — apple-health would be a native system tool (no auth credentials, just HealthKit permission).

## Related

- [[2026-07-01-recurring-tasks-reminders]] — same pattern of native OS integration
- `EventKitActionClient.swift` — reference implementation for native tool executors
