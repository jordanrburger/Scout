import Foundation
import Combine
import SwiftUI

@MainActor
final class LaunchdScheduleService: ObservableObject {
    @Published private(set) var upcoming: [UpcomingRun] = []

    struct CalendarEntry: Equatable, Sendable {
        let label: String
        let weekday: Int?   // Calendar convention: 1=Sun ... 7=Sat. nil means every day.
        let hour: Int
        let minute: Int
    }

    private let agentsDirectory: URL
    private let fileEvents: any FileSystemEventSource
    private let clock: any ClockSource
    private var tickTimer: Timer?
    private var watchTask: Task<Void, Never>?

    init(
        agentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents"),
        fileEvents: any FileSystemEventSource,
        clock: any ClockSource = SystemClock()
    ) {
        self.agentsDirectory = agentsDirectory
        self.fileEvents = fileEvents
        self.clock = clock
    }

    func loadInitial() {
        recompute()
        startWatching()
        startTicker()
    }

    nonisolated static func parsePlist(at url: URL) throws -> [CalendarEntry] {
        let schedule = try PlistIO.readSchedule(from: url)
        switch schedule.trigger {
        case .calendar(let fires):
            return fires.map { fire in
                CalendarEntry(
                    label: schedule.label,
                    weekday: fire.weekday,
                    hour: fire.hour,
                    minute: fire.minute
                )
            }
        case .interval:
            // Interval-based triggers (heartbeat) don't belong in the upcoming strip.
            return []
        }
    }

    nonisolated static func nextFires(
        from entries: [CalendarEntry],
        after now: Date,
        limit: Int
    ) -> [UpcomingRun] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!

        var results: [UpcomingRun] = []
        var cursor = now
        let maxIterations = max(limit * 10, 20)
        for _ in 0..<maxIterations {
            let upcomingFires: [(Date, CalendarEntry)] = entries.compactMap { entry in
                nextFireForEntry(entry, after: cursor, calendar: cal).map { ($0, entry) }
            }
            guard let (soonest, entry) = upcomingFires.min(by: { $0.0 < $1.0 }) else { break }
            let type = inferRunType(fromLabel: entry.label, date: soonest)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            let upc = UpcomingRun(
                id: "\(type.rawValue)-\(iso.string(from: soonest))",
                type: type,
                scheduledAt: soonest,
                plistLabel: entry.label
            )
            results.append(upc)
            cursor = soonest.addingTimeInterval(1)
            if results.count >= limit { break }
        }
        return results
    }

    nonisolated private static func nextFireForEntry(
        _ entry: CalendarEntry,
        after start: Date,
        calendar: Calendar
    ) -> Date? {
        var comps = DateComponents()
        comps.hour = entry.hour
        comps.minute = entry.minute
        if let w = entry.weekday { comps.weekday = w }
        return calendar.nextDate(
            after: start,
            matching: comps,
            matchingPolicy: .nextTime
        )
    }

    nonisolated private static func inferRunType(fromLabel label: String, date: Date) -> RunType {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let hour = cal.component(.hour, from: date)
        let weekday = cal.component(.weekday, from: date)
        let isWeekend = (weekday == 1 || weekday == 7)

        if label.contains("briefing") {
            if isWeekend { return .weekendBriefing }
            switch hour {
            case 8:  return .morningBriefing
            case 11: return .consolidation11am
            case 13: return .consolidation1pm
            case 17: return .consolidation5pm
            case 19: return .consolidation7pm
            default: return .manual
            }
        }
        if label.contains("consolidation") { return .consolidation7pm }
        if label.contains("dreaming") {
            if isWeekend && hour == 6 { return .dreamingWeekend6am }
            if isWeekend && hour == 7 { return .dreamingWeekend7am }
            return .dreamingNightly
        }
        return .manual
    }

    private func recompute() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: agentsDirectory, includingPropertiesForKeys: nil) else {
            upcoming = []
            return
        }
        var all: [CalendarEntry] = []
        for url in files where url.lastPathComponent.hasPrefix("com.scout.") && url.pathExtension == "plist" {
            if let parsed = try? Self.parsePlist(at: url) {
                all.append(contentsOf: parsed)
            }
        }
        upcoming = Self.nextFires(from: all, after: clock.now(), limit: 20)
    }

    private func startWatching() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.fileEvents.events(for: self.agentsDirectory) {
                if event.url.lastPathComponent.hasPrefix("com.scout.") {
                    self.recompute()
                }
            }
        }
    }

    private func startTicker() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
    }
}
