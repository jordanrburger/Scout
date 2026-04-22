import SwiftUI
import AppKit

struct RunDetailView: View {
    let run: Run
    @EnvironmentObject var state: AppState
    @State private var confirmRetry = false
    @State private var resolvedCommits: [Commit] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            TabView {
                LogViewer(logPath: run.logPath)
                    .tabItem { Label("Log", systemImage: "text.alignleft") }
                DiffViewer(commits: resolvedCommits)
                    .tabItem { Label("Diff", systemImage: "arrow.triangle.branch") }
                ErrorsTab(errors: run.errorsDetected)
                    .tabItem { Label("Errors", systemImage: "exclamationmark.triangle") }
                MetadataTab(run: run)
                    .tabItem { Label("Raw", systemImage: "curlybraces") }
            }
            actionBar
        }
        .padding()
        .navigationTitle(run.type.rawValue)
        .task(id: run.id) {
            // Resolve commits lazily on run selection to keep launch fast.
            resolvedCommits = await state.sessionLogService.commits(for: run)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(run.type.rawValue).font(.title2).fontWeight(.bold)
            HStack(spacing: 16) {
                Text(run.status.rawValue)
                    .foregroundStyle(run.status == .success ? .green : .red)
                Text("Started \(run.startedAt.formatted(date: .abbreviated, time: .shortened))")
                if let c = run.cost { Text("Cost: $\(c as NSDecimalNumber)") }
                if let e = run.exitCode { Text("Exit \(e)") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Retry") { confirmRetry = true }
                .disabled(run.status == .running)
            Button("Open log file") {
                NSWorkspace.shared.open(run.logPath)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([run.logPath])
            }
        }
        .confirmationDialog(
            "Retry \(run.type.rawValue)?",
            isPresented: $confirmRetry,
            titleVisibility: .visible
        ) {
            Button("Retry") {
                Task { try? await state.runnerService.retry(run: run, bypassBudget: false) }
            }
            Button("Retry (bypass budget)") {
                Task { try? await state.runnerService.retry(run: run, bypassBudget: true) }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}
