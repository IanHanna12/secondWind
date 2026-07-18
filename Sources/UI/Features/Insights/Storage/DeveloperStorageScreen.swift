import SwiftUI
import SecondWindCore

struct DeveloperStorageScreen: View {
    let model: SecondWindViewModel

    private var entries: [StorageInventoryEntry] {
        model.storageInventory.entries.filter { $0.category == .developerStorage }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(
                    eyebrow: "KNOWN DEVELOPER STORAGE",
                    title: "Developer storage",
                    detail: "Build artifacts, package caches, containers, simulators, and archives that Second Wind explicitly recognizes."
                ) { EmptyView() }

                if entries.isEmpty {
                    ContentUnavailableView("No known developer storage", systemImage: "hammer", description: Text("Run a scan to inspect the developer locations Second Wind understands."))
                } else {
                    Metric(title: "Known developer storage", value: bytes(entries.filter(\.countsTowardCategoryTotal).reduce(0) { $0 + $1.byteSize }), symbol: "hammer.fill", tint: .orange)
                    SoftCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Developer locations", systemImage: "list.bullet.rectangle")
                                .font(.headline)
                            ForEach(entries) { entry in
                                DeveloperStorageRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }
}

private struct DeveloperStorageRow: View {
    let entry: StorageInventoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.isActionable ? "hammer.fill" : "lock.shield.fill")
                .foregroundStyle(entry.isActionable ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.subheadline.weight(.semibold))
                Text(entry.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text("Source: \(entry.origin)").font(.caption2).foregroundStyle(.secondary)
                if let path = entry.path {
                    Text(path).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(path)
                }
            }
            Spacer()
            Text(bytes(entry.byteSize)).monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}
