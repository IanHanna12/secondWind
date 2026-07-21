import SwiftUI
import SecondWindCore
import SecondWindApplication

struct RecoveryActivityScreen: View {
    let model: SecondWindViewModel
    @State private var itemPendingPermanentDeletion: RecoveryItem?
    @State private var showsAllTimelineEvents = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Recovery & activity").font(.largeTitle.bold())
                    Text("Restore locally stored items or review the local record of every meaningful action.").foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Export") {
                    Button("JSON") { model.exportAudit(.json) }
                    Button("Markdown") { model.exportAudit(.markdown) }
                }
                Button("Refresh") { model.refreshActivity() }
            }
            List {
                Section("Recovery storage") {
                    if model.recoveryItems.isEmpty {
                        ContentUnavailableView("Nothing in Recovery", systemImage: "checkmark.shield", description: Text("Items stored here remain available to restore and are never deleted automatically."))
                    }
                    else {
                        ForEach(model.recoveryItems) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(URL(fileURLWithPath: item.originalPath).lastPathComponent).font(.headline)
                                    Text("Original: \(item.originalPath)")
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(item.originalPath)
                                    Text("Recovery reference: \(item.id.uuidString)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text("Stored \(item.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(item.needsReview ? "Review required; never auto-deleted" : "Available for restore until \(item.reviewAfter.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Restore") { model.restore(item) }
                                Button("Delete", role: .destructive) {
                                    itemPendingPermanentDeletion = item
                                }
                            }
                        }
                    }
                }
                RecoveryTimelineSection(
                    days: RecoveryTimelineBuilder().build(
                        recoveryItems: model.recoveryItems,
                        auditRecords: model.auditRecords
                    ),
                    showsAllEvents: $showsAllTimelineEvents
                )
                Section("Local activity") {
                    if model.auditRecords.isEmpty { Text("Your first scan will appear here.").foregroundStyle(.secondary) }
                    ForEach(model.auditRecords) { record in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(record.kind.rawValue) — \(record.result)")
                            Text(record.timestamp.formatted()).font(.caption).foregroundStyle(.secondary)
                            if !record.ruleVersions.isEmpty {
                                Text("Rules: \(record.ruleVersions.joined(separator: ", "))")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .padding(32)
        .confirmationDialog(
            "Delete this item permanently?",
            isPresented: Binding(
                get: { itemPendingPermanentDeletion != nil },
                set: { if !$0 { itemPendingPermanentDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) {
                if let item = itemPendingPermanentDeletion {
                    model.deletePermanently(item)
                }
                itemPendingPermanentDeletion = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \(itemPendingPermanentDeletion?.originalPath ?? "this item") from Recovery. It cannot be restored or undone.")
        }
    }
}

private struct RecoveryTimelineSection: View {
    let days: [RecoveryTimelineDay]
    @Binding var showsAllEvents: Bool

    private let initialEventLimit = 8

    private var allEvents: [RecoveryTimelineEvent] {
        days.flatMap(\.events)
    }

    private var displayedEvents: [RecoveryTimelineEvent] {
        showsAllEvents ? allEvents : Array(allEvents.prefix(initialEventLimit))
    }

    var body: some View {
        if !allEvents.isEmpty {
            Section("Recent recovery activity") {
                ForEach(Array(displayedEvents.enumerated()), id: \.element.id) { index, event in
                    VStack(alignment: .leading, spacing: 8) {
                        if index == 0 || !Calendar.current.isDate(event.timestamp, inSameDayAs: displayedEvents[index - 1].timestamp) {
                            Text(event.timestamp.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                        RecoveryTimelineEventRow(event: event)
                    }
                    .padding(.vertical, 4)
                }
                if allEvents.count > initialEventLimit {
                    Button(showsAllEvents ? "Show recent activity" : "Show all \(allEvents.count) events") {
                        showsAllEvents.toggle()
                    }
                }
            }
        }
    }
}

private struct RecoveryTimelineEventRow: View {
    let event: RecoveryTimelineEvent

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var timestamp: Date {
        event.timestamp
    }

    private var title: String {
        switch event {
        case let .recoveryItem(item): return "Stored in Recovery: \(URL(fileURLWithPath: item.originalPath).lastPathComponent)"
        case let .activity(record): return "\(record.kind.rawValue) — \(record.result)"
        }
    }

    private var detail: String {
        switch event {
        case let .recoveryItem(item): return item.originalPath
        case let .activity(record): return record.paths.isEmpty ? "No paths recorded" : "\(record.paths.count) recorded path(s)"
        }
    }

    private var symbol: String {
        switch event {
        case .recoveryItem: return "arrow.uturn.backward.circle.fill"
        case let .activity(record):
            switch record.kind {
            case .restore: return "arrow.uturn.backward"
            case .permanentDelete: return "trash.fill"
            case .failure: return "exclamationmark.triangle.fill"
            default: return "checkmark.circle.fill"
            }
        }
    }

    private var tint: Color {
        switch event {
        case .recoveryItem: return .green
        case let .activity(record): return record.kind == .failure ? .orange : .secondary
        }
    }
}
