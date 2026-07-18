import SwiftUI
import SecondWindPlatform

struct ApplicationsScreen: View {
    let model: SecondWindViewModel
    let openCleanup: () -> Void
    @State private var selectedApplicationID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(
                eyebrow: "REVIEWED APP REMOVAL",
                title: "Applications",
                detail: "Inspect an app and its exact support paths before preparing a reversible removal plan."
            ) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    model.loadApplications()
                    selectFirstApplicationIfNeeded()
                }
                .buttonStyle(.bordered)
            }

            if model.applications.isEmpty {
                ContentUnavailableView("No applications found", systemImage: "app.dashed", description: Text("Second Wind checks /Applications and your local Applications folder."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: $selectedApplicationID) {
                        ForEach(model.applications) { app in
                            HStack(spacing: 10) {
                                Image(systemName: "app.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.displayName).lineLimit(1)
                                    Text(app.bundleIdentifier ?? "No bundle identifier")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .tag(app.id)
                        }
                    }
                    .frame(minWidth: 260, idealWidth: 310, maxWidth: 360)

                    ApplicationRemovalDetail(
                        application: selectedApplication,
                        preview: matchingPreview,
                        isLoading: model.isLoadingApplicationPreview,
                        prepareRemoval: {
                            guard let selectedApplication else { return }
                            model.prepareUninstall(selectedApplication)
                            openCleanup()
                        }
                    )
                    .frame(minWidth: 460)
                }
            }
        }
        .padding(32)
        .task {
            if model.applications.isEmpty { model.loadApplications() }
            selectFirstApplicationIfNeeded()
        }
        .onChange(of: selectedApplicationID) { _, newValue in
            guard let app = model.applications.first(where: { $0.id == newValue }) else { return }
            model.inspectApplication(app)
        }
    }

    private var selectedApplication: InstalledApplication? {
        model.applications.first { $0.id == selectedApplicationID }
    }

    private var matchingPreview: ApplicationRemovalPreview? {
        guard let selectedApplication, model.applicationPreview?.application.id == selectedApplication.id else { return nil }
        return model.applicationPreview
    }

    private func selectFirstApplicationIfNeeded() {
        guard selectedApplicationID == nil || !model.applications.contains(where: { $0.id == selectedApplicationID }) else { return }
        selectedApplicationID = model.applications.first?.id
        if let app = model.applications.first {
            model.inspectApplication(app)
        }
    }
}

private struct ApplicationRemovalDetail: View {
    let application: InstalledApplication?
    let preview: ApplicationRemovalPreview?
    let isLoading: Bool
    let prepareRemoval: () -> Void

    var body: some View {
        Group {
            if let application {
                if let preview {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 14) {
                                Image(systemName: "app.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                    .frame(width: 48, height: 48)
                                    .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(application.displayName).font(.title2.bold())
                                    Text(application.url.path)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            HStack(spacing: 12) {
                                Metric(title: "App bundle", value: bytes(preview.applicationBytes), symbol: "app.fill", tint: .blue)
                                Metric(title: "Exact support data", value: bytes(preview.exactRemnantBytes), symbol: "folder.fill", tint: .green)
                                Metric(title: "Reviewed removal", value: bytes(preview.removableBytes), symbol: "arrow.right.circle.fill", tint: .orange)
                            }

                            ApplicationAccessCard(inspection: preview.inspection)

                            SoftCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("Included in a reviewed plan", systemImage: "checkmark.shield.fill")
                                        .font(.headline)
                                        .foregroundStyle(.green)
                                    Text("The app bundle and only exact bundle-identifier support paths are prepared. You will review every path again before it moves.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if preview.exactRemnants.isEmpty {
                                        Text("No exact support paths were found.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(preview.exactRemnants) { remnant in
                                            ApplicationSupportRow(remnant: remnant, tint: .green)
                                        }
                                    }
                                }
                            }

                            if !preview.protectedRemnants.isEmpty {
                                SoftCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Label("Not included automatically", systemImage: "lock.shield.fill")
                                            .font(.headline)
                                            .foregroundStyle(.orange)
                                        Text("These are name-based matches, not proven support paths. They stay protected.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        ForEach(preview.protectedRemnants) { remnant in
                                            ApplicationSupportRow(remnant: remnant, tint: .orange)
                                        }
                                    }
                                }
                            }

                            Button("Prepare reviewed removal", action: prepareRemoval)
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal, 8)
                    }
                } else if isLoading {
                    ContentUnavailableView("Inspecting \(application.displayName)", systemImage: "magnifyingglass", description: Text("Measuring the app bundle and its known support paths locally."))
                } else {
                    ContentUnavailableView("Select an application", systemImage: "app.dashed")
                }
            } else {
                ContentUnavailableView("Select an application", systemImage: "app.dashed", description: Text("Choose an app to see its storage and removal plan."))
            }
        }
    }
}

private struct ApplicationAccessCard: View {
    let inspection: ApplicationRemovalInspection

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Move inspection", systemImage: "checklist.checked")
                    .font(.headline)
                inspectionRow("Path", inspection.path)
                inspectionRow("Owner", inspection.owner)
                inspectionRow("Permissions", inspection.permissions)
                inspectionRow("ACL", inspection.hasExtendedACL ? "Extended ACL present" : "No extended ACL")
                inspectionRow("Protection", inspection.protectionStatus)
                inspectionRow("Move", inspection.moveAuthorization.description)
            }
        }
    }

    private func inspectionRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).frame(width: 78, alignment: .leading)
            Text(value).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

private struct ApplicationSupportRow: View {
    let remnant: AppRemnant
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: remnant.isExactKnownRemnant ? "folder.fill" : "lock.fill")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(remnant.kind.title).font(.caption.weight(.semibold))
                Text(remnant.url.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(remnant.url.path)
                Text(remnant.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(bytes(remnant.byteSize))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}
