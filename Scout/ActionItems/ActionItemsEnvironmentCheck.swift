import Foundation

struct ActionItemsEnvironmentResult: Equatable, Sendable {
    let ok: Bool
    let python3Path: URL?
    let missingScripts: [String]
}

final class ActionItemsEnvironmentCheck: @unchecked Sendable {
    static let requiredScripts = ["add_comment.py", "mark_done.py", "snooze.py"]

    private let actionItemsDirectory: URL
    private let runner: any ProcessRunner

    init(actionItemsDirectory: URL, runner: any ProcessRunner) {
        self.actionItemsDirectory = actionItemsDirectory
        self.runner = runner
    }

    /// Probe for python3 on $PATH and confirm each of the three CLIs exists + is executable.
    func run() async throws -> ActionItemsEnvironmentResult {
        let fm = FileManager.default
        var missing: [String] = []
        for name in Self.requiredScripts {
            let p = actionItemsDirectory.appendingPathComponent(name)
            if !fm.fileExists(atPath: p.path) || !fm.isExecutableFile(atPath: p.path) {
                missing.append(name)
            }
        }

        var python3URL: URL? = nil
        let probe = try? await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", "--version"],
            environment: [:],
            workingDirectory: nil
        )
        if let probe, probe.exitCode == 0 {
            python3URL = URL(fileURLWithPath: "/usr/bin/env")
        }

        return ActionItemsEnvironmentResult(
            ok: python3URL != nil && missing.isEmpty,
            python3Path: python3URL,
            missingScripts: missing
        )
    }
}
