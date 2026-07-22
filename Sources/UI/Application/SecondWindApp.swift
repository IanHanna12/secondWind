import AppKit
import Combine
import Observation
import SwiftUI
import UniformTypeIdentifiers
import SecondWindCore
import SecondWindApplication
import SecondWindMacOS
import SecondWindPersistence
import SecondWindServices

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

private enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Home"
    case snapshots = "Storage overview"
    case developerStorage = "Developer storage"
    case monitor = "System monitor"
    case cleanup = "Clean Up"
    case applications = "Applications"
    case rules = "Rules"
    case volumeCheck = "Volume check"
    case systemTasks = "System tasks"
    case settings = "Settings"
    case activity = "Recovery & activity"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .snapshots: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .developerStorage: return "hammer"
        case .monitor: return "waveform.path.ecg"
        case .cleanup: return "sparkles"
        case .applications: return "app.dashed"
        case .rules: return "checklist"
        case .volumeCheck: return "externaldrive.badge.checkmark"
        case .systemTasks: return "wrench.and.screwdriver"
        case .settings: return "gearshape"
        case .activity: return "clock.arrow.circlepath"
        }
    }
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

@MainActor @Observable final class SecondWindViewModel {
    var findings: [Finding] = []
    var selectedIDs: Set<UUID> = []
    var selectedBytes: Int64 = 0
    var actionableFindingCount = 0
    var actionableBytes: Int64 = 0
    var protectedFindingCount = 0
    var reviewRequiredSelectionCount = 0
    var cleanupReviewCandidates: [UUID: CleanupReviewCandidate] = [:]
    var cleanupCategoryBytes: [FindingCategory: Int64] = [:]
    var proposedPlan: CleanupPlan?
    var cleanupPresentation: CleanupPresentationPhase = .idle
    var cleanupCompletion: CleanupCompletion?
    var message: String?
    var isScanning = false
    var scanProgress: ScanProgress?
    var snapshot: DashboardSnapshot
    var liveMetrics: LiveSystemMetrics
    var applications: [InstalledApplication] = []
    var applicationStorage = ApplicationInventory(storageInventory: StorageInventory(entries: []), applications: [])
    var applicationPreview: ApplicationRemovalPreview?
    var isLoadingApplicationPreview = false
    var inspectedApplicationID: String?
    var auditRecords: [AuditRecord]
    var recoveryItems: [RecoveryItem]
    var storageInventory = StorageInventory(entries: [])
    var storageSnapshots = StorageSnapshotReport.empty
    var latestScanSummary: StorageScanSummary?
    var menuMonitor = UserDefaults.standard.bool(forKey: "menuBarMonitorEnabled")
    let home = FileManager.default.homeDirectoryForCurrentUser
    let auditStore: AuditStore
    let recoveryStore: RecoveryStore
    let monitorService: MonitorService
    let liveMetricsService: LiveMetricsService
    let storageScanService: any StorageScanning
    let applicationInventoryBuilder = ApplicationInventoryBuilder()
    let preferenceService = PreferenceService()
    let rulePolicyStore = RulePolicyStore()
    let operationCoordinator: any OperationCoordinator = LocalOperationCoordinator()
    var scanTask: Task<Void, Never>?
    var activeScanID: UUID?
    var activeOperationID: OperationID?
    var findingBytesByID: [UUID: Int64] = [:]
    var actionableFindingIDs: Set<UUID> = []
    var reviewRequiredFindingIDs: Set<UUID> = []

    init() {
        let monitorService = MonitorService()
        let auditStore = AuditStore()
        let recoveryStore = RecoveryStore()
        self.monitorService = monitorService
        self.auditStore = auditStore
        self.recoveryStore = recoveryStore
        self.storageScanService = LocalStorageScanService(auditStore: auditStore)
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
        let rules = rulePolicyStore.effectiveRules()
        let recoveryItems = recoveryItems
        let totalBytes = snapshot.storageTotal
        let availableBytes = snapshot.storageAvailable
        let coordinator = operationCoordinator
        let storageScanService = storageScanService
        scanTask = Task { [weak self, storageScanService, coordinator, recoveryItems, totalBytes, availableBytes] in
            let operationID: OperationID
            do { operationID = try await coordinator.start(kind: .scan) }
            catch {
                guard let self, self.activeScanID == scanID else { return }
                self.isScanning = false
                self.message = error.localizedDescription
                return
            }
            guard let self, self.activeScanID == scanID else {
                await coordinator.cancel(operationID)
                return
            }
            self.activeOperationID = operationID
            let request = StorageScanRequest(operationID: operationID, home: self.home, rules: rules, recoveryItems: recoveryItems, totalBytes: totalBytes, availableBytes: availableBytes)
            var completed = false
            for await event in storageScanService.events(for: request) {
                guard self.activeScanID == scanID else { return }
                switch event {
                case let .progress(progress):
                    self.scanProgress = progress
                    await coordinator.updateProgress(.init(completedUnits: progress.completedUnits, totalUnits: progress.totalUnits, title: progress.currentTitle), for: operationID)
                case let .completed(result):
                    self.apply(result)
                    completed = true
                }
            }
            if completed { await coordinator.finish(operationID) }
            else if Task.isCancelled { await coordinator.cancel(operationID) }
            else { await coordinator.fail(operationID, with: .providerUnavailable(provider: "Local scan")) }
        }
    }

    private func apply(_ result: StorageScanResult) {
        replaceFindings(result.findings)
        applications = result.applications
        storageInventory = result.inventory
        applicationStorage = applicationInventoryBuilder.build(storageInventory: result.inventory, applications: result.applications)
        storageSnapshots = result.snapshotReport
        latestScanSummary = result.summary
        isScanning = false
        scanProgress = nil
        activeScanID = nil
        activeOperationID = nil
        scanTask = nil
        refreshActivity()
    }
    func cancelScan() {
        scanTask?.cancel()
        if let activeOperationID {
            Task { await operationCoordinator.cancel(activeOperationID) }
        }
        scanTask = nil
        activeScanID = nil
        activeOperationID = nil
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
                recoveryStore: recoveryStore,
                trashMover: finderTrashMover,
                auditStore: auditStore
            )
            let coordinator = operationCoordinator
            Task {
                do {
                    let operationID = try await coordinator.start(kind: .cleanup)
                    let outcome = try await executor.executeWithOutcome(plan.confirmed(), operationID: operationID, verifier: LocalCleanupOutcomeVerifier(), availableBytesBefore: snapshot.storageAvailable)
                    await coordinator.finish(operationID)
                    let completedCount = outcome.results.filter { result in
                        switch result.outcome { case .completedAndVerified, .completedNotYetObservable: return true; default: return false }
                    }.count
                    cleanupCompletion = .init(itemCount: completedCount, reclaimedBytes: outcome.movedBytes, destination: plan.destination)
                    clearSelection()
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
                let remainingFindings = findings.filter { finding in
                    movedPaths.contains { path in
                        finding.path != path && !finding.path.hasPrefix(path + "/")
                    }
                }
                replaceFindings(remainingFindings)
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

@MainActor
@Observable
private final class NavigationModel {
    var section: AppSection? = .dashboard
}
