import SwiftUI

/// Preset-only snooze menu. Earlier revisions tried to ship a ``DatePicker``
/// seeded via ``State(initialValue:)`` in ``init``; on macOS 26 inside
/// ``.popover`` the wrapper would sometimes silently drop the seed and
/// ``picked`` would read as ``Date(timeIntervalSinceReferenceDate: 0)``
/// — formatted in ET that's ``2000-12-31``, which is what ``snooze.py``
/// saw on the command line. Quick presets avoid the whole class of bug
/// and are how snoozing usually gets used anyway.
struct SnoozePopoverView: View {
    let sourceDate: Date
    let onCommit: (Date) async -> Void
    let onCancel: () -> Void

    @State private var submitting = false

    private static let presets: [(label: String, days: Int)] = [
        ("Tomorrow",     1),
        ("In 3 days",    3),
        ("Next week",    7),
        ("In 2 weeks",   14),
        ("Next month",   30),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, 8)
            ForEach(Self.presets, id: \.label) { preset in
                row(label: preset.label, days: preset.days)
            }
            Divider().padding(.horizontal, 8)
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { _ in } // keeps default pointer
                .keyboardShortcut(.cancelAction)
        }
        .frame(width: 220)
        .padding(.vertical, 4)
    }

    private var header: some View {
        Text("Snooze until…")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 6)
    }

    private func row(label: String, days: Int) -> some View {
        Button {
            commit(days: days)
        } label: {
            HStack {
                Text(label).font(.system(size: 12))
                Spacer(minLength: 8)
                Text(relativeLabel(days: days))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(submitting)
    }

    private func commit(days: Int) {
        guard let target = Calendar(identifier: .iso8601)
            .date(byAdding: .day, value: days, to: sourceDate),
              target > sourceDate
        else { return }
        submitting = true
        Task { await onCommit(target) }
    }

    private func relativeLabel(days: Int) -> String {
        guard let d = Calendar(identifier: .iso8601)
            .date(byAdding: .day, value: days, to: sourceDate) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE MMM d"
        fmt.timeZone = TimeZone(identifier: "America/New_York")
        return fmt.string(from: d)
    }
}
