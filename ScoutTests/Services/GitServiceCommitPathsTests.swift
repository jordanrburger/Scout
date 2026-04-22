import Testing
import Foundation
@testable import Scout

@Suite("GitService.commitPaths")
struct GitServiceCommitPathsTests {

    @Test func bailsSilentlyOutsideRepo() async throws {
        let runner = ScriptedRunner(scripted: [
            ProcessResult(exitCode: 128, stdout: Data(), stderr: Data())  // rev-parse fails
        ])
        let git = GitService(
            repoURL: URL(fileURLWithPath: "/tmp/not-a-repo"),
            runner: runner
        )
        try await git.commitPaths(["file.txt"], message: "msg")
        #expect(runner.calls.count == 1)
    }

    @Test func skipsWhenNoPathDiff() async throws {
        let runner = ScriptedRunner(scripted: [
            ProcessResult(exitCode: 0, stdout: Data(), stderr: Data()),  // rev-parse
            ProcessResult(exitCode: 0, stdout: Data(), stderr: Data()),  // add
            ProcessResult(exitCode: 0, stdout: Data(), stderr: Data()),  // diff --quiet → 0 = clean
        ])
        let git = GitService(repoURL: URL(fileURLWithPath: "/tmp/r"), runner: runner)
        try await git.commitPaths(["file.txt"], message: "msg")
        #expect(runner.calls.count == 3)  // no commit invoked
    }

    @Test func commitsScopedToPaths() async throws {
        let runner = ScriptedRunner(scripted: [
            ProcessResult(exitCode: 0, stdout: Data(), stderr: Data()),
            ProcessResult(exitCode: 0, stdout: Data(), stderr: Data()),
            ProcessResult(exitCode: 1, stdout: Data(), stderr: Data()),  // diff = dirty
            ProcessResult(exitCode: 0, stdout: Data(), stderr: Data()),
        ])
        let git = GitService(repoURL: URL(fileURLWithPath: "/tmp/r"), runner: runner)
        try await git.commitPaths(["launchd/a.plist", "launchd/b.plist"], message: "msg")

        #expect(runner.calls.count == 4)
        let commit = runner.calls[3]
        #expect(commit.arguments.contains("commit"))
        #expect(commit.arguments.contains("-m"))
        #expect(commit.arguments.contains("msg"))
        #expect(commit.arguments.contains("--"))
        #expect(commit.arguments.contains("launchd/a.plist"))
        #expect(commit.arguments.contains("launchd/b.plist"))
    }

    @Test func throwsOnCommitFailure() async throws {
        let runner = ScriptedRunner(scripted: [
            ProcessResult(exitCode: 0, stdout: Data(), stderr: Data()),
            ProcessResult(exitCode: 0, stdout: Data(), stderr: Data()),
            ProcessResult(exitCode: 1, stdout: Data(), stderr: Data()),
            ProcessResult(exitCode: 1, stdout: Data(), stderr: Data("hook failed".utf8)),
        ])
        let git = GitService(repoURL: URL(fileURLWithPath: "/tmp/r"), runner: runner)
        await #expect(throws: GitServiceError.self) {
            try await git.commitPaths(["f"], message: "m")
        }
    }
}

final class ScriptedRunner: ProcessRunner, @unchecked Sendable {
    struct Call { let executable: URL; let arguments: [String] }
    private var scripted: [ProcessResult]
    private(set) var calls: [Call] = []
    private let lock = NSLock()

    init(scripted: [ProcessResult]) { self.scripted = scripted }

    func run(
        executable: URL, arguments: [String],
        environment: [String: String], workingDirectory: URL?
    ) async throws -> ProcessResult {
        lock.lock(); defer { lock.unlock() }
        calls.append(Call(executable: executable, arguments: arguments))
        if scripted.isEmpty {
            return ProcessResult(exitCode: 0, stdout: Data(), stderr: Data())
        }
        return scripted.removeFirst()
    }
}
