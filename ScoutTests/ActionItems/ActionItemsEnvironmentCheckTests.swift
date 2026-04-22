import Testing
import Foundation
@testable import Scout

@Suite("ActionItemsEnvironmentCheck")
struct ActionItemsEnvironmentCheckTests {
    @Test func passesWhenPythonAndAllScriptsExist() async throws {
        let dir = try Self.tmpActionItems()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let check = ActionItemsEnvironmentCheck(actionItemsDirectory: dir, runner: SystemProcessRunner())
        let result = try await check.run()
        #expect(result.ok)
        #expect(result.python3Path != nil)
        #expect(result.missingScripts.isEmpty)
    }

    @Test func failsWhenScriptsMissing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let check = ActionItemsEnvironmentCheck(actionItemsDirectory: dir, runner: SystemProcessRunner())
        let result = try await check.run()
        #expect(!result.ok)
        #expect(result.missingScripts.sorted() == ["add_comment.py", "mark_done.py", "snooze.py"])
    }

    private static func tmpActionItems() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = base.appendingPathComponent("action-items")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["add_comment.py", "mark_done.py", "snooze.py"] {
            let path = dir.appendingPathComponent(name)
            try "#!/usr/bin/env python3\nprint('stub')\n".write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }
        return dir
    }
}
