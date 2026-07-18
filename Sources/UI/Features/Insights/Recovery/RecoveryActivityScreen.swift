import SwiftUI
import SecondWindCore

struct RecoveryActivityScreen: View {
    let model: SecondWindViewModel
    @State private var itemPendingPermanentDeletion: RecoveryItem?

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
