import SwiftUI
import SecondWindCore
import SecondWindMacOS

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
                            warningSection(for: plan)
                            actionSections(for: plan)
                            nextStepSection
                            destinationSection
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

    @ViewBuilder
    private func warningSection(for plan: CleanupPlan) -> some View {
        if !plan.warnings.isEmpty {
            Section("Before you confirm") {
                ForEach(plan.warnings, id: \.self) {
                    Label($0, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Toggle("I reviewed the items that need attention.", isOn: $acknowledgedWarnings)
            }
        }
    }

    @ViewBuilder
    private func actionSections(for plan: CleanupPlan) -> some View {
        ForEach(PlanActionGroup.allCases) { group in
            let actions = group.actions(in: plan.actions)
            if !actions.isEmpty {
                Section {
                    ForEach(actions) { PlanActionRow(action: $0) }
                } header: {
                    Label(group.title, systemImage: group.symbol)
                        .foregroundStyle(group.tint)
                }
            }
        }
    }

    private var nextStepSection: some View {
        Section("What happens next") {
            Label("Choose a final action below. Both options keep the reviewed items recoverable; opening this sheet never moves files.", systemImage: "arrow.left.arrow.right.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    private var destinationSection: some View {
        Section("Choose what happens") {
            CleanupDestinationButton(
                detail: "Move the reviewed items to Finder Trash. macOS keeps them available until you empty Trash.",
                title: "Move to Trash",
                symbol: "trash",
                action: { model.executePlan(destination: .finderTrash) }
            )
            CleanupDestinationButton(
                detail: "Store the reviewed items locally so you can restore them later. Recovery storage is never deleted automatically.",
                title: "Keep in Recovery",
                symbol: "arrow.uturn.backward.circle",
                prominent: true,
                action: { model.executePlan(destination: .recovery) }
            )
        }
        .disabled(requiresWarningAcknowledgement)
    }

    private var requiresWarningAcknowledgement: Bool {
        model.proposedPlan?.warnings.isEmpty == false && !acknowledgedWarnings
    }
}

private struct CleanupDestinationButton: View {
    let detail: String
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if prominent {
                Button(title, systemImage: symbol, action: action)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(title, systemImage: symbol, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
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
