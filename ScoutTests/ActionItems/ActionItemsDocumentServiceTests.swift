import Testing
import Foundation
@testable import Scout

@Suite("ActionItemsDocumentService")
@MainActor
struct ActionItemsDocumentServiceTests {
    static func tmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func loadsPresentFile() async throws {
        let dir = try Self.tmpDir()
        let url = dir.appendingPathComponent("action-items-2026-04-20.md")
        try "# Action Items — 2026-04-20\n\n## 🔴 Urgent\n\n- [ ] **A** — body\n".write(to: url, atomically: true, encoding: .utf8)

        let service = ActionItemsDocumentService(directory: dir, fileEvents: NoopFS())
        let y = Calendar(identifier: .iso8601).date(from: DateComponents(
            timeZone: TimeZone(identifier: "America/New_York"),
            year: 2026, month: 4, day: 20
        ))!
        try await service.load(date: y)

        switch service.state {
        case .loaded(let doc):
            #expect(doc.title.contains("2026-04-20"))
            #expect(doc.sections.count == 1)
            #expect(doc.sections[0].tasks.count == 1)
        default:
            Issue.record("expected .loaded, got \(service.state)")
        }
    }

    @Test func emitsMissingWhenFileAbsent() async throws {
        let dir = try Self.tmpDir()
        let service = ActionItemsDocumentService(directory: dir, fileEvents: NoopFS())
        let y = Calendar(identifier: .iso8601).date(from: DateComponents(
            timeZone: TimeZone(identifier: "America/New_York"),
            year: 2099, month: 1, day: 1
        ))!
        try await service.load(date: y)
        switch service.state {
        case .missing: break
        default: Issue.record("expected .missing, got \(service.state)")
        }
    }

    @Test func reparsesOnFileChange() async throws {
        let dir = try Self.tmpDir()
        let url = dir.appendingPathComponent("action-items-2026-04-20.md")
        try "# T\n\n## 🔴 Urgent\n\n- [ ] **A** — body\n".write(to: url, atomically: true, encoding: .utf8)

        let fakeFS = InjectableFS()
        let service = ActionItemsDocumentService(directory: dir, fileEvents: fakeFS)
        let y = Calendar(identifier: .iso8601).date(from: DateComponents(
            timeZone: TimeZone(identifier: "America/New_York"),
            year: 2026, month: 4, day: 20
        ))!
        try await service.load(date: y)

        // Mutate the file, then push an FSEvent.
        try "# T\n\n## 🔴 Urgent\n\n- [ ] **A** — body\n- [ ] **B** — body\n".write(to: url, atomically: true, encoding: .utf8)
        fakeFS.emit(FileSystemEvent(url: url, kind: .modified))

        // Wait up to 1s for the reparse.
        var tries = 0
        while tries < 20 {
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            if case .loaded(let doc) = service.state, doc.sections.first?.tasks.count == 2 { return }
            tries += 1
        }
        Issue.record("document did not reparse to 2 tasks in time; final state: \(service.state)")
    }
}

/// Test-only FS event source that lets tests push events manually.
final class InjectableFS: FileSystemEventSource, @unchecked Sendable {
    private var continuations: [AsyncStream<FileSystemEvent>.Continuation] = []
    func events(for url: URL) -> AsyncStream<FileSystemEvent> {
        AsyncStream { cont in self.continuations.append(cont) }
    }
    func emit(_ e: FileSystemEvent) { continuations.forEach { $0.yield(e) } }
}
