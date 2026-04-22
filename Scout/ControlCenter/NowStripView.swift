import SwiftUI

/// Three-up hero: Now · Today · Next up. Each column shares the same
/// typographic block — small uppercase label, large serif value, mono sub.
struct NowStripView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            column(label: "Now") { nowColumn }
            divider
            column(label: "Today") { todayColumn }
            divider
            column(label: "Next up") { nextColumn }
        }
        .editorialCard(padding: 18)
    }

    // MARK: - Column layout helper

    private func column<Content: View>(label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(DS.sans(10.5, weight: .medium))
                .tracking(0.08 * 10.5)
                .foregroundStyle(DS.Ink.p4)
                .padding(.bottom, 8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }

    private var divider: some View {
        Rectangle().fill(DS.Rule.soft).frame(width: 0.5)
            .padding(.vertical, 4)
    }

    // MARK: - Columns

    @ViewBuilder private var nowColumn: some View {
        let latest = state.sessionLogService.runs.first
        VStack(alignment: .leading, spacing: 4) {
            if let r = latest, r.status == .running {
                bigName(r.type.rawValue)
                sub("running · started \(r.startedAt.formatted(.relative(presentation: .named)))", color: DS.Status.warn)
            } else if let r = latest {
                bigName(r.type.rawValue)
                sub(
                    "\(tick(for: r.status)) \(r.status.rawValue) · \(r.startedAt.formatted(.relative(presentation: .named))) · \(r.commits.count) commit\(r.commits.count == 1 ? "" : "s")",
                    color: r.status == .success ? DS.Status.ok : DS.Status.err
                )
            } else {
                bigName("No runs yet")
                sub("Scout is quiet", color: DS.Ink.p4)
            }
        }
    }

    @ViewBuilder private var todayColumn: some View {
        let runs = todayRuns()
        let failures = runs.filter { [.failure, .timeout, .rateLimited].contains($0.status) }.count
        let total = runs.compactMap(\.cost).reduce(Decimal(0), +)
        VStack(alignment: .leading, spacing: 4) {
            bigName("\(runs.count) runs · \(failures) failed")
            sub("cost $\(total as NSDecimalNumber) · budget $8.00", color: DS.Ink.p3)
        }
    }

    @ViewBuilder private var nextColumn: some View {
        let next = state.scheduleService.upcoming.first
        VStack(alignment: .leading, spacing: 4) {
            if let u = next {
                bigName(u.type.rawValue)
                sub("in \(u.scheduledAt.formatted(.relative(presentation: .named))) · dispatcher armed", color: DS.Ink.p3)
            } else {
                bigName("No scheduled runs")
                sub("check LaunchAgents", color: DS.Status.warn)
            }
        }
    }

    // MARK: - Text atoms

    private func bigName(_ s: String) -> some View {
        Text(s)
            .font(DS.serif(22, weight: .medium))
            .foregroundStyle(DS.Ink.p1)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func sub(_ s: String, color: Color) -> some View {
        Text(s)
            .font(DS.mono(12))
            .foregroundStyle(color)
    }

    private func tick(for status: RunStatus) -> String {
        status == .success ? "✓" : status == .running ? "●" : "✗"
    }

    private func todayRuns() -> [Run] {
        let cal = Calendar.current
        return state.sessionLogService.runs.filter { cal.isDateInToday($0.startedAt) }
    }
}
