import Foundation

/// A scheduled fire that hasn't happened yet. Distinct from `Run` because it
/// has no log file, cost, commits, etc. — only a scheduled time and type.
struct UpcomingRun: Identifiable, Equatable, Hashable, Sendable {
    let id: String          // "{type.rawValue}-{scheduledAt ISO8601}"
    let type: RunType
    let scheduledAt: Date
    let plistLabel: String  // e.g. "com.scout.briefing"
}
