import Combine
import SwiftUI
import SecondWindCore
import SecondWindMacOS

struct SystemMonitorScreen: View {
    let model: SecondWindViewModel

    private let timer = Timer
        .publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageTitle
                gauges
                systemCards
                topProcesses
            }
            .padding(30)
            .frame(maxWidth: 1_100, alignment: .leading)
        }
        .onAppear { model.refreshDashboard(); model.refreshLiveMetrics() }
        .onReceive(timer) { _ in model.refreshDashboard(); model.refreshLiveMetrics() }
    }

    private var pageTitle: some View {
        PageTitle(
            eyebrow: "LIVE LOCAL METRICS",
            title: "System monitor",
            detail: "Refreshes every second while this view is open."
        ) {
            Button("Refresh", systemImage: "arrow.clockwise") {
                model.refreshDashboard()
                model.refreshLiveMetrics()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var gauges: some View {
        HStack(spacing: 14) {
            LiveGauge(
                title: "CPU utilization",
                value: model.liveMetrics.cpuUtilization,
                detail: model.liveMetrics.cpuUtilization == nil ? "Calculating…" : "Across all logical cores",
                tint: .orange,
                symbol: "cpu"
            )
            LiveGauge(
                title: "Memory population",
                value: model.liveMetrics.memory.usedFraction,
                detail: memoryText(model.liveMetrics.memory.usedBytes, label: "used"),
                tint: .blue,
                symbol: "memorychip"
            )
            LiveGauge(
                title: "Storage used",
                value: storageUsedFraction,
                detail: storageText(model.snapshot.storageAvailable, label: "available"),
                tint: .mint,
                symbol: "internaldrive"
            )
        }
    }

    private var systemCards: some View {
        HStack(alignment: .top, spacing: 16) {
            memoryPressureCard
            graphicsCard
        }
    }

    private var memoryPressureCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Memory pressure", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.headline)
                Text(model.liveMetrics.memory.pressureLabel)
                    .font(.title2.bold())
                    .foregroundStyle(pressureColor(model.liveMetrics.memory.pressureLabel))
                Text("\(memoryText(model.liveMetrics.memory.availableBytes, label: "immediately available")) of \(memoryText(model.liveMetrics.memory.totalBytes, label: "total")).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var graphicsCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Graphics", systemImage: "rectangle.inset.filled")
                    .font(.headline)
                Text(model.liveMetrics.gpuName ?? "GPU unavailable")
                    .font(.headline)
                Text("macOS does not provide a stable public per-GPU utilization counter. This shows the active Metal device, not a guessed percentage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var topProcesses: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Top CPU processes", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                if model.snapshot.topProcesses.isEmpty {
                    Text("Process sampling is loading…")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.snapshot.topProcesses) { process in
                        ProcessUsageRow(process: process)
                    }
                }
            }
        }
    }

    private var storageUsedFraction: Double {
        Double(model.snapshot.storageUsed) / Double(max(1, model.snapshot.storageTotal))
    }

    private func memoryText(_ bytes: Int64, label: String) -> String {
        "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)) \(label)"
    }

    private func storageText(_ bytes: Int64, label: String) -> String {
        "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) \(label)"
    }

    private func pressureColor(_ label: String) -> Color {
        switch label {
        case "Normal": return .green
        case "Elevated": return .orange
        default: return .red
        }
    }
}

private struct ProcessUsageRow: View {
    let process: ProcessUsage

    var body: some View {
        HStack {
            Text(process.command)
                .lineLimit(1)
            Spacer()
            Text(String(format: "%.1f%% CPU", process.cpuPercent))
                .monospacedDigit()
            Text(ByteCountFormatter.string(fromByteCount: process.residentMemoryBytes, countStyle: .memory))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .font(.subheadline)
    }
}
