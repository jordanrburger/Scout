import SwiftUI
import AppKit

struct MenuBarExtraContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        statusSection
        Divider()
        scheduleSection
        Divider()
        Button("Open Control Center") { openMainWindow() }
        Button("Open Scout folder in Finder") {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Scout")
            NSWorkspace.shared.open(url)
        }
        Divider()
        Button("Quit Scout") { NSApp.terminate(nil) }
    }

    @ViewBuilder private var statusSection: some View {
        let latest = state.sessionLogService.runs.first
        if let r = latest, r.status == .running {
            Text("Running: \(r.type.rawValue)")
        } else if let r = latest {
            Text("Last: \(r.type.rawValue) · \(r.status.rawValue)")
        } else {
            Text("No recent runs").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var scheduleSection: some View {
        let upc = state.scheduleService.upcoming.prefix(5)
        if upc.isEmpty {
            Text("No upcoming runs scheduled").foregroundStyle(.secondary)
        } else {
            ForEach(Array(upc), id: \.id) { u in
                Button("\(u.scheduledAt.formatted(.dateTime.hour().minute())) · \(u.type.rawValue) — Run now") {
                    Task { try? await state.runnerService.runNow(type: u.type, bypassBudget: false) }
                }
            }
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.title == "Scout" }) {
            win.makeKeyAndOrderFront(nil)
        }
    }
}
