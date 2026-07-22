import AppKit
import SwiftUI
import SecondWindCore
import SecondWindPersistence

struct RulesScreen: View {
    @State private var policy: RulePolicy
    @State private var route = SafeCleanupRoute.userCaches
    @State private var title = ""
    @State private var explanation = ""
    private let store = RulePolicyStore()

    init() { _policy = State(initialValue: RulePolicyStore().policy()) }

    var body: some View {
        List {
            Section("Bundled rules") {
                Text("Bundled routes are fixed safety boundaries. You can disable a rule locally, but cannot redirect it to another path.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(BuiltInRules.all, id: \.id) { rule in
                    Toggle(isOn: enabledBinding(for: rule)) {
                        VStack(alignment: .leading) {
                            Text(rule.title)
                            Text("\(rule.relativePath) · \(rule.risk.rawValue) · \(rule.action.rawValue)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Add safe route rule") {
                Picker("Approved route", selection: $route) { ForEach(SafeCleanupRoute.allCases) { Text($0.title).tag($0) } }
                TextField("Title", text: $title)
                TextField("Why this is safe", text: $explanation)
                Button("Add rule") {
                    let name = title.isEmpty ? route.title : title
                    policy.userRules.append(.init(title: name, route: route, explanation: explanation.isEmpty ? "User-approved route within Second Wind's safe boundary." : explanation))
                    save()
                    title = ""; explanation = ""
                }
            }
            Section("Your route rules") {
                if policy.userRules.isEmpty { Text("No local route rules yet.").foregroundStyle(.secondary) }
                ForEach($policy.userRules) { $rule in
                    Toggle(isOn: $rule.isEnabled) { VStack(alignment: .leading) { Text(rule.title); Text(rule.route.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary) } }
                        .onChange(of: rule.isEnabled) { _, _ in save() }
                }
                .onDelete { policy.userRules.remove(atOffsets: $0); save() }
            }
            Section { Button("Export rules as JSON") { export() } } footer: { Text("JSON is an export record. Rules are created and edited only here.") }
        }
        .navigationTitle("Rules")
    }

    private func enabledBinding(for rule: BuiltInRule) -> Binding<Bool> {
        Binding(
            get: { !policy.disabledBuiltInRuleIDs.contains(rule.id) },
            set: { enabled in
                if enabled {
                    policy.disabledBuiltInRuleIDs.remove(rule.id)
                } else {
                    policy.disabledBuiltInRuleIDs.insert(rule.id)
                }
                save()
            }
        )
    }

    private func save() {
        try? store.save(policy)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Second Wind Rules.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? JSONEncoder.secondWind.encode(policy).write(to: url, options: .atomic)
    }
}
