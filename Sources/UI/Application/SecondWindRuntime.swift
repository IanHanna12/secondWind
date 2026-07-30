import Foundation
import SecondWindApplication
import SecondWindCore
import SecondWindMacOS
import SecondWindPersistence
import SecondWindServices

/// The one composition root for the local app.
///
/// Concrete stores and platform services are created here once, then exposed
/// through the workflow entry point or the small read-only capabilities still
/// used by presentation.
@MainActor
struct SecondWindRuntime {
    let home: URL
    let store: LocalDataStore
    let workflows: SecondWindWorkflows
    let operationCoordinator: any OperationCoordinator
    let monitor: MonitorService
    let liveMetrics: LiveMetricsService
    let applicationInventory: ApplicationInventoryBuilder
    let preferences: PreferenceService

    static func local(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> SecondWindRuntime {
        let store = LocalDataStore()
        let operationCoordinator = LocalOperationCoordinator()
        let workflows = SecondWindWorkflows(
            home: home,
            store: store,
            operationCoordinator: operationCoordinator
        )

        return SecondWindRuntime(
            home: home,
            store: store,
            workflows: workflows,
            operationCoordinator: operationCoordinator,
            monitor: MonitorService(),
            liveMetrics: LiveMetricsService(),
            applicationInventory: ApplicationInventoryBuilder(),
            preferences: PreferenceService()
        )
    }
}
