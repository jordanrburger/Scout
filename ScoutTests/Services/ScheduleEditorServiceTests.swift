import Testing
import Foundation
@testable import Scout

// MARK: - Shared helpers + fakes

struct TempDirs { let root: URL; let repo: URL; let live: URL }

@MainActor
func makeTempDirs() -> TempDirs {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("scout-sched-\(UUID().uuidString)")
    let repo = root.appendingPathComponent("launchd")
    let live = root.appendingPathComponent("LaunchAgents")
    try? FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
    return TempDirs(root: root, repo: repo, live: live)
}

func copyFixture(_ name: String, to dir: URL) throws {
    let src = Bundle(for: FixtureAnchor.self)
        .url(forResource: name, withExtension: "plist")!
    let dst = dir.appendingPathComponent("\(name).plist")
    try? FileManager.default.removeItem(at: dst)
    try FileManager.default.copyItem(at: src, to: dst)
}

@MainActor
func makeSchedulesService(
    repo: URL, live: URL,
    launchctl: FakeLaunchctl = FakeLaunchctl(),
    git: FakeGit = FakeGit(),
    fileEvents: any FileSystemEventSource = NoopFileEvents()
) -> ScheduleEditorService {
    ScheduleEditorService(
        repoDirectory: repo,
        agentsDirectory: live,
        userUid: 501,
        launchctl: launchctl,
        git: git,
        fileEvents: fileEvents
    )
}

final class FakeLaunchctl: LaunchctlClient, @unchecked Sendable {
    var bootoutExitCodes: [Int32] = []
    var bootstrapError: LaunchctlError? = nil
    private(set) var bootoutPaths: [URL] = []
    private(set) var bootstrapPaths: [URL] = []
    private let lock = NSLock()

    func bootout(userUid: uid_t, plistPath: URL) async throws -> Int32 {
        lock.lock(); defer { lock.unlock() }
        bootoutPaths.append(plistPath)
        return bootoutExitCodes.isEmpty ? 0 : bootoutExitCodes.removeFirst()
    }
    func bootstrap(userUid: uid_t, plistPath: URL) async throws {
        lock.lock()
        bootstrapPaths.append(plistPath)
        let err = bootstrapError
        lock.unlock()
        if let err { throw err }
    }
}

final class FakeGit: GitServiceProtocol, @unchecked Sendable {
    struct Call: Sendable { let paths: [String]; let message: String }
    var nextError: Error? = nil
    private(set) var calls: [Call] = []
    private let lock = NSLock()

    func commitPaths(_ relPaths: [String], message: String) async throws {
        lock.lock()
        calls.append(Call(paths: relPaths, message: message))
        let err = nextError
        nextError = nil
        lock.unlock()
        if let err { throw err }
    }
}

struct NoopFileEvents: FileSystemEventSource {
    func events(for url: URL) -> AsyncStream<FileSystemEvent> {
        AsyncStream { _ in }
    }
}

// MARK: - loadAll + drift

@Suite("ScheduleEditorService.loadAll")
@MainActor
struct ScheduleEditorServiceLoadAllTests {

    @Test func loadsRepoPlistsIntoPublishedState() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }
        try copyFixture("com.scout.briefing-weekend", to: tmp.repo)
        try copyFixture("com.scout.heartbeat", to: tmp.repo)

        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live)
        try await svc.loadAll()
        #expect(svc.schedules.count == 2)
        #expect(svc.schedules.contains { $0.id == "com.scout.briefing-weekend" })
        #expect(svc.schedules.contains { $0.id == "com.scout.heartbeat" })
    }

    @Test func ignoresNonScoutPlists() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }
        try copyFixture("com.scout.heartbeat", to: tmp.repo)
        try Data().write(to: tmp.repo.appendingPathComponent("com.example.plist"))

        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live)
        try await svc.loadAll()
        #expect(svc.schedules.count == 1)
    }

    @Test func flagsDriftWhenLiveMissing() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }
        try copyFixture("com.scout.heartbeat", to: tmp.repo)

        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live)
        try await svc.loadAll()
        #expect(svc.drift.count == 1)
        #expect(svc.drift.first?.kind == .liveMissing)
    }
}

// MARK: - Validation

@Suite("ScheduleEditorService validation")
struct ScheduleEditorServiceValidationTests {

    @Test func rejectsInvalidLabel() {
        let s = Schedule(
            id: "BadLabel", label: "BadLabel",
            runnerScript: URL(fileURLWithPath: "/s.sh"),
            trigger: .calendar([CalendarFire(weekday: nil, hour: 1, minute: 0)])
        )
        #expect(throws: ScheduleValidationError.self) {
            try ScheduleEditorService.validate(s, existingIds: [])
        }
    }

    @Test func rejectsNonScoutPrefix() {
        let s = Schedule(
            id: "com.example.x", label: "com.example.x",
            runnerScript: URL(fileURLWithPath: "/s.sh"),
            trigger: .interval(seconds: 60)
        )
        #expect(throws: ScheduleValidationError.self) {
            try ScheduleEditorService.validate(s, existingIds: [])
        }
    }

    @Test func rejectsDuplicateId() {
        let s = Schedule(
            id: "com.scout.dup", label: "com.scout.dup",
            runnerScript: URL(fileURLWithPath: "/s.sh"),
            trigger: .interval(seconds: 60)
        )
        #expect(throws: ScheduleValidationError.self) {
            try ScheduleEditorService.validate(s, existingIds: ["com.scout.dup"])
        }
    }

    @Test func rejectsEmptyCalendar() {
        let s = Schedule(
            id: "com.scout.empty", label: "com.scout.empty",
            runnerScript: URL(fileURLWithPath: "/s.sh"),
            trigger: .calendar([])
        )
        #expect(throws: ScheduleValidationError.self) {
            try ScheduleEditorService.validate(s, existingIds: [])
        }
    }

    @Test func rejectsZeroInterval() {
        let s = Schedule(
            id: "com.scout.zero", label: "com.scout.zero",
            runnerScript: URL(fileURLWithPath: "/s.sh"),
            trigger: .interval(seconds: 0)
        )
        #expect(throws: ScheduleValidationError.self) {
            try ScheduleEditorService.validate(s, existingIds: [])
        }
    }

    @Test func acceptsValid() throws {
        let s = Schedule(
            id: "com.scout.ok", label: "com.scout.ok",
            runnerScript: URL(fileURLWithPath: "/s.sh"),
            trigger: .interval(seconds: 60)
        )
        try ScheduleEditorService.validate(s, existingIds: [])
    }
}

// MARK: - Save

@Suite("ScheduleEditorService.save")
@MainActor
struct ScheduleEditorServiceSaveTests {

    @Test func writesBothPathsAndReloads() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }
        try copyFixture("com.scout.heartbeat", to: tmp.repo)
        try copyFixture("com.scout.heartbeat", to: tmp.live)

        let fakeCtl = FakeLaunchctl()
        let fakeGit = FakeGit()
        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live,
                                        launchctl: fakeCtl, git: fakeGit)
        try await svc.loadAll()

        var edited = svc.schedules.first { $0.id == "com.scout.heartbeat" }!
        edited.trigger = .interval(seconds: 3600)

        try await svc.save(edited, commitMessageOverride: nil)

        let repoRead = try PlistIO.readSchedule(
            from: tmp.repo.appendingPathComponent("com.scout.heartbeat.plist")
        )
        let liveRead = try PlistIO.readSchedule(
            from: tmp.live.appendingPathComponent("com.scout.heartbeat.plist")
        )
        #expect(repoRead.trigger.semanticallyEquals(.interval(seconds: 3600)))
        #expect(liveRead.trigger.semanticallyEquals(.interval(seconds: 3600)))
        #expect(fakeCtl.bootoutPaths.count == 1)
        #expect(fakeCtl.bootstrapPaths.count == 1)
        #expect(fakeGit.calls.count == 1)
        #expect(fakeGit.calls.first?.message
                == "schedules: update com.scout.heartbeat (trigger)")
    }

    @Test func swallowsAnyBootoutExitCode() async throws {
        // bootout returns 3 (not loaded), 5 (not found — common on create),
        // or other codes in various states. The service must proceed to
        // bootstrap regardless; only bootstrap failure is fatal.
        for code in [Int32(3), 5, 36, 113] {
            let tmp = makeTempDirs()
            defer { try? FileManager.default.removeItem(at: tmp.root) }
            try copyFixture("com.scout.heartbeat", to: tmp.repo)
            let fakeCtl = FakeLaunchctl()
            fakeCtl.bootoutExitCodes = [code]
            let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live,
                                            launchctl: fakeCtl)
            try await svc.loadAll()
            var s = svc.schedules.first!
            s.trigger = .interval(seconds: 120)

            try await svc.save(s, commitMessageOverride: nil)
            #expect(fakeCtl.bootstrapPaths.count == 1)
        }
    }

    @Test func createRollsBackBothFilesOnBootstrapFailure() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }
        // Fresh: no existing research plist.
        let fakeCtl = FakeLaunchctl()
        fakeCtl.bootstrapError = .bootstrapFailed(exitCode: 5, stderr: "nope")
        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live,
                                        launchctl: fakeCtl)
        try await svc.loadAll()

        let s = Schedule(
            id: "com.scout.research", label: "com.scout.research",
            runnerScript: URL(fileURLWithPath: "/s.sh"),
            trigger: .calendar([CalendarFire(weekday: nil, hour: 14, minute: 0)])
        )
        await #expect(throws: LaunchctlError.self) {
            try await svc.create(s, commitMessageOverride: nil)
        }
        // Both files removed (no orphan state).
        #expect(!FileManager.default.fileExists(atPath:
            tmp.repo.appendingPathComponent("com.scout.research.plist").path))
        #expect(!FileManager.default.fileExists(atPath:
            tmp.live.appendingPathComponent("com.scout.research.plist").path))
    }

    @Test func bootstrapFailureRollsBackLive() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }
        try copyFixture("com.scout.heartbeat", to: tmp.repo)
        try copyFixture("com.scout.heartbeat", to: tmp.live)
        let fakeCtl = FakeLaunchctl()
        fakeCtl.bootstrapError = .bootstrapFailed(exitCode: 5, stderr: "nope")
        let fakeGit = FakeGit()
        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live,
                                        launchctl: fakeCtl, git: fakeGit)
        try await svc.loadAll()
        var s = svc.schedules.first!
        s.trigger = .interval(seconds: 120)

        await #expect(throws: LaunchctlError.self) {
            try await svc.save(s, commitMessageOverride: nil)
        }
        #expect(!FileManager.default.fileExists(atPath:
            tmp.live.appendingPathComponent("com.scout.heartbeat.plist").path))
        #expect(FileManager.default.fileExists(atPath:
            tmp.repo.appendingPathComponent("com.scout.heartbeat.plist").path))
        #expect(fakeGit.calls.isEmpty)
    }

    @Test func gitFailureEnqueuesErrorButPreservesEdit() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }
        try copyFixture("com.scout.heartbeat", to: tmp.repo)
        try copyFixture("com.scout.heartbeat", to: tmp.live)
        let fakeGit = FakeGit()
        fakeGit.nextError = GitServiceError.commitFailed(exitCode: 1, stderr: "hook")
        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live,
                                        git: fakeGit)
        try await svc.loadAll()
        var s = svc.schedules.first!
        s.trigger = .interval(seconds: 120)

        try await svc.save(s, commitMessageOverride: nil)

        #expect(svc.commitErrors.count == 1)
        let reread = try PlistIO.readSchedule(
            from: tmp.repo.appendingPathComponent("com.scout.heartbeat.plist")
        )
        #expect(reread.trigger.semanticallyEquals(.interval(seconds: 120)))
    }

    @Test func respectsCommitMessageOverride() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }
        try copyFixture("com.scout.heartbeat", to: tmp.repo)
        try copyFixture("com.scout.heartbeat", to: tmp.live)
        let fakeGit = FakeGit()
        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live,
                                        git: fakeGit)
        try await svc.loadAll()
        var s = svc.schedules.first!
        s.trigger = .interval(seconds: 120)

        try await svc.save(s, commitMessageOverride: "custom msg")
        #expect(fakeGit.calls.first?.message == "custom msg")
    }
}

// MARK: - Create

@Suite("ScheduleEditorService.create")
@MainActor
struct ScheduleEditorServiceCreateTests {

    @Test func writesNewAndCommits() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }
        let fakeGit = FakeGit()
        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live, git: fakeGit)
        try await svc.loadAll()

        let s = Schedule(
            id: "com.scout.research", label: "com.scout.research",
            runnerScript: URL(fileURLWithPath: "/Users/scout-dev/Scout/run-research.sh"),
            trigger: .calendar([CalendarFire(weekday: 3, hour: 2, minute: 0)])
        )
        try await svc.create(s, commitMessageOverride: nil)

        #expect(FileManager.default.fileExists(atPath:
            tmp.repo.appendingPathComponent("com.scout.research.plist").path))
        #expect(FileManager.default.fileExists(atPath:
            tmp.live.appendingPathComponent("com.scout.research.plist").path))
        #expect(fakeGit.calls.first?.message == "schedules: add com.scout.research")
        #expect(svc.schedules.contains { $0.id == "com.scout.research" })
    }

    @Test func rejectsDuplicate() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }
        try copyFixture("com.scout.heartbeat", to: tmp.repo)
        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live)
        try await svc.loadAll()

        let dup = Schedule(
            id: "com.scout.heartbeat", label: "com.scout.heartbeat",
            runnerScript: URL(fileURLWithPath: "/x.sh"),
            trigger: .interval(seconds: 60)
        )
        await #expect(throws: ScheduleValidationError.self) {
            try await svc.create(dup, commitMessageOverride: nil)
        }
    }
}

// MARK: - Delete

@Suite("ScheduleEditorService.delete")
@MainActor
struct ScheduleEditorServiceDeleteTests {

    @Test func removesBothFilesAndCommits() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }
        try copyFixture("com.scout.heartbeat", to: tmp.repo)
        try copyFixture("com.scout.heartbeat", to: tmp.live)
        let fakeGit = FakeGit()
        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live, git: fakeGit)
        try await svc.loadAll()
        let s = svc.schedules.first!

        try await svc.delete(s, commitMessageOverride: nil)

        #expect(!FileManager.default.fileExists(atPath:
            tmp.repo.appendingPathComponent("com.scout.heartbeat.plist").path))
        #expect(!FileManager.default.fileExists(atPath:
            tmp.live.appendingPathComponent("com.scout.heartbeat.plist").path))
        #expect(fakeGit.calls.first?.message == "schedules: remove com.scout.heartbeat")
        #expect(svc.schedules.isEmpty)
    }

    @Test func toleratesMissingLiveFile() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }
        try copyFixture("com.scout.heartbeat", to: tmp.repo)
        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live)
        try await svc.loadAll()
        let s = svc.schedules.first!
        try await svc.delete(s, commitMessageOverride: nil)
        #expect(svc.schedules.isEmpty)
    }
}

// MARK: - Watch

@Suite("ScheduleEditorService watch")
@MainActor
struct ScheduleEditorServiceWatchTests {

    final class ManualEvents: FileSystemEventSource, @unchecked Sendable {
        var continuation: AsyncStream<FileSystemEvent>.Continuation?
        func events(for url: URL) -> AsyncStream<FileSystemEvent> {
            AsyncStream { cont in self.continuation = cont }
        }
        func emit(url: URL, kind: FileSystemEvent.Kind) {
            continuation?.yield(FileSystemEvent(url: url, kind: kind))
        }
    }

    @Test func reloadsOnRepoDirEvent() async throws {
        let tmp = makeTempDirs()
        defer { try? FileManager.default.removeItem(at: tmp.root) }

        let events = ManualEvents()
        let svc = makeSchedulesService(repo: tmp.repo, live: tmp.live, fileEvents: events)
        try await svc.loadAll()
        #expect(svc.schedules.isEmpty)

        try copyFixture("com.scout.heartbeat", to: tmp.repo)
        svc.startWatching()
        // Give the Task time to subscribe to the AsyncStream.
        try await Task.sleep(for: .milliseconds(30))
        events.emit(
            url: tmp.repo.appendingPathComponent("com.scout.heartbeat.plist"),
            kind: .created
        )
        try await Task.sleep(for: .milliseconds(100))
        #expect(svc.schedules.contains { $0.id == "com.scout.heartbeat" })
    }
}
