import SwiftUI
import SecondWindCore
import SecondWindApplication

/// The screen-level composition of the read-only scan, filtering, and item
/// selection flow. Its supporting views live beside it by responsibility.
struct CleanupScreen: View {
    let model: SecondWindViewModel
    @State private var query = ""
    @State private var riskFilter = CleanupRiskFilter.all
    @State private var categoryFilter: FindingCategory?
    @State private var sortOrder = CleanupSortOrder.size
    @State private var visibleFindings: [Finding] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(
                eyebrow: "REVIEW BEFORE YOU CHANGE",
                title: "Clean Up",
                detail: "Scan is read-only. Every selected item is shown again in a plan before anything moves."
            ) {
                Button(
                    model.isScanning ? "Cancel scan" : "Scan",
                    systemImage: model.isScanning ? "xmark" : "arrow.clockwise"
                ) {
                    model.isScanning ? model.cancelScan() : model.scan()
                }
                .buttonStyle(.borderedProminent)
            }

            CleanupReadinessCard(model: model, visibleFindings: visibleFindings)
            CleanupFilterBar(
                riskFilter: $riskFilter,
                categoryFilter: $categoryFilter,
                sortOrder: $sortOrder,
                categoryTotals: categoryTotals,
                shownCount: visibleFindings.count
            )

            findingsContent
        }
        .padding(32)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CleanupSelectionBar(model: model)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(.regularMaterial)
        }
        .onAppear(perform: refreshVisibleFindings)
        .onChange(of: model.findings) { _, _ in refreshVisibleFindings() }
        .onChange(of: query) { _, _ in refreshVisibleFindings() }
        .onChange(of: riskFilter) { _, _ in refreshVisibleFindings() }
        .onChange(of: categoryFilter) { _, _ in refreshVisibleFindings() }
        .onChange(of: sortOrder) { _, _ in refreshVisibleFindings() }
    }

    @ViewBuilder
    private var findingsContent: some View {
        if model.findings.isEmpty && !model.isScanning {
            ContentUnavailableView(
                "No known cleanup items",
                systemImage: "checkmark.shield",
                description: Text("Second Wind found nothing eligible under its bundled, local rules.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(CleanupFindingGroup.allCases) { group in
                    let items = group.items(in: visibleFindings)
                    if !items.isEmpty {
                        CleanupFindingSection(group: group, items: items, model: model)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search names or paths")
        }
    }

    private func refreshVisibleFindings() {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchingFindings = model.findings.filter { finding in
            riskFilter.matches(finding.risk)
                && (categoryFilter == nil || finding.category == categoryFilter)
                && (normalizedQuery.isEmpty
                    || finding.title.lowercased().contains(normalizedQuery)
                    || finding.path.lowercased().contains(normalizedQuery))
        }
        visibleFindings = matchingFindings.sorted(by: sortOrder.comparator)
    }

    private var categoryTotals: [CleanupCategoryTotal] {
        model.cleanupCategoryBytes
            .map { CleanupCategoryTotal(category: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }
}

struct CleanupCategoryTotal: Identifiable {
    let category: FindingCategory
    let bytes: Int64
    var id: FindingCategory { category }
}

enum CleanupFindingGroup: CaseIterable, Identifiable {
    case safe, reviewRequired, protected

    var id: String { title }
    var risk: Risk {
        switch self {
        case .safe: return .safe
        case .reviewRequired: return .reviewRequired
        case .protected: return .protected
        }
    }

    var title: String {
        switch self {
        case .safe: return "Recreated automatically"
        case .reviewRequired: return "Manual review"
        case .protected: return "Sensitive & protected"
        }
    }

    var detail: String {
        switch self {
        case .safe: return "reversible"
        case .reviewRequired: return "select deliberately"
        case .protected: return "cannot be selected"
        }
    }

    var isSelectable: Bool { self != .protected }
    var actionTitle: String {
        switch self {
        case .safe: return "Select recreated"
        case .reviewRequired: return "Select for review"
        case .protected: return "Protected"
        }
    }

    var actionSymbol: String {
        switch self {
        case .safe, .reviewRequired: return "plus.circle"
        case .protected: return "lock.fill"
        }
    }

    var symbol: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .reviewRequired: return "exclamationmark.shield.fill"
        case .protected: return "lock.shield.fill"
        }
    }

    var tint: Color {
        switch self {
        case .safe: return .green
        case .reviewRequired: return .orange
        case .protected: return .red
        }
    }

    func items(in findings: [Finding]) -> [Finding] {
        findings.filter { $0.risk == risk }
    }
}

enum CleanupRiskFilter: String, CaseIterable, Identifiable {
    case all, safe, reviewRequired, protected

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All items"
        case .safe: return "Recreated automatically"
        case .reviewRequired: return "Needs review"
        case .protected: return "Protected"
        }
    }

    func matches(_ risk: Risk) -> Bool {
        switch self {
        case .all: return true
        case .safe: return risk == .safe
        case .reviewRequired: return risk == .reviewRequired
        case .protected: return risk == .protected
        }
    }
}

enum CleanupSortOrder: String, CaseIterable, Identifiable {
    case size, name, risk

    var id: String { rawValue }
    var title: String {
        switch self {
        case .size: return "Largest first"
        case .name: return "Name"
        case .risk: return "Safety"
        }
    }

    var comparator: (Finding, Finding) -> Bool {
        switch self {
        case .size:
            return { left, right in
                left.byteSize == right.byteSize
                    ? left.title.localizedStandardCompare(right.title) == .orderedAscending
                    : left.byteSize > right.byteSize
            }
        case .name:
            return { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .risk:
            return { left, right in
                left.risk.rawValue == right.risk.rawValue
                    ? left.byteSize > right.byteSize
                    : left.risk.rawValue < right.risk.rawValue
            }
        }
    }
}
