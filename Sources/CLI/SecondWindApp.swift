import AppKit
import Combine
import Observation
import SwiftUI
import UniformTypeIdentifiers
import SecondWindCore
import SecondWindApplication
import SecondWindInfrastructure
import SecondWindPlatform
import SecondWindSnapshots

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
        let hostingView = NSHostingView(rootView: StewardRootView())
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

private enum AppSection: String, CaseIterable, Identifiable { case dashboard = "Home", snapshots = "Storage history", monitor = "System monitor", cleanup = "Clean Up", applications = "Applications", maintenance = "Volume check", settings = "Settings", activity = "Recovery & activity"; var id: String { rawValue }
    var symbol: String { switch self { case .dashboard: return "gauge.with.dots.needle.67percent"; case .snapshots: return "clock.arrow.trianglehead.counterclockwise.rotate.90"; case .monitor: return "waveform.path.ecg"; case .cleanup: return "sparkles"; case .applications: return "app.dashed"; case .maintenance: return "wrench.and.screwdriver"; case .settings: return "gearshape"; case .activity: return "clock.arrow.circlepath" } }
}

private enum AuditExportFormat { case json, markdown
    var fileName: String { self == .json ? "Second Wind Activity.json" : "Second Wind Activity.md" }
    var contentType: UTType { self == .json ? .json : .plainText }
}

private struct CleanupCompletion {
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

@MainActor @Observable private final class StewardViewModel {
    var findings: [Finding] = []
    var selectedIDs: Set<UUID> = []
    var proposedPlan: CleanupPlan?
    var showPlan = false
    var cleanupCompletion: CleanupCompletion?
    var showCleanupCompletion = false
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
        scanTask = Task.detached { [home, auditStore, totalBytes, availableBytes, snapshotService, bridge] in
            let localFileSystem = LocalFileSystem()
            let outcome = RuleEngine(home: home, fileSystem: localFileSystem).scan { progress in
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
                    ruleVersions: plan.actions.map(\.title),
                    paths: plan.actions.map(\.sourcePath),
                    bytes: plan.totalBytes,
                    result: "reviewed plan"
                ))
            }
            showPlan = true
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
            _ = try PlanExecutor(
                planBuilder: planBuilder,
                recoveryRepository: recoveryStore,
                trashMover: finderTrashMover,
                auditRecorder: auditStore
            ).execute(plan.confirmed())
            cleanupCompletion = .init(itemCount: plan.actions.count, reclaimedBytes: plan.totalBytes, destination: plan.destination)
            selectedIDs.removeAll()
            proposedPlan = nil
            showPlan = false
            scan()
            refreshActivity()
            DispatchQueue.main.async { self.showCleanupCompletion = true }
        }
        catch { message = error.localizedDescription }
    }
    func moveDirectlyToTrash(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        let finderTrashMover = FinderTrashMover()
        var movedPaths: [String] = []
        var failures: [(path: String, reason: String)] = []

        for url in urls {
            let path = url.standardizedFileURL.path
            do {
                try finderTrashMover.moveToTrash(url)
                movedPaths.append(path)
            } catch {
                failures.append((path, error.localizedDescription))
            }
        }

        if !movedPaths.isEmpty {
            try? auditStore.append(.init(
                kind: .manualTrash,
                ruleVersions: [],
                paths: movedPaths,
                bytes: 0,
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
                ruleVersions: [],
                paths: failures.map(\.path),
                bytes: 0,
                destination: .finderTrash,
                result: failures.map { "\($0.path): \($0.reason)" }.joined(separator: "\n")
            ))
        }
        refreshActivity()

        switch (movedPaths.count, failures.count) {
        case (0, _):
            message = "Nothing moved to Trash. \(failures.first?.reason ?? "macOS did not allow the change.")"
        case (_, 0):
            message = "Moved \(movedPaths.count) item(s) to Finder Trash."
        default:
            message = "Moved \(movedPaths.count) item(s) to Finder Trash. \(failures.count) could not be moved: \(failures.first?.reason ?? "unknown error")"
        }
    }
    func moveSelectedItemsToTrash() {
        let urls = findings
            .filter { selectedIDs.contains($0.id) }
            .map { URL(fileURLWithPath: $0.path).standardizedFileURL }
        moveDirectlyToTrash(urls)
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
    func restore(_ item: RecoveryItem) { do { let destination = try recoveryStore.restore(item); try? auditStore.append(.init(kind: .restore, planID: item.planID, ruleVersions: [], paths: [destination.path], bytes: item.byteSize, destination: .recovery, result: "restored")); refreshActivity(); message = "Restored to \(destination.path)" } catch { message = error.localizedDescription } }
    func deletePermanently(_ item: RecoveryItem) {
        do {
            try recoveryStore.deletePermanently(item)
            try? auditStore.append(.init(kind: .permanentDelete, planID: item.planID, ruleVersions: [], paths: [item.originalPath], bytes: item.byteSize, destination: .recovery, result: "permanently deleted from recovery storage"))
            refreshActivity()
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
    func setPreference(_ preference: StewardPreference, enabled: Bool) {
        preferenceService.set(preference, enabled: enabled)
        try? auditStore.append(.init(kind: .preference, ruleVersions: [preference.rawValue], paths: [], bytes: 0, result: enabled ? "enabled" : "disabled"))
        refreshActivity()
    }
    func resetPreference(_ preference: StewardPreference) {
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

private struct StewardRootView: View {
    @State private var model = StewardViewModel()
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
                }
                Section("INSIGHTS") {
                    sidebarItem(.snapshots)
                    sidebarItem(.monitor)
                    sidebarItem(.activity)
                }
                Section("SYSTEM") {
                    sidebarItem(.maintenance)
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
            case .maintenance: MaintenanceView(model: model)
            case .settings: SettingsView(model: model)
            case .activity: ActivityView(model: model)
            }
        }
        .alert("Second Wind", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
        .sheet(isPresented: $model.showPlan) { PlanReviewView(model: model) }
        .sheet(isPresented: $model.showCleanupCompletion) {
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
    let model: StewardViewModel
    let openCleanup: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageTitle(
                    eyebrow: "SECOND WIND",
                    title: "Make space with confidence",
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
    let model: StewardViewModel
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

private struct StorageSnapshotsView: View {
    let model: StewardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(
                    eyebrow: "LOCAL CHANGE HISTORY",
                    title: "Storage snapshots",
                    detail: "Second Wind records only the storage it understands from bundled rules. Your files stay on this Mac."
                ) {
                    Button(model.isScanning ? "Cancel scan" : "Record a new snapshot", systemImage: model.isScanning ? "xmark" : "arrow.clockwise") {
                        model.isScanning ? model.cancelScan() : model.scan()
                    }
                        .buttonStyle(.borderedProminent)
                }
                StorageSnapshotContent(report: model.storageSnapshots, recordSnapshot: model.scan)
            }
            .padding(30)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }
}

private struct StorageSnapshotContent: View {
    let report: StorageSnapshotReport
    let recordSnapshot: () -> Void

    var body: some View {
        if let current = report.current {
            RecordedStorageSnapshots(report: report, current: current)
        } else {
            EmptyStorageSnapshots(recordSnapshot: recordSnapshot)
        }
    }
}

private struct RecordedStorageSnapshots: View {
    let report: StorageSnapshotReport
    let current: StorageSnapshot

    var body: some View {
        StorageSnapshotMetrics(report: report, current: current)
        StorageSnapshotObservation(report: report)
        StorageReclaimPreview(report: report, current: current)
        StorageChanges(report: report)
        StorageSnapshotEntries(entries: current.entries)
        StorageSnapshotTimeline(history: report.history)
    }
}

private struct StorageSnapshotMetrics: View {
    let report: StorageSnapshotReport
    let current: StorageSnapshot

    var body: some View {
        HStack(spacing: 14) {
            Metric(title: "Current free space", value: bytes(current.availableBytes), symbol: "externaldrive.fill", tint: .mint)
            Metric(title: "Tracked items", value: "\(current.entries.count)", symbol: "tray.full.fill", tint: .blue)
            Metric(title: "Eligible to plan", value: bytes(report.reclaimableBytes), symbol: "arrow.uturn.backward.circle.fill", tint: .green)
        }
    }
}

private struct StorageSnapshotObservation: View {
    let report: StorageSnapshotReport

    var body: some View {
        if report.isFirstSnapshot {
            SoftCard {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "eye.circle.fill").font(.title2).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your local baseline is ready").font(.headline)
                        Text("Run another scan after you use your Mac. Second Wind will show which known areas grew or shrank; it never guesses about unknown personal data.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            StorageSnapshotComparisonCard(report: report)
        }
    }
}

private struct StorageReclaimPreview: View {
    let report: StorageSnapshotReport
    let current: StorageSnapshot

    var body: some View {
        if report.reclaimableBytes > 0 {
            StorageOutcomePreview(
                available: current.availableBytes,
                total: current.totalBytes,
                reclaimable: report.reclaimableBytes,
                title: "Potential outcome from reviewed items",
                detail: "This is an upper bound across eligible and review-required findings. Select individual items in Clean Up before creating a plan."
            )
        }
    }
}

private struct StorageChanges: View {
    let report: StorageSnapshotReport

    var body: some View {
        if !report.changes.isEmpty {
            SoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("What changed since the previous snapshot", systemImage: "chart.line.uptrend.xyaxis").font(.headline)
                    Text("Changes smaller than 1 MB are omitted to keep this useful.").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(report.changes.prefix(8))) { change in StorageChangeRow(change: change) }
                }
            }
        } else if !report.isFirstSnapshot {
            SoftCard {
                Label("No meaningful changes in known storage since the previous snapshot.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StorageSnapshotEntries: View {
    let entries: [StorageSnapshotEntry]

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Known storage right now", systemImage: "list.bullet.rectangle").font(.headline)
                Text("These are explanations, not automatic cleanup instructions.").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(entries.prefix(10))) { entry in StorageSnapshotEntryRow(entry: entry) }
            }
        }
    }
}

private struct StorageSnapshotTimeline: View {
    let history: [StorageSnapshot]

    var body: some View {
        if history.count > 1 {
            SoftCard {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Local timeline", systemImage: "clock.arrow.circlepath").font(.headline)
                    ForEach(Array(history.reversed().prefix(8))) { snapshot in
                        HStack {
                            Text(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text(bytes(snapshot.availableBytes) + " free").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }
}

private struct EmptyStorageSnapshots: View {
    let recordSnapshot: () -> Void

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("No storage snapshots yet").font(.headline)
                Text("Record a read-only scan to create the first local baseline. Nothing will be cleaned.").foregroundStyle(.secondary)
                Button("Record first snapshot", action: recordSnapshot).buttonStyle(.borderedProminent)
            }
        }
    }
}

private func bytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

private struct StorageSnapshotComparisonCard: View {
    let report: StorageSnapshotReport

    var body: some View {
        SoftCard {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: comparisonSymbol).font(.title2).foregroundStyle(comparisonColor)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Since the previous local snapshot").font(.headline)
                    Text(message).foregroundStyle(.secondary)
                    Text("This compares free disk space and known rule findings only; it does not claim to explain all System Data.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var change: Int64 { report.availableSpaceChange ?? 0 }
    private var comparisonSymbol: String { change >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill" }
    private var comparisonColor: Color { change >= 0 ? .green : .orange }
    private var message: String {
        let amount = ByteCountFormatter.string(fromByteCount: abs(change), countStyle: .file)
        if change > 0 { return "Free disk space increased by \(amount)." }
        if change < 0 { return "Free disk space decreased by \(amount)." }
        return "Free disk space is unchanged."
    }
}

private struct StorageChangeRow: View {
    let change: StorageChange

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(change.title).font(.subheadline.weight(.semibold))
                    RiskPill(risk: change.risk)
                }
                Text(change.kind == .newlyObserved ? "First observed by Second Wind · \(change.category)" : change.category)
                    .font(.caption).foregroundStyle(.secondary)
                Text(change.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text(changeLabel).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
        }
        .padding(.vertical, 5)
    }

    private var symbol: String { change.kind == .shrank ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill" }
    private var tint: Color { change.kind == .shrank ? .green : .orange }
    private var changeLabel: String {
        let amount = ByteCountFormatter.string(fromByteCount: abs(change.byteChange), countStyle: .file)
        return change.kind == .shrank ? "−\(amount)" : "+\(amount)"
    }
}

private struct StorageSnapshotEntryRow: View {
    let entry: StorageSnapshotEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.isActionable ? "checkmark.shield.fill" : "lock.shield.fill")
                .foregroundStyle(entry.isActionable ? .green : .orange).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(entry.title).font(.subheadline.weight(.semibold)); RiskPill(risk: entry.risk) }
                Text(entry.category + " · " + entry.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: entry.byteSize, countStyle: .file)).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

private struct CleanupView: View {
    let model: StewardViewModel
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
                        if !availableCategories.isEmpty {
                            Picker("Category", selection: $categoryFilter) {
                                Text("All categories").tag(FindingCategory?.none)
                                ForEach(availableCategories) { category in
                                    Text(category.title).tag(Optional(category))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(CleanupSortOrder.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        if !categoryTotals.isEmpty {
                            Menu {
                                ForEach(categoryTotals) { total in
                                    Label(
                                        "\(total.category.title) · \(ByteCountFormatter.string(fromByteCount: total.bytes, countStyle: .file))",
                                        systemImage: total.category == .developer ? "hammer.fill" : "externaldrive.fill"
                                    )
                                    .labelStyle(.titleAndIcon)
                                }
                            } label: {
                                Label("Totals", systemImage: "chart.pie.fill")
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

    private var availableCategories: [FindingCategory] {
        categoryTotals.map(\.category)
    }

}

private struct CleanupReadinessCard: View {
    let model: StewardViewModel
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
    let model: StewardViewModel

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
    let model: StewardViewModel
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
                Text(item.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
}
private struct StorageOutcomePreview: View {
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
    let model: StewardViewModel
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

private struct ApplicationsView: View {
    let model: StewardViewModel
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

private struct ApplicationSupportRow: View {
    let remnant: AppRemnant
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: remnant.isExactKnownRemnant ? "folder.fill" : "lock.fill")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(remnant.url.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
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

@MainActor @Observable private final class MaintenanceModel {
    var volumes: [VolumeReference] = []
    var selectedVolumeURL: URL?
    var result = "Choose a local volume and review the verification."
    var showConfirmation = false
    var isRunning = false
    init() { volumes = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeUUIDStringKey, .volumeIsLocalKey], options: []) ?? []).map(VolumeReference.init).filter(\.isLocal); selectedVolumeURL = volumes.first?.url }
    var selectedVolume: VolumeReference? { volumes.first { $0.url == selectedVolumeURL } }
}
private struct MaintenanceView: View {
    let model: StewardViewModel
    @State private var state = MaintenanceModel()
    var body: some View { VStack(alignment: .leading, spacing: 18) {
        PageTitle(eyebrow: "LOCAL VOLUME CHECK", title: "Verify a local volume", detail: "Read-only filesystem verification. No helper, shell text, or arbitrary path is involved.") { EmptyView() }
        Picker("Local volume", selection: $state.selectedVolumeURL) { ForEach(state.volumes, id: \.url) { Text($0.url.path).tag(Optional($0.url)) } }
        SoftCard { VStack(alignment: .leading, spacing: 8) { Label("What will happen", systemImage: "checklist").font(.headline); Text(MaintenanceTask.verifyVolume.explanation); Text("macOS receives the selected local volume only after it passes local-volume validation. The check does not modify files.").font(.caption).foregroundStyle(.secondary); if !state.result.isEmpty { Text(state.result).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } } }
        Button(state.isRunning ? "Verifying…" : "Review and verify") { do { try MaintenancePreflight().validate(task: .verifyVolume, volume: state.selectedVolume); state.showConfirmation = true } catch { state.result = error.localizedDescription } }.buttonStyle(.borderedProminent).disabled(state.isRunning || state.selectedVolume == nil)
        Text("Not included: privileged maintenance, LaunchServices resets, RAM cleaning, permission repair, or generic “speed up” actions.").font(.caption).foregroundStyle(.secondary)
    }.padding(30).confirmationDialog("Verify \(state.selectedVolume?.url.path ?? "this volume")?", isPresented: $state.showConfirmation, titleVisibility: .visible) { Button("Verify volume") { run() }; Button("Cancel", role: .cancel) {} } message: { Text("This runs macOS's read-only local-volume verification task.") } }
    private func run() {
        state.isRunning = true
        let task = MaintenanceTask.verifyVolume
        let volume = state.selectedVolume
        model.recordMaintenanceStarted(task: task, volume: volume)
        Task {
            let outcome: Result<MaintenanceExecutionResult, Error>
            do {
                outcome = .success(try await Task.detached { try LocalMaintenanceRunner().run(task: task, volume: volume) }.value)
            } catch { outcome = .failure(error) }
            state.isRunning = false
            model.recordMaintenance(result: outcome, task: task, volume: volume)
            switch outcome {
            case .success(let result): state.result = result.succeeded ? "Completed. \(result.output)" : "macOS reported a problem. \(result.output)"
            case .failure(let error): state.result = error.localizedDescription
            }
        }
    }
}

private struct SettingsView: View {
    let model: StewardViewModel
    private let preferenceService = PreferenceService()

    var body: some View {
        Form {
            Section("Finder and Dock") {
                ForEach(StewardPreference.allCases) { preference in
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
        }
        .padding(28)
        .navigationTitle("Settings")
    }
}

private struct ActivityView: View {
    let model: StewardViewModel
    @State private var itemPendingPermanentDeletion: RecoveryItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Recovery & activity").font(.largeTitle.bold())
                    Text("Restore locally stored items or review the local record of every meaningful action.").foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Export") {
                    Button("JSON") { model.exportAudit(.json) }
                    Button("Markdown") { model.exportAudit(.markdown) }
                }
                Button("Refresh") { model.refreshActivity() }
            }
            List {
                Section("Recovery storage") {
                    if model.recoveryItems.isEmpty {
                        ContentUnavailableView("Nothing in Recovery", systemImage: "checkmark.shield", description: Text("Items stored here remain available to restore and are never deleted automatically."))
                    }
                    else {
                        ForEach(model.recoveryItems) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.originalPath).lineLimit(1)
                                    Text(item.needsReview ? "Review required; never auto-deleted" : "Available for restore until \(item.reviewAfter.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Restore") { model.restore(item) }
                                Button("Delete", role: .destructive) {
                                    itemPendingPermanentDeletion = item
                                }
                            }
                        }
                    }
                }
                Section("Local activity") {
                    if model.auditRecords.isEmpty { Text("Your first scan will appear here.").foregroundStyle(.secondary) }
                    ForEach(model.auditRecords) { record in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(record.kind.rawValue) — \(record.result)")
                            Text(record.timestamp.formatted()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(32)
        .confirmationDialog(
            "Delete this item permanently?",
            isPresented: Binding(
                get: { itemPendingPermanentDeletion != nil },
                set: { if !$0 { itemPendingPermanentDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) {
                if let item = itemPendingPermanentDeletion {
                    model.deletePermanently(item)
                }
                itemPendingPermanentDeletion = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \(itemPendingPermanentDeletion?.originalPath ?? "this item") from Recovery. It cannot be restored or undone.")
        }
    }
}
private struct PageTitle<Accessory: View>: View { let eyebrow: String; let title: String; let detail: String; @ViewBuilder let accessory: () -> Accessory; var body: some View { HStack(alignment: .bottom) { VStack(alignment: .leading, spacing: 6) { Text(eyebrow).font(.caption.weight(.bold)).foregroundStyle(.green); Text(title).font(.system(size: 34, weight: .bold, design: .rounded)); Text(detail).foregroundStyle(.secondary) }; Spacer(); accessory() } } }
private struct SoftCard<Content: View>: View { @ViewBuilder let content: () -> Content; var body: some View { content().frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.06))) } }
private struct RiskPill: View { let risk: Risk; var body: some View { Text(risk.rawValue).font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3).foregroundStyle(risk == .safe ? .green : risk == .protected ? .red : .orange).background((risk == .safe ? Color.green : risk == .protected ? Color.red : Color.orange).opacity(0.12), in: Capsule()) } }
private struct LiveGauge: View { let title: String; let value: Double?; let detail: String; let tint: Color; let symbol: String; var body: some View { VStack(alignment: .leading, spacing: 10) { HStack { Image(systemName: symbol).foregroundStyle(tint); Text(title).font(.headline) }; Text(value.map { "\(Int($0 * 100))%" } ?? "—").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit(); ProgressView(value: value ?? 0).tint(tint); Text(detail).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18)) } }
private struct Metric: View { let title: String; let value: String; let symbol: String; let tint: Color; var body: some View { HStack(spacing: 12) { Image(systemName: symbol).font(.title3).foregroundStyle(tint).frame(width: 34, height: 34).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.bold()).monospacedDigit() } }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16)) } }
