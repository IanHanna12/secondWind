import SwiftUI
import SecondWindCore
import SecondWindPersistence
import SecondWindServices

/// The storage feature's single composing view. Its child views are focused
/// specifications of the same current inventory and its local history.
struct StorageIntelligenceView: View {
    let model: SecondWindViewModel
    @State private var selectedCategory: StorageCategory?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(
                    eyebrow: "LOCAL STORAGE INTELLIGENCE",
                    title: "Storage overview",
                    detail: "Second Wind records only the storage it explicitly understands. Snapshots are captured automatically after scans and local storage changes."
                ) { EmptyView() }
                StorageRecommendationsSection(inventory: model.storageInventory)
                StorageSnapshotContent(report: model.storageSnapshots, isScanning: model.isScanning, scanSummary: model.latestScanSummary, selectedCategory: $selectedCategory)
            }
            .padding(30)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }
}

private struct StorageRecommendationsSection: View {
    let inventory: StorageInventory

    private var recommendations: [StorageRecommendation] {
        StorageRecommendationEngine().recommendations(for: inventory)
    }

    var body: some View {
        if !recommendations.isEmpty {
            SoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Explainable recommendations", systemImage: "lightbulb.max.fill")
                        .font(.headline)
                    Text("These are deterministic rules based on known location, size, and when available the local modification date. They never select or remove anything automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(recommendations) { recommendation in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(recommendation.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(bytes(recommendation.entry.byteSize)).monospacedDigit()
                            }
                            Text(recommendation.entry.title + " · " + recommendation.detail)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }
}

private struct StorageSnapshotContent: View {
    let report: StorageSnapshotReport
    let isScanning: Bool
    let scanSummary: StorageScanSummary?
    @Binding var selectedCategory: StorageCategory?

    var body: some View {
        if let current = report.current {
            RecordedStorageSnapshots(report: report, current: current, scanSummary: scanSummary, selectedCategory: $selectedCategory)
        } else {
            EmptyStorageSnapshots(isScanning: isScanning)
        }
    }
}

private struct RecordedStorageSnapshots: View {
    let report: StorageSnapshotReport
    let current: StorageSnapshot
    let scanSummary: StorageScanSummary?
    @Binding var selectedCategory: StorageCategory?

    var body: some View {
        StorageSnapshotMetrics(report: report, current: current)
        StorageScanSummarySection(summary: scanSummary)
        StorageSnapshotObservation(report: report)
        StorageCategoryOverview(report: report, selectedCategory: $selectedCategory)
        StorageCategoryExplorer(current: current, selectedCategory: selectedCategory)
        StorageDeltaDashboardCard(dashboard: StorageDeltaDashboardBuilder().build(report: report))
        StorageReclaimPreview(report: report, current: current)
        StorageChanges(report: report)
        StorageSnapshotEntries(entries: current.entries)
        ScanHistoryCard(entries: ScanHistoryBuilder().build(snapshots: report.history))
    }
}

private struct StorageScanSummarySection: View {
    let summary: StorageScanSummary?

    var body: some View {
        if let summary {
            SoftCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Latest scan summary", systemImage: "checkmark.circle.fill")
                        .font(.headline).foregroundStyle(.green)
                    HStack(spacing: 18) {
                        ScanSummaryValue(title: "Findings", value: "\(summary.findingCount)")
                        ScanSummaryValue(title: "Eligible", value: "\(summary.eligibleCount)")
                        ScanSummaryValue(title: "Needs review", value: "\(summary.reviewRequiredCount)")
                        ScanSummaryValue(title: "Protected", value: "\(summary.protectedCount)")
                    }
                    Text("\(bytes(summary.observedBytes)) across \(summary.observedLocationCount) known locations in \(String(format: "%.1f", summary.duration)) seconds. The scan reads only explicit local locations.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ScanSummaryValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct StorageCategoryOverview: View {
    let report: StorageSnapshotReport
    @Binding var selectedCategory: StorageCategory?

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Known storage by category", systemImage: "square.3.layers.3d.down.right")
                    .font(.headline)
                Text("These totals cover only locations Second Wind explicitly understands; they are not a replacement for macOS storage management.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(report.categorySummaries) { summary in
                    Button {
                        selectedCategory = selectedCategory == summary.category ? nil : summary.category
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.category.title).font(.subheadline.weight(.semibold))
                                Text("\(summary.entryCount) known item\(summary.entryCount == 1 ? "" : "s") · \(summary.category.explanation)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(bytes(summary.byteSize)).monospacedDigit()
                            Image(systemName: selectedCategory == summary.category ? "chevron.up" : "chevron.down")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct StorageCategoryExplorer: View {
    let current: StorageSnapshot
    let selectedCategory: StorageCategory?

    var body: some View {
        if let selectedCategory {
            let entries = current.entries.filter { StorageCategory.fromStoredTitle($0.category) == selectedCategory }
            SoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(selectedCategory.title, systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Text(selectedCategory.explanation).font(.caption).foregroundStyle(.secondary)
                    ForEach(entries) { entry in StorageSnapshotEntryRow(entry: entry) }
                }
            }
        }
    }
}

private struct StorageDeltaDashboardCard: View {
    let dashboard: StorageDeltaDashboard

    var body: some View {
        if dashboard.hasComparison {
            SoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Storage delta", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                    Text(comparisonDetail)
                        .font(.caption).foregroundStyle(.secondary)
                    if let availableSpaceChange = dashboard.availableSpaceChange {
                        DeltaSummaryRow(
                            title: "Free space",
                            detail: availableSpaceChange >= 0 ? "More free space since the previous scan" : "Less free space since the previous scan",
                            change: availableSpaceChange
                        )
                    }
                    if let largestCategoryGrowth = dashboard.largestCategoryGrowth {
                        DeltaSummaryRow(
                            title: "Largest category growth",
                            detail: largestCategoryGrowth.category.title,
                            change: largestCategoryGrowth.byteChange
                        )
                    }
                    if let largestEntryGrowth = dashboard.largestEntryGrowth {
                        DeltaSummaryRow(
                            title: "Largest location growth",
                            detail: largestEntryGrowth.title,
                            change: largestEntryGrowth.byteChange
                        )
                    }
                    ForEach(dashboard.categoryChanges.prefix(3)) { change in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(change.category.title).font(.subheadline.weight(.semibold))
                                Text(bytes(change.currentBytes) + " currently known")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(change.byteChange >= 0 ? "+\(bytes(change.byteChange))" : "−\(bytes(-change.byteChange))")
                                .monospacedDigit()
                                .foregroundStyle(change.byteChange >= 0 ? .orange : .green)
                        }
                    }
                }
            }
        }
    }

    private var comparisonDetail: String {
        guard let date = dashboard.comparisonDate else { return "No earlier local snapshot is available." }
        return "Compared with the local snapshot from \(date.formatted(date: .abbreviated, time: .shortened)). Changes below 1 MB are omitted."
    }
}

private struct DeltaSummaryRow: View {
    let title: String
    let detail: String
    let change: Int64

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(change >= 0 ? "+\(bytes(change))" : "−\(bytes(-change))")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(change >= 0 ? .orange : .green)
        }
    }
}

private struct StorageSnapshotMetrics: View {
    let report: StorageSnapshotReport
    let current: StorageSnapshot

    var body: some View {
        HStack(spacing: 14) {
            Metric(title: "Current free space", value: bytes(current.availableBytes), symbol: "externaldrive.fill", tint: .mint)
            Metric(title: "Tracked items", value: "\(current.entries.count)", symbol: "tray.full.fill", tint: .blue)
            Metric(title: "Eligible to plan", value: bytes(report.reclaimableBytes), symbol: "arrow.uturn.backward.circle.fill", tint: .green)
        }
    }
}

private struct StorageSnapshotObservation: View {
    let report: StorageSnapshotReport

    var body: some View {
        if report.isFirstSnapshot {
            SoftCard {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "eye.circle.fill").font(.title2).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your local baseline is ready").font(.headline)
                        Text("Run another scan after you use your Mac. Second Wind will show which known areas grew or shrank; it never guesses about unknown personal data.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            StorageSnapshotComparisonCard(report: report)
        }
    }
}

private struct StorageReclaimPreview: View {
    let report: StorageSnapshotReport
    let current: StorageSnapshot

    var body: some View {
        if report.reclaimableBytes > 0 {
            StorageOutcomePreview(
                available: current.availableBytes,
                total: current.totalBytes,
                reclaimable: report.reclaimableBytes,
                title: "Potential outcome from reviewed items",
                detail: "This is an upper bound across eligible and review-required findings. Select individual items in Clean Up before creating a plan."
            )
        }
    }
}

private struct StorageChanges: View {
    let report: StorageSnapshotReport

    var body: some View {
        if !report.changes.isEmpty {
            SoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("What changed since the previous snapshot", systemImage: "chart.line.uptrend.xyaxis").font(.headline)
                    Text("Changes smaller than 1 MB are omitted to keep this useful.").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(report.changes.prefix(8))) { change in StorageChangeRow(change: change) }
                }
            }
        } else if !report.isFirstSnapshot {
            SoftCard {
                Label("No meaningful changes in known storage since the previous snapshot.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StorageSnapshotEntries: View {
    let entries: [StorageSnapshotEntry]

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Known storage right now", systemImage: "list.bullet.rectangle").font(.headline)
                Text("These are explanations, not automatic cleanup instructions.").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(entries.prefix(10))) { entry in StorageSnapshotEntryRow(entry: entry) }
            }
        }
    }
}

private struct ScanHistoryCard: View {
    let entries: [ScanHistoryEntry]

    var body: some View {
        if entries.count > 1 {
            SoftCard {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Local scan history", systemImage: "clock.arrow.circlepath").font(.headline)
                    ForEach(entries.prefix(8)) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                if let observedBytesChange = entry.observedBytesChange {
                                    Text(observedBytesChange >= 0
                                        ? "Known storage +\(bytes(observedBytesChange))"
                                        : "Known storage −\(bytes(-observedBytesChange))"
                                    )
                                    .foregroundStyle(.secondary)
                                } else {
                                    Text("First local baseline").foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(bytes(entry.snapshot.availableBytes) + " free").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }
}

private struct EmptyStorageSnapshots: View {
    let isScanning: Bool

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("No storage snapshots yet").font(.headline)
                Text(isScanning
                    ? "Second Wind is recording the first read-only baseline now. Nothing will be cleaned."
                    : "The next read-only scan will create the first local baseline automatically. Nothing will be cleaned."
                )
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StorageSnapshotComparisonCard: View {
    let report: StorageSnapshotReport

    var body: some View {
        SoftCard {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: comparisonSymbol).font(.title2).foregroundStyle(comparisonColor)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Since the previous local snapshot").font(.headline)
                    Text(message).foregroundStyle(.secondary)
                    Text("This compares free disk space and known rule findings only; it does not claim to explain all System Data.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var change: Int64 { report.availableSpaceChange ?? 0 }
    private var comparisonSymbol: String { change >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill" }
    private var comparisonColor: Color { change >= 0 ? .green : .orange }
    private var message: String {
        let amount = ByteCountFormatter.string(fromByteCount: abs(change), countStyle: .file)
        if change > 0 { return "Free disk space increased by \(amount)." }
        if change < 0 { return "Free disk space decreased by \(amount)." }
        return "Free disk space is unchanged."
    }
}

private struct StorageChangeRow: View {
    let change: StorageChange

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(change.title).font(.subheadline.weight(.semibold))
                    RiskPill(risk: change.risk)
                }
                Text(changeDetail)
                    .font(.caption).foregroundStyle(.secondary)
                Text(change.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text(changeLabel).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
        }
        .padding(.vertical, 5)
    }

    private var symbol: String { change.kind == .shrank || change.kind == .noLongerObserved ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill" }
    private var tint: Color { change.kind == .shrank || change.kind == .noLongerObserved ? .green : .orange }
    private var changeDetail: String {
        switch change.kind {
        case .newlyObserved: return "First observed by Second Wind · \(change.category)"
        case .noLongerObserved: return "No longer observed by the latest scan · \(change.category)"
        case .grew, .shrank: return change.category
        }
    }
    private var changeLabel: String {
        let amount = ByteCountFormatter.string(fromByteCount: abs(change.byteChange), countStyle: .file)
        return change.kind == .shrank || change.kind == .noLongerObserved ? "−\(amount)" : "+\(amount)"
    }
}

private struct StorageSnapshotEntryRow: View {
    let entry: StorageSnapshotEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.isActionable ? "checkmark.shield.fill" : "lock.shield.fill")
                .foregroundStyle(entry.isActionable ? .green : .orange).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(entry.title).font(.subheadline.weight(.semibold)); RiskPill(risk: entry.risk) }
                Text(entry.category + " · " + entry.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let origin = entry.origin {
                    Text("Source: \(origin)").font(.caption2).foregroundStyle(.secondary)
                }
                if let path = entry.path {
                    Text(path).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(path)
                }
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: entry.byteSize, countStyle: .file)).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}
