import SwiftUI
import SecondWindApplication
import SecondWindCore

struct CleanupReadinessCard: View {
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
            return "Checking \(model.scanProgress?.title ?? "local locations") · no files are changed while scanning."
        }
        if model.actionableFindingCount > 0 {
            return "Up to \(ByteCountFormatter.string(fromByteCount: model.actionableBytes, countStyle: .file)) is available across safe and review-required items."
        }
        return "Protected items, if present, remain visible but can never be selected."
    }
}

struct CleanupFilterBar: View {
    @Binding var riskFilter: CleanupRiskFilter
    @Binding var categoryFilter: FindingCategory?
    @Binding var sortOrder: CleanupSortOrder
    let categoryTotals: [CleanupCategoryTotal]
    let shownCount: Int

    var body: some View {
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
                        Button("All categories") { categoryFilter = nil }
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
                Text("\(shownCount) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CleanupSelectionBar: View {
    let model: SecondWindViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectionSummary)
                    .font(.subheadline.weight(.semibold))
                selectionDetail
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

    @ViewBuilder
    private var selectionDetail: some View {
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

    private var selectionSummary: String {
        model.selectedIDs.isEmpty
            ? "Select items to continue"
            : "\(model.selectedIDs.count) selected · \(ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))"
    }
}
