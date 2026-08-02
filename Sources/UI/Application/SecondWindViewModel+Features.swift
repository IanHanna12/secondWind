import AppKit
import Foundation
import SecondWindApplication
import SecondWindCore
import SecondWindMacOS
import SecondWindPersistence

@MainActor
extension SecondWindViewModel {
    // MARK: Monitoring

    func refreshDashboard() {
        let service = monitorService
        Task.detached {
            let dashboardSnapshot = service.snapshot(includeProcesses: true)
            await MainActor.run {
                self.snapshot = dashboardSnapshot
            }
        }
    }

    func refreshLiveMetrics() {
        liveMetrics = liveMetricsService.sample()
    }

    func refreshLiveSystem() {
        refreshLiveMetrics()
        refreshDashboard()
    }

    // MARK: Cleanup selection

    func selectFindings(_ ids: Set<UUID>) {
        replaceSelection(with: ids.intersection(actionableFindingIDs))
    }

    func toggleSelection(for finding: Finding) {
        guard actionableFindingIDs.contains(finding.id) else { return }

        if selectedIDs.remove(finding.id) != nil {
            selectedBytes -= finding.byteSize
            if reviewRequiredFindingIDs.contains(finding.id) {
                reviewRequiredSelectionCount -= 1
            }
        } else {
            selectedIDs.insert(finding.id)
            selectedBytes += finding.byteSize
            if reviewRequiredFindingIDs.contains(finding.id) {
                reviewRequiredSelectionCount += 1
            }
        }
    }

    func selectSafeFindings(_ candidates: [Finding]) {
        addEligibleFindings(candidates.filter { $0.risk == .safe })
    }

    func addEligibleFindings(_ candidates: [Finding]) {
        let candidateIDs = Set(candidates.map(\.id)).intersection(actionableFindingIDs)
        selectFindings(selectedIDs.union(candidateIDs))
    }

    func clearSelection() {
        replaceSelection(with: [])
    }

    func replaceFindings(_ newFindings: [Finding]) {
        findings = newFindings
        findingBytesByID = Dictionary(uniqueKeysWithValues: newFindings.map { ($0.id, $0.byteSize) })
        actionableFindingIDs = Set(newFindings.filter(isActionable).map(\.id))
        reviewRequiredFindingIDs = Set(newFindings
            .filter { $0.confidence == .needsUserReview }
            .map(\.id))
        actionableFindingCount = actionableFindingIDs.count
        actionableBytes = newFindings
            .filter { actionableFindingIDs.contains($0.id) }
            .reduce(0) { $0 + $1.byteSize }
        protectedFindingCount = newFindings.count - actionableFindingCount
        cleanupReviewCandidates = Dictionary(
            uniqueKeysWithValues: CleanupReviewBuilder()
                .build(findings: newFindings)
                .map { ($0.id, $0) }
        )
        cleanupCategoryBytes = newFindings.reduce(into: [:]) { totals, finding in
            guard let category = finding.category else { return }
            totals[category, default: 0] += finding.byteSize
        }
        replaceSelection(with: selectedIDs.intersection(actionableFindingIDs))
    }

    private func replaceSelection(with ids: Set<UUID>) {
        selectedIDs = ids
        selectedBytes = ids.reduce(0) { total, id in
            total + (findingBytesByID[id] ?? 0)
        }
        reviewRequiredSelectionCount = ids.intersection(reviewRequiredFindingIDs).count
    }

    // MARK: Applications

    func loadApplications() {
        applications = InstalledApplicationDiscoverer(home: home).applications()
        applicationStorage = applicationInventoryBuilder.build(
            storageInventory: storageInventory,
            applications: applications
        )
    }

    func selectApplicationStorageEntries(_ entries: [ApplicationEntry]) {
        let paths = Set(entries.compactMap(\.storage.path))
        let matchingFindingIDs = findings
            .filter { paths.contains($0.path) }
            .map(\.id)
        selectFindings(selectedIDs.union(matchingFindingIDs))

        if matchingFindingIDs.isEmpty {
            message = "These known application paths are protected or are not current cleanup findings. No items were added to the plan."
        } else {
            message = "Added \(matchingFindingIDs.count) eligible application item(s) to the existing cleanup selection."
        }
    }

    func inspectApplication(_ app: InstalledApplication) {
        inspectedApplicationID = app.id
        applicationPreview = nil
        isLoadingApplicationPreview = true

        let home = home
        Task { [weak self, app, home] in
            let preview = await Task.detached {
                InstalledApplicationDiscoverer(home: home).removalPreview(for: app)
            }.value
            guard self?.inspectedApplicationID == app.id else { return }
            self?.applicationPreview = preview
            self?.isLoadingApplicationPreview = false
        }
    }

    func prepareUninstall(_ app: InstalledApplication) {
        let candidates = InstalledApplicationDiscoverer(home: home).uninstallFindings(for: app)
        replaceFindings(candidates)
        selectFindings(Set(candidates
            .filter { $0.risk.isExecutable && $0.supportedAction == .uninstall }
            .map(\.id)))
        message = "Removal plan prepared for \(app.displayName). Open Clean Up to review every affected path."
    }

    // MARK: Recovery and activity

    func hasRestoreDestinationConflict(for item: RecoveryItem) -> Bool {
        localStore.recovery.hasRestoreDestinationConflict(for: item)
    }

    func integrityReport(for item: RecoveryItem) -> RecoveryIntegrityReport {
        recoveryIntegrityReports[item.id] ?? .init(item: item, status: .unverified, canRestore: false)
    }

    func restore(_ item: RecoveryItem, choice: RestoreConflictChoice = .besideExisting) {
        restore([item], choice: choice)
    }

    func restore(_ items: [RecoveryItem], choice: RestoreConflictChoice) {
        performRecoveryBatch(items, action: .restore, choice: choice)
    }

    func deletePermanently(_ item: RecoveryItem) {
        deletePermanently([item])
    }

    func deletePermanently(_ items: [RecoveryItem]) {
        performRecoveryBatch(items, action: .permanentDelete, choice: nil)
    }

    func checkRecoveryIntegrity() {
        let selection = RecoveryItemSelection(items: recoveryItems)
        Task { await runIntegrityCheck(for: selection) }
    }

    func refreshActivity() {
        auditRecords = localStore.audit.records()
        applyRecoveryItems(localStore.recovery.allItems())
    }

    private func performRecoveryBatch(_ items: [RecoveryItem], action: RecoveryBatchAction, choice: RestoreConflictChoice?) {
        guard let selection = currentRecoverySelection(from: items) else { return }
        let request = RecoveryBatchRequest(action: action, selection: selection, choice: choice)
        Task { await runRecoveryBatch(request) }
    }

    private func runIntegrityCheck(for selection: RecoveryItemSelection) async {
        let operationID: OperationID
        do {
            operationID = try await operationCoordinator.start(kind: .recoveryIntegrityCheck)
            try localStore.audit.append(recoveryAuditRecord(
                operationID: operationID,
                kind: .maintenance,
                selection: selection,
                result: "Recovery integrity check started"
            ))
        } catch {
            message = error.localizedDescription
            return
        }

        let reports = await integrityReports(for: selection.items)
        applyIntegrityReports(reports)
        let result = RecoveryIntegrityCheckResult(reports: reports, checkedSelection: selection)

        do {
            try localStore.audit.append(recoveryAuditRecord(
                operationID: operationID,
                kind: result.auditKind,
                selection: result.auditSelection,
                result: result.auditMessage
            ))
            await operationCoordinator.finish(operationID)
            message = result.userMessage
        } catch {
            await operationCoordinator.fail(operationID, with: .persistenceFailure(document: "local activity"))
            message = "Integrity results were computed, but Second Wind could not save the local activity record."
        }
    }

    private func runRecoveryBatch(_ request: RecoveryBatchRequest) async {
        let operationID: OperationID
        do {
            operationID = try await operationCoordinator.start(kind: request.operationKind)
            try localStore.audit.append(recoveryAuditRecord(
                operationID: operationID,
                kind: request.auditKind,
                selection: request.selection,
                result: request.startMessage
            ))
        } catch {
            message = error.localizedDescription
            return
        }

        let store = localStore.recovery
        let outcome = await Task.detached { request.execute(using: store) }.value
        let result = RecoveryBatchResult(outcome: outcome)

        do {
            try localStore.audit.append(recoveryAuditRecord(
                operationID: operationID,
                kind: result.auditKind(for: request.action),
                selection: request.selection,
                result: result.message
            ))
            await finishRecoveryOperation(operationID, successfully: result.isFullyCompleted)
            refreshActivity()
            scan()
            message = result.message
        } catch {
            await operationCoordinator.fail(operationID, with: .persistenceFailure(document: "local activity"))
            refreshActivity()
            message = "\(result.message) Second Wind could not save the final local activity record."
        }
    }

    private func currentRecoverySelection(from candidates: [RecoveryItem]) -> RecoveryItemSelection? {
        let currentItemIDs = Set(recoveryItems.map(\.id))
        let currentItems = candidates.filter { candidate in currentItemIDs.contains(candidate.id) }
        guard !currentItems.isEmpty else { return nil }
        return RecoveryItemSelection(items: currentItems)
    }

    private func integrityReports(for items: [RecoveryItem]) async -> [RecoveryIntegrityReport] {
        let store = localStore.recovery
        return await Task.detached {
            items.map { item in store.integrityReport(for: item) }
        }.value
    }

    private func applyRecoveryItems(_ items: [RecoveryItem]) {
        recoveryItems = items
        Task { recoveryIntegrityReports = await integrityReportLookup(for: items) }
    }

    private func applyIntegrityReports(_ reports: [RecoveryIntegrityReport]) {
        recoveryIntegrityReports = integrityReportLookup(from: reports)
    }

    private func integrityReportLookup(for items: [RecoveryItem]) async -> [UUID: RecoveryIntegrityReport] {
        let reports = await integrityReports(for: items)
        return integrityReportLookup(from: reports)
    }

    private func integrityReportLookup(from reports: [RecoveryIntegrityReport]) -> [UUID: RecoveryIntegrityReport] {
        var reportsByItemID: [UUID: RecoveryIntegrityReport] = [:]
        for report in reports {
            reportsByItemID[report.item.id] = report
        }
        return reportsByItemID
    }

    private func recoveryAuditRecord(
        operationID: OperationID,
        kind: AuditKind,
        selection: RecoveryItemSelection,
        result: String
    ) -> AuditRecord {
        .init(
            operationID: operationID,
            kind: kind,
            planID: selection.planID,
            ruleVersions: [],
            paths: selection.originalPaths,
            bytes: selection.totalBytes,
            destination: .recovery,
            result: result
        )
    }

    private func finishRecoveryOperation(_ operationID: OperationID, successfully: Bool) async {
        if successfully {
            await operationCoordinator.finish(operationID)
        } else {
            await operationCoordinator.fail(operationID, with: .recoveryConflict(path: "Recovery"))
        }
    }

    // MARK: System activity and preferences

    @discardableResult
    func applyRulePolicyChange(_ change: RulePolicyChange) -> RulePolicy? {
        do {
            let updatedPolicy = try localStore.rulePolicy.apply(change)
            rulePolicy = updatedPolicy
            rulePolicyLoadError = nil
            try? localStore.audit.append(.init(kind: .preference, ruleVersions: ["local rule policy"], paths: [], bytes: 0, result: "updated"))
            refreshActivity()
            return updatedPolicy
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    func recordMaintenanceStarted(task: MaintenanceTask, volume: VolumeReference?) {
        appendMaintenanceRecord(kind: .maintenance, task: task, volume: volume, result: "started")
    }

    func recordMaintenance(result: Result<MaintenanceExecutionResult, Error>, task: MaintenanceTask, volume: VolumeReference?) {
        let record: (kind: AuditKind, result: String)
        switch result {
        case let .success(execution):
            record = (execution.succeeded ? .maintenance : .failure, execution.succeeded ? "completed: \(execution.output)" : "macOS reported a problem: \(execution.output)")
        case let .failure(error):
            record = (.failure, "failed: \(error.localizedDescription)")
        }
        appendMaintenanceRecord(kind: record.kind, task: task, volume: volume, result: record.result)
    }

    func exportAudit(_ format: AuditExportFormat) {
        if format == .diagnostics {
            let warning = NSAlert()
            warning.messageText = "Export diagnostics with full paths?"
            warning.informativeText = "This deliberately created file includes full local paths, inventory metadata, Recovery references, and local activity. Keep it private."
            warning.addButton(withTitle: "Export diagnostics")
            warning.addButton(withTitle: "Cancel")
            guard warning.runModal() == .alertFirstButtonReturn else { return }
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = format.fileName
        panel.allowedContentTypes = [format.contentType]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try auditData(for: format).write(to: url, options: .atomic)
            message = "Exported local activity to \(url.lastPathComponent)."
        } catch {
            message = error.localizedDescription
        }
    }

    private func isActionable(_ finding: Finding) -> Bool {
        finding.risk.isExecutable && finding.supportedAction != .none
    }

    private func appendMaintenanceRecord(kind: AuditKind, task: MaintenanceTask, volume: VolumeReference?, result: String) {
        try? localStore.audit.append(.init(kind: kind, ruleVersions: [task.rawValue], paths: [volume?.url.path ?? "/"], bytes: 0, destination: .systemTask, result: result))
        refreshActivity()
    }

    private func auditData(for format: AuditExportFormat) throws -> Data {
        switch format {
        case .json:
            return try localStore.audit.exportJSON()
        case .markdown:
            return Data(localStore.audit.exportMarkdown().utf8)
        case .diagnostics:
            return try JSONEncoder.secondWind.encode(diagnosticsExport())
        }
    }

    private func diagnosticsExport() -> LocalDiagnosticsExport {
        LocalDiagnosticsExport(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            snapshotID: storageSnapshots.current?.id,
            inventory: storageSnapshots.current?.entries ?? [],
            auditRecords: auditRecords,
            recoveryItems: recoveryItems,
            providerNames: Array(Set(storageInventory.entries.map(\.provider))).sorted()
        )
    }
}

private struct LocalDiagnosticsExport: Codable {
    let appVersion: String
    let build: String
    let snapshotID: UUID?
    let inventory: [StorageSnapshotEntry]
    let auditRecords: [AuditRecord]
    let recoveryItems: [RecoveryItem]
    let providerNames: [String]
}

private struct RecoveryItemSelection: Sendable {
    let items: [RecoveryItem]

    init(items: [RecoveryItem]) {
        var selectedItemIDs = Set<UUID>()
        self.items = items.filter { item in
            selectedItemIDs.insert(item.id).inserted
        }
    }

    var count: Int { items.count }
    var originalPaths: [String] { items.map(\.originalPath) }
    var totalBytes: Int64 { items.reduce(0) { total, item in total + item.byteSize } }
    var planID: UUID? { count == 1 ? items.first?.planID : nil }
}

private struct RecoveryBatchRequest: Sendable {
    let action: RecoveryBatchAction
    let selection: RecoveryItemSelection
    let choice: RestoreConflictChoice?

    var operationKind: OperationKind {
        action == .restore ? .restore : .permanentDeletion
    }

    var auditKind: AuditKind {
        action == .restore ? .restore : .permanentDelete
    }

    var startMessage: String {
        "Started \(actionName) for \(selection.count) Recovery item(s)."
    }

    func execute(using store: RecoveryStore) -> RecoveryBatchOutcome {
        switch action {
        case .restore:
            return store.restore(selection.items, choice: choice ?? .besideExisting)
        case .permanentDelete:
            return store.deletePermanently(selection.items)
        }
    }

    private var actionName: String {
        action == .restore ? "restore" : "permanent deletion"
    }
}

private struct RecoveryIntegrityCheckResult {
    let reports: [RecoveryIntegrityReport]
    let checkedSelection: RecoveryItemSelection
    let damagedSelection: RecoveryItemSelection

    init(reports: [RecoveryIntegrityReport], checkedSelection: RecoveryItemSelection) {
        self.reports = reports
        self.checkedSelection = checkedSelection
        let damagedItems = reports.compactMap { report in
            report.canRestore ? nil : report.item
        }
        damagedSelection = RecoveryItemSelection(items: damagedItems)
    }

    var auditKind: AuditKind {
        damagedSelection.items.isEmpty ? .maintenance : .failure
    }

    var auditSelection: RecoveryItemSelection {
        damagedSelection.items.isEmpty ? checkedSelection : damagedSelection
    }

    var auditMessage: String {
        damagedSelection.items.isEmpty
            ? "Recovery integrity check completed"
            : "\(damagedSelection.count) Recovery item(s) need attention"
    }

    var userMessage: String {
        damagedSelection.items.isEmpty
            ? "All \(reports.count) Recovery item(s) passed their integrity check."
            : "\(damagedSelection.count) Recovery item(s) are damaged. Restore is disabled; permanent deletion remains available."
    }
}

private struct RecoveryBatchResult {
    let outcome: RecoveryBatchOutcome
    let rolledBackCount: Int
    let unresolvedCount: Int
    let skippedCount: Int

    init(outcome: RecoveryBatchOutcome) {
        self.outcome = outcome
        var rolledBackCount = 0
        var unresolvedCount = 0
        var skippedCount = 0

        for itemResult in outcome.results {
            switch itemResult.outcome {
            case .rolledBack:
                rolledBackCount += 1
            case .unresolvedAfterRollback:
                unresolvedCount += 1
            case .skipped:
                skippedCount += 1
            case .completed, .failed:
                break
            }
        }

        self.rolledBackCount = rolledBackCount
        self.unresolvedCount = unresolvedCount
        self.skippedCount = skippedCount
    }

    var isFullyCompleted: Bool { outcome.isFullyCompleted }

    func auditKind(for action: RecoveryBatchAction) -> AuditKind {
        isFullyCompleted ? (action == .restore ? .restore : .permanentDelete) : .failure
    }

    var message: String {
        let actionName = outcome.action == .restore ? "restored" : "permanently deleted"
        var message = "\(outcome.completedCount) item(s) \(actionName)."
        if rolledBackCount > 0 { message += " \(rolledBackCount) item(s) were rolled back into Recovery." }
        if unresolvedCount > 0 { message += " \(unresolvedCount) item(s) need attention after rollback." }
        if skippedCount > 0 { message += " \(skippedCount) item(s) were not started." }
        if outcome.requiresAttentionCount > 0 && unresolvedCount == 0 {
            message += " Some items could not be completed; nothing else was started."
        }
        return message
    }
}
