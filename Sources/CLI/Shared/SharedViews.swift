import SwiftUI
import SecondWindCore

struct PageTitle<Accessory: View>: View {
    let eyebrow: String
    let title: String
    let detail: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow).font(.caption.weight(.bold)).foregroundStyle(.green)
                Text(title).font(.system(size: 34, weight: .bold, design: .rounded))
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
    }
}

struct SoftCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.06)))
    }
}

struct RiskPill: View {
    let risk: Risk

    var body: some View {
        Text(risk.rawValue)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(risk == .safe ? .green : risk == .protected ? .red : .orange)
            .background((risk == .safe ? Color.green : risk == .protected ? Color.red : Color.orange).opacity(0.12), in: Capsule())
    }
}

struct LiveGauge: View {
    let title: String
    let value: Double?
    let detail: String
    let tint: Color
    let symbol: String

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol).foregroundStyle(tint)
                    Text(title).font(.headline)
                }
                Text(value.map { "\(Int($0 * 100))%" } ?? "—")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                ProgressView(value: value ?? 0).tint(tint)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct Metric: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        SoftCard {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.title3.bold()).monospacedDigit()
                }
            }
        }
    }
}

func bytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}
