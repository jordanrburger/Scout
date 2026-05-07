import Foundation

/// View mode for the Schedules tab — Table (default), Cards, or Timeline.
/// Persists across app launches via `@SceneStorage("schedulesView")`.
enum SchedulesViewMode: String, CaseIterable, Identifiable, Hashable {
    case table
    case cards
    case timeline

    var id: String { rawValue }

    /// The default view when no scene-storage value exists.
    static let `default`: SchedulesViewMode = .table

    /// Timeline is reserved for a future plan; the segmented picker still
    /// shows the segment, but selection routes to a placeholder pane.
    var isAvailable: Bool {
        switch self {
        case .table, .cards: return true
        case .timeline:      return false
        }
    }

    /// Display label for the segmented picker.
    var displayName: String {
        switch self {
        case .table:    return "Table"
        case .cards:    return "Cards"
        case .timeline: return "Timeline"
        }
    }
}
