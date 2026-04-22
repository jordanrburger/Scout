import Testing
import Foundation
@testable import Scout

@Suite("ActionItems end-to-end integration")
@MainActor
struct ActionItemsIntegrationTests {
    @Test func writerInvokesRealCLIAndViewPicksUpChange() async throws {
        // Skip if python3 isn't available in the environment.
        guard Self.python3Available() else { return }

        // 1. Temp directory with a real action-items file.
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let aiDir = base.appendingPathComponent("action-items")
        try FileManager.default.createDirectory(at: aiDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        // 2. Copy the three real CLIs in.
        for name in ActionItemsEnvironmentCheck.requiredScripts {
            let src = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Scout/action-items/\(name)")
            let dst = aiDir.appendingPathComponent(name)
            try FileManager.default.copyItem(at: src, to: dst)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst.path)
        }

        // 3. Write a trivial MD.
        let mdURL = aiDir.appendingPathComponent("action-items-2026-04-20.md")
        let initial = """
        # Action Items — 2026-04-20

        ## 🔴 Urgent

        - [ ] **IntegrationTestTask** — verify end-to-end write-back
        """
        try initial.write(to: mdURL, atomically: true, encoding: .utf8)

        // 4. Mount the service.
        let service = ActionItemsDocumentService(directory: aiDir, fileEvents: FileWatcher())
        let date = Calendar(identifier: .iso8601).date(from: DateComponents(
            timeZone: TimeZone(identifier: "America/New_York"), year: 2026, month: 4, day: 20
        ))!
        try await service.load(date: date)

        // 5. Invoke the writer.
        let writer = ActionItemsWriter(
            python3: URL(fileURLWithPath: "/usr/bin/env"),
            actionItemsDirectory: aiDir,
            scoutDirectory: base,
            runner: SystemProcessRunner(),
            gitService: nil
        )
        _ = try await writer.submit(
            .addComment(subject: "IntegrationTestTask", text: "hello from integration", author: "user"),
            displayedDate: date
        )

        // 6. Wait for FSEvents + reparse.
        var tries = 0
        while tries < 40 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if case .loaded(let doc) = service.state,
               let t = doc.sections.first?.tasks.first,
               t.comments.contains(where: { $0.text.contains("hello from integration") }) {
                return
            }
            tries += 1
        }
        Issue.record("Comment never appeared in reparsed document; final state: \(service.state)")
    }

    private static func python3Available() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", "--version"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }
}
