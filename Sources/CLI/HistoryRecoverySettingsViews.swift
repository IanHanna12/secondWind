import SwiftUI
import SecondWindCore
import SecondWindPlatform

struct SettingsView: View {
    let model: SecondWindViewModel
    private let preferenceService = PreferenceService()

    var body: some View {
        Form {
            Section("Finder and Dock") {
                ForEach(SystemPreference.allCases) { preference in
                    HStack {
                        Toggle(preference.rawValue, isOn: Binding(get: { preferenceService.value(preference) ?? false }, set: { model.setPreference(preference, enabled: $0) }))
                            .disabled(!preferenceService.isSupported(preference))
                        VStack(alignment: .leading) {
                            Text(preference.explanation).font(.caption).foregroundStyle(.secondary)
                            Button("Reset to macOS default") { model.resetPreference(preference) }.font(.caption)
                        }
                    }
                }
            }
            Section("Menu bar") {
                Toggle("Enable menu-bar readout", isOn: Binding(get: { model.menuMonitor }, set: { model.setMenuMonitor(enabled: $0) }))
                Text("The menu-bar monitor is opt-in and performs no network activity.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .navigationTitle("Settings")
    }
}

struct ActivityView: View {
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
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.originalPath).lineLimit(1)
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
