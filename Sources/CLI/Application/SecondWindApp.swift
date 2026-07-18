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
        let hostingView = NSHostingView(rootView: SecondWindApplicationView())
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

private enum AppSection: String, CaseIterable, Identifiable { case dashboard = "Home", snapshots = "Storage overview", developerStorage = "Developer storage", monitor = "System monitor", cleanup = "Clean Up", applications = "Applications", rules = "Rules", volumeCheck = "Volume check", systemTasks = "System tasks", settings = "Settings", activity = "Recovery & activity"; var id: String { rawValue }
    var symbol: String { switch self { case .dashboard: return "gauge.with.dots.needle.67percent"; case .snapshots: return "clock.arrow.trianglehead.counterclockwise.rotate.90"; case .developerStorage: return "hammer"; case .monitor: return "waveform.path.ecg"; case .cleanup: return "sparkles"; case .applications: return "app.dashed"; case .rules: return "checklist"; case .volumeCheck: return "externaldrive.badge.checkmark"; case .systemTasks: return "wrench.and.screwdriver"; case .settings: return "gearshape"; case .activity: return "clock.arrow.circlepath" } }
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

struct StorageScanSummary: Sendable {
    let completedAt: Date
    let duration: TimeInterval
    let findingCount: Int
    let eligibleCount: Int
    let reviewRequiredCount: Int
    let protectedCount: Int
    let observedBytes: Int64
    let observedLocationCount: Int

    init(findings: [Finding], inventory: StorageInventory, startedAt: Date, completedAt: Date = Date()) {
        self.completedAt = completedAt
        duration = completedAt.timeIntervalSince(startedAt)
        findingCount = findings.count
        eligibleCount = findings.filter { $0.risk.isExecutable && $0.supportedAction != .none }.count
        reviewRequiredCount = findings.filter { $0.risk == .reviewRequired }.count
        protectedCount = findings.filter { $0.risk == .protected || $0.supportedAction == .none }.count
        observedBytes = inventory.entries.filter(\.countsTowardCategoryTotal).reduce(0) { $0 + $1.byteSize }
        observedLocationCount = inventory.entries.count
    }
}

private final class ScanUIBridge: @unchecked Sendable {
    private let receiveProgress: @MainActor @Sendable (ScanProgress) -> Void
    private let receiveCompletion: @MainActor @Sendable ([Finding], StorageInventory, StorageSnapshotReport, StorageScanSummary) -> Void

    init(
        receiveProgress: @escaping @MainActor @Sendable (ScanProgress) -> Void,
        receiveCompletion: @escaping @MainActor @Sendable ([Finding], StorageInventory, StorageSnapshotReport, StorageScanSummary) -> Void
    ) {
        self.receiveProgress = receiveProgress
        self.receiveCompletion = receiveCompletion
    }

    func report(_ progress: ScanProgress) {
        Task { @MainActor in
            receiveProgress(progress)
        }
    }

    func complete(findings: [Finding], inventory: StorageInventory, report: StorageSnapshotReport, summary: StorageScanSummary) {
        Task { @MainActor in
            receiveCompletion(findings, inventory, report, summary)
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
    var storageInventory = StorageInventory(entries: [])
    var storageSnapshots = StorageSnapshotReport.empty
    var latestScanSummary: StorageScanSummary?
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
        let scanStartedAt = Date()
        let rules = rulePolicyStore.effectiveRules()
        scanProgress = .init(completedUnits: 0, totalUnits: rules.count + 3, currentTitle: "Preparing local scan")
        let totalBytes = snapshot.storageTotal
        let availableBytes = snapshot.storageAvailable
        let snapshotService = storageSnapshotService
        let bridge = ScanUIBridge(
            receiveProgress: { [weak self] progress in
                guard self?.activeScanID == scanID else { return }
                self?.scanProgress = progress
            },
            receiveCompletion: { [weak self] results, inventory, report, summary in
                guard self?.activeScanID == scanID else { return }
                self?.findings = results
                self?.storageInventory = inventory
                self?.storageSnapshots = report
                self?.latestScanSummary = summary
                self?.selectedIDs.formIntersection(Set(results.map(\.id)))
                self?.isScanning = false
                self?.scanProgress = nil
                self?.activeScanID = nil
                self?.scanTask = nil
                self?.refreshActivity()
            }
        )
        let currentRecoveryItems = recoveryItems
        scanTask = Task.detached { [home, auditStore, totalBytes, availableBytes, snapshotService, bridge, rules, currentRecoveryItems, scanStartedAt] in
            let localFileSystem = LocalFileSystem()
            let outcome = CleanupScanner(home: home, fileSystem: localFileSystem, rules: rules).scan { progress in
                guard !Task.isCancelled else { return false }
                bridge.report(progress)
                return true
            }
            guard case let .completed(results) = outcome, !Task.isCancelled else { return }
            bridge.report(.init(completedUnits: rules.count + 3, totalUnits: rules.count + 3, currentTitle: "Finishing scan"))
            try? auditStore.append(.init(kind: .scan, ruleVersions: Array(Set(results.map { "\($0.ruleID) v\($0.ruleVersion)" })).sorted(), paths: results.map(\.path), bytes: results.reduce(0) { $0 + $1.byteSize }, result: "\(results.count) findings"))
            let inventory = StorageInventoryObserver(home: home).observe(findings: results, recoveryItems: currentRecoveryItems)
            let snapshot = snapshotService.capture(inventory: inventory, totalBytes: totalBytes, availableBytes: availableBytes)
            let history = (try? snapshotService.store.append(snapshot)) ?? snapshotService.store.snapshots()
            let report = snapshotService.report(for: snapshot, history: history)
            bridge.complete(findings: results, inventory: inventory, report: report, summary: StorageScanSummary(findings: results, inventory: inventory, startedAt: scanStartedAt))
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

private struct SecondWindApplicationView: View {
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
                    sidebarItem(.developerStorage)
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
            case .dashboard: DashboardScreen(model: model) { navigation.section = .cleanup }
            case .snapshots: StorageIntelligenceView(model: model)
            case .developerStorage: DeveloperStorageScreen(model: model)
            case .monitor: SystemMonitorScreen(model: model)
            case .cleanup: CleanupScreen(model: model)
            case .applications: ApplicationsScreen(model: model) { navigation.section = .cleanup }
            case .rules: RulesScreen()
            case .volumeCheck: VolumeCheckScreen(model: model)
            case .systemTasks: SystemTasksScreen(model: model)
            case .settings: SettingsScreen(model: model)
            case .activity: RecoveryActivityScreen(model: model)
            }
        }
        .alert("Second Wind", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
        .sheet(isPresented: Binding(
            get: { model.cleanupPresentation == .reviewingPlan },
            set: { if !$0, model.cleanupPresentation == .reviewingPlan { model.cleanupPresentation = .idle } }
        )) { CleanupPlanReviewSheet(model: model) }
        .sheet(isPresented: Binding(
            get: { model.cleanupPresentation == .showingCompletion },
            set: { if !$0, model.cleanupPresentation == .showingCompletion { model.cleanupPresentation = .idle } }
        )) {
            if let completion = model.cleanupCompletion {
                CleanupCompletionSheet(completion: completion) { navigation.section = .activity }
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
