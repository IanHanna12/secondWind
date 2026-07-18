import SwiftUI
import SecondWindPlatform

struct SettingsScreen: View {
    let model: SecondWindViewModel
    private let preferenceService = PreferenceService()

    var body: some View {
        Form {
            Section("Finder and Dock") {
                ForEach(SystemPreference.allCases) { preference in
                    HStack {
                        Toggle(preference.rawValue, isOn: Binding(get: { preferenceService.value(preference) ?? false }, set: { model.setPreference(preference, enabled: $0) }))
                            .disabled(!preferenceService.isSupported(preference))
                        VStack(alignment: .leading) {
                            Text(preference.explanation).font(.caption).foregroundStyle(.secondary)
                            Button("Reset to macOS default") { model.resetPreference(preference) }.font(.caption)
                        }
                    }
                }
            }
            Section("Menu bar") {
                Toggle("Enable menu-bar readout", isOn: Binding(get: { model.menuMonitor }, set: { model.setMenuMonitor(enabled: $0) }))
                Text("The menu-bar monitor is opt-in and performs no network activity.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Version and build") {
                LabeledContent("App version") {
                    Text(BuildIdentity.current.versionDescription)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Source revision") {
                    Text(BuildIdentity.current.revision)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Built") {
                    Text(BuildIdentity.current.buildDateDescription)
                        .textSelection(.enabled)
                }
                Text("The app version describes this development stage. The source revision identifies the exact local source used to build it. Second Wind does not check for updates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .navigationTitle("Settings")
    }
}

private struct BuildIdentity {
    let version: String?
    let buildNumber: String?
    let revision: String
    let buildDate: Date?

    static let current: Self = {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let revision = bundle.object(forInfoDictionaryKey: "SecondWindSourceRevision") as? String
        let buildDateText = bundle.object(forInfoDictionaryKey: "SecondWindBuildDate") as? String
        return Self(
            version: version,
            buildNumber: buildNumber,
            revision: revision.flatMap { $0 == "unavailable" ? nil : $0 } ?? "Not embedded",
            buildDate: buildDateText.flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }()

    var versionDescription: String {
        guard let version else { return "Not embedded" }
        guard let buildNumber else { return version }
        return "\(version) (\(buildNumber))"
    }

    var buildDateDescription: String {
        guard let buildDate else { return "Not embedded" }
        return buildDate.formatted(date: .abbreviated, time: .shortened)
    }
}
