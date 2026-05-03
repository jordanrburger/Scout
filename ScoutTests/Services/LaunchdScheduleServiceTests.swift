import Testing
import Foundation
@testable import Scout

@Suite("LaunchdScheduleService")
struct LaunchdScheduleServiceTests {

    @Test func parsesRealBriefingPlist() throws {
        let url = Bundle(for: FixtureAnchor.self).url(forResource: "com.scout.briefing", withExtension: "plist")!
        let entries = try LaunchdScheduleService.parsePlist(at: url)
        #expect(!entries.isEmpty)
        // briefing.plist uses launchd weekday 1-5 (Mon-Fri).
        // After Calendar conversion via PlistIO: Monday=2, Friday=6.
        #expect(entries.contains { $0.weekday == 2 && $0.hour == 8 && $0.minute == 3 })
        #expect(entries.first?.label == "com.scout.briefing")
    }

    @Test func nextFiresHonorWeekday() {
        let entries = [
            LaunchdScheduleService.CalendarEntry(label: "com.scout.briefing", weekday: 2, hour: 8, minute: 3),
            LaunchdScheduleService.CalendarEntry(label: "com.scout.briefing", weekday: 4, hour: 11, minute: 3)
        ]
        // "Now" = Sunday 2026-04-19 13:00 ET
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 19; c.hour = 13; c.minute = 0
        c.timeZone = TimeZone(identifier: "America/New_York")
        let now = Calendar(identifier: .gregorian).date(from: c)!
        let fires = LaunchdScheduleService.nextFires(
            from: entries,
            after: now,
            limit: 3,
            timeZone: TimeZone(identifier: "America/New_York")!
        )
        #expect(fires.count == 3)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let firstComps = cal.dateComponents([.weekday, .hour, .minute], from: fires[0].scheduledAt)
        #expect(firstComps.weekday == 2) // Monday
        #expect(firstComps.hour == 8)
        #expect(firstComps.minute == 3)
    }
}
