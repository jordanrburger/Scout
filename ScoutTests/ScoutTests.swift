//
//  ScoutTests.swift
//  ScoutTests
//

import Testing
import Foundation

struct ScoutTests {

    @Test func fixturesAreAccessible() throws {
        let bundle = Bundle(for: FixtureAnchor.self)
        // Try finding individual fixtures — if any work, we're good.
        let trackerURL = bundle.url(forResource: "usage-tracker", withExtension: "jsonl")
        #expect(trackerURL != nil, "usage-tracker.jsonl should be in the test bundle")

        // The Fixtures directory may or may not be preserved as a folder —
        // depends on Xcode's resource handling. We check both.
        let fixturesDir = bundle.url(forResource: "Fixtures", withExtension: nil)
        let hasFolder = fixturesDir.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if !hasFolder {
            // Flat resource layout — still acceptable for tests that look up by name
            let logsURL = bundle.url(forResource: "scout-2026-04-19_08-08", withExtension: "log")
            #expect(logsURL != nil, "at minimum individual fixtures should be reachable")
        }
    }
}

final class FixtureAnchor {}
