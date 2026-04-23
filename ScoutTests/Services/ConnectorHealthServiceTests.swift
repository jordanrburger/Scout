import Testing
import Foundation
@testable import Scout

@Suite("ConnectorHealthService")
struct ConnectorHealthServiceTests {
    @Test func buildsMatrixFromFixtureAndFiltersAckedAlerts() async throws {
        let fixtures = Bundle(for: FixtureAnchor.self).resourceURL!
        let logsDir = fixtures.appendingPathComponent("Connector_fixture_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: logsDir) }

        // Copy the two fixtures into a temp logsDir so the service sees them.
        try FileManager.default.copyItem(
            at: fixtures.appendingPathComponent("connector-calls-2026-04-22.jsonl"),
            to: logsDir.appendingPathComponent("connector-calls-2026-04-22.jsonl")
        )
        try FileManager.default.copyItem(
            at: fixtures.appendingPathComponent("connector-alerts.log"),
            to: logsDir.appendingPathComponent("connector-alerts.log")
        )

        let ackURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-acked.json")
        defer { try? FileManager.default.removeItem(at: ackURL) }

        let service = await ConnectorHealthService(
            logsDirectory: logsDir,
            ackStoreURL: ackURL,
            fileEvents: NoopFS(),
            connectors: ["mcp:plugin_slack_slack",
                         "mcp:claude_ai_Gmail",
                         "mcp:claude_ai_Google_Drive"]
        )
        try await service.loadInitial()
        let matrix = await service.matrix
        #expect(matrix.sessionsNewestFirst.count == 3)

        // The fixture log has one active CRITICAL (Drive).
        let active = await service.activeAlerts
        #expect(active.count == 1)
        #expect(active.first?.connector == "mcp:claude_ai_Google_Drive")

        // Acknowledge it → activeAlerts is empty.
        let fp = active.first!.fingerprint
        await service.acknowledge(fingerprint: fp)
        #expect(await service.activeAlerts.isEmpty)
    }
}
