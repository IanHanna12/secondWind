import Foundation
import SecondWindCore

/// A chronological, UI-neutral view of recovery items and completed cleanup
/// activity. Scan records stay in scan history rather than duplicating here.
public struct RecoveryTimelineDay: Identifiable, Sendable {
    public let date: Date
    public let events: [RecoveryTimelineEvent]

    public var id: Date { date }
}

public enum RecoveryTimelineEvent: Identifiable, Sendable {
    case recoveryItem(RecoveryItem)
    case activity(AuditRecord)

    public var id: String {
        switch self {
        case let .recoveryItem(item): return "recovery|\(item.id.uuidString)"
        case let .activity(record): return "audit|\(record.id.uuidString)"
        }
    }

    public var timestamp: Date {
        switch self {
        case let .recoveryItem(item): return item.createdAt
        case let .activity(record): return record.timestamp
        }
    }
}

public struct RecoveryTimelineBuilder: Builder {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func build(recoveryItems: [RecoveryItem], auditRecords: [AuditRecord]) -> [RecoveryTimelineDay] {
        let recoveryEvents = recoveryItems.map(RecoveryTimelineEvent.recoveryItem)
        let activityEvents = auditRecords
            .filter { record in
                switch record.kind {
                case .dryRun, .executionStarted, .executionFinished, .manualTrash, .restore, .permanentDelete, .failure:
                    return true
                case .scan, .preference, .maintenance:
                    return false
                }
            }
            .map(RecoveryTimelineEvent.activity)
        let eventsByDay = Dictionary(grouping: recoveryEvents + activityEvents) {
            calendar.startOfDay(for: $0.timestamp)
        }

        return eventsByDay
            .map { date, events in
                RecoveryTimelineDay(date: date, events: events.sorted { $0.timestamp > $1.timestamp })
            }
            .sorted { $0.date > $1.date }
    }
}
