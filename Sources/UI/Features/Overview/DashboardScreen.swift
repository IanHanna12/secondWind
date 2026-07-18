import SwiftUI
import SecondWindCore
import SecondWindMacOS
import SecondWindPersistence

struct DashboardScreen: View {
    let model: SecondWindViewModel
    let openCleanup: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageTitle(
                    eyebrow: "SECOND WIND",
                    title: "Review before making space",
                    detail: "A clear local picture of your Mac, with every change reviewed first."
                ) {
                    Button("Refresh", systemImage: "arrow.clockwise") { model.refreshDashboard() }
                        .buttonStyle(.bordered)
                }

                HomeStatusCard(model: model, openCleanup: openCleanup)

                HStack(spacing: 14) {
                    Metric(title: "Available storage", value: ByteCountFormatter.string(fromByteCount: model.snapshot.storageAvailable, countStyle: .file), symbol: "externaldrive.fill", tint: .mint)
                    Metric(title: "Memory installed", value: ByteCountFormatter.string(fromByteCount: Int64(model.snapshot.physicalMemory), countStyle: .memory), symbol: "memorychip.fill", tint: .blue)
                    Metric(title: "System load", value: String(format: "%.2f", model.snapshot.loadAverage), symbol: "waveform.path.ecg", tint: .orange)
                }

                StorageCategoryHomeCard(report: model.storageSnapshots)

                HStack(alignment: .top, spacing: 16) {
                    SoftCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Storage, explained", systemImage: "internaldrive.fill")
                                .font(.headline)
                            ProgressView(value: Double(model.snapshot.storageUsed), total: Double(max(1, model.snapshot.storageTotal)))
                                .tint(storageTint)
                            HStack {
                                Text("\(ByteCountFormatter.string(fromByteCount: model.snapshot.storageUsed, countStyle: .file)) used")
                                Spacer()
                                Text("\(storagePercentage)%").monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Divider()
                            Text(storageFootnote)
                                .font(.subheadline)
                        }
                    }
                    SoftCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Right now", systemImage: "chart.bar.xaxis")
                                .font(.headline)
                            if model.snapshot.topProcesses.isEmpty {
                                Text("Process data is loading…").foregroundStyle(.secondary)
                            } else {
                                ForEach(model.snapshot.topProcesses.prefix(3)) { process in
                                    HStack {
                                        Text(process.command).lineLimit(1)
                                        Spacer()
                                        Text(String(format: "%.1f%%", process.cpuPercent))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)
                                }
                            }
                            Spacer(minLength: 0)
                            Text("Process readings are local and appear only while Second Wind is open.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SoftCard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Private by design").font(.headline)
                            Text("No telemetry, analytics, cloud sync, update checks, or background network activity.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var storagePercentage: Int {
        Int((Double(model.snapshot.storageUsed) / Double(max(1, model.snapshot.storageTotal))) * 100)
    }

    private var storageTint: Color {
        model.snapshot.storageAvailable < model.snapshot.storageTotal / 10 ? .orange : .green
    }

    private var storageFootnote: String {
        model.isScanning
            ? "Checking the bundled cleanup areas now."
            : "\(model.findings.count) known items were found in the areas Second Wind understands."
    }
}

private struct StorageCategoryHomeCard: View {
    let report: StorageSnapshotReport

    var body: some View {
        if !report.categorySummaries.isEmpty {
            SoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Known storage", systemImage: "square.3.layers.3d.down.right")
                            .font(.headline)
                        Spacer()
                        Text("Local scan")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("A categorized view of storage Second Wind explicitly understands.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(report.categorySummaries.prefix(4)) { summary in
                        HStack {
                            Text(summary.category.title)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: summary.byteSize, countStyle: .file))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }
}

private struct HomeStatusCard: View {
    let model: SecondWindViewModel
    let openCleanup: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Button(actionTitle, action: openCleanup)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isScanning)
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [.green.opacity(0.20), Color(nsColor: .controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.green.opacity(0.16)))
    }

    private var symbol: String {
        model.isScanning ? "magnifyingglass" : model.actionableFindingCount > 0 ? "sparkles" : "checkmark.shield.fill"
    }

    private var eyebrow: String {
        model.isScanning ? "LOCAL SCAN IN PROGRESS" : "STORAGE HEALTH"
    }

    private var title: String {
        if model.isScanning { return "Looking for reclaimable space" }
        if model.snapshot.storageAvailable < model.snapshot.storageTotal / 10 { return "Storage is getting tight" }
        if model.actionableFindingCount > 0 { return "You have space to reclaim" }
        return "Your storage looks healthy"
    }

    private var detail: String {
        if model.isScanning { return "Second Wind is reading only the bundled cleanup locations on this Mac." }
        if model.actionableFindingCount > 0 {
            return "Up to \(ByteCountFormatter.string(fromByteCount: model.actionableBytes, countStyle: .file)) is ready to review. Nothing changes until you approve a plan."
        }
        return "No eligible items were found in the local areas Second Wind knows how to handle safely."
    }

    private var actionTitle: String {
        model.actionableFindingCount > 0 ? "Review cleanup" : "Open Clean Up"
    }
}
