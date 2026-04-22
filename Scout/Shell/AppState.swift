import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    enum MenuBarStatus { case idle, running, lastFailed, budgetSkipped }

    @Published var menuBarStatus: MenuBarStatus = .idle

    // Existing Control Center services
    let fileWatcher: FileWatcher
    let trackerService: UsageTrackerService
    let sessionLogService: SessionLogService
    let scheduleService: LaunchdScheduleService
    let scheduleEditorService: ScheduleEditorService
    let gitService: GitService
    let runnerService: RunnerService
    let notificationService: NotificationService

    // New Action Items services
    let actionItemsDocumentService: ActionItemsDocumentService
    let actionItemsWriterBox: ActionItemsWriterBox
    let actionItemsEnvState: ActionItemsEnvironmentState
    let scoutDirectory: URL
    let actionItemsDirectory: URL

    private var previousStatus: [Run.ID: RunStatus] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let scoutDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Scout")
        let actionItemsDir = scoutDir.appendingPathComponent("action-items")
        let watcher = FileWatcher()
        let runner = SystemProcessRunner()

        let git = GitService(repoURL: scoutDir, runner: runner)
        let tracker = UsageTrackerService(
            trackerURL: scoutDir.appendingPathComponent(".scout-logs/usage-tracker.jsonl"),
            fileEvents: watcher
        )
        let logs = SessionLogService(
            logsDirectory: scoutDir.appendingPathComponent(".scout-logs"),
            trackerService: tracker,
            gitService: git,
            fileEvents: watcher
        )
        let sched = LaunchdScheduleService(fileEvents: watcher)
        let editor = ScheduleEditorService(
            repoDirectory: scoutDir.appendingPathComponent("launchd"),
            agentsDirectory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents"),
            userUid: getuid(),
            launchctl: SystemLaunchctlClient(runner: runner),
            git: git,
            fileEvents: watcher
        )
        let runnerSvc = RunnerService(scoutDirectory: scoutDir, runner: runner)
        let notif = NotificationService()

        let docService = ActionItemsDocumentService(directory: actionItemsDir, fileEvents: watcher)
        let writerActor = ActionItemsWriter(
            python3: URL(fileURLWithPath: "/usr/bin/env"),
            actionItemsDirectory: actionItemsDir,
            scoutDirectory: scoutDir,
            runner: runner,
            gitService: git
        )
        let writerBox = ActionItemsWriterBox(writer: writerActor)
        let envState = ActionItemsEnvironmentState()

        self.fileWatcher = watcher
        self.gitService = git
        self.trackerService = tracker
        self.sessionLogService = logs
        self.scheduleService = sched
        self.scheduleEditorService = editor
        self.runnerService = runnerSvc
        self.notificationService = notif
        self.actionItemsDocumentService = docService
        self.actionItemsWriterBox = writerBox
        self.actionItemsEnvState = envState
        self.scoutDirectory = scoutDir
        self.actionItemsDirectory = actionItemsDir

        Task { [weak self] in
            _ = try? await tracker.loadInitial()
            _ = try? await logs.loadInitial()
            await MainActor.run { sched.loadInitial() }
            _ = try? await editor.loadAll()
            await MainActor.run { editor.startWatching() }
            await self?.recomputeMenuStatus()

            // Run environment check; publish result.
            let check = ActionItemsEnvironmentCheck(
                actionItemsDirectory: actionItemsDir,
                runner: runner
            )
            if let result = try? await check.run() {
                await MainActor.run { envState.result = result }
            }
        }

        startNotificationWatch()
    }

    func recomputeMenuStatus() async {
        let latest = sessionLogService.runs.first
        let next: MenuBarStatus = switch latest?.status {
        case .running: .running
        case .failure, .timeout, .rateLimited: .lastFailed
        case .skippedBudget: .budgetSkipped
        default: .idle
        }
        menuBarStatus = next
    }

    private func startNotificationWatch() {
        sessionLogService.$runs.sink { [weak self] runs in
            guard let self else { return }
            Task { @MainActor in
                for r in runs {
                    let prev = self.previousStatus[r.id]
                    if prev == .running,
                       r.status != .running,
                       r.status != .success {
                        self.notificationService.notify(run: r)
                    }
                    self.previousStatus[r.id] = r.status
                }
                await self.recomputeMenuStatus()
            }
        }.store(in: &cancellables)
    }
}
