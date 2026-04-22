import Foundation

enum WriteOp: Sendable {
    case addComment(subject: String, text: String, author: String)
    case markDone(subject: String)
    case reopen(subject: String)
    case snooze(subject: String, until: Date)

    var verb: String {
        switch self {
        case .addComment: return "comment"
        case .markDone:   return "mark-done"
        case .reopen:     return "reopen"
        case .snooze:     return "snooze"
        }
    }

    var subject: String {
        switch self {
        case .addComment(let s, _, _), .markDone(let s), .reopen(let s), .snooze(let s, _):
            return s
        }
    }

    /// CLI name for this op. Relative to the action-items/ directory.
    var cliScript: String {
        switch self {
        case .addComment: return "add_comment.py"
        case .markDone, .reopen: return "mark_done.py"
        case .snooze: return "snooze.py"
        }
    }

    func cliArguments(scriptPath: URL, dateISO: String) -> [String] {
        var args = ["python3", scriptPath.path, dateISO, "--subject", subject]
        switch self {
        case .addComment(_, let text, let author):
            args += ["--text", text, "--author", author, "--inline"]
        case .reopen:
            args += ["--undo"]
        case .markDone:
            break
        case .snooze(_, let until):
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = TimeZone(identifier: "America/New_York")
            args += ["--until", fmt.string(from: until)]
        }
        return args
    }
}

enum ActionItemsWriterError: Error, Equatable {
    enum Classification: Equatable { case noMatch, ambiguous, environment, other }
    case cliNonZeroExit(exitCode: Int32, stderr: String, classification: Classification)
    case processFailed(Error)

    static func == (lhs: ActionItemsWriterError, rhs: ActionItemsWriterError) -> Bool {
        switch (lhs, rhs) {
        case let (.cliNonZeroExit(a, b, c), .cliNonZeroExit(d, e, f)):
            return a == d && b == e && c == f
        case (.processFailed, .processFailed): return true
        default: return false
        }
    }
}

struct WriteResult: Sendable {
    let stderr: String
}

actor ActionItemsWriter {
    private let python3: URL
    private let actionItemsDirectory: URL
    private let scoutDirectory: URL
    private let runner: any ProcessRunner
    private let gitService: GitService?

    /// Tail of the serial task chain. Each new submission awaits the previous
    /// task's completion before running, giving us a true serial queue on top
    /// of the actor (actors are re-entrant at each `await`, so a plain actor
    /// method isn't enough to serialize across suspensions).
    private var tail: Task<Void, Never>?

    init(
        python3: URL,
        actionItemsDirectory: URL,
        scoutDirectory: URL,
        runner: any ProcessRunner,
        gitService: GitService?
    ) {
        self.python3 = python3
        self.actionItemsDirectory = actionItemsDirectory
        self.scoutDirectory = scoutDirectory
        self.runner = runner
        self.gitService = gitService
    }

    /// Submit a write. Submissions are strictly serialized — only one CLI
    /// runs end-to-end at a time, even across concurrent callers.
    @discardableResult
    func submit(_ op: WriteOp, displayedDate: Date) async throws -> WriteResult {
        let previous = tail
        let task = Task { [runner, python3, actionItemsDirectory, scoutDirectory, gitService] in
            _ = await previous?.value  // wait for predecessor to finish
            return try await Self.perform(
                op: op,
                displayedDate: displayedDate,
                python3: python3,
                actionItemsDirectory: actionItemsDirectory,
                scoutDirectory: scoutDirectory,
                runner: runner,
                gitService: gitService
            )
        }
        // Chain the tail as a non-throwing observer so the next submission
        // waits regardless of whether this one succeeds.
        tail = Task { _ = try? await task.value }
        return try await task.value
    }

    private static func perform(
        op: WriteOp,
        displayedDate: Date,
        python3: URL,
        actionItemsDirectory: URL,
        scoutDirectory: URL,
        runner: any ProcessRunner,
        gitService: GitService?
    ) async throws -> WriteResult {
        let script = actionItemsDirectory.appendingPathComponent(op.cliScript)
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = TimeZone(identifier: "America/New_York")
        let dateISO = fmt.string(from: displayedDate)

        let result: ProcessResult
        do {
            result = try await runner.run(
                executable: python3,
                arguments: op.cliArguments(scriptPath: script, dateISO: dateISO),
                environment: [:],
                workingDirectory: scoutDirectory
            )
        } catch {
            throw ActionItemsWriterError.processFailed(error)
        }

        let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
        if result.exitCode != 0 {
            throw ActionItemsWriterError.cliNonZeroExit(
                exitCode: result.exitCode,
                stderr: stderr,
                classification: Self.classify(exitCode: result.exitCode, stderr: stderr)
            )
        }

        let slug = Self.slugify(op.subject)
        try? await gitService?.commitAll(message: "action-items: \(op.verb) \(slug)")

        return WriteResult(stderr: stderr)
    }

    private static func classify(exitCode: Int32, stderr: String) -> ActionItemsWriterError.Classification {
        switch exitCode {
        case 2: return .noMatch
        case 3: return .ambiguous
        case 1, 4, 5: return .other
        default:
            if stderr.lowercased().contains("no module named") || stderr.contains("command not found") {
                return .environment
            }
            return .other
        }
    }

    private static func slugify(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed.prefix(40)
        return prefix
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "\"", with: "")
    }
}
