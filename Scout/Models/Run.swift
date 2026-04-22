import Foundation

enum RunType: String, CaseIterable, Codable, Sendable {
    case morningBriefing
    case weekendBriefing
    case consolidation11am
    case consolidation1pm
    case consolidation5pm
    case consolidation7pm
    case dreamingNightly
    case dreamingWeekend6am
    case dreamingWeekend7am
    case research
    case manual
}

enum RunSource: String, Codable, Sendable {
    case launchdScheduled
    case heartbeat
    case manual
    case retry
}

/// Run outcome classification consumed by the Control Center.
///
/// Exhaustive switches: `RunRow.iconName`. All other consumers
/// (`RunRow.iconColor`, `RunRow.statusColor`, `NotificationService.verb`,
/// `AppState.recomputeMenuStatus`) fall through `default` branches to
/// muted/idle/generic treatment — intentional for statuses that should
/// de-emphasize in the UI (`.orphaned`, `.skippedBudget`,
/// `.skippedConcurrency`). When adding a new case, audit those consumers
/// to decide whether `default` is still correct.
enum RunStatus: String, Codable, Sendable {
    case scheduled
    case running
    case success
    case failure
    case timeout
    case orphaned
    case skippedBudget
    case skippedConcurrency
    case rateLimited
}

struct Run: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let type: RunType
    let runnerScript: String
    let source: RunSource
    let scheduledAt: Date?
    let startedAt: Date
    let endedAt: Date?
    let status: RunStatus
    let exitCode: Int?
    let cost: Decimal?
    let budgetCap: Decimal?
    let logPath: URL
    let logSizeBytes: Int64
    let errorsDetected: [DetectedError]
    let commits: [Commit]
    let retryOf: Run.ID?

    static func makeId(type: RunType, startedAt: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return "\(type.rawValue)-\(iso.string(from: startedAt))"
    }
}

#if DEBUG
extension Run {
    /// Test-only convenience. Fills in plausible defaults; override what you need.
    static func make(
        type: RunType = .morningBriefing,
        source: RunSource = .launchdScheduled,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: RunStatus = .success,
        exitCode: Int? = 0,
        cost: Decimal? = nil,
        logPath: URL = URL(fileURLWithPath: "/tmp/fake.log"),
        commits: [Commit] = [],
        retryOf: Run.ID? = nil
    ) -> Run {
        Run(
            id: makeId(type: type, startedAt: startedAt),
            type: type,
            runnerScript: "run-scout.sh",
            source: source,
            scheduledAt: nil,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
            exitCode: exitCode,
            cost: cost,
            budgetCap: 10,
            logPath: logPath,
            logSizeBytes: 0,
            errorsDetected: [],
            commits: commits,
            retryOf: retryOf
        )
    }
}
#endif
