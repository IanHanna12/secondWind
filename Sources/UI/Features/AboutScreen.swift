import SwiftUI

struct AboutScreen: View {
    var body: some View {
        Form {
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
                Text("Second Wind does not check for updates or send remote telemetry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .navigationTitle("About")
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
