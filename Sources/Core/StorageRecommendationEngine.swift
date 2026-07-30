import Foundation

/// Deterministic, local recommendation rules for known inventory entries.
/// Recommendations describe why an item is worth reviewing; they never select
/// an item or authorize a cleanup action.
public struct StorageRecommendation: Identifiable, Sendable {
    public let entry: StorageInventoryEntry
    public let title: String
    public let detail: String
    public let reasons: [String]

    public var id: String { entry.key }
}

public struct StorageRecommendationEngine: Sendable {
    private let largeItemThreshold: Int64 = 500 * 1_024 * 1_024
    private let ageThreshold: TimeInterval = 120 * 24 * 60 * 60

    public init() {}

    public func recommendations(for inventory: StorageInventory, now: Date = Date()) -> [StorageRecommendation] {
        inventory.entries.compactMap { entry in
            guard entry.isActionable, entry.byteSize >= largeItemThreshold else { return nil }
            if entry.category == .developerStorage {
                return StorageRecommendation(
                    entry: entry,
                    title: "Large developer storage",
                    detail: "\(formattedBytes(entry.byteSize)) is known developer storage. \(entry.explanation) Review it before creating a cleanup plan.",
                    reasons: [
                        "Located in the Developer Storage category.",
                        "Uses \(formattedBytes(entry.byteSize)) of known storage.",
                        entry.explanation,
                        "Supports \(actionDescription(entry.supportedAction))."
                    ]
                )
            }
            if (entry.category == .downloads || entry.category == .documents),
               let modifiedAt = entry.modifiedAt,
               now.timeIntervalSince(modifiedAt) >= ageThreshold {
                let days = Int(now.timeIntervalSince(modifiedAt) / (24 * 60 * 60))
                return StorageRecommendation(
                    entry: entry,
                    title: "Older large file",
                    detail: "\(formattedBytes(entry.byteSize)) was last modified \(days) days ago. Its content is not assumed disposable; review it deliberately.",
                    reasons: [
                        "Uses \(formattedBytes(entry.byteSize)) of known storage.",
                        "Last modified \(days) days ago.",
                        "Matches an explicit cleanup rule; it is never selected automatically."
                    ]
                )
            }
                return StorageRecommendation(
                    entry: entry,
                    title: "Large reviewed cleanup candidate",
                    detail: "\(formattedBytes(entry.byteSize)) is explicitly covered by \(entry.origin). \(entry.explanation)",
                    reasons: [
                        "Uses \(formattedBytes(entry.byteSize)) of known storage.",
                        "Observed by \(entry.provider).",
                        entry.ruleID.map { "Matches rule \($0)\(entry.ruleVersion.map { " v\($0)" } ?? "")." } ?? "Has no cleanup rule.",
                        entry.explanation
                    ]
                )
        }
        .sorted { $0.entry.byteSize > $1.entry.byteSize }
        .prefix(5)
        .map { $0 }
    }

    private func formattedBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func actionDescription(_ action: SupportedAction) -> String {
        switch action {
        case .none: return "no cleanup action"
        case .cleanup: return "Recovery or Finder Trash after review"
        case .uninstall: return "the reviewed application-removal workflow"
        }
    }
}
