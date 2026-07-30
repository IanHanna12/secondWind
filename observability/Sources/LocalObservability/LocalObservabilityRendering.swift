import Foundation

public struct DefaultPrometheusMetricsRenderer: PrometheusMetricsRendering {
    public init() {}

    public func render(snapshot: LocalObservabilitySnapshot) -> String {
        var lines: [String] = []
        gauge(&lines, "secondwind_storage_bytes", snapshot.inventory.observedBytes, "Storage understood by the latest completed Second Wind scan.")
        gauge(&lines, "secondwind_storage_items", snapshot.inventory.entryCount, "Storage items understood by the latest completed scan.")
        gauge(&lines, "secondwind_reviewable_items", snapshot.inventory.cleanupEligibleEntryCount, "Items ready for Second Wind's reviewed cleanup workflow.")
        gauge(&lines, "secondwind_protected_items", snapshot.inventory.protectedEntryCount, "Items protected from cleanup.")
        for category in snapshot.inventory.categories {
            gauge(&lines, "secondwind_category_storage_bytes", category.observedBytes, "Storage understood in each fixed Second Wind category.", labels: ["category": category.category])
            gauge(&lines, "secondwind_category_items", category.entryCount, "Items understood in each fixed Second Wind category.", labels: ["category": category.category])
            gauge(&lines, "secondwind_category_change_bytes", category.deltaBytes, "Storage change since the previous snapshot by category.", labels: ["category": category.category])
        }
        gauge(&lines, "secondwind_completed_scans", snapshot.scan.completedCount, "Completed scans recorded in local activity.")
        gauge(&lines, "secondwind_recorded_failures", snapshot.scan.failedCount, "Failures recorded in local activity.")
        gauge(&lines, "secondwind_recorded_cancellations", snapshot.scan.cancelledCount, "Cancellations recorded in local activity.")
        gauge(&lines, "secondwind_recovery_bytes", snapshot.recovery.bytes, "Bytes currently stored in local Recovery.")
        gauge(
            &lines,
            "secondwind_recovery_entries",
            snapshot.recovery.itemCount,
            "Independent entries currently stored in local Recovery. A directory and all of its contents count as one entry."
        )
        if let oldestItemAgeSeconds = snapshot.recovery.oldestItemAgeSeconds {
            gauge(&lines, "secondwind_recovery_oldest_item_age_seconds", oldestItemAgeSeconds, "Age of the oldest local Recovery item in seconds.")
        }
        gauge(&lines, "secondwind_completed_cleanups", snapshot.cleanup.executionCount, "Completed cleanup actions recorded in local activity.")
        gauge(&lines, "secondwind_cleaned_bytes", snapshot.cleanup.completedBytes, "Storage moved by completed cleanup actions.")
        gauge(&lines, "secondwind_trashed_bytes", snapshot.cleanup.trashBytes, "Storage moved to Finder Trash by completed cleanup actions.")
        gauge(&lines, "secondwind_recovery_moved_bytes", snapshot.cleanup.recoveryBytes, "Storage moved into local Recovery by completed cleanup actions.")
        if let applications = snapshot.applications {
            gauge(&lines, "secondwind_application_linked_items", applications.associatedEntryCount, "Items linked to applications without exporting application identities.")
            gauge(&lines, "secondwind_application_storage_bytes", applications.observedBytes, "Storage linked to applications without exporting application identities.")
            gauge(&lines, "secondwind_application_change_bytes", applications.deltaBytes, "Storage change linked to applications without exporting application identities.")
        }
        gauge(&lines, "secondwind_snapshot_updated_at_seconds", snapshot.generatedAt.timeIntervalSince1970, "Unix timestamp when the local observability snapshot was refreshed.")
        return lines.joined(separator: "\n") + "\n"
    }

    private func gauge<T: BinaryInteger>(_ lines: inout [String], _ name: String, _ value: T, _ help: String, labels: [String: String] = [:]) {
        metricPrefix(&lines, name, help)
        lines.append("\(name)\(labelText(labels)) \(value)")
    }

    private func gauge(_ lines: inout [String], _ name: String, _ value: TimeInterval, _ help: String, labels: [String: String] = [:]) {
        metricPrefix(&lines, name, help)
        let formattedValue = String(format: "%.3f", value)
        lines.append("\(name)\(labelText(labels)) \(formattedValue)")
    }

    private func metricPrefix(_ lines: inout [String], _ name: String, _ help: String) {
        lines.append("# HELP \(name) \(help)")
        lines.append("# TYPE \(name) gauge")
    }

    private func labelText(_ labels: [String: String]) -> String {
        guard !labels.isEmpty else { return "" }
        let values = labels.sorted { $0.key < $1.key }.map { key, value in
            let escapedValue = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\(key)=\"\(escapedValue)\""
        }
        return "{\(values.joined(separator: ","))}"
    }
}

public struct DefaultObservabilityJSONRenderer: ObservabilityJSONRendering {
    private let encoder: JSONEncoder

    public init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    public func health(snapshot: LocalObservabilitySnapshot?) throws -> Data {
        try encoder.encode(HealthResponse(snapshot: snapshot))
    }

    public func summary(snapshot: LocalObservabilitySnapshot) throws -> Data {
        try encoder.encode(snapshot)
    }

    public func latestDelta(snapshot: LocalObservabilitySnapshot) throws -> Data {
        try encoder.encode(snapshot.delta)
    }
}

private struct HealthResponse: Codable {
    let status: String
    let generatedAt: Date?
    let lastCompletedScanAt: Date?
    let snapshotAvailable: Bool

    init(snapshot: LocalObservabilitySnapshot?) {
        status = snapshot == nil ? "waiting_for_snapshot" : "ok"
        generatedAt = snapshot?.generatedAt
        lastCompletedScanAt = snapshot?.scan.lastCompletedAt
        snapshotAvailable = snapshot != nil
    }
}
