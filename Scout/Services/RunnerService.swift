import Foundation

final class RunnerService: @unchecked Sendable {
    private let scoutDirectory: URL
    private let runner: any ProcessRunner

    init(scoutDirectory: URL, runner: any ProcessRunner) {
        self.scoutDirectory = scoutDirectory
        self.runner = runner
    }

    func retry(run: Run, bypassBudget: Bool) async throws {
        try await invoke(
            script: run.runnerScript,
            type: run.type,
            bypassBudget: bypassBudget,
            retryOf: run.id
        )
    }

    func runNow(type: RunType, bypassBudget: Bool) async throws {
        try await invoke(
            script: script(for: type),
            type: type,
            bypassBudget: bypassBudget,
            retryOf: nil
        )
    }

    private func invoke(
        script: String,
        type: RunType,
        bypassBudget: Bool,
        retryOf: String?
    ) async throws {
        var env: [String: String] = [:]
        if bypassBudget { env["SCOUT_BYPASS_BUDGET"] = "1" }
        if let retryOf { env["SCOUT_RETRY_OF"] = retryOf }
        env["SCOUT_FORCE_MODE"] = modeString(for: type)

        let scriptURL = scoutDirectory.appendingPathComponent(script)
        _ = try await runner.run(
            executable: scriptURL,
            arguments: [],
            environment: env,
            workingDirectory: scoutDirectory
        )
    }

    private func script(for type: RunType) -> String {
        switch type {
        case .dreamingNightly, .dreamingWeekend6am, .dreamingWeekend7am:
            return "run-dreaming.sh"
        case .research:
            return "run-research.sh"
        default:
            return "run-scout.sh"
        }
    }

    private func modeString(for type: RunType) -> String {
        switch type {
        case .morningBriefing: return "morning-briefing"
        case .weekendBriefing: return "weekend-briefing"
        case .consolidation11am: return "consolidation-11am"
        case .consolidation1pm: return "consolidation-1pm"
        case .consolidation5pm: return "consolidation-5pm"
        case .consolidation7pm: return "consolidation-7pm"
        case .dreamingNightly: return "dreaming-nightly"
        case .dreamingWeekend6am: return "dreaming-weekend-6am"
        case .dreamingWeekend7am: return "dreaming-weekend-7am"
        case .research: return "research"
        case .manual: return "manual"
        }
    }
}
