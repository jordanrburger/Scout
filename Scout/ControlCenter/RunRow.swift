import SwiftUI

/// Editorial session row: status icon → name/when → status → commits → cost.
/// No boxes; hairline rules do the separation.
struct RunRow: View {
    let run: Run

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.type.rawValue)
                    .font(DS.sans(13, weight: .medium))
                    .foregroundStyle(DS.Ink.p1)
                Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(DS.mono(11.5))
                    .foregroundStyle(DS.Ink.p4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            statusCell
                .frame(width: 100, alignment: .leading)
            Text(commitsString)
                .font(DS.mono(11.5, weight: .medium))
                .foregroundStyle(DS.Ink.p3)
                .frame(width: 90, alignment: .trailing)
            Text(costString)
                .font(DS.mono(11.5))
                .foregroundStyle(DS.Ink.p3)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { EditorialRule() }
        .contentShape(Rectangle())
    }

    private var statusCell: some View {
        HStack(spacing: 5) {
            if run.status == .running {
                Circle().fill(DS.Status.warn).frame(width: 6, height: 6)
            }
            Text(run.status.rawValue)
                .font(DS.mono(11, weight: .medium))
                .tracking(0.02 * 11)
                .foregroundStyle(statusColor)
        }
    }

    private var commitsString: String {
        run.commits.isEmpty ? "—" : "\(run.commits.count) commit\(run.commits.count == 1 ? "" : "s")"
    }

    private var costString: String {
        run.cost.map { "$\($0 as NSDecimalNumber)" } ?? "—"
    }

    private var iconName: String {
        switch run.status {
        case .success:            return "checkmark.circle"
        case .failure, .timeout:  return "exclamationmark.triangle"
        case .running:            return "circle.dotted"
        case .orphaned:           return "questionmark.circle"
        case .rateLimited:        return "hourglass"
        case .skippedBudget:      return "pause.circle"
        case .skippedConcurrency: return "lock.circle"
        case .scheduled:          return "clock"
        }
    }

    private var iconColor: Color {
        switch run.status {
        case .success:                                   return DS.Status.ok
        case .failure, .timeout, .rateLimited:           return DS.Status.err
        case .running:                                   return DS.Status.warn
        default:                                         return DS.Ink.p3
        }
    }

    private var statusColor: Color {
        switch run.status {
        case .success:                                   return DS.Status.ok
        case .failure, .timeout, .rateLimited:           return DS.Status.err
        case .running:                                   return DS.Status.warn
        default:                                         return DS.Ink.p3
        }
    }
}
