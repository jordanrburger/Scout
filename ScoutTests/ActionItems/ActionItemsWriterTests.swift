import Testing
import Foundation
@testable import Scout

@Suite("ActionItemsWriter")
struct ActionItemsWriterTests {
    @Test func buildsAddCommentCommandLine() async throws {
        let recorder = RecordingRunner()
        let writer = ActionItemsWriter(
            python3: URL(fileURLWithPath: "/usr/bin/env"),
            actionItemsDirectory: URL(fileURLWithPath: "/tmp/ai"),
            scoutDirectory: URL(fileURLWithPath: "/tmp"),
            runner: recorder,
            gitService: nil
        )
        let date = Calendar(identifier: .iso8601).date(from: DateComponents(
            timeZone: TimeZone(identifier: "America/New_York"), year: 2026, month: 4, day: 20
        ))!
        _ = try? await writer.submit(.addComment(
            subject: "Engage on PROJ-123",
            text: "Paging reviewer.",
            author: "user"
        ), displayedDate: date)

        let call = try #require(await recorder.calls.first)
        #expect(call.arguments.contains("python3"))
        #expect(call.arguments.contains("/tmp/ai/add_comment.py"))
        #expect(call.arguments.contains("2026-04-20"))
        #expect(call.arguments.contains("--subject"))
        #expect(call.arguments.contains("Engage on PROJ-123"))
        #expect(call.arguments.contains("--text"))
        #expect(call.arguments.contains("Paging reviewer."))
        #expect(call.arguments.contains("--author"))
        #expect(call.arguments.contains("user"))
        #expect(call.arguments.contains("--inline"))
    }

    @Test func serializesConcurrentSubmissions() async throws {
        let recorder = SlowRecordingRunner(delayMS: 80)
        let writer = ActionItemsWriter(
            python3: URL(fileURLWithPath: "/usr/bin/env"),
            actionItemsDirectory: URL(fileURLWithPath: "/tmp/ai"),
            scoutDirectory: URL(fileURLWithPath: "/tmp"),
            runner: recorder,
            gitService: nil
        )
        let date = Date()

        async let a = writer.submit(.markDone(subject: "A"), displayedDate: date)
        async let b = writer.submit(.markDone(subject: "B"), displayedDate: date)
        async let c = writer.submit(.markDone(subject: "C"), displayedDate: date)
        _ = try? await (a, b, c)

        let events = await recorder.events
        // Expect three complete start→end pairs, non-overlapping.
        #expect(events.count == 6)
        for i in stride(from: 0, to: events.count, by: 2) {
            #expect(events[i].kind == .start)
            #expect(events[i + 1].kind == .end)
            if i + 2 < events.count {
                #expect(events[i + 1].at <= events[i + 2].at,
                        "runs overlapped; writer didn't serialize")
            }
        }
    }

    @Test func throwsOnNonZeroExit() async throws {
        let runner = FailingRunner(exit: 2, stderr: "No task matched --subject 'X'.")
        let writer = ActionItemsWriter(
            python3: URL(fileURLWithPath: "/usr/bin/env"),
            actionItemsDirectory: URL(fileURLWithPath: "/tmp/ai"),
            scoutDirectory: URL(fileURLWithPath: "/tmp"),
            runner: runner,
            gitService: nil
        )
        do {
            _ = try await writer.submit(.markDone(subject: "X"), displayedDate: Date())
            Issue.record("expected throw")
        } catch let err as ActionItemsWriterError {
            switch err {
            case .cliNonZeroExit(let code, let stderr, let classification):
                #expect(code == 2)
                #expect(stderr.contains("No task matched"))
                #expect(classification == .noMatch)
            default: Issue.record("unexpected classification")
            }
        }
    }
}

// MARK: - Test doubles

actor RecordingRunner: ProcessRunner {
    struct Call: Sendable { let executable: URL; let arguments: [String]; let env: [String: String] }
    var calls: [Call] = []
    func run(executable: URL, arguments: [String], environment: [String : String], workingDirectory: URL?) async throws -> ProcessResult {
        calls.append(.init(executable: executable, arguments: arguments, env: environment))
        return ProcessResult(exitCode: 0, stdout: Data(), stderr: Data())
    }
}

actor SlowRecordingRunner: ProcessRunner {
    struct Event: Sendable { enum Kind { case start, end }; let kind: Kind; let at: Date }
    var events: [Event] = []
    let delayMS: Int
    init(delayMS: Int) { self.delayMS = delayMS }
    func run(executable: URL, arguments: [String], environment: [String : String], workingDirectory: URL?) async throws -> ProcessResult {
        events.append(.init(kind: .start, at: Date()))
        try? await Task.sleep(nanoseconds: UInt64(delayMS) * 1_000_000)
        events.append(.init(kind: .end, at: Date()))
        return ProcessResult(exitCode: 0, stdout: Data(), stderr: Data())
    }
}

struct FailingRunner: ProcessRunner {
    let exit: Int32
    let stderr: String
    func run(executable: URL, arguments: [String], environment: [String : String], workingDirectory: URL?) async throws -> ProcessResult {
        ProcessResult(exitCode: exit, stdout: Data(), stderr: stderr.data(using: .utf8) ?? Data())
    }
}
