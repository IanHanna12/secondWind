import SwiftUI

/// A read-only map of the existing local data flow. It documents how the
/// app's current facts travel; it is not a second workflow or data model.
struct ArchitectureExplorerScreen: View {
    private let stages = [
        ArchitectureStage("Local inputs", "Known local folders, installed applications, Recovery items, and enabled rules."),
        ArchitectureStage("Storage observation providers", "Providers record factual observations without deciding what to clean."),
        ArchitectureStage("Storage Inventory", "The one canonical, reconciled inventory of locations Second Wind understands."),
        ArchitectureStage("Application Inventory", "A read-only projection that explains storage relationships to installed applications."),
        ArchitectureStage("Snapshots and explorer", "Local snapshots compare the same inventory over time; inspectors only project its facts."),
        ArchitectureStage("Cleanup review and plan", "The user reviews explicit reasons and confirms a plan before anything moves."),
        ArchitectureStage("Recovery and activity", "Completed changes remain locally recoverable and auditable.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(
                    eyebrow: "EXPLAINABLE ARCHITECTURE",
                    title: "How Second Wind knows",
                    detail: "This view maps the existing local flow behind inventory, cleanup, snapshots, and Recovery. It does not expose implementation details or run any work."
                ) { EmptyView() }

                SoftCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(stages) { stage in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(stage.title).font(.headline)
                                    Text(stage.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                SoftCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("What this does not do", systemImage: "eye.slash.fill").font(.headline)
                        Text("No cloud sync, remote telemetry, automatic cleanup, opaque scoring, AI-generated recommendations, or second storage inventory is involved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }
}

private struct ArchitectureStage: Identifiable {
    let title: String
    let detail: String
    var id: String { title }

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }
}
