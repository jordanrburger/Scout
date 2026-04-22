import SwiftUI

/// 12-month activity grid. Cells are tinted by `DS.Status.ok`. Editorial
/// header + legend; failures are marked with a tiny red overlay dot.
struct ActivityHeatmapView: View {
    @EnvironmentObject var state: AppState
    @Binding var dayFilter: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            let cells = buildCells()
            let weeks = stride(from: 0, to: cells.count, by: 7).map {
                Array(cells[$0..<min($0 + 7, cells.count)])
            }
            HStack(alignment: .top, spacing: 3) {
                ForEach(weeks.indices, id: \.self) { wi in
                    VStack(spacing: 3) {
                        ForEach(weeks[wi], id: \.date) { cell in
                            cellView(cell)
                        }
                    }
                }
            }
            legend
                .padding(.top, 10)
        }
        .editorialCard(padding: 18)
    }

    private var header: some View {
        HStack {
            Text("Activity — last 12 months".uppercased())
                .font(DS.sans(11, weight: .medium))
                .tracking(0.06 * 11)
                .foregroundStyle(DS.Ink.p4)
            Spacer()
        }
        .padding(.bottom, 14)
    }

    private func cellView(_ cell: HeatmapCell) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color(for: cell))
            .frame(width: 10, height: 10)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(DS.Status.err)
                    .frame(width: 3, height: 3)
                    .opacity(cell.hasFailure ? 1 : 0)
                    .offset(x: 2, y: -2)
            }
            .overlay {
                if dayFilter.map({ Calendar.current.isDate($0, inSameDayAs: cell.date) }) ?? false {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(DS.Accent.ink, lineWidth: 1.25)
                }
            }
            .onTapGesture {
                dayFilter = (dayFilter.map { Calendar.current.isDate($0, inSameDayAs: cell.date) } ?? false)
                    ? nil : cell.date
            }
            .help("""
            \(cell.date.formatted(.dateTime.year().month().day())) · \
            \(cell.successes) ✓ · \(cell.failures) ✗ · $\(cell.cost as NSDecimalNumber)
            """)
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(DS.mono(11))
                .foregroundStyle(DS.Ink.p4)
            ForEach(legendSwatches, id: \.0) { _, c in
                RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            }
            Text("More")
                .font(DS.mono(11))
                .foregroundStyle(DS.Ink.p4)
            Spacer()
            Text("\(totalSessions) sessions · 12 mo")
                .font(DS.mono(11))
                .foregroundStyle(DS.Ink.p3)
        }
    }

    private var legendSwatches: [(String, Color)] {
        [
            ("0", DS.Paper.sunk),
            ("1", DS.Status.ok.opacity(0.22)),
            ("2", DS.Status.ok.opacity(0.45)),
            ("3", DS.Status.ok.opacity(0.70)),
            ("4", DS.Status.ok),
        ]
    }

    private func color(for c: HeatmapCell) -> Color {
        switch c.successes {
        case 0:     return DS.Paper.sunk
        case 1...2: return DS.Status.ok.opacity(0.22)
        case 3...4: return DS.Status.ok.opacity(0.45)
        case 5...6: return DS.Status.ok.opacity(0.70)
        default:    return DS.Status.ok
        }
    }

    private var totalSessions: Int {
        state.sessionLogService.runs.count
    }

    private struct HeatmapCell {
        let date: Date
        let successes: Int
        let failures: Int
        let cost: Decimal
        var hasFailure: Bool { failures > 0 }
    }

    private func buildCells() -> [HeatmapCell] {
        let runs = state.sessionLogService.runs
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -364, to: today)!
        return (0...364).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: start)!
            let dayRuns = runs.filter { cal.isDate($0.startedAt, inSameDayAs: day) }
            let ok = dayRuns.filter { $0.status == .success }.count
            let bad = dayRuns.filter {
                [.failure, .timeout, .rateLimited].contains($0.status)
            }.count
            let cost = dayRuns.compactMap(\.cost).reduce(Decimal(0), +)
            return HeatmapCell(date: day, successes: ok, failures: bad, cost: cost)
        }
    }
}
