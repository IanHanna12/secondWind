import SwiftUI
import SecondWindCore
import SecondWindSnapshots

struct StorageSnapshotsView: View {
    let model: SecondWindViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(
                    eyebrow: "LOCAL CHANGE HISTORY",
                    title: "Storage snapshots",
                    detail: "Second Wind records only the storage it understands from bundled rules. Snapshots are captured automatically after scans and local storage changes."
                ) { EmptyView() }
                StorageSnapshotContent(report: model.storageSnapshots, isScanning: model.isScanning)
            }
            .padding(30)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }
}

private struct StorageSnapshotContent: View {
    let report: StorageSnapshotReport
    let isScanning: Bool

    var body: some View {
        if let current = report.current {
            RecordedStorageSnapshots(report: report, current: current)
        } else {
            EmptyStorageSnapshots(isScanning: isScanning)
        }
    }
}

private struct RecordedStorageSnapshots: View {
    let report: StorageSnapshotReport
    let current: StorageSnapshot

    var body: some View {
        StorageSnapshotMetrics(report: report, current: current)
        StorageSnapshotObservation(report: report)
        StorageReclaimPreview(report: report, current: current)
        StorageChanges(report: report)
        StorageSnapshotEntries(entries: current.entries)
        StorageSnapshotTimeline(history: report.history)
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

private struct StorageSnapshotTimeline: View {
    let history: [StorageSnapshot]

    var body: some View {
        if history.count > 1 {
            SoftCard {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Local timeline", systemImage: "clock.arrow.circlepath").font(.headline)
                    ForEach(Array(history.reversed().prefix(8))) { snapshot in
                        HStack {
                            Text(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text(bytes(snapshot.availableBytes) + " free").monospacedDigit().foregroundStyle(.secondary)
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
                Text(change.kind == .newlyObserved ? "First observed by Second Wind · \(change.category)" : change.category)
                    .font(.caption).foregroundStyle(.secondary)
                Text(change.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text(changeLabel).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
        }
        .padding(.vertical, 5)
    }

    private var symbol: String { change.kind == .shrank ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill" }
    private var tint: Color { change.kind == .shrank ? .green : .orange }
    private var changeLabel: String {
        let amount = ByteCountFormatter.string(fromByteCount: abs(change.byteChange), countStyle: .file)
        return change.kind == .shrank ? "−\(amount)" : "+\(amount)"
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
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: entry.byteSize, countStyle: .file)).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}
