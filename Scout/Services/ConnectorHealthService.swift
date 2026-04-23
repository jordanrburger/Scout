import Foundation
import Combine
import SwiftUI

/// Loads `.scout-logs/connector-calls-*.jsonl` and `connector-alerts.log`
/// from the given logs directory and publishes:
/// 1. A `ConnectorHealthMatrix` (connectors × recent sessions).
/// 2. `activeAlerts`: non-acked `ConnectorAlert`s from the log.
///
/// Shell scripts remain the source of truth for *which* alerts should fire
/// (`connector-health-report.sh` owns the 14-day sustained-state logic).
/// This service does not re-implement that logic — it only reads and
/// renders.
@MainActor
final class ConnectorHealthService: ObservableObject {
    @Published private(set) var matrix: ConnectorHealthMatrix
    @Published private(set) var activeAlerts: [ConnectorAlert] = []

    private let logsDirectory: URL
    private let ackStore: ConnectorAckStore
    private let fileEvents: any FileSystemEventSource
    private let connectors: [String]
    private var watchTask: Task<Void, Never>?

    init(
        logsDirectory: URL,
        ackStoreURL: URL,
        fileEvents: any FileSystemEventSource,
        connectors: [String] = ConnectorHealthService.defaultConnectors
    ) {
        self.logsDirectory = logsDirectory
        self.ackStore = ConnectorAckStore(fileURL: ackStoreURL)
        self.fileEvents = fileEvents
        self.connectors = connectors
        self.matrix = ConnectorHealthMatrix(calls: [], connectors: connectors)
    }

    /// The 8 connectors tracked by `~/Scout/scripts/connector-health-report.sh:29-41`.
    /// Keep in sync with the shell side (manual diff until someone pays the
    /// test-double cost of end-to-end verification).
    static let defaultConnectors: [String] = [
        "mcp:plugin_slack_slack",
        "mcp:plugin_linear_linear",
        "mcp:claude_ai_Gmail",
        "mcp:claude_ai_Google_Calendar",
        "mcp:claude_ai_Granola",
        "mcp:claude_ai_Google_Drive",
        "github",
        "mcp:claude-in-chrome"
    ]

    func loadInitial() async throws {
        await refresh()
        startWatching()
    }

    func acknowledge(fingerprint: String) {
        ackStore.ack(fingerprint: fingerprint)
        recomputeActiveAlerts(all: allAlertsFromLog())
    }

    // MARK: - Internals

    private func refresh() async {
        // 1. Matrix from all connector-calls-*.jsonl in logsDirectory within 14d window.
        let calls = await loadCallsWithinWindow()
        matrix = ConnectorHealthMatrix(calls: calls, connectors: connectors)
        // 2. Alerts from connector-alerts.log.
        let all = allAlertsFromLog()
        recomputeActiveAlerts(all: all)
        // 3. GC ack store against the live fingerprint set.
        ackStore.gc(active: Set(all.map(\.fingerprint)))
    }

    private func allAlertsFromLog() -> [ConnectorAlert] {
        let url = logsDirectory.appendingPathComponent("connector-alerts.log")
        return ConnectorAlert.parseFile(at: url)
    }

    private func recomputeActiveAlerts(all: [ConnectorAlert]) {
        // Deduplicate: keep latest ts per (connector, level).
        var latest: [String: ConnectorAlert] = [:]
        for a in all {
            let key = "\(a.connector)|\(a.level.rawValue)"
            if let existing = latest[key], existing.ts >= a.ts { continue }
            latest[key] = a
        }
        activeAlerts = latest.values
            .filter { !ackStore.isAcked($0.fingerprint) }
            .sorted { $0.ts > $1.ts }
    }

    private func loadCallsWithinWindow() async -> [ConnectorCall] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let jsonlURLs = entries.filter {
            let name = $0.lastPathComponent
            return name.hasPrefix("connector-calls-") && name.hasSuffix(".jsonl")
        }
        let windowStart = Date().addingTimeInterval(-14 * 24 * 3600)
        return await Task.detached { () -> [ConnectorCall] in
            var out: [ConnectorCall] = []
            for url in jsonlURLs {
                out.append(contentsOf: ConnectorCall.parseFile(at: url)
                    .filter { $0.ts >= windowStart })
            }
            return out
        }.value
    }

    private func startWatching() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.fileEvents.events(for: self.logsDirectory) {
                let name = event.url.lastPathComponent
                let relevant = name.hasPrefix("connector-calls-")
                    || name == "connector-alerts.log"
                if relevant { await self.refresh() }
            }
        }
    }
}
