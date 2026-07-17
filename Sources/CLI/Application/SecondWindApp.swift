import AppKit
import Combine
import Observation
import SwiftUI
import UniformTypeIdentifiers
import SecondWindCore
import SecondWindApplication
import SecondWindSystem
import SecondWindPlatform
import SecondWindPersistence

@main
struct SecondWindMain {
    private static var window: NSWindow?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Second Wind"
        window.minSize = NSSize(width: 920, height: 620)
        let hostingView = NSHostingView(rootView: SecondWindRootView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 1120, height: 760)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

private enum AppSection: String, CaseIterable, Identifiable { case dashboard = "Home", snapshots = "Storage history", monitor = "System monitor", cleanup = "Clean Up", applications = "Applications", rules = "Rules", volumeCheck = "Volume check", systemTasks = "System tasks", settings = "Settings", activity = "Recovery & activity"; var id: String { rawValue }
    var symbol: String { switch self { case .dashboard: return "gauge.with.dots.needle.67percent"; case .snapshots: return "clock.arrow.trianglehead.counterclockwise.rotate.90"; case .monitor: return "waveform.path.ecg"; case .cleanup: return "sparkles"; case .applications: return "app.dashed"; case .rules: return "checklist"; case .volumeCheck: return "externaldrive.badge.checkmark"; case .systemTasks: return "wrench.and.screwdriver"; case .settings: return "gearshape"; case .activity: return "clock.arrow.circlepath" } }
}

enum AuditExportFormat { case json, markdown
    var fileName: String { self == .json ? "Second Wind Activity.json" : "Second Wind Activity.md" }
    var contentType: UTType { self == .json ? .json : .plainText }
}

struct CleanupCompletion {
    let itemCount: Int
    let reclaimedBytes: Int64
    let destination: PlanDestination
}

private final class ScanUIBridge: @unchecked Sendable {
    private let receiveProgress: @MainActor @Sendable (ScanProgress) -> Void
    private let receiveCompletion: @MainActor @Sendable ([Finding], StorageSnapshotReport) -> Void

    init(
        receiveProgress: @escaping @MainActor @Sendable (ScanProgress) -> Void,
        receiveCompletion: @escaping @MainActor @Sendable ([Finding], StorageSnapshotReport) -> Void
    ) {
        self.receiveProgress = receiveProgress
        self.receiveCompletion = receiveCompletion
    }

    func report(_ progress: ScanProgress) {
        Task { @MainActor in
            receiveProgress(progress)
        }
    }

    func complete(findings: [Finding], report: StorageSnapshotReport) {
        Task { @MainActor in
            receiveCompletion(findings, report)
        }
    }
}

@MainActor @Observable final class SecondWindViewModel {
    var findings: [Finding] = []
    var selectedIDs: Set<UUID> = []
    var proposedPlan: CleanupPlan?
    var cleanupPresentation: CleanupPresentationPhase = .idle
    var cleanupCompletion: CleanupCompletion?
    var message: String?
    var isScanning = false
    var scanProgress: ScanProgress?
    var snapshot: DashboardSnapshot
    var liveMetrics: LiveSystemMetrics
    var applications: [InstalledApplication] = []
    var applicationPreview: ApplicationRemovalPreview?
    var isLoadingApplicationPreview = false
    private var inspectedApplicationID: String?
    var auditRecords: [AuditRecord]
    var recoveryItems: [RecoveryItem]
    var storageSnapshots = StorageSnapshotReport.empty
    var menuMonitor = UserDefaults.standard.bool(forKey: "menuBarMonitorEnabled")
    let home = FileManager.default.homeDirectoryForCurrentUser
    private let auditStore: AuditStore
    private let recoveryStore: RecoveryStore
    private let monitorService: MonitorService
    private let liveMetricsService: LiveMetricsService
    private let storageSnapshotService = StorageSnapshotService()
    private let preferenceService = PreferenceService()
    private let rulePolicyStore = RulePolicyStore()
    private var scanTask: Task<Void, Never>?
    private var activeScanID: UUID?

    init() {
        let monitorService = MonitorService()
        let auditStore = AuditStore()
        let recoveryStore = RecoveryStore()
        self.monitorService = monitorService
        self.auditStore = auditStore
        self.recoveryStore = recoveryStore
        self.liveMetricsService = LiveMetricsService()
        self.snapshot = monitorService.snapshot()
        self.auditRecords = auditStore.records()
        self.recoveryItems = recoveryStore.allItems()
        liveMetrics = .unavailable
    }

    func scan() {
        cancelScan()
        let scanID = UUID()
        activeScanID = scanID
        isScanning = true
        scanProgress = .init(completedUnits: 0, totalUnits: BuiltInRules.all.count + 2, currentTitle: "Preparing local scan")
        let totalBytes = snapshot.storageTotal
        let availableBytes = snapshot.storageAvailable
        let snapshotService = storageSnapshotService
        let bridge = ScanUIBridge(
            receiveProgress: { [weak self] progress in
                guard self?.activeScanID == scanID else { return }
                self?.scanProgress = progress
            },
            receiveCompletion: { [weak self] results, report in
                guard self?.activeScanID == scanID else { return }
                self?.findings = results
                self?.storageSnapshots = report
                self?.selectedIDs.formIntersection(Set(results.map(\.id)))
                self?.isScanning = false
                self?.scanProgress = nil
                self?.activeScanID = nil
                self?.scanTask = nil
                self?.refreshActivity()
            }
        )
        let rules = rulePolicyStore.effectiveRules()
        scanTask = Task.detached { [home, auditStore, totalBytes, availableBytes, snapshotService, bridge, rules] in
            let localFileSystem = LocalFileSystem()
            let outcome = CleanupScanner(home: home, fileSystem: localFileSystem, rules: rules).scan { progress in
                guard !Task.isCancelled else { return false }
                bridge.report(progress)
                return true
            }
            guard case let .completed(results) = outcome, !Task.isCancelled else { return }
            try? auditStore.append(.init(kind: .scan, ruleVersions: Array(Set(results.map { "\($0.ruleID) v\($0.ruleVersion)" })).sorted(), paths: results.map(\.path), bytes: results.reduce(0) { $0 + $1.byteSize }, result: "\(results.count) findings"))
            let snapshot = snapshotService.capture(findings: results, totalBytes: totalBytes, availableBytes: availableBytes)
            let history = (try? snapshotService.store.append(snapshot)) ?? snapshotService.store.snapshots()
            let report = snapshotService.report(for: snapshot, history: history)
            bridge.complete(findings: results, report: report)
        }
    }
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        activeScanID = nil
        isScanning = false
        scanProgress = nil
    }
    func makePlan() {
        do {
            proposedPlan = try PlanBuilder(home: home).makePlan(
                findings: findings,
                selectedIDs: selectedIDs,
                destination: .recovery
            )
            if let plan = proposedPlan {
                try? auditStore.append(.init(
                    kind: .dryRun,
                    planID: plan.id,
                    ruleVersions: plan.actions.map(\.ruleVersionDescription),
                    paths: plan.actions.map(\.sourcePath),
                    bytes: plan.totalBytes,
                    result: "reviewed plan"
                ))
            }
            cleanupPresentation = .reviewingPlan
            refreshActivity()
        }
        catch { message = error.localizedDescription }
    }
    func executePlan(destination: PlanDestination) {
        guard proposedPlan != nil else { return }
        do {
            let plan = try PlanBuilder(home: home).makePlan(
                findings: findings,
                selectedIDs: selectedIDs,
                destination: destination
            )
            let planBuilder = PlanBuilder(home: home)
            let finderTrashMover = FinderTrashMover()
            let executor = PlanExecutor(
                planBuilder: planBuilder,
                recoveryRepository: recoveryStore,
                trashMover: finderTrashMover,
                auditRecorder: auditStore
            )
            Task {
                do {
                    _ = try await executor.execute(plan.confirmed())
                    cleanupCompletion = .init(itemCount: plan.actions.count, reclaimedBytes: plan.totalBytes, destination: plan.destination)
                    selectedIDs.removeAll()
                    proposedPlan = nil
                    cleanupPresentation = .idle
                    scan()
                    refreshActivity()
                    cleanupPresentation = .showingCompletion
                } catch let error as PlanExecutionError {
                    if case let .actionFailed(completedPaths, _, _) = error, !completedPaths.isEmpty {
                        scan()
                    }
                    message = error.localizedDescription
                } catch {
                    message = error.localizedDescription
                }
            }
        }
        catch { message = error.localizedDescription }
    }
    /// Fast-path Trash still operates only on findings from the current scan.
    /// It intentionally has no public URL-based entry point.
    func moveFindingsDirectlyToTrash(_ candidates: [Finding]) {
        let currentFindings = candidates.filter { candidate in
            findings.contains(where: { $0.id == candidate.id }) &&
                candidate.risk.isExecutable && candidate.supportedAction != .none
        }
        guard !currentFindings.isEmpty else { return }

        Task {
            let finderTrashMover = FinderTrashMover()
            var movedPaths: [String] = []
            var failures: [(path: String, reason: String)] = []

            for finding in currentFindings {
                let url = URL(fileURLWithPath: finding.path).standardizedFileURL
                let path = url.standardizedFileURL.path
                do {
                    try await finderTrashMover.moveToTrash(url)
                    movedPaths.append(path)
                } catch {
                    failures.append((path, error.localizedDescription))
                }
            }

            if !movedPaths.isEmpty {
                let movedFindings = currentFindings.filter { finding in movedPaths.contains(finding.path) }
                try? auditStore.append(.init(
                    kind: .manualTrash,
                    ruleVersions: Array(Set(movedFindings.map { "\($0.ruleID) v\($0.ruleVersion)" })).sorted(),
                    paths: movedPaths,
                    bytes: movedFindings.reduce(0) { $0 + $1.byteSize },
                    destination: .finderTrash,
                    result: "moved \(movedPaths.count) user-selected item(s) to Finder Trash"
                ))
                findings.removeAll { finding in
                    movedPaths.contains { path in
                        finding.path == path || finding.path.hasPrefix(path + "/")
                    }
                }
                selectedIDs.formIntersection(Set(findings.map(\.id)))
            }
            if !failures.isEmpty {
                try? auditStore.append(.init(
                    kind: .failure,
                    ruleVersions: Array(Set(currentFindings.map { "\($0.ruleID) v\($0.ruleVersion)" })).sorted(),
                    paths: failures.map(\.path),
                    bytes: 0,
                    destination: .finderTrash,
                    result: failures.map { "\($0.path): \($0.reason)" }.joined(separator: "\n")
                ))
            }
            refreshActivity()
            if !movedPaths.isEmpty {
                scan()
            }

            switch (movedPaths.count, failures.count) {
            case (0, _):
                message = "Nothing moved to Trash. \(failures.first?.reason ?? "macOS did not allow the change.")"
            case (_, 0):
                message = "Moved \(movedPaths.count) item(s) to Finder Trash."
            default:
                message = "Moved \(movedPaths.count) item(s) to Finder Trash. \(failures.count) could not be moved: \(failures.first?.reason ?? "unknown error")"
            }
        }
    }
    func moveSelectedItemsToTrash() {
        let selectedFindings = findings
            .filter { selectedIDs.contains($0.id) }
        moveFindingsDirectlyToTrash(selectedFindings)
    }
    func refreshDashboard() {
        let monitorService = monitorService
        Task.detached {
            let dashboardSnapshot = monitorService.snapshot(includeProcesses: true)
            await MainActor.run { self.snapshot = dashboardSnapshot }
        }
    }
    func refreshLiveMetrics() { liveMetrics = liveMetricsService.sample() }
    func refreshLiveSystem() {
        refreshLiveMetrics()
        refreshDashboard()
    }
    var selectedBytes: Int64 { findings.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.byteSize } }
    var actionableFindingCount: Int { findings.filter { $0.risk.isExecutable && $0.supportedAction != .none }.count }
    var actionableBytes: Int64 { findings.filter { $0.risk.isExecutable && $0.supportedAction != .none }.reduce(0) { $0 + $1.byteSize } }
    var protectedFindingCount: Int { findings.filter { !$0.risk.isExecutable || $0.supportedAction == .none }.count }
    var reviewRequiredSelectionCount: Int { findings.filter { selectedIDs.contains($0.id) && $0.confidence == .needsUserReview }.count }
    func selectFindings(_ ids: Set<UUID>) {
        let eligible = findings.filter { finding in
            finding.risk.isExecutable && finding.supportedAction != .none
        }.map(\.id)
        selectedIDs = ids.intersection(Set(eligible))
    }
    func toggleSelection(for finding: Finding) {
        var updated = selectedIDs
        if updated.contains(finding.id) {
            updated.remove(finding.id)
        } else {
            updated.insert(finding.id)
        }
        selectFindings(updated)
    }
    func selectSafeFindings(_ candidates: [Finding]) {
        let safeIDs = candidates.filter { $0.risk == .safe && $0.supportedAction != .none }.map(\.id)
        selectFindings(selectedIDs.union(safeIDs))
    }
    func clearSelection() { selectedIDs.removeAll() }
    func loadApplications() { applications = ApplicationInventory(home: home).applications() }
    func inspectApplication(_ app: InstalledApplication) {
        inspectedApplicationID = app.id
        applicationPreview = nil
        isLoadingApplicationPreview = true
        let home = home
        Task { [weak self, app, home] in
            let preview = await Task.detached {
                ApplicationInventory(home: home).removalPreview(for: app)
            }.value
            guard self?.inspectedApplicationID == app.id else { return }
            self?.applicationPreview = preview
            self?.isLoadingApplicationPreview = false
        }
    }
    func prepareUninstall(_ app: InstalledApplication) { let candidates = ApplicationInventory(home: home).uninstallFindings(for: app); findings = candidates; selectedIDs = Set(candidates.filter { $0.risk.isExecutable && $0.supportedAction == .uninstall }.map(\.id)); message = "Removal plan prepared for \(app.displayName). Open Clean Up to review every affected path." }
    func restore(_ item: RecoveryItem) { do { let destination = try recoveryStore.restore(item); try? auditStore.append(.init(kind: .restore, planID: item.planID, ruleVersions: [], paths: [destination.path], bytes: item.byteSize, destination: .recovery, result: "restored")); refreshActivity(); scan(); message = "Restored to \(destination.path)" } catch { message = error.localizedDescription } }
    func deletePermanently(_ item: RecoveryItem) {
        do {
            try recoveryStore.deletePermanently(item)
            try? auditStore.append(.init(kind: .permanentDelete, planID: item.planID, ruleVersions: [], paths: [item.originalPath], bytes: item.byteSize, destination: .recovery, result: "permanently deleted from recovery storage"))
            refreshActivity()
            scan()
            message = "Permanently deleted \(item.originalPath)."
        } catch {
            message = error.localizedDescription
        }
    }
    func recordMaintenanceStarted(task: MaintenanceTask, volume: VolumeReference?) {
        try? auditStore.append(.init(kind: .maintenance, ruleVersions: [task.rawValue], paths: [volume?.url.path ?? "/"], bytes: 0, destination: .systemTask, result: "started"))
        refreshActivity()
    }
    func recordMaintenance(result: Result<MaintenanceExecutionResult, Error>, task: MaintenanceTask, volume: VolumeReference?) {
        let text: String
        let kind: AuditKind
        switch result {
        case .success(let result): text = result.succeeded ? "completed: \(result.output)" : "macOS reported a problem: \(result.output)"; kind = .maintenance
        case .failure(let error): text = "failed: \(error.localizedDescription)"; kind = .failure
        }
        try? auditStore.append(.init(kind: kind, ruleVersions: [task.rawValue], paths: [volume?.url.path ?? "/"], bytes: 0, destination: .systemTask, result: text))
        refreshActivity()
    }
    func setPreference(_ preference: SystemPreference, enabled: Bool) {
        preferenceService.set(preference, enabled: enabled)
        try? auditStore.append(.init(kind: .preference, ruleVersions: [preference.rawValue], paths: [], bytes: 0, result: enabled ? "enabled" : "disabled"))
        refreshActivity()
    }
    func resetPreference(_ preference: SystemPreference) {
        preferenceService.reset(preference)
        try? auditStore.append(.init(kind: .preference, ruleVersions: [preference.rawValue], paths: [], bytes: 0, result: "reset to macOS default"))
        refreshActivity()
    }
    func setMenuMonitor(enabled: Bool) {
        menuMonitor = enabled
        UserDefaults.standard.set(enabled, forKey: "menuBarMonitorEnabled")
        try? auditStore.append(.init(kind: .preference, ruleVersions: ["menuBarMonitor"], paths: [], bytes: 0, result: enabled ? "enabled" : "disabled"))
        refreshActivity()
    }
    func exportAudit(_ format: AuditExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = format.fileName
        panel.allowedContentTypes = [format.contentType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data: Data
            switch format {
            case .json: data = try auditStore.exportJSON()
            case .markdown: data = Data(auditStore.exportMarkdown().utf8)
            }
            try data.write(to: url, options: .atomic)
            message = "Exported local activity to \(url.lastPathComponent)."
        } catch { message = error.localizedDescription }
    }
    func refreshActivity() { auditRecords = auditStore.records(); recoveryItems = recoveryStore.allItems() }
}

enum CleanupPresentationPhase {
    case idle
    case reviewingPlan
    case showingCompletion
}

private struct SecondWindRootView: View {
    @State private var model = SecondWindViewModel()
    @State private var navigation = NavigationModel()
    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.section) {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "wind.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Second Wind").font(.headline)
                            Text("Private Mac care").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 10)
                }
                Section("OVERVIEW") {
                    sidebarItem(.dashboard)
                }
                Section("MAKE SPACE") {
                    sidebarItem(.cleanup)
                    sidebarItem(.applications)
                    sidebarItem(.rules)
                }
                Section("INSIGHTS") {
                    sidebarItem(.snapshots)
                    sidebarItem(.monitor)
                    sidebarItem(.activity)
                }
                Section("SYSTEM") {
                    sidebarItem(.volumeCheck)
                    sidebarItem(.systemTasks)
                    sidebarItem(.settings)
                }
            }
                .listStyle(.sidebar)
                .navigationTitle("Second Wind")
        } detail: {
            switch navigation.section ?? .dashboard {
            case .dashboard: DashboardView(model: model) { navigation.section = .cleanup }
            case .snapshots: StorageSnapshotsView(model: model)
            case .monitor: LiveSystemView(model: model)
            case .cleanup: CleanupView(model: model)
            case .applications: ApplicationsView(model: model) { navigation.section = .cleanup }
            case .rules: RulesView()
            case .volumeCheck: VolumeCheckView(model: model)
            case .systemTasks: SystemTasksView(model: model)
            case .settings: SettingsView(model: model)
            case .activity: ActivityView(model: model)
            }
        }
        .alert("Second Wind", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
        .sheet(isPresented: Binding(
            get: { model.cleanupPresentation == .reviewingPlan },
            set: { if !$0, model.cleanupPresentation == .reviewingPlan { model.cleanupPresentation = .idle } }
        )) { PlanReviewView(model: model) }
        .sheet(isPresented: Binding(
            get: { model.cleanupPresentation == .showingCompletion },
            set: { if !$0, model.cleanupPresentation == .showingCompletion { model.cleanupPresentation = .idle } }
        )) {
            if let completion = model.cleanupCompletion {
                CleanupCompletionView(completion: completion) { navigation.section = .activity }
            }
        }
        .task { model.refreshDashboard(); model.scan() }
        .frame(minWidth: 920, minHeight: 620)
    }

    @ViewBuilder
    private func sidebarItem(_ section: AppSection) -> some View {
        Label(section.rawValue, systemImage: section.symbol).tag(section)
    }
}

@MainActor @Observable private final class NavigationModel { var section: AppSection? = .dashboard }

private struct DashboardView: View {
    let model: SecondWindViewModel
    let openCleanup: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageTitle(
                    eyebrow: "SECOND WIND",
                    title: "Review before making space",
                    detail: "A clear local picture of your Mac, with every change reviewed first."
                ) {
                    Button("Refresh", systemImage: "arrow.clockwise") { model.refreshDashboard() }
                        .buttonStyle(.bordered)
                }

                HomeStatusCard(model: model, openCleanup: openCleanup)

                HStack(spacing: 14) {
                    Metric(title: "Available storage", value: ByteCountFormatter.string(fromByteCount: model.snapshot.storageAvailable, countStyle: .file), symbol: "externaldrive.fill", tint: .mint)
                    Metric(title: "Memory installed", value: ByteCountFormatter.string(fromByteCount: Int64(model.snapshot.physicalMemory), countStyle: .memory), symbol: "memorychip.fill", tint: .blue)
                    Metric(title: "System load", value: String(format: "%.2f", model.snapshot.loadAverage), symbol: "waveform.path.ecg", tint: .orange)
                }

                HStack(alignment: .top, spacing: 16) {
                    SoftCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Storage, explained", systemImage: "internaldrive.fill")
                                .font(.headline)
                            ProgressView(value: Double(model.snapshot.storageUsed), total: Double(max(1, model.snapshot.storageTotal)))
                                .tint(storageTint)
                            HStack {
                                Text("\(ByteCountFormatter.string(fromByteCount: model.snapshot.storageUsed, countStyle: .file)) used")
                                Spacer()
                                Text("\(storagePercentage)%").monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Divider()
                            Text(storageFootnote)
                                .font(.subheadline)
                        }
                    }
                    SoftCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Right now", systemImage: "chart.bar.xaxis")
                                .font(.headline)
                            if model.snapshot.topProcesses.isEmpty {
                                Text("Process data is loading…").foregroundStyle(.secondary)
                            } else {
                                ForEach(model.snapshot.topProcesses.prefix(3)) { process in
                                    HStack {
                                        Text(process.command).lineLimit(1)
                                        Spacer()
                                        Text(String(format: "%.1f%%", process.cpuPercent))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)
                                }
                            }
                            Spacer(minLength: 0)
                            Text("Process readings are local and appear only while Second Wind is open.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SoftCard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Private by design").font(.headline)
                            Text("No telemetry, analytics, cloud sync, update checks, or background network activity.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var storagePercentage: Int {
        Int((Double(model.snapshot.storageUsed) / Double(max(1, model.snapshot.storageTotal))) * 100)
    }

    private var storageTint: Color {
        model.snapshot.storageAvailable < model.snapshot.storageTotal / 10 ? .orange : .green
    }

    private var storageFootnote: String {
        model.isScanning
            ? "Checking the bundled cleanup areas now."
            : "\(model.findings.count) known items were found in the areas Second Wind understands."
    }
}

private struct HomeStatusCard: View {
    let model: SecondWindViewModel
    let openCleanup: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Button(actionTitle, action: openCleanup)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isScanning)
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [.green.opacity(0.20), Color(nsColor: .controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.green.opacity(0.16)))
    }

    private var symbol: String {
        model.isScanning ? "magnifyingglass" : model.actionableFindingCount > 0 ? "sparkles" : "checkmark.shield.fill"
    }

    private var eyebrow: String {
        model.isScanning ? "LOCAL SCAN IN PROGRESS" : "STORAGE HEALTH"
    }

    private var title: String {
        if model.isScanning { return "Looking for reclaimable space" }
        if model.snapshot.storageAvailable < model.snapshot.storageTotal / 10 { return "Storage is getting tight" }
        if model.actionableFindingCount > 0 { return "You have space to reclaim" }
        return "Your storage looks healthy"
    }

    private var detail: String {
        if model.isScanning { return "Second Wind is reading only the bundled cleanup locations on this Mac." }
        if model.actionableFindingCount > 0 {
            return "Up to \(ByteCountFormatter.string(fromByteCount: model.actionableBytes, countStyle: .file)) is ready to review. Nothing changes until you approve a plan."
        }
        return "No eligible items were found in the local areas Second Wind knows how to handle safely."
    }

    private var actionTitle: String {
        model.actionableFindingCount > 0 ? "Review cleanup" : "Open Clean Up"
    }
}

private struct CleanupView: View {
    let model: SecondWindViewModel
    @State private var query = ""
    @State private var riskFilter = CleanupRiskFilter.all
    @State private var categoryFilter: FindingCategory?
    @State private var sortOrder = CleanupSortOrder.size

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(
                eyebrow: "REVIEW BEFORE YOU CHANGE",
                title: "Clean Up",
                detail: "Scan is read-only. Every selected item is shown again in a plan before anything moves."
            ) {
                Button(model.isScanning ? "Cancel scan" : "Scan", systemImage: model.isScanning ? "xmark" : "arrow.clockwise") {
                    model.isScanning ? model.cancelScan() : model.scan()
                }
                    .buttonStyle(.borderedProminent)
            }

            CleanupReadinessCard(model: model, visibleFindings: visibleFindings)

            SoftCard {
                HStack {
                        Picker("Show", selection: $riskFilter) {
                            ForEach(CleanupRiskFilter.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(CleanupSortOrder.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        if !categoryTotals.isEmpty {
                            Menu {
                                Button("All categories") {
                                    categoryFilter = nil
                                }
                                Divider()
                                ForEach(categoryTotals) { total in
                                    Button {
                                        categoryFilter = total.category
                                    } label: {
                                        Label(
                                            "\(total.category.title) · \(ByteCountFormatter.string(fromByteCount: total.bytes, countStyle: .file))",
                                            systemImage: categoryFilter == total.category
                                                ? "checkmark.circle.fill"
                                                : total.category == .developer ? "hammer.fill" : "externaldrive.fill"
                                        )
                                    }
                                }
                            } label: {
                                Label(categoryFilter?.title ?? "All categories", systemImage: "chart.pie.fill")
                            }
                        }
                        Spacer()
                        Text("\(visibleFindings.count) shown")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                }
            }

            if model.findings.isEmpty && !model.isScanning {
                ContentUnavailableView("No known cleanup items", systemImage: "checkmark.shield", description: Text("Second Wind found nothing eligible under its bundled, local rules."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(CleanupFindingGroup.allCases) { group in
                        let items = group.items(in: visibleFindings)
                        if !items.isEmpty {
                            Section {
                                ForEach(items) { item in
                                    FindingRow(
                                        item: item,
                                        isSelected: model.selectedIDs.contains(item.id),
                                        toggleSelection: item.risk.isExecutable && item.supportedAction != .none
                                            ? { model.toggleSelection(for: item) }
                                            : nil
                                    )
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: group.symbol)
                                    Text(group.title)
                                    Spacer()
                                    Text(group.detail)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(group.tint)
                            }
                        }
                    }
                }
                .searchable(text: $query, prompt: "Search names or paths")
            }
        }
        .padding(32)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CleanupSelectionBar(model: model)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(.regularMaterial)
        }
    }

    private var visibleFindings: [Finding] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = model.findings.filter { finding in
            let riskMatches = riskFilter.matches(finding.risk)
            let categoryMatches = categoryFilter == nil || finding.category == categoryFilter
            let queryMatches = normalizedQuery.isEmpty || finding.title.lowercased().contains(normalizedQuery) || finding.path.lowercased().contains(normalizedQuery)
            return riskMatches && categoryMatches && queryMatches
        }
        return filtered.sorted(by: sortOrder.comparator)
    }

    private var categoryTotals: [CleanupCategoryTotal] {
        Dictionary(grouping: model.findings.compactMap { finding -> (FindingCategory, Int64)? in
            guard let category = finding.category else { return nil }
            return (category, finding.byteSize)
        }, by: \.0)
        .map { category, values in
            CleanupCategoryTotal(category: category, bytes: values.reduce(0) { $0 + $1.1 })
        }
        .sorted { $0.bytes > $1.bytes }
    }

}

private struct CleanupReadinessCard: View {
    let model: SecondWindViewModel
    let visibleFindings: [Finding]

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let progress = model.scanProgress {
                    ProgressView(value: progress.fraction)
                        .tint(tint)
                        .frame(maxWidth: 260)
                }
            }
            Spacer()
            if !model.isScanning && model.actionableFindingCount > 0 {
                Button("Select safe items") { model.selectSafeFindings(visibleFindings) }
                    .buttonStyle(.bordered)
                    .disabled(!visibleFindings.contains { $0.risk == .safe && $0.supportedAction != .none })
            }
        }
        .padding(18)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(0.14)))
    }

    private var tint: Color {
        model.isScanning ? .blue : model.actionableFindingCount > 0 ? .green : .secondary
    }
    private var symbol: String {
        model.isScanning ? "magnifyingglass" : model.actionableFindingCount > 0 ? "checkmark.shield.fill" : "checkmark.circle.fill"
    }
    private var eyebrow: String {
        model.isScanning ? "LOCAL SCAN IN PROGRESS" : "STEP 1 OF 2 · CHOOSE ITEMS"
    }
    private var title: String {
        if model.isScanning { return "Checking the cleanup areas Second Wind understands" }
        if model.actionableFindingCount > 0 { return "\(model.actionableFindingCount) items are eligible to review" }
        return "Nothing eligible needs attention"
    }
    private var detail: String {
        if model.isScanning {
            let currentTitle = model.scanProgress?.currentTitle ?? "local locations"
            return "Checking \(currentTitle) · no files are changed while scanning."
        }
        if model.actionableFindingCount > 0 {
            return "Up to \(ByteCountFormatter.string(fromByteCount: model.actionableBytes, countStyle: .file)) is available across safe and review-required items."
        }
        return "Protected items, if present, remain visible but can never be selected."
    }
}

private struct CleanupSelectionBar: View {
    let model: SecondWindViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectionSummary)
                    .font(.subheadline.weight(.semibold))
                if model.reviewRequiredSelectionCount > 0 {
                    Label("\(model.reviewRequiredSelectionCount) selected item(s) need your attention", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if model.selectedIDs.isEmpty {
                    Text("Use the circle beside an item to add it to your plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("You will review a complete plan before anything changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.selectedBytes > 0 {
                Text("+\(ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            if !model.selectedIDs.isEmpty {
                Button("Clear selection") { model.clearSelection() }
            }
            Button("Move selected items to Trash", systemImage: "trash") {
                model.moveSelectedItemsToTrash()
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedIDs.isEmpty)
            Button("Review plan") { model.makePlan() }
                .disabled(model.selectedIDs.isEmpty)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }

    private var selectionSummary: String {
        model.selectedIDs.isEmpty
            ? "Select items to continue"
            : "\(model.selectedIDs.count) selected · \(ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))"
    }
}

private struct CleanupCategoryTotal: Identifiable {
    let category: FindingCategory
    let bytes: Int64
    var id: FindingCategory { category }
}

private enum CleanupFindingGroup: CaseIterable, Identifiable {
    case safe, reviewRequired, protected
    var id: String { title }
    var risk: Risk {
        switch self {
        case .safe: return .safe
        case .reviewRequired: return .reviewRequired
        case .protected: return .protected
        }
    }
    var title: String {
        switch self {
        case .safe: return "Safe to clean"
        case .reviewRequired: return "Needs your review"
        case .protected: return "Protected"
        }
    }
    var detail: String {
        switch self {
        case .safe: return "reversible"
        case .reviewRequired: return "select deliberately"
        case .protected: return "cannot be selected"
        }
    }
    var symbol: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .reviewRequired: return "exclamationmark.shield.fill"
        case .protected: return "lock.shield.fill"
        }
    }
    var tint: Color {
        switch self {
        case .safe: return .green
        case .reviewRequired: return .orange
        case .protected: return .red
        }
    }
    func items(in findings: [Finding]) -> [Finding] {
        findings.filter { $0.risk == risk }
    }
}

private enum CleanupRiskFilter: String, CaseIterable, Identifiable {
    case all, safe, reviewRequired, protected
    var id: String { rawValue }
    var title: String {
        switch self { case .all: return "All items"; case .safe: return "Safe"; case .reviewRequired: return "Needs review"; case .protected: return "Protected" }
    }
    func matches(_ risk: Risk) -> Bool {
        switch self {
        case .all: return true
        case .safe: return risk == .safe
        case .reviewRequired: return risk == .reviewRequired
        case .protected: return risk == .protected
        }
    }
}

private enum CleanupSortOrder: String, CaseIterable, Identifiable {
    case size, name, risk
    var id: String { rawValue }
    var title: String { switch self { case .size: return "Largest first"; case .name: return "Name"; case .risk: return "Safety" } }
    var comparator: (Finding, Finding) -> Bool {
        switch self {
        case .size: return { $0.byteSize == $1.byteSize ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.byteSize > $1.byteSize }
        case .name: return { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .risk: return { $0.risk.rawValue == $1.risk.rawValue ? $0.byteSize > $1.byteSize : $0.risk.rawValue < $1.risk.rawValue }
        }
    }
}
private struct LiveSystemView: View {
    let model: SecondWindViewModel
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 20) {
        PageTitle(eyebrow: "LIVE LOCAL METRICS", title: "System monitor", detail: "Refreshes every second while this view is open.") { Button("Refresh", systemImage: "arrow.clockwise") { model.refreshLiveSystem() }.buttonStyle(.borderedProminent) }
        HStack(spacing: 14) { LiveGauge(title: "CPU utilization", value: model.liveMetrics.cpuUtilization, detail: model.liveMetrics.cpuUtilization == nil ? "Calculating…" : "Across all logical cores", tint: .orange, symbol: "cpu"); LiveGauge(title: "Memory population", value: model.liveMetrics.memory.usedFraction, detail: ByteCountFormatter.string(fromByteCount: model.liveMetrics.memory.usedBytes, countStyle: .memory) + " used", tint: .blue, symbol: "memorychip"); LiveGauge(title: "Storage used", value: Double(model.snapshot.storageUsed) / Double(max(1, model.snapshot.storageTotal)), detail: ByteCountFormatter.string(fromByteCount: model.snapshot.storageAvailable, countStyle: .file) + " available", tint: .mint, symbol: "internaldrive") }
        HStack(alignment: .top, spacing: 16) { SoftCard { VStack(alignment: .leading, spacing: 10) { Label("Memory pressure", systemImage: "gauge.with.dots.needle.67percent").font(.headline); Text(model.liveMetrics.memory.pressureLabel).font(.title2.bold()).foregroundStyle(pressureColor(model.liveMetrics.memory.pressureLabel)); Text("\(ByteCountFormatter.string(fromByteCount: model.liveMetrics.memory.availableBytes, countStyle: .memory)) immediately available of \(ByteCountFormatter.string(fromByteCount: model.liveMetrics.memory.totalBytes, countStyle: .memory)).").font(.caption).foregroundStyle(.secondary) } }; SoftCard { VStack(alignment: .leading, spacing: 10) { Label("Graphics", systemImage: "rectangle.inset.filled").font(.headline); Text(model.liveMetrics.gpuName ?? "GPU unavailable").font(.headline); Text("macOS does not provide a stable public per-GPU utilization counter. This shows the active Metal device, not a guessed percentage.").font(.caption).foregroundStyle(.secondary) } } }
        SoftCard { VStack(alignment: .leading, spacing: 12) { Label("Top CPU processes", systemImage: "chart.bar.xaxis").font(.headline); if model.snapshot.topProcesses.isEmpty { Text("Process sampling is loading…").foregroundStyle(.secondary) } else { ForEach(model.snapshot.topProcesses) { process in HStack { Text(process.command).lineLimit(1); Spacer(); Text(String(format: "%.1f%% CPU", process.cpuPercent)).monospacedDigit(); Text(ByteCountFormatter.string(fromByteCount: process.residentMemoryBytes, countStyle: .memory)).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing) }.font(.subheadline) } } } }
    }.padding(30).frame(maxWidth: 1100, alignment: .leading) }.onAppear { model.refreshLiveSystem() }.onReceive(timer) { _ in model.refreshLiveSystem() } }
    private func pressureColor(_ label: String) -> Color { label == "Normal" ? .green : label == "Elevated" ? .orange : .red }
}
private struct FindingRow: View {
    let item: Finding
    let isSelected: Bool
    let toggleSelection: (() -> Void)?

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
                Text(item.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
        return "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)"
    }
}
struct StorageOutcomePreview: View {
    let available: Int64
    let total: Int64
    let reclaimable: Int64
    var title = "Projected storage outcome"
    var detail = "This forecasts disk storage reclaimed by the reviewed plan. It does not free RAM."

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label(title, systemImage: "arrow.right.circle.fill").font(.headline)
                    Spacer()
                    Text("+\(ByteCountFormatter.string(fromByteCount: reclaimable, countStyle: .file))").font(.headline).foregroundStyle(.green)
                }
                ProgressView(value: Double(min(total, available + reclaimable)), total: Double(max(1, total))).tint(.green)
                HStack {
                    Text("Now: \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available")
                    Spacer()
                    Text("After this plan: up to \(ByteCountFormatter.string(fromByteCount: min(total, available + reclaimable), countStyle: .file))")
                }.font(.caption).foregroundStyle(.secondary)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlanReviewView: View {
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
                            if !plan.warnings.isEmpty {
                                Section("Before you confirm") {
                                    ForEach(plan.warnings, id: \.self) {
                                        Label($0, systemImage: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                    }
                                    Toggle("I reviewed the items that need attention.", isOn: $acknowledgedWarnings)
                                }
                            }
                            ForEach(PlanActionGroup.allCases) { group in
                                let actions = group.actions(in: plan.actions)
                                if !actions.isEmpty {
                                    Section {
                                        ForEach(actions) { action in
                                            PlanActionRow(action: action)
                                        }
                                    } header: {
                                        Label(group.title, systemImage: group.symbol)
                                            .foregroundStyle(group.tint)
                                    }
                                }
                            }
                            Section {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Choose a final action below. Both options keep the reviewed items recoverable; opening this sheet never moves files.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            } header: {
                                Text("What happens next")
                            }
                            Section("Choose what happens") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Move the reviewed items to Finder Trash. macOS keeps them available until you empty Trash.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button("Move to Trash", systemImage: "trash") {
                                        model.executePlan(destination: .finderTrash)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(requiresWarningAcknowledgement)
                                }
                                .padding(.vertical, 4)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Store the reviewed items locally so you can restore them later. Recovery storage is never deleted automatically.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button("Keep in Recovery", systemImage: "arrow.uturn.backward.circle") {
                                        model.executePlan(destination: .recovery)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(requiresWarningAcknowledgement)
                                }
                                .padding(.vertical, 4)
                            }
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

    private var requiresWarningAcknowledgement: Bool {
        model.proposedPlan?.warnings.isEmpty == false && !acknowledgedWarnings
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
    var title: String { self == .safe ? "Safe to clean" : "Reviewed items" }
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

private struct CleanupCompletionView: View {
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
