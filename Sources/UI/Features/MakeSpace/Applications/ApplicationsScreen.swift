import SwiftUI
import SecondWindCore
import SecondWindMacOS
import SecondWindPersistence

struct ApplicationsScreen: View {
    let model: SecondWindViewModel
    let openCleanup: () -> Void
    @State private var selectedApplicationID: String?
    @State private var query = ""
    @State private var filter = ApplicationProfileFilter.all
    @State private var sort = ApplicationProfileSort.totalStorage

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(
                eyebrow: "APPLICATION STORAGE",
                title: "Applications",
                detail: "Known storage is grouped by application. Every relationship points back to its original path and never changes cleanup eligibility."
            ) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    model.loadApplications()
                    selectFirstApplicationIfNeeded()
                }
                .buttonStyle(.bordered)
            }

            ApplicationInventorySummary(inventory: model.applicationStorage)
            ApplicationChanges(changes: model.storageSnapshots.applicationChanges) { applicationID in
                selectedApplicationID = applicationID
                inspectSelectedApplication(id: applicationID)
            }

            HStack(spacing: 12) {
                TextField("Search applications or bundle identifiers", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                Picker("Show", selection: $filter) {
                    ForEach(ApplicationProfileFilter.allCases) { filter in Text(filter.title).tag(filter) }
                }
                .labelsHidden()
                .frame(width: 180)
                Picker("Sort", selection: $sort) {
                    ForEach(ApplicationProfileSort.allCases) { sort in Text(sort.title).tag(sort) }
                }
                .labelsHidden()
                .frame(width: 180)
                Spacer()
                Text("\(visibleProfiles.count) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if visibleProfiles.isEmpty {
                ContentUnavailableView(
                    "No matching applications",
                    systemImage: "app.dashed",
                    description: Text("Run a local scan to connect known storage with installed applications, or change the filter."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: $selectedApplicationID) {
                        ForEach(visibleProfiles) { profile in
                            ApplicationProfileRow(profile: profile)
                                .tag(profile.id)
                        }
                    }
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 390)

                        ApplicationStorageDetail(
                            profile: selectedProfile,
                            change: selectedProfile.flatMap { profile in
                                model.storageSnapshots.applicationChanges.first { $0.identity.id == profile.id }
                            },
                            preview: matchingPreview,
                        isLoading: model.isLoadingApplicationPreview,
                        selectEligibleEntries: { entries in
                            model.selectApplicationStorageEntries(entries)
                            openCleanup()
                        },
                        prepareRemoval: {
                            guard let application = selectedInstalledApplication else { return }
                            model.prepareUninstall(application)
                            openCleanup()
                        }
                    )
                    .frame(minWidth: 540)
                }
            }
        }
        .padding(32)
        .task {
            if model.applications.isEmpty { model.loadApplications() }
            selectFirstApplicationIfNeeded()
        }
        .onChange(of: selectedApplicationID) { _, newValue in
            inspectSelectedApplication(id: newValue)
        }
        .onChange(of: visibleProfiles.map(\.id)) { _, _ in
            selectFirstApplicationIfNeeded()
        }
    }

    private var visibleProfiles: [ApplicationProfile] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.applicationStorage.profiles
            .filter { profile in
                filter.matches(profile) && (
                    normalizedQuery.isEmpty ||
                    profile.identity.displayName.lowercased().contains(normalizedQuery) ||
                    profile.identity.bundleIdentifier?.lowercased().contains(normalizedQuery) == true
                )
            }
            .sorted(by: sort.comparator)
    }

    private var selectedProfile: ApplicationProfile? {
        visibleProfiles.first { $0.id == selectedApplicationID }
    }

    private var selectedInstalledApplication: InstalledApplication? {
        guard let selectedProfile else { return nil }
        return model.applications.first {
            $0.bundleIdentifier == selectedProfile.identity.bundleIdentifier || $0.id == selectedProfile.identity.applicationPath
        }
    }

    private var matchingPreview: ApplicationRemovalPreview? {
        guard let application = selectedInstalledApplication,
              model.applicationPreview?.application.id == application.id else { return nil }
        return model.applicationPreview
    }

    private func selectFirstApplicationIfNeeded() {
        guard !visibleProfiles.isEmpty else {
            selectedApplicationID = nil
            return
        }
        guard let selectedApplicationID,
              visibleProfiles.contains(where: { $0.id == selectedApplicationID }) else {
            selectedApplicationID = visibleProfiles.first?.id
            inspectSelectedApplication(id: selectedApplicationID)
            return
        }
    }

    private func inspectSelectedApplication(id: String?) {
        guard let id,
              let application = model.applications.first(where: { $0.bundleIdentifier == id || $0.id == id }) else { return }
        model.inspectApplication(application)
    }
}

private enum ApplicationProfileFilter: String, CaseIterable, Identifiable {
    case all
    case installed
    case possibleOrphans
    case cleanupCandidates
    case sharedStorage

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All applications"
        case .installed: return "Installed"
        case .possibleOrphans: return "Possible orphans"
        case .cleanupCandidates: return "Cleanup candidates"
        case .sharedStorage: return "Shared storage"
        }
    }

    func matches(_ profile: ApplicationProfile) -> Bool {
        switch self {
        case .all: return true
        case .installed: return profile.identity.isInstalled
        case .possibleOrphans: return profile.isPossibleOrphan
        case .cleanupCandidates: return profile.cleanupCandidateBytes > 0
        case .sharedStorage: return profile.hasSharedStorage
        }
    }
}

private enum ApplicationProfileSort: String, CaseIterable, Identifiable {
    case totalStorage
    case relatedStorage
    case name
    case cleanupPotential

    var id: String { rawValue }
    var title: String {
        switch self {
        case .totalStorage: return "Largest storage"
        case .relatedStorage: return "Largest related data"
        case .name: return "Name"
        case .cleanupPotential: return "Cleanup potential"
        }
    }

    var comparator: (ApplicationProfile, ApplicationProfile) -> Bool {
        switch self {
        case .totalStorage: return { $0.totalKnownBytes > $1.totalKnownBytes }
        case .relatedStorage: return { $0.relatedBytes > $1.relatedBytes }
        case .name: return { $0.identity.displayName.localizedStandardCompare($1.identity.displayName) == .orderedAscending }
        case .cleanupPotential: return { $0.cleanupCandidateBytes > $1.cleanupCandidateBytes }
        }
    }
}

private struct ApplicationInventorySummary: View {
    let inventory: ApplicationInventory

    var body: some View {
        HStack(spacing: 12) {
            Metric(title: "Installed", value: "\(inventory.installedProfiles.count)", symbol: "app.fill", tint: .blue)
            Metric(title: "Possible orphans", value: "\(inventory.possibleOrphans.count)", symbol: "questionmark.folder", tint: .orange)
            Metric(title: "Known app storage", value: bytes(inventory.profiles.reduce(0) { $0 + $1.totalKnownBytes }), symbol: "externaldrive.fill", tint: .green)
        }
    }
}

private struct ApplicationChanges: View {
    let changes: [ApplicationChange]
    let selectApplication: (String) -> Void

    var body: some View {
        Group {
            if !changes.isEmpty {
                SoftCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Application storage changes", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.headline)
                        Text("Derived from the same local storage snapshots. Select an application to review the paths behind its known storage.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(changes.prefix(4)) { change in
                            Button {
                                selectApplication(change.identity.id)
                            } label: {
                                HStack {
                                    Text(change.identity.displayName).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text((change.byteChange >= 0 ? "+" : "") + bytes(change.byteChange))
                                        .font(.caption.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(change.byteChange >= 0 ? .orange : .green)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct ApplicationProfileRow: View {
    let profile: ApplicationProfile

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: profile.isPossibleOrphan ? "questionmark.app.fill" : "app.fill")
                .foregroundStyle(profile.isPossibleOrphan ? .orange : .green)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.identity.displayName).lineLimit(1)
                Text(profile.identity.bundleIdentifier ?? "No bundle identifier")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if profile.isPossibleOrphan {
                    Text("Possible orphaned application data")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if profile.cleanupCandidateBytes > 0 {
                    Text("\(bytes(profile.cleanupCandidateBytes)) can be reviewed")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            Spacer(minLength: 8)
            Text(bytes(profile.totalKnownBytes))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 3)
    }
}

private struct ApplicationStorageDetail: View {
    let profile: ApplicationProfile?
    let change: ApplicationChange?
    let preview: ApplicationRemovalPreview?
    let isLoading: Bool
    let selectEligibleEntries: ([ApplicationEntry]) -> Void
    let prepareRemoval: () -> Void

    var body: some View {
        Group {
            if let profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ApplicationProfileHeader(profile: profile)
                        ApplicationMetadataCard(identity: profile.identity)
                        if let change {
                            ApplicationChangeCard(change: change)
                        }
                        HStack(spacing: 12) {
                            Metric(title: "Application", value: bytes(profile.applicationBytes), symbol: "app.fill", tint: .blue)
                            Metric(title: "Related data", value: bytes(profile.relatedBytes), symbol: "folder.fill", tint: .green)
                            Metric(title: "Total known", value: bytes(profile.totalKnownBytes), symbol: "externaldrive.fill", tint: .orange)
                        }

                        if profile.entries.isEmpty {
                            ContentUnavailableView("No known storage yet", systemImage: "folder.badge.questionmark", description: Text("Second Wind found the application, but no explicitly understood storage paths were observed in the latest local scan."))
                        } else {
                            ForEach(profile.relationships) { relationship in
                                ApplicationStorageRelationshipCard(
                                    relationship: relationship,
                                    entries: profile.entries(for: relationship),
                                    selectEligibleEntries: selectEligibleEntries
                                )
                            }
                        }

                        if profile.identity.isInstalled {
                            CompleteApplicationRemovalCard(
                                preview: preview,
                                isLoading: isLoading,
                                prepareRemoval: prepareRemoval
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } else {
                ContentUnavailableView("Select an application", systemImage: "app.dashed", description: Text("Choose an application to see its known storage footprint."))
            }
        }
    }
}

private struct ApplicationChangeCard: View {
    let change: ApplicationChange

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Changed paths since the previous snapshot", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Text("\(change.byteChange >= 0 ? "+" : "")\(bytes(change.byteChange)) across known storage for this application.")
                    .font(.subheadline)
                    .foregroundStyle(change.byteChange >= 0 ? .orange : .green)
                ForEach(change.entryChanges.prefix(5)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.caption.weight(.semibold))
                            Text(changeDescription(entry.kind)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(entry.byteChange >= 0 ? "+" : "")\(bytes(entry.byteChange))")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func changeDescription(_ kind: StorageChangeKind) -> String {
        switch kind {
        case .grew: return "Known path grew"
        case .shrank: return "Known path shrank"
        case .newlyObserved: return "Newly observed"
        case .noLongerObserved: return "No longer observed"
        }
    }
}

private struct ApplicationProfileHeader: View {
    let profile: ApplicationProfile

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: profile.isPossibleOrphan ? "questionmark.app.fill" : "app.fill")
                .font(.title2)
                .foregroundStyle(profile.isPossibleOrphan ? .orange : .green)
                .frame(width: 48, height: 48)
                .background((profile.isPossibleOrphan ? Color.orange : Color.green).opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.identity.displayName).font(.title2.bold())
                Text(profile.isPossibleOrphan ? "Possible orphaned application data" : "Installed application")
                    .font(.subheadline)
                    .foregroundStyle(profile.isPossibleOrphan ? .orange : .secondary)
            }
            Spacer()
        }
    }
}

private struct ApplicationMetadataCard: View {
    let identity: ApplicationIdentity

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 7) {
                Label("Application metadata", systemImage: "info.circle")
                    .font(.headline)
                metadataRow("Bundle ID", identity.bundleIdentifier ?? "Unavailable")
                metadataRow("Version", identity.version ?? "Unavailable")
                metadataRow("Build", identity.build ?? "Unavailable")
                metadataRow("Location", identity.applicationPath ?? "Application bundle not found")
            }
        }
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).frame(width: 72, alignment: .leading)
            Text(value).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        }
    }
}

private struct ApplicationStorageRelationshipCard: View {
    let relationship: ApplicationStorageRelationship
    let entries: [ApplicationEntry]
    let selectEligibleEntries: ([ApplicationEntry]) -> Void

    private var totalBytes: Int64 { entries.reduce(0) { $0 + $1.storage.byteSize } }
    private var eligibleEntries: [ApplicationEntry] { entries.filter { $0.storage.isActionable } }

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(relationship.title, systemImage: icon)
                        .font(.headline)
                    Spacer()
                    Text(bytes(totalBytes)).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                ForEach(entries) { entry in
                    ApplicationEntryRow(entry: entry)
                }
                if !eligibleEntries.isEmpty {
                    Button("Select eligible items for cleanup") {
                        selectEligibleEntries(eligibleEntries)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var icon: String {
        switch relationship {
        case .application: return "app.fill"
        case .cache: return "bolt.fill"
        case .logs: return "doc.text.fill"
        case .preferences: return "gearshape.fill"
        case .container, .groupContainer: return "shippingbox.fill"
        case .developerData: return "hammer.fill"
        case .sharedResource: return "person.2.fill"
        default: return "folder.fill"
        }
    }
}

private struct ApplicationEntryRow: View {
    let entry: ApplicationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.storage.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(bytes(entry.storage.byteSize)).font(.caption.weight(.semibold)).monospacedDigit()
            }
            if let path = entry.storage.path {
                Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(path)
            }
            Text(entry.association.reason).font(.caption).foregroundStyle(.secondary)
            Text("\(entry.storage.origin) · \(entry.storage.explanation)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(dataKind)
                Text(entry.association.evidence.title)
                Text(entry.storage.isActionable ? "Eligible for existing cleanup review" : entry.storage.risk == .protected ? "Protected" : "Review required")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(entry.storage.isActionable ? .green : entry.storage.risk == .protected ? .orange : .secondary)
        }
        .padding(.vertical, 3)
    }

    private var dataKind: String {
        switch entry.association.relationship {
        case .cache, .logs, .generatedData, .developerData:
            return "Generated data"
        case .supportData, .preferences, .savedApplicationState, .container, .userData:
            return "Application or user data"
        case .sharedResource, .groupContainer:
            return "Shared data"
        case .application:
            return "Application bundle"
        default:
            return "Known storage"
        }
    }
}

private struct CompleteApplicationRemovalCard: View {
    let preview: ApplicationRemovalPreview?
    let isLoading: Bool
    let prepareRemoval: () -> Void

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Complete application removal review", systemImage: "checklist.checked")
                    .font(.headline)
                if let preview {
                    Text("The application bundle and exact bundle-identifier support paths can enter the existing reviewed removal workflow. Name-based, shared, and uncertain paths remain protected.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ApplicationAccessCard(inspection: preview.inspection)
                    Button("Prepare reviewed removal", action: prepareRemoval)
                        .buttonStyle(.borderedProminent)
                } else if isLoading {
                    ProgressView("Inspecting application removal")
                } else {
                    Text("Removal inspection is unavailable until this installed app is selected again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ApplicationAccessCard: View {
    let inspection: ApplicationRemovalInspection

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Move inspection").font(.subheadline.weight(.semibold))
            inspectionRow("Owner", inspection.owner)
            inspectionRow("Permissions", inspection.permissions)
            inspectionRow("ACL", inspection.hasExtendedACL ? "Extended ACL present" : "No extended ACL")
            inspectionRow("Protection", inspection.protectionStatus)
            inspectionRow("Move", inspection.moveAuthorization.description)
        }
    }

    private func inspectionRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).frame(width: 78, alignment: .leading)
            Text(value).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
