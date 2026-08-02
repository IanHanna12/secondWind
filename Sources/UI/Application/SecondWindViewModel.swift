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
    var scanProgress: OperationProgress?
    var snapshot: DashboardSnapshot
    var liveMetrics: LiveSystemMetrics
    var applications: [InstalledApplication] = []
    var applicationStorage = ApplicationInventory(storageInventory: StorageInventory(entries: []), applications: [])
    var applicationPreview: ApplicationRemovalPreview?
    var isLoadingApplicationPreview = false
    var inspectedApplicationID: String?
    var auditRecords: [AuditRecord]
    var recoveryItems: [RecoveryItem]
    var recoveryIntegrityReports: [UUID: RecoveryIntegrityReport] = [:]
    var storageInventory = StorageInventory(entries: [])
    var storageSnapshots = StorageSnapshotReport.empty
    var latestScanSummary: StorageScanSummary?
    var rulePolicy: RulePolicy
    var rulePolicyLoadError: String?
    let runtime: SecondWindRuntime
    var home: URL { runtime.home }
    var localStore: LocalDataStore { runtime.store }
    var monitorService: MonitorService { runtime.monitor }
    var liveMetricsService: LiveMetricsService { runtime.liveMetrics }
    var applicationInventoryBuilder: ApplicationInventoryBuilder { runtime.applicationInventory }
    var operationCoordinator: any OperationCoordinator { runtime.operationCoordinator }
    var workflows: SecondWindWorkflows { runtime.workflows }
    var scanTask: Task<Void, Never>?
    var activeScanID: UUID?
    var activeOperationID: OperationID?
    var findingBytesByID: [UUID: Int64] = [:]
    var actionableFindingIDs: Set<UUID> = []
    var reviewRequiredFindingIDs: Set<UUID> = []

    init(runtime: SecondWindRuntime) {
        self.runtime = runtime
        self.snapshot = runtime.monitor.snapshot()
        self.auditRecords = runtime.store.audit.records()
        do {
            self.rulePolicy = try runtime.store.rulePolicy.load()
            self.rulePolicyLoadError = nil
        } catch {
            self.rulePolicy = .init()
            self.rulePolicyLoadError = error.localizedDescription
        }
        let storedRecoveryItems = runtime.store.recovery.allItems()
        self.recoveryItems = storedRecoveryItems
        self.recoveryIntegrityReports = Dictionary(
            uniqueKeysWithValues: storedRecoveryItems.map {
                ($0.id, runtime.store.recovery.integrityReport(for: $0))
            }
        )
        liveMetrics = .unavailable
    }

    func scan() {
        cancelScan()
        let scanID = UUID()
        activeScanID = scanID
        isScanning = true
        let rules = localStore.rulePolicy.effectiveRules()
        let recoveryItems = recoveryItems
        let totalBytes = snapshot.storageTotal
        let availableBytes = snapshot.storageAvailable
        let workflows = workflows
        scanTask = Task { [weak self, workflows, recoveryItems, totalBytes, availableBytes] in
            guard let self else { return }
            let request = StorageScanRequest(home: self.home, rules: rules, recoveryItems: recoveryItems, totalBytes: totalBytes, availableBytes: availableBytes)
            var completed = false
            for await event in workflows.scan(request) {
                guard self.activeScanID == scanID else { return }
                switch event {
                case let .started(run):
                    self.activeOperationID = run.id
                case let .progress(progress):
                    self.scanProgress = progress
                case let .completed(result):
                    self.apply(result)
                    completed = true
                case let .failed(run):
                    self.applyFailedScan(run)
                    return
                }
            }
            if !completed && !Task.isCancelled {
                self.isScanning = false
                self.message = "The scan ended before a completed inventory was available."
            }
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

    private func applyFailedScan(_ run: ScanRun) {
        isScanning = false
        scanProgress = nil
        activeScanID = nil
        activeOperationID = nil
        scanTask = nil
        message = run.failure?.localizedDescription ?? "The scan could not complete. The previous completed inventory remains visible."
    }
    func cancelScan() {
        scanTask?.cancel()
        if let activeOperationID {
            Task { await workflows.cancel(activeOperationID) }
        }
        scanTask = nil
        activeScanID = nil
        activeOperationID = nil
        isScanning = false
        scanProgress = nil
    }
    func makePlan() {
        do {
            let plan = try workflows.makeCleanupPlan(
                findings: findings,
                selectedIDs: selectedIDs,
                destination: .recovery
            )
            try workflows.recordCleanupReview(plan)
            proposedPlan = plan
            cleanupPresentation = .reviewingPlan
            refreshActivity()
        }
        catch { message = error.localizedDescription }
    }
    func executePlan(destination: PlanDestination) {
        guard proposedPlan != nil else { return }
        do {
            let plan = try workflows.makeCleanupPlan(
                findings: findings,
                selectedIDs: selectedIDs,
                destination: destination
            )
            Task {
                do {
                    let outcome = try await workflows.executeCleanup(
                        plan,
                        availableBytesBefore: snapshot.storageAvailable
                    )
                    let completedCount = completedActionCount(in: outcome)
                    cleanupCompletion = .init(itemCount: completedCount, reclaimedBytes: outcome.movedBytes, destination: plan.destination)
                    clearSelection()
                    proposedPlan = nil
                    cleanupPresentation = .idle
                    scan()
                    refreshActivity()
                    cleanupPresentation = .showingCompletion
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

        do {
            let candidateIDs = Set(currentFindings.map(\.id))
            let plan = try workflows.makeCleanupPlan(
                findings: currentFindings,
                selectedIDs: candidateIDs,
                destination: .finderTrash
            )
            Task {
                do {
                    let outcome = try await workflows.executeCleanup(
                        plan,
                        availableBytesBefore: snapshot.storageAvailable
                    )
                    let movedCount = completedActionCount(in: outcome)
                    let failureCount = outcome.results.count - movedCount
                    refreshActivity()
                    if movedCount > 0 {
                        scan()
                    }
                    message = directTrashSummary(
                        movedCount: movedCount,
                        failureCount: failureCount
                    )
                } catch {
                    message = error.localizedDescription
                }
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func moveSelectedItemsToTrash() {
        let selectedFindings = findings
            .filter { selectedIDs.contains($0.id) }
        moveFindingsDirectlyToTrash(selectedFindings)
    }

    private func completedActionCount(in outcome: CleanupOutcome) -> Int {
        outcome.results.filter { result in
            switch result.outcome {
            case .completedAndVerified, .completedNotYetObservable:
                return true
            case .skipped,
                 .failed,
                 .sourceAbsent,
                 .destinationConflict,
                 .rolledBack:
                return false
            }
        }.count
    }

    private func directTrashSummary(
        movedCount: Int,
        failureCount: Int
    ) -> String {
        if movedCount == 0 {
            return "Nothing moved to Trash. macOS did not allow the change."
        }
        if failureCount == 0 {
            return "Moved \(movedCount) item(s) to Finder Trash."
        }
        return "Moved \(movedCount) item(s) to Finder Trash. \(failureCount) could not be moved."
    }
}

enum CleanupPresentationPhase {
    case idle
    case reviewingPlan
    case showingCompletion
}
