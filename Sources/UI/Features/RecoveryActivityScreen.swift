import AppKit
import SwiftUI
import SecondWindCore
import SecondWindApplication

struct RecoveryActivityScreen: View {
    let model: SecondWindViewModel
    @State private var selectedRecoveryIDs: Set<UUID> = []
    @State private var itemPendingRestoreConflict: RecoveryItem?
    @State private var itemPendingReplacement: RecoveryItem?
    @State private var itemsPendingBatchRestore: [RecoveryItem] = []
    @State private var itemsPendingPermanentDeletion: [RecoveryItem] = []
    @State private var showsAllTimelineEvents = false

    private var selectedItems: [RecoveryItem] {
        model.recoveryItems.filter { selectedRecoveryIDs.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.byteSize }
    }

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
                    Divider()
                    Button("Diagnostics with full paths…") { model.exportAudit(.diagnostics) }
                }
                Button("Check integrity") { model.checkRecoveryIntegrity() }
                Button("Refresh") { model.refreshActivity() }
            }
            List {
                Section("Recovery storage") {
                    if model.recoveryItems.isEmpty {
                        ContentUnavailableView("Nothing in Recovery", systemImage: "checkmark.shield", description: Text("Items stored here remain available to restore and are never deleted automatically."))
                    } else {
                        if !selectedItems.isEmpty {
                            HStack {
                                Text("\(selectedItems.count) selected · \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Button("Restore selected") { requestBatchRestore(selectedItems) }
                                Button("Delete selected", role: .destructive) {
                                    itemsPendingPermanentDeletion = selectedItems
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        ForEach(model.recoveryItems) { item in
                            HStack(alignment: .top) {
                                Toggle(
                                    "Select \(LocalPathDisplay.name(for: item.originalPath))",
                                    isOn: selectionBinding(for: item)
                                )
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .accessibilityLabel("Select \(LocalPathDisplay.name(for: item.originalPath))")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(LocalPathDisplay.name(for: item.originalPath)).font(.headline)
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
                                    RecoveryIntegrityLabel(report: model.integrityReport(for: item))
                                    RecoveryContextLabel(context: item.context)
                                }
                                Spacer()
                                Button("Restore") { requestRestore(item) }
                                    .disabled(!model.integrityReport(for: item).canRestore)
                                Button("Delete", role: .destructive) {
                                    itemsPendingPermanentDeletion = [item]
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
        .onChange(of: model.recoveryItems.map(\.id)) { _, ids in
            selectedRecoveryIDs.formIntersection(Set(ids))
        }
        .confirmationDialog(
            "Choose how to restore this item",
            isPresented: Binding(
                get: { itemPendingRestoreConflict != nil },
                set: { if !$0 { itemPendingRestoreConflict = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore beside existing item") {
                if let item = itemPendingRestoreConflict { model.restore(item, choice: .besideExisting) }
                itemPendingRestoreConflict = nil
            }
            Button("Choose another destination…") {
                if let item = itemPendingRestoreConflict { chooseAnotherDestination(for: item) }
                itemPendingRestoreConflict = nil
            }
            Button("Replace existing item…", role: .destructive) {
                itemPendingReplacement = itemPendingRestoreConflict
                itemPendingRestoreConflict = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("An item already exists at the original location. Choose a safe restore destination, or separately confirm replacement.")
        }
        .confirmationDialog(
            "Replace the existing item?",
            isPresented: Binding(
                get: { itemPendingReplacement != nil },
                set: { if !$0 { itemPendingReplacement = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace permanently", role: .destructive) {
                if let item = itemPendingReplacement {
                    model.restore(item, choice: .replaceAfterDestructiveConfirmation)
                }
                itemPendingReplacement = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the item currently at \(itemPendingReplacement?.originalPath ?? "the original location") before restoring the Recovery item. This cannot be undone.")
        }
        .confirmationDialog(
            "Restore selected items beside existing items?",
            isPresented: Binding(
                get: { !itemsPendingBatchRestore.isEmpty },
                set: { if !$0 { itemsPendingBatchRestore = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore beside existing items") {
                model.restore(itemsPendingBatchRestore, choice: .besideExisting)
                itemsPendingBatchRestore = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing files stay unchanged. Each colliding Recovery item receives a descriptive adjacent name. The batch is preflighted before any item moves.")
        }
        .confirmationDialog(
            itemsPendingPermanentDeletion.count == 1 ? "Delete this item permanently?" : "Delete \(itemsPendingPermanentDeletion.count) items permanently?",
            isPresented: Binding(
                get: { !itemsPendingPermanentDeletion.isEmpty },
                set: { if !$0 { itemsPendingPermanentDeletion = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) {
                model.deletePermanently(itemsPendingPermanentDeletion)
                itemsPendingPermanentDeletion = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \(itemsPendingPermanentDeletion.count) selected item(s) from Recovery. It cannot be restored or undone.")
        }
    }

    private func selectionBinding(for item: RecoveryItem) -> Binding<Bool> {
        Binding(
            get: { selectedRecoveryIDs.contains(item.id) },
            set: { selected in
                if selected { selectedRecoveryIDs.insert(item.id) }
                else { selectedRecoveryIDs.remove(item.id) }
            }
        )
    }

    private func requestRestore(_ item: RecoveryItem) {
        if model.hasRestoreDestinationConflict(for: item) {
            itemPendingRestoreConflict = item
        } else {
            model.restore(item, choice: .besideExisting)
        }
    }

    private func requestBatchRestore(_ items: [RecoveryItem]) {
        if items.contains(where: { model.hasRestoreDestinationConflict(for: $0) }) {
            itemsPendingBatchRestore = items
        } else {
            model.restore(items, choice: .besideExisting)
        }
    }

    private func chooseAnotherDestination(for item: RecoveryItem) {
        let panel = NSSavePanel()
        // The destination is real filesystem state, so retain `.noindex` here.
        panel.nameFieldStringValue = URL(fileURLWithPath: item.originalPath).lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        model.restore(item, choice: .anotherDestination(destination))
    }
}

private struct RecoveryIntegrityLabel: View {
    let report: RecoveryIntegrityReport

    var body: some View {
        switch report.status {
        case .healthy:
            Label("Integrity verified", systemImage: "checkmark.shield.fill")
                .font(.caption).foregroundStyle(.green)
        case let .damaged(reason):
            Label("Damaged — \(reason)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .unverified:
            Label("Integrity not yet checked", systemImage: "questionmark.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct RecoveryContextLabel: View {
    let context: RecoveryContext

    var body: some View {
        let values = [
            context.ruleID.map { "Rule: \($0)" },
            context.category.map { "Category: \($0.rawValue)" },
            context.applicationID.map { "App: \($0)" }
        ].compactMap { $0 }
        if !values.isEmpty {
            Text(values.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
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

    private var timestamp: Date { event.timestamp }

    private var title: String {
        switch event {
        case let .recoveryItem(item):
            return "Stored in Recovery: \(LocalPathDisplay.name(for: item.originalPath))"
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
