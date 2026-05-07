import SwiftUI

struct SchedulesView: View {
    @EnvironmentObject var service: ScheduleEditorService
    @State private var selection: Schedule.ID? = nil
    @State private var isShowingNewSheet = false

    // Plan 5 scope gap: this view was built around editing per-slot launchd
    // plists (com.scout.briefing.plist etc.). Plan 5 collapsed those plists
    // into a single com.scout.schedule-tick.plist that polls schedule.yaml,
    // so the legacy editor model has nothing meaningful to display. Body
    // replaced with a placeholder; the existing implementation (`legacyBody`,
    // `list`, `commitErrorBanner`, `statusDot`) is retained so Plan 6's
    // schedule.yaml editor can lift the table/sheet plumbing. See
    // docs/superpowers/FOLLOWUPS.md "Plan 5 → Plan 6 — Schedules tab rewrite"
    // for the full rebuild plan.
    var body: some View {
        ContentUnavailableView {
            Label("Schedule editor is being rebuilt", systemImage: "calendar.badge.clock")
        } description: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Plan 5 moved scheduling from per-slot launchd plists to a single dispatcher backed by ~/Scout/.scout-state/schedule.yaml.")
                Text("The new editor lands in Plan 6. Until then, edit the YAML directly or use scoutctl schedule {list, show, validate, init} from the terminal.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 520, alignment: .leading)
        }
    }

    private var legacyBody: some View {
        NavigationSplitView {
            list
        } detail: {
            if let id = selection,
               let schedule = service.schedules.first(where: { $0.id == id }) {
                ScheduleDetailView(schedule: schedule)
                    .id(schedule.id)
            } else {
                ContentUnavailableView(
                    "No schedule selected",
                    systemImage: "calendar",
                    description: Text("Pick a schedule on the left to edit it.")
                )
            }
        }
        .sheet(isPresented: $isShowingNewSheet) {
            NewScheduleSheet()
                .environmentObject(service)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            commitErrorBanner
            Table(service.schedules, selection: $selection) {
                TableColumn("Label") { s in
                    Text(s.id).font(.body.monospaced())
                }
                TableColumn("Runner") { s in
                    Text(s.runnerScript.lastPathComponent)
                }
                TableColumn("Trigger") { s in
                    Text(ScheduleTriggerFormatter.summary(for: s.trigger))
                }
                TableColumn("Status") { s in
                    statusDot(for: s)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingNewSheet = true
                    } label: {
                        Label("New Schedule", systemImage: "plus")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var commitErrorBanner: some View {
        if !service.commitErrors.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(service.commitErrors) { err in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Saved \(err.scheduleId) — git commit failed: \(err.stderr)")
                            .font(.callout)
                        Spacer()
                        Button("Dismiss") { service.dismissCommitError(err.id) }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.12))
        }
    }

    @ViewBuilder
    private func statusDot(for schedule: Schedule) -> some View {
        let hasDrift = service.drift.contains { $0.id == schedule.id }
        let color: Color = hasDrift ? .orange : .green
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}
