import Foundation
import Combine
import SwiftUI

enum ScheduleDriftKind: Equatable, Sendable {
    case liveMissing     // repo has it, ~/Library/LaunchAgents/ doesn't
    case repoMissing     // live has it, repo doesn't
}

struct ScheduleDrift: Identifiable, Equatable, Sendable {
    let id: String
    let kind: ScheduleDriftKind
}

struct CommitError: Identifiable, Equatable, Sendable {
    let id: UUID
    let scheduleId: String
    let message: String
    let stderr: String

    init(scheduleId: String, message: String, stderr: String) {
        self.id = UUID()
        self.scheduleId = scheduleId
        self.message = message
        self.stderr = stderr
    }
}

enum ScheduleValidationError: Error, Equatable {
    case invalidLabel(String)
    case duplicateId(String)
    case emptyCalendar
    case nonPositiveInterval
    case labelMismatch(id: String, label: String)
}

@MainActor
final class ScheduleEditorService: ObservableObject {
    @Published private(set) var schedules: [Schedule] = []
    @Published private(set) var drift: [ScheduleDrift] = []
    @Published private(set) var commitErrors: [CommitError] = []

    let repoDirectory: URL
    let agentsDirectory: URL
    let userUid: uid_t
    private let launchctl: any LaunchctlClient
    private let git: any GitServiceProtocol
    private let fileEvents: any FileSystemEventSource
    private var watchTask: Task<Void, Never>?

    init(
        repoDirectory: URL,
        agentsDirectory: URL,
        userUid: uid_t,
        launchctl: any LaunchctlClient,
        git: any GitServiceProtocol,
        fileEvents: any FileSystemEventSource
    ) {
        self.repoDirectory = repoDirectory
        self.agentsDirectory = agentsDirectory
        self.userUid = userUid
        self.launchctl = launchctl
        self.git = git
        self.fileEvents = fileEvents
    }

    deinit { watchTask?.cancel() }

    func dismissCommitError(_ id: UUID) {
        commitErrors.removeAll { $0.id == id }
    }

    // MARK: - Load

    func loadAll() async throws {
        let fm = FileManager.default
        let repoFiles = (try? fm.contentsOfDirectory(
            at: repoDirectory, includingPropertiesForKeys: nil
        )) ?? []
        var loaded: [Schedule] = []
        for url in repoFiles
            where url.lastPathComponent.hasPrefix("com.scout.")
               && url.pathExtension == "plist" {
            if let sched = try? PlistIO.readSchedule(from: url) {
                loaded.append(sched)
            }
        }
        loaded.sort { $0.id < $1.id }
        self.schedules = loaded

        let liveNames = Set(((try? fm.contentsOfDirectory(
            at: agentsDirectory, includingPropertiesForKeys: nil
        )) ?? []).map { $0.lastPathComponent })

        var driftOut: [ScheduleDrift] = []
        for s in loaded where !liveNames.contains("\(s.id).plist") {
            driftOut.append(ScheduleDrift(id: s.id, kind: .liveMissing))
        }
        let repoNames = Set(loaded.map { "\($0.id).plist" })
        for name in liveNames
            where name.hasPrefix("com.scout.") && !repoNames.contains(name) {
            let stem = (name as NSString).deletingPathExtension
            driftOut.append(ScheduleDrift(id: stem, kind: .repoMissing))
        }
        self.drift = driftOut
    }

    func startWatching() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.fileEvents.events(for: self.repoDirectory) {
                guard event.url.lastPathComponent.hasPrefix("com.scout.") else { continue }
                try? await self.loadAll()
            }
        }
    }

    // MARK: - Validation

    nonisolated static func validate(_ s: Schedule, existingIds: Set<String>) throws {
        if s.label != s.id {
            throw ScheduleValidationError.labelMismatch(id: s.id, label: s.label)
        }
        let pattern = #"^com\.scout\.[a-z0-9-]+$"#
        guard s.id.range(of: pattern, options: .regularExpression) != nil else {
            throw ScheduleValidationError.invalidLabel(s.id)
        }
        if existingIds.contains(s.id) {
            throw ScheduleValidationError.duplicateId(s.id)
        }
        switch s.trigger {
        case .calendar(let fires) where fires.isEmpty:
            throw ScheduleValidationError.emptyCalendar
        case .interval(let secs) where secs <= 0:
            throw ScheduleValidationError.nonPositiveInterval
        default:
            break
        }
    }

    // MARK: - Save

    /// Persist `edited` to both repo and live paths, reload via launchctl,
    /// and commit the repo change. A git failure does not throw — it enqueues
    /// a `CommitError` so the banner UI can surface it.
    func save(_ edited: Schedule, commitMessageOverride: String?) async throws {
        let original = schedules.first(where: { $0.id == edited.id })
        let isCreate = (original == nil)

        let repoURL = repoDirectory.appendingPathComponent("\(edited.id).plist")
        let liveURL = agentsDirectory.appendingPathComponent("\(edited.id).plist")

        try PlistIO.writeSchedule(edited, to: repoURL)
        do {
            try PlistIO.writeSchedule(edited, to: liveURL)
        } catch {
            if isCreate { try? FileManager.default.removeItem(at: repoURL) }
            throw error
        }

        // bootout is best-effort cleanup. launchctl returns several non-zero
        // codes when the service isn't loaded — 3 ("No such process"), 5
        // ("Input/output error" — its idiom for "service not found"), etc.
        // We don't care which; only bootstrap's success matters.
        _ = try? await launchctl.bootout(userUid: userUid, plistPath: liveURL)

        do {
            try await launchctl.bootstrap(userUid: userUid, plistPath: liveURL)
        } catch {
            try? FileManager.default.removeItem(at: liveURL)
            if isCreate { try? FileManager.default.removeItem(at: repoURL) }
            throw error
        }

        if let idx = schedules.firstIndex(where: { $0.id == edited.id }) {
            schedules[idx] = edited
        } else {
            schedules.append(edited)
            schedules.sort { $0.id < $1.id }
        }

        let message: String
        if let override = commitMessageOverride {
            message = override
        } else if let original {
            let suffix = ScheduleDiff.summarize(original: original, edited: edited)
            message = suffix.isEmpty
                ? "schedules: update \(edited.id)"
                : "schedules: update \(edited.id) (\(suffix))"
        } else {
            message = "schedules: add \(edited.id)"
        }
        await tryCommit(paths: [repoURL.path], message: message, scheduleId: edited.id)
    }

    // MARK: - Create

    func create(_ schedule: Schedule, commitMessageOverride: String?) async throws {
        try Self.validate(schedule, existingIds: Set(schedules.map { $0.id }))
        try await save(schedule, commitMessageOverride: commitMessageOverride)
    }

    // MARK: - Delete

    func delete(_ schedule: Schedule, commitMessageOverride: String?) async throws {
        let repoURL = repoDirectory.appendingPathComponent("\(schedule.id).plist")
        let liveURL = agentsDirectory.appendingPathComponent("\(schedule.id).plist")

        // Best-effort bootout. The file may or may not be loaded; any exit
        // code is fine because we're removing the file anyway.
        _ = try? await launchctl.bootout(userUid: userUid, plistPath: liveURL)

        try? FileManager.default.removeItem(at: liveURL)
        try? FileManager.default.removeItem(at: repoURL)

        schedules.removeAll { $0.id == schedule.id }

        let message = commitMessageOverride ?? "schedules: remove \(schedule.id)"
        await tryCommit(paths: [repoURL.path], message: message, scheduleId: schedule.id)
    }

    // MARK: - Internal helpers

    private func tryCommit(paths: [String], message: String, scheduleId: String) async {
        do {
            try await git.commitPaths(paths, message: message)
        } catch {
            let stderr: String
            if case GitServiceError.commitFailed(_, let s) = error {
                stderr = s
            } else {
                stderr = String(describing: error)
            }
            commitErrors.append(CommitError(
                scheduleId: scheduleId,
                message: message,
                stderr: stderr
            ))
        }
    }
}
