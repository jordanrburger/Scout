import Testing
import Foundation
@testable import Scout

actor CapturingProcessRunner: ProcessRunner {
    struct Call: Sendable {
        let executable: URL
        let arguments: [String]
        let env: [String: String]
    }
    private(set) var calls: [Call] = []
    var nextResult = ProcessResult(exitCode: 0, stdout: Data(), stderr: Data())

    nonisolated func run(
        executable: URL, arguments: [String],
        environment: [String: String], workingDirectory: URL?
    ) async throws -> ProcessResult {
        await record(executable: executable, arguments: arguments, env: environment)
        return await nextResult
    }

    func record(executable: URL, arguments: [String], env: [String: String]) {
        calls.append(.init(executable: executable, arguments: arguments, env: env))
    }
}

@Suite("RunnerService")
struct RunnerServiceTests {
    @Test func retrySetsBypassBudgetAndRetryOfEnv() async throws {
        let mock = CapturingProcessRunner()
        let service = RunnerService(
            scoutDirectory: URL(fileURLWithPath: "/Users/x/Scout"),
            runner: mock
        )
        let original = Run.make(type: .morningBriefing)
        try await service.retry(run: original, bypassBudget: true)
        let calls = await mock.calls
        #expect(calls.count == 1)
        #expect(calls[0].env["SCOUT_BYPASS_BUDGET"] == "1")
        #expect(calls[0].env["SCOUT_RETRY_OF"] == original.id)
        #expect(calls[0].executable.path.hasSuffix("run-scout.sh"))
    }

    @Test func runNowOmitsRetryOfAndBudgetBypassByDefault() async throws {
        let mock = CapturingProcessRunner()
        let service = RunnerService(
            scoutDirectory: URL(fileURLWithPath: "/Users/x/Scout"),
            runner: mock
        )
        try await service.runNow(type: .consolidation11am, bypassBudget: false)
        let calls = await mock.calls
        #expect(calls.count == 1)
        #expect(calls[0].env["SCOUT_BYPASS_BUDGET"] == nil)
        #expect(calls[0].env["SCOUT_RETRY_OF"] == nil)
        #expect(calls[0].env["SCOUT_FORCE_MODE"] == "consolidation-11am")
        #expect(calls[0].executable.path.hasSuffix("run-scout.sh"))
    }

    @Test func dreamingRoutesToDreamingScript() async throws {
        let mock = CapturingProcessRunner()
        let service = RunnerService(
            scoutDirectory: URL(fileURLWithPath: "/Users/x/Scout"),
            runner: mock
        )
        try await service.runNow(type: .dreamingNightly, bypassBudget: false)
        let calls = await mock.calls
        #expect(calls[0].executable.path.hasSuffix("run-dreaming.sh"))
    }
}
