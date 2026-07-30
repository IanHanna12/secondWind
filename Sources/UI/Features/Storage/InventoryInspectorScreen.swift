import SwiftUI
import SecondWindApplication
import SecondWindCore

/// A transparent, read-only projection of the current canonical inventory.
/// It never scans, classifies, or changes cleanup eligibility by itself.
struct InventoryInspectorScreen: View {
    let model: SecondWindViewModel
    @State private var grouping = InventoryInspectorGrouping.category
    @State private var query = ""
    @State private var selectedEntryID: String?

    private let explanationProvider = DefaultStorageExplanationProvider()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(
                eyebrow: "EXPLAINABLE STORAGE",
                title: "Inventory inspector",
                detail: "A read-only view of the same Storage Inventory used by Cleanup, Applications, snapshots, and Recovery."
            ) { EmptyView() }

            SoftCard {
                HStack(spacing: 12) {
                    TextField("Search names or paths", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                    Picker("Organize by", selection: $grouping) {
                        ForEach(InventoryInspectorGrouping.allCases) { grouping in
                            Text(grouping.title).tag(grouping)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Text("\(visibleEntries.count) known entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HSplitView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(groups) { group in
                            InventoryInspectorGroupSection(
                                group: group,
                                selectedEntryID: $selectedEntryID
                            )
                        }
                    }
                }
                .background(.background)
                .frame(minWidth: 340, idealWidth: 420, maxWidth: 500)

                InventoryExplanationDetail(explanation: selectedExplanation)
                    .frame(minWidth: 500)
            }
        }
        .padding(32)
    }

    private var visibleEntries: [StorageInventoryEntry] {
        let searchText = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.storageInventory.entries.filter { entry in
            searchText.isEmpty || entry.title.lowercased().contains(searchText) || entry.path?.lowercased().contains(searchText) == true
        }
    }

    private var groups: [InventoryInspectorGroup] {
        Dictionary(grouping: visibleEntries, by: grouping.key(for:))
            .map { InventoryInspectorGroup(title: $0.key, entries: $0.value.sorted { $0.byteSize > $1.byteSize }) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    private var selectedExplanation: StorageInventoryExplanation? {
        guard let selectedEntryID,
              let entry = visibleEntries.first(where: { $0.id == selectedEntryID }) else { return nil }
        return explanationProvider.explain(entry)
    }

}

private enum InventoryInspectorGrouping: String, CaseIterable, Identifiable {
    case category
    case application
    case rule
    case protection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .category: return "Category"
        case .application: return "Application"
        case .rule: return "Rule"
        case .protection: return "Cleanup status"
        }
    }

    func key(for entry: StorageInventoryEntry) -> String {
        switch self {
        case .category: return entry.category.title
        case .application: return entry.applicationAssociations.first?.application.displayName ?? "No application association"
        case .rule: return ruleGroupName(for: entry)
        case .protection: return entry.risk == .protected ? "Protected" : entry.isActionable ? "Eligible after review" : "Requires review"
        }
    }

    private func ruleGroupName(for entry: StorageInventoryEntry) -> String {
        guard let ruleID = entry.ruleID else {
            return "No cleanup rule"
        }

        guard let builtInRule = BuiltInRules.all.first(where: { $0.id == ruleID }) else {
            return "Custom rule"
        }

        return builtInRule.title
    }
}

private struct InventoryInspectorGroup: Identifiable {
    let title: String
    let entries: [StorageInventoryEntry]

    var id: String { title }
    var totalBytes: Int64 { entries.reduce(0) { $0 + $1.byteSize } }
}

private struct InventoryInspectorRow: View {
    let entry: StorageInventoryEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isActionable ? "checkmark.shield.fill" : "lock.fill")
                .foregroundStyle(entry.isActionable ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).lineLimit(1)
                Text(entry.path ?? entry.origin)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(bytes(entry.byteSize))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}

private struct InventoryInspectorGroupSection: View {
    let group: InventoryInspectorGroup
    @Binding var selectedEntryID: String?

    var body: some View {
        Section {
            ForEach(group.entries) { entry in
                Button {
                    selectedEntryID = entry.id
                } label: {
                    InventoryInspectorRow(entry: entry)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectionBackground(for: entry))
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("\(group.title) · \(bytes(group.totalBytes))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
        }
    }

    @ViewBuilder
    private func selectionBackground(for entry: StorageInventoryEntry) -> some View {
        if selectedEntryID == entry.id {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.tint.opacity(0.2))
        } else {
            Color.clear
        }
    }
}

private struct InventoryExplanationDetail: View {
    let explanation: StorageInventoryExplanation?

    var body: some View {
        Group {
            if let explanation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(explanation.entry.title).font(.title2.bold())
                        Text(bytes(explanation.entry.byteSize)).font(.headline.monospacedDigit()).foregroundStyle(.secondary)
                        InventoryExplanationSection(title: "Why this exists", items: explanation.facts)
                        if !explanation.cleanupReasons.isEmpty {
                            InventoryExplanationSection(title: "Why this can be cleaned", items: explanation.cleanupReasons)
                        }
                        if !explanation.protectionReasons.isEmpty {
                            InventoryExplanationSection(title: "Why this is protected", items: explanation.protectionReasons)
                        }
                        if !explanation.relationshipReasons.isEmpty {
                            InventoryExplanationSection(title: "Why this belongs to an application", items: explanation.relationshipReasons)
                        }
                        InventoryJourneySection(steps: explanation.journey)
                    }
                    .padding(.horizontal, 10)
                }
            } else {
                ContentUnavailableView("Select an inventory entry", systemImage: "square.3.layers.3d.down.right", description: Text("Choose a known storage location to inspect the facts Second Wind used."))
            }
        }
    }
}

private struct InventoryExplanationSection: View {
    let title: String
    let items: [String]

    init(title: String, items: [String]) {
        self.title = title
        self.items = items
    }

    init(title: String, items: [StorageExplanationFact]) {
        self.title = title
        self.items = items.map { fact in
            [fact.title + ": " + fact.value, fact.detail].compactMap { $0 }.joined(separator: " — ")
        }
    }

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Label(item, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct InventoryJourneySection: View {
    let steps: [StorageJourneyStep]

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Storage journey").font(.headline)
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(.caption.weight(.semibold))
                            Text(step.detail).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
