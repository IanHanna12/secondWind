import SwiftUI
import SecondWindApplication
import SecondWindCore

struct CleanupFindingSection: View {
    let group: CleanupFindingGroup
    let items: [Finding]
    let model: SecondWindViewModel

    var body: some View {
        Section {
            ForEach(items) { item in
                if let candidate = model.cleanupReviewCandidates[item.id] {
                    FindingRow(
                        candidate: candidate,
                        isSelected: model.selectedIDs.contains(item.id),
                        toggleSelection: item.risk.isExecutable && item.supportedAction != .none
                            ? { model.toggleSelection(for: item) }
                            : nil
                    )
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: group.symbol)
                Text(group.title)
                Spacer()
                Text(group.detail)
                Button(group.actionTitle, systemImage: group.actionSymbol) {
                    model.addEligibleFindings(items)
                }
                .buttonStyle(.bordered)
                .disabled(!group.isSelectable)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(group.tint)
        }
    }
}

struct FindingRow: View {
    let candidate: CleanupReviewCandidate
    let isSelected: Bool
    let toggleSelection: (() -> Void)?

    private var item: Finding { candidate.finding }

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
                Text(candidate.reason.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Suggested by: \(candidate.reason.origin)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(candidate.regeneration.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(candidate.recovery.detail)
                    .font(.caption2)
                    .foregroundStyle(candidate.recovery == .available ? .green : .secondary)
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
        let name = LocalPathDisplay.name(for: url)
        return "\(url.deletingLastPathComponent().lastPathComponent)/\(name)"
    }
}
