import AppKit
import SwiftUI
import SecondWindCore

struct RulesScreen: View {
    let model: SecondWindViewModel
    @State private var policy: RulePolicy
    @State private var route = SafeCleanupRoute.userCaches
    @State private var title = ""
    @State private var explanation = ""

    init(model: SecondWindViewModel) {
        self.model = model
        _policy = State(initialValue: model.rulePolicy)
    }

    var body: some View {
        List {
            if let rulePolicyLoadError = model.rulePolicyLoadError {
                Section("Stored policy unavailable") {
                    Label(rulePolicyLoadError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Second Wind left the stored document untouched and is using its built-in rules for this session. Fix or replace the policy before saving local changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Bundled rules") {
                Text("Bundled routes are fixed safety boundaries. You can disable a rule locally, but cannot redirect it to another path.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(BuiltInRules.all, id: \.id) { rule in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: enabledBinding(for: rule)) {
                            VStack(alignment: .leading) {
                                Text(rule.title)
                                Text("\(rule.relativePath) · \(rule.id) v\(rule.version)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        BuiltInRuleInspector(rule: rule, entries: entriesMatched(by: rule))
                    }
                }
            }
            Section("Add safe route rule") {
                Picker("Approved route", selection: $route) { ForEach(SafeCleanupRoute.allCases) { Text($0.title).tag($0) } }
                TextField("Title", text: $title)
                TextField("Why this is safe", text: $explanation)
                Button("Add rule") {
                    let name = title.isEmpty ? route.title : title
                    let reason = explanation.isEmpty
                        ? "User-approved route within Second Wind's safe boundary."
                        : explanation
                    let change = RulePolicyChange.addUserRule(
                        title: name,
                        route: route,
                        explanation: reason
                    )
                    if let updatedPolicy = model.applyRulePolicyChange(change) {
                        policy = updatedPolicy
                        title = ""
                        explanation = ""
                    }
                }
            }
            Section("Your route rules") {
                if policy.userRules.isEmpty { Text("No local route rules yet.").foregroundStyle(.secondary) }
                ForEach(policy.userRules) { rule in
                    Toggle(isOn: userRuleEnabledBinding(for: rule)) {
                        VStack(alignment: .leading) {
                            Text(rule.title)
                            Text(rule.route.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: removeUserRules)
            }
            Section { Button("Export rules as JSON") { export() } } footer: { Text("JSON is an export record. Rules are created and edited only here.") }
        }
        .navigationTitle("Rules")
    }

    private func enabledBinding(for rule: BuiltInRule) -> Binding<Bool> {
        Binding(
            get: { !policy.disabledBuiltInRuleIDs.contains(rule.id) },
            set: { enabled in
                if let updatedPolicy = model.applyRulePolicyChange(.builtInRule(id: rule.id, enabled: enabled)) {
                    policy = updatedPolicy
                }
            }
        )
    }

    private func userRuleEnabledBinding(for rule: UserCleanupRule) -> Binding<Bool> {
        Binding(
            get: {
                policy.userRules.first(where: { $0.id == rule.id })?.isEnabled ?? false
            },
            set: { enabled in
                if let updatedPolicy = model.applyRulePolicyChange(.userRule(id: rule.id, enabled: enabled)) {
                    policy = updatedPolicy
                }
            }
        )
    }

    private func removeUserRules(at offsets: IndexSet) {
        let ids = Set(offsets.compactMap { index in
            policy.userRules.indices.contains(index) ? policy.userRules[index].id : nil
        })
        guard !ids.isEmpty else { return }
        if let updatedPolicy = model.applyRulePolicyChange(.removeUserRules(ids: ids)) {
            policy = updatedPolicy
        }
    }

    private func entriesMatched(by rule: BuiltInRule) -> [StorageInventoryEntry] {
        model.storageInventory.entries.filter { entry in
            entry.ruleID == rule.id
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Second Wind Rules.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? JSONEncoder.secondWind.encode(policy).write(to: url, options: .atomic)
    }
}

private struct BuiltInRuleInspector: View {
    let rule: BuiltInRule
    let entries: [StorageInventoryEntry]

    var body: some View {
        DisclosureGroup("Inspect rule") {
            VStack(alignment: .leading, spacing: 7) {
                ruleFact("Identifier", rule.id)
                ruleFact("Version", "\(rule.version)")
                ruleFact("Category", StorageCategory.forFindingCategory(rule.category).title)
                ruleFact("Approved root", rule.relativePath)
                ruleFact("Scope", rule.findingScope == .root ? "The approved root" : "Each direct child inside the approved root")
                ruleFact("Supported action", actionDescription)
                ruleFact("Protection behaviour", protectionDescription)
                ruleFact("Match confidence", confidenceDescription)
                Text(rule.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                Text("Current inventory preview · \(entries.count) entries · \(bytes(entries.reduce(0) { $0 + $1.byteSize }))")
                    .font(.caption.weight(.semibold))
                if entries.isEmpty {
                    Text("No current inventory entry matches this rule.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries.prefix(6)) { entry in
                        HStack {
                            Text(entry.title).lineLimit(1)
                            Spacer()
                            Text(bytes(entry.byteSize)).monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.leading, 6)
            .padding(.top, 4)
        }
        .font(.caption)
    }

    private var actionDescription: String {
        switch rule.action {
        case .none: return "No cleanup action"
        case .cleanup: return "Recovery or Finder Trash after review"
        case .uninstall: return "Reviewed application removal"
        }
    }

    private var protectionDescription: String {
        switch rule.risk {
        case .safe: return "Eligible only after the user reviews and confirms a plan"
        case .reviewRequired: return "Visible for deliberate per-item review before planning"
        case .protected: return "Never enters a cleanup plan"
        }
    }

    private var confidenceDescription: String {
        switch rule.confidence {
        case .exact: return "Exact built-in path match"
        case .needsUserReview: return "Known path; its contents require user review"
        }
    }

    private func ruleFact(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).fontWeight(.semibold).frame(width: 112, alignment: .leading)
            Text(value).foregroundStyle(.secondary)
        }
    }
}
