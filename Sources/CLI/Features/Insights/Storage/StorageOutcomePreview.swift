import SwiftUI

struct StorageOutcomePreview: View {
    let available: Int64
    let total: Int64
    let reclaimable: Int64
    var title = "Projected storage outcome"
    var detail = "This forecasts disk storage reclaimed by the reviewed plan. It does not free RAM."

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label(title, systemImage: "arrow.right.circle.fill").font(.headline)
                    Spacer()
                    Text("+\(ByteCountFormatter.string(fromByteCount: reclaimable, countStyle: .file))").font(.headline).foregroundStyle(.green)
                }
                ProgressView(value: Double(min(total, available + reclaimable)), total: Double(max(1, total))).tint(.green)
                HStack {
                    Text("Now: \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available")
                    Spacer()
                    Text("After this plan: up to \(ByteCountFormatter.string(fromByteCount: min(total, available + reclaimable), countStyle: .file))")
                }.font(.caption).foregroundStyle(.secondary)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
