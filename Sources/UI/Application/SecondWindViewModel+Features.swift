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
        applications = InstalledApplicationInventory(home: home).applications()
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
                InstalledApplicationInventory(home: home).removalPreview(for: app)
            }.value
            guard self?.inspectedApplicationID == app.id else { return }
            self?.applicationPreview = preview
            self?.isLoadingApplicationPreview = false
        }
    }

    func prepareUninstall(_ app: InstalledApplication) {
        let candidates = InstalledApplicationInventory(home: home).uninstallFindings(for: app)
        replaceFindings(candidates)
        selectFindings(Set(candidates
            .filter { $0.risk.isExecutable && $0.supportedAction == .uninstall }
            .map(\.id)))
        message = "Removal plan prepared for \(app.displayName). Open Clean Up to review every affected path."
    }

    // MARK: Recovery and activity

    func restore(_ item: RecoveryItem) {
        do {
            let destination = try recoveryStore.restore(item)
            try? auditStore.append(.init(kind: .restore, planID: item.planID, ruleVersions: [], paths: [destination.path], bytes: item.byteSize, destination: .recovery, result: "restored"))
            refreshActivity()
            scan()
            message = "Restored to \(destination.path)"
        } catch {
            message = error.localizedDescription
        }
    }

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

    func refreshActivity() {
        auditRecords = auditStore.records()
        recoveryItems = recoveryStore.allItems()
    }

    // MARK: System activity and preferences

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

    func setPreference(_ preference: SystemPreference, enabled: Bool) {
        preferenceService.set(preference, enabled: enabled)
        appendPreferenceRecord(preference.rawValue, result: enabled ? "enabled" : "disabled")
    }

    func resetPreference(_ preference: SystemPreference) {
        preferenceService.reset(preference)
        appendPreferenceRecord(preference.rawValue, result: "reset to macOS default")
    }

    func setMenuMonitor(enabled: Bool) {
        menuMonitor = enabled
        UserDefaults.standard.set(enabled, forKey: "menuBarMonitorEnabled")
        appendPreferenceRecord("menuBarMonitor", result: enabled ? "enabled" : "disabled")
    }

    func exportAudit(_ format: AuditExportFormat) {
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
        try? auditStore.append(.init(kind: kind, ruleVersions: [task.rawValue], paths: [volume?.url.path ?? "/"], bytes: 0, destination: .systemTask, result: result))
        refreshActivity()
    }

    private func appendPreferenceRecord(_ identifier: String, result: String) {
        try? auditStore.append(.init(kind: .preference, ruleVersions: [identifier], paths: [], bytes: 0, result: result))
        refreshActivity()
    }

    private func auditData(for format: AuditExportFormat) throws -> Data {
        switch format {
        case .json:
            return try auditStore.exportJSON()
        case .markdown:
            return Data(auditStore.exportMarkdown().utf8)
        }
    }
}
