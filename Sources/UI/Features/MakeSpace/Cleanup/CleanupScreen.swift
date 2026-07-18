import SwiftUI
import SecondWindCore
import SecondWindApplication
import SecondWindMacOS

struct CleanupScreen: View {
    let model: SecondWindViewModel
    @State private var query = ""
    @State private var riskFilter = CleanupRiskFilter.all
    @State private var categoryFilter: FindingCategory?
    @State private var sortOrder = CleanupSortOrder.size

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(
                eyebrow: "REVIEW BEFORE YOU CHANGE",
                title: "Clean Up",
                detail: "Scan is read-only. Every selected item is shown again in a plan before anything moves."
            ) {
                Button(model.isScanning ? "Cancel scan" : "Scan", systemImage: model.isScanning ? "xmark" : "arrow.clockwise") {
                    model.isScanning ? model.cancelScan() : model.scan()
                }
                    .buttonStyle(.borderedProminent)
            }

            CleanupReadinessCard(model: model, visibleFindings: visibleFindings)

            SoftCard {
                HStack {
                        Picker("Show", selection: $riskFilter) {
                            ForEach(CleanupRiskFilter.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(CleanupSortOrder.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        if !categoryTotals.isEmpty {
                            Menu {
                                Button("All categories") {
                                    categoryFilter = nil
                                }
                                Divider()
                                ForEach(categoryTotals) { total in
                                    Button {
                                        categoryFilter = total.category
                                    } label: {
                                        Label(
                                            "\(total.category.title) · \(ByteCountFormatter.string(fromByteCount: total.bytes, countStyle: .file))",
                                            systemImage: categoryFilter == total.category
                                                ? "checkmark.circle.fill"
                                                : total.category == .developer ? "hammer.fill" : "externaldrive.fill"
                                        )
                                    }
                                }
                            } label: {
                                Label(categoryFilter?.title ?? "All categories", systemImage: "chart.pie.fill")
                            }
                        }
                        Spacer()
                        Text("\(visibleFindings.count) shown")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                }
            }

            if model.findings.isEmpty && !model.isScanning {
                ContentUnavailableView("No known cleanup items", systemImage: "checkmark.shield", description: Text("Second Wind found nothing eligible under its bundled, local rules."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(CleanupFindingGroup.allCases) { group in
                        let items = group.items(in: visibleFindings)
                        if !items.isEmpty {
                            Section {
                                ForEach(items) { item in
                                    FindingRow(
                                        item: item,
                                        isSelected: model.selectedIDs.contains(item.id),
                                        toggleSelection: item.risk.isExecutable && item.supportedAction != .none
                                            ? { model.toggleSelection(for: item) }
                                            : nil
                                    )
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: group.symbol)
                                    Text(group.title)
                                    Spacer()
                                    Text(group.detail)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(group.tint)
                            }
                        }
                    }
                }
                .searchable(text: $query, prompt: "Search names or paths")
            }
        }
        .padding(32)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CleanupSelectionBar(model: model)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(.regularMaterial)
        }
    }

    private var visibleFindings: [Finding] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = model.findings.filter { finding in
            let riskMatches = riskFilter.matches(finding.risk)
            let categoryMatches = categoryFilter == nil || finding.category == categoryFilter
            let queryMatches = normalizedQuery.isEmpty || finding.title.lowercased().contains(normalizedQuery) || finding.path.lowercased().contains(normalizedQuery)
            return riskMatches && categoryMatches && queryMatches
        }
        return filtered.sorted(by: sortOrder.comparator)
    }

    private var categoryTotals: [CleanupCategoryTotal] {
        Dictionary(grouping: model.findings.compactMap { finding -> (FindingCategory, Int64)? in
            guard let category = finding.category else { return nil }
            return (category, finding.byteSize)
        }, by: \.0)
        .map { category, values in
            CleanupCategoryTotal(category: category, bytes: values.reduce(0) { $0 + $1.1 })
        }
        .sorted { $0.bytes > $1.bytes }
    }

}

private struct CleanupReadinessCard: View {
    let model: SecondWindViewModel
    let visibleFindings: [Finding]

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let progress = model.scanProgress {
                    ProgressView(value: progress.fraction)
                        .tint(tint)
                        .frame(maxWidth: 260)
                    Text("\(progress.completedUnits) of \(progress.totalUnits) known areas checked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !model.isScanning && model.actionableFindingCount > 0 {
                Button("Select recreated items") { model.selectSafeFindings(visibleFindings) }
                    .buttonStyle(.bordered)
                    .disabled(!visibleFindings.contains { $0.risk == .safe && $0.supportedAction != .none })
            }
        }
        .padding(18)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(0.14)))
    }

    private var tint: Color {
        model.isScanning ? .blue : model.actionableFindingCount > 0 ? .green : .secondary
    }
    private var symbol: String {
        model.isScanning ? "magnifyingglass" : model.actionableFindingCount > 0 ? "checkmark.shield.fill" : "checkmark.circle.fill"
    }
    private var eyebrow: String {
        model.isScanning ? "LOCAL SCAN IN PROGRESS" : "STEP 1 OF 2 · CHOOSE ITEMS"
    }
    private var title: String {
        if model.isScanning { return "Checking the cleanup areas Second Wind understands" }
        if model.actionableFindingCount > 0 { return "\(model.actionableFindingCount) items are eligible to review" }
        return "Nothing eligible needs attention"
    }
    private var detail: String {
        if model.isScanning {
            let currentTitle = model.scanProgress?.currentTitle ?? "local locations"
            return "Checking \(currentTitle) · no files are changed while scanning."
        }
        if model.actionableFindingCount > 0 {
            return "Up to \(ByteCountFormatter.string(fromByteCount: model.actionableBytes, countStyle: .file)) is available across safe and review-required items."
        }
        return "Protected items, if present, remain visible but can never be selected."
    }
}

private struct CleanupSelectionBar: View {
    let model: SecondWindViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectionSummary)
                    .font(.subheadline.weight(.semibold))
                if model.reviewRequiredSelectionCount > 0 {
                    Label("\(model.reviewRequiredSelectionCount) selected item(s) need your attention", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if model.selectedIDs.isEmpty {
                    Text("Use the circle beside an item to add it to your plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("You will review a complete plan before anything changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.selectedBytes > 0 {
                Text("+\(ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            if !model.selectedIDs.isEmpty {
                Button("Clear selection") { model.clearSelection() }
            }
            Button("Move selected items to Trash", systemImage: "trash") {
                model.moveSelectedItemsToTrash()
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedIDs.isEmpty)
            Button("Review plan") { model.makePlan() }
                .disabled(model.selectedIDs.isEmpty)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }

    private var selectionSummary: String {
        model.selectedIDs.isEmpty
            ? "Select items to continue"
            : "\(model.selectedIDs.count) selected · \(ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))"
    }
}

private struct CleanupCategoryTotal: Identifiable {
    let category: FindingCategory
    let bytes: Int64
    var id: FindingCategory { category }
}

private enum CleanupFindingGroup: CaseIterable, Identifiable {
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
        case .reviewRequired: return "Needs your review"
        case .protected: return "Protected"
        }
    }
    var detail: String {
        switch self {
        case .safe: return "reversible"
        case .reviewRequired: return "select deliberately"
        case .protected: return "cannot be selected"
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

private enum CleanupRiskFilter: String, CaseIterable, Identifiable {
    case all, safe, reviewRequired, protected
    var id: String { rawValue }
    var title: String {
        switch self { case .all: return "All items"; case .safe: return "Recreated automatically"; case .reviewRequired: return "Needs review"; case .protected: return "Protected" }
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

private enum CleanupSortOrder: String, CaseIterable, Identifiable {
    case size, name, risk
    var id: String { rawValue }
    var title: String { switch self { case .size: return "Largest first"; case .name: return "Name"; case .risk: return "Safety" } }
    var comparator: (Finding, Finding) -> Bool {
        switch self {
        case .size: return { $0.byteSize == $1.byteSize ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.byteSize > $1.byteSize }
        case .name: return { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .risk: return { $0.risk.rawValue == $1.risk.rawValue ? $0.byteSize > $1.byteSize : $0.risk.rawValue < $1.risk.rawValue }
        }
    }
}

private struct FindingRow: View {
    let item: Finding
    let isSelected: Bool
    let toggleSelection: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            selectionControl
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(item.title).font(.headline)
                    RiskPill(risk: item.risk)
                }
                Text(safetyDetail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
                Text(item.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Location: \(visiblePath)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(item.path)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var selectionControl: some View {
        if let toggleSelection {
            Button(action: toggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .green : .secondary)
                    .frame(width: 34, height: 34)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Remove from plan" : "Add to plan")
            .accessibilityLabel(isSelected ? "Remove \(item.title) from plan" : "Add \(item.title) to plan")
        } else {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var symbol: String {
        item.risk == .safe ? "checkmark.shield.fill" : item.risk == .protected ? "lock.shield.fill" : "exclamationmark.shield.fill"
    }

    private var tint: Color {
        item.risk == .safe ? .green : item.risk == .protected ? .red : .orange
    }

    private var safetyDetail: String {
        if item.risk == .protected { return "Protected — Second Wind will not include this in a plan." }
        if item.confidence == .needsUserReview { return "Review required before including this in a plan." }
        return "Eligible for a reversible cleanup plan."
    }

    private var visiblePath: String {
        let url = URL(fileURLWithPath: item.path)
        return "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)"
    }
}
struct CleanupPlanReviewSheet: View {
    let model: SecondWindViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledgedWarnings = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = model.proposedPlan {
                    VStack(spacing: 0) {
                        PlanReviewHeader(plan: plan, snapshot: model.snapshot)
                        List {
                            if !plan.warnings.isEmpty {
                                Section("Before you confirm") {
                                    ForEach(plan.warnings, id: \.self) {
                                        Label($0, systemImage: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                    }
                                    Toggle("I reviewed the items that need attention.", isOn: $acknowledgedWarnings)
                                }
                            }
                            ForEach(PlanActionGroup.allCases) { group in
                                let actions = group.actions(in: plan.actions)
                                if !actions.isEmpty {
                                    Section {
                                        ForEach(actions) { action in
                                            PlanActionRow(action: action)
                                        }
                                    } header: {
                                        Label(group.title, systemImage: group.symbol)
                                            .foregroundStyle(group.tint)
                                    }
                                }
                            }
                            Section {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Choose a final action below. Both options keep the reviewed items recoverable; opening this sheet never moves files.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            } header: {
                                Text("What happens next")
                            }
                            Section("Choose what happens") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Move the reviewed items to Finder Trash. macOS keeps them available until you empty Trash.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button("Move to Trash", systemImage: "trash") {
                                        model.executePlan(destination: .finderTrash)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(requiresWarningAcknowledgement)
                                }
                                .padding(.vertical, 4)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Store the reviewed items locally so you can restore them later. Recovery storage is never deleted automatically.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button("Keep in Recovery", systemImage: "arrow.uturn.backward.circle") {
                                        model.executePlan(destination: .recovery)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(requiresWarningAcknowledgement)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No plan to review", systemImage: "checklist")
                }
            }
            .navigationTitle("Confirm cleanup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 580)
    }

    private var requiresWarningAcknowledgement: Bool {
        model.proposedPlan?.warnings.isEmpty == false && !acknowledgedWarnings
    }
}

private struct PlanReviewHeader: View {
    let plan: CleanupPlan
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("STEP 2 OF 2 · FINAL REVIEW")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("Confirm the changes")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Nothing has moved yet. Check the complete list below, then explicitly confirm.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 16))
            }
            HStack(spacing: 24) {
                Label("\(plan.actions.count) items", systemImage: "checklist")
                Label(ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file), systemImage: "externaldrive")
                Label("Choose final action", systemImage: "arrow.left.arrow.right")
                Spacer()
                Text("Up to \(ByteCountFormatter.string(fromByteCount: min(snapshot.storageTotal, snapshot.storageAvailable + plan.totalBytes), countStyle: .file)) available after")
                    .font(.caption.weight(.medium))
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [.green.opacity(0.18), Color(nsColor: .controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private enum PlanActionGroup: CaseIterable, Identifiable {
    case safe, reviewRequired

    var id: String { title }
    var risk: Risk { self == .safe ? .safe : .reviewRequired }
    var title: String { self == .safe ? "Recreated automatically" : "Reviewed items" }
    var symbol: String { self == .safe ? "checkmark.shield.fill" : "exclamationmark.shield.fill" }
    var tint: Color { self == .safe ? .green : .orange }

    func actions(in actions: [PlanAction]) -> [PlanAction] {
        actions.filter { $0.risk == risk }
    }
}

private struct PlanActionRow: View {
    let action: PlanAction

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.risk == .safe ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(action.risk == .safe ? .green : .orange)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(action.title).font(.headline)
                    RiskPill(risk: action.risk)
                }
                Text(action.sourcePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(action.sourcePath)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: action.byteSize, countStyle: .file))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 5)
    }
}

struct CleanupCompletionSheet: View {
    let completion: CleanupCompletion
    let openRecovery: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(.green)
            VStack(spacing: 7) {
                Text("Cleanup complete")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("\(completion.itemCount) item(s) moved · up to \(ByteCountFormatter.string(fromByteCount: completion.reclaimedBytes, countStyle: .file)) reclaimed")
                    .foregroundStyle(.secondary)
            }
            SoftCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: completion.destination == .recovery ? "arrow.uturn.backward.circle.fill" : "trash.circle.fill")
                        .font(.title2)
                        .foregroundStyle(completion.destination == .recovery ? .green : .orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(completion.destination == .recovery ? "Items are stored locally" : "Items are now in Finder Trash")
                            .font(.headline)
                        Text(completion.destination == .recovery ? "Open Recovery & activity any time to restore an item. Recovery storage is never deleted automatically." : "Finder controls when items in Trash are permanently deleted.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button("Done") { dismiss() }
                Spacer()
                if completion.destination == .recovery {
                    Button("Open Recovery") {
                        dismiss()
                        openRecovery()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(30)
        .frame(width: 500)
    }
}
