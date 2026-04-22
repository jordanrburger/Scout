import SwiftUI

/// Editorial status console. Two-column page on wide windows: a primary
/// column with the hero / schedule / heatmap / sessions, and a rail with
/// budget, repo state, signals, and keyboard hints.
struct ControlCenterView: View {
    @State private var dayFilter: Date? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    HStack(alignment: .top, spacing: 32) {
                        primaryColumn
                            .frame(maxWidth: .infinity, alignment: .leading)
                        rail
                            .frame(width: 320)
                    }
                }
                .frame(maxWidth: 1120, alignment: .leading)
                .padding(.horizontal, 42)
                .padding(.top, 28)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(DS.Paper.base)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Control Center")
                .font(DS.serif(28, weight: .medium))
                .foregroundStyle(DS.Ink.p1)
            Text("Status · Activity · Sessions")
                .font(DS.sans(14))
                .foregroundStyle(DS.Ink.p3)
            Spacer()
        }
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { EditorialRule() }
        .padding(.bottom, 24)
    }

    // MARK: - Columns

    private var primaryColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            NowStripView()
            UpcomingStripView()
            ActivityHeatmapView(dayFilter: $dayFilter)
            SessionsListView(dayFilter: dayFilter)
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 20) {
            BudgetRailCard()
            RepoStateRailCard()
            SignalsRailCard()
            KeyboardRailCard()
        }
    }
}

// MARK: - Rail cards

/// Small card header used throughout the rail.
private struct RailCardHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(DS.sans(11, weight: .medium))
            .tracking(0.06 * 11)
            .foregroundStyle(DS.Ink.p4)
            .padding(.bottom, 10)
    }
}

struct BudgetRailCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RailCardHeader(title: "Today's budget")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("$\(todayCost as NSDecimalNumber)")
                    .font(DS.serif(22, weight: .medium))
                    .foregroundStyle(DS.Ink.p1)
                Text("/ $\(dailyCap as NSDecimalNumber)")
                    .font(DS.mono(13))
                    .foregroundStyle(DS.Ink.p4)
            }
            progressBar(fraction: CGFloat(truncating: fraction as NSNumber))
                .padding(.top, 10)
            Text(monthlySummary)
                .font(DS.mono(11.5))
                .foregroundStyle(DS.Ink.p3)
                .padding(.top, 6)
        }
        .editorialCard(padding: 16)
    }

    private var todayCost: Decimal {
        let cal = Calendar.current
        return state.sessionLogService.runs
            .filter { cal.isDateInToday($0.startedAt) }
            .compactMap(\.cost)
            .reduce(Decimal(0), +)
    }
    private var dailyCap: Decimal { 8 }
    private var fraction: Decimal {
        min(1, todayCost / dailyCap)
    }
    private var monthlySummary: String {
        let cal = Calendar.current
        let month = state.sessionLogService.runs
            .filter { cal.isDate($0.startedAt, equalTo: Date(), toGranularity: .month) }
            .compactMap(\.cost)
            .reduce(Decimal(0), +)
        return "Monthly: $\(month as NSDecimalNumber) / $250.00 · on track"
    }

    private func progressBar(fraction: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(DS.Paper.sunk)
                RoundedRectangle(cornerRadius: 3)
                    .fill(DS.Status.ok)
                    .frame(width: max(4, geo.size.width * max(0, min(1, fraction))))
            }
        }
        .frame(height: 5)
    }
}

struct RepoStateRailCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RailCardHeader(title: "Repo state")
            row("path",     "~/Scout",  DS.Ink.p1)
            row("branch",   "main",     DS.Ink.p1)
            row("obsidian", "mirrored", DS.Status.ok)
        }
        .editorialCard(padding: 16)
    }

    private func row(_ key: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(key)
                .font(DS.sans(12))
                .foregroundStyle(DS.Ink.p3)
            Spacer()
            Text(value)
                .font(DS.mono(12))
                .foregroundStyle(color)
        }
    }
}

struct SignalsRailCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RailCardHeader(title: "Signals")
            signalRow(
                color: DS.Status.err,
                tag: "ANTHROPIC API",
                body: "Check live status — top-up / cap-raise may be needed."
            )
            divider
            signalRow(
                color: DS.Status.warn,
                tag: "RESEARCH",
                body: "No schedule configured — heartbeat skips research every dispatch."
            )
            divider
            signalRow(
                color: DS.Status.ok,
                tag: "DREAMING",
                body: "Overnight run completed — see Sessions for commits + cost."
            )
            .padding(.bottom, 0)
        }
        .editorialCard(padding: 16)
    }

    private var divider: some View {
        EditorialRule().padding(.vertical, 8)
    }

    private func signalRow(color: Color, tag: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(tag)
                    .font(DS.mono(11, weight: .medium))
                    .foregroundStyle(color)
            }
            Text(body)
                .font(DS.sans(13))
                .foregroundStyle(DS.Ink.p2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct KeyboardRailCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RailCardHeader(title: "Keyboard")
            kb("⌘1", "Control Center")
            kb("⌘2", "Action Items")
            kb("⌘R", "Run briefing now")
            kb("⌘K", "Quick find")
            kb("⌘↵", "Mark done (on task)")
        }
        .editorialCard(padding: 16)
    }

    private func kb(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(DS.mono(12, weight: .medium))
                .foregroundStyle(DS.Ink.p2)
                .frame(width: 32, alignment: .leading)
            Text(label)
                .font(DS.sans(12.5))
                .foregroundStyle(DS.Ink.p3)
            Spacer()
        }
    }
}
