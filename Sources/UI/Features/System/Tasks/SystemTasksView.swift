import SwiftUI
import SecondWindCore
import SecondWindMacOS

struct SystemTasksScreen: View {
    let model: SecondWindViewModel
    @State private var helperStatus = OptionalPrivilegeDetector().detect()
    @State private var taskPhase = SystemTaskPhase.ready
    @State private var statusMessage = "Enable the optional helper to run an available task."
    @State private var isShowingReinstallConfirmation = false

    private let startupVolume = VolumeReference(url: URL(fileURLWithPath: "/"))

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(
                eyebrow: "OPTIONAL SYSTEM TASKS",
                title: "System tasks",
                detail: "The optional helper runs only fixed macOS tasks. It accepts no command text or arbitrary paths."
            ) { EmptyView() }

            helperSetupCard
            if MaintenanceTask.periodicScripts.isAvailable {
                periodicScriptsCard
            }
            spotlightIndexCard

            if let task = taskPhase.task, taskPhase.isRunning {
                SoftCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Running \(task.title)…")
                            .font(.subheadline.weight(.medium))
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
            }

            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(30)
        .onAppear { refreshHelperStatus() }
        .confirmationDialog(
            "Run \(taskPhase.task?.title ?? "this system task")?",
            isPresented: Binding(
                get: { taskPhase.isAwaitingConfirmation },
                set: { if !$0, taskPhase.isAwaitingConfirmation { taskPhase = .ready } }
            ),
            titleVisibility: .visible
        ) {
            if let task = taskPhase.task {
                Button(task.title) { run(task) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS runs only this fixed task through the optional helper.")
        }
        .alert(
            "Reinstall privileged helper?",
            isPresented: $isShowingReinstallConfirmation
        ) {
            Button("Reinstall") { reinstallHelper() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This unregisters the current helper, then registers the copy included in this app build.")
        }
    }

    private var helperSetupCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Optional privileged helper", systemImage: "lock.shield").font(.headline)
                    Spacer()
                    Button("Refresh") { refreshHelperStatus() }
                }
                Text(helperStatus.helperState.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !helperStatus.canRunHelperTasks {
                    Text("Build the App scheme in Xcode with your signing team, then choose Enable and approve the helper in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    switch helperStatus.helperState {
                    case .notBundled:
                        EmptyView()
                    case .notRegistered:
                        Button("Enable privileged helper") { registerHelper() }
                    case .requiresApproval:
                        Button("Open System Settings") { OptionalHelperRegistration().openApprovalSettings() }
                    case .enabled:
                        EmptyView()
                    case .unavailable:
                        EmptyView()
                    }
                } else {
                    Button("Reinstall privileged helper") {
                        isShowingReinstallConfirmation = true
                    }
                    .disabled(taskPhase.isRunning)
                }
            }
        }
    }

    private var periodicScriptsCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Periodic scripts", systemImage: "calendar.badge.clock").font(.headline)
                Text("Runs macOS's fixed periodic maintenance scripts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Run periodic scripts") { taskPhase = .awaitingConfirmation(.periodicScripts) }
                    .disabled(!helperStatus.canRunHelperTasks || taskPhase.isRunning)
            }
        }
    }

    private var spotlightIndexCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Spotlight index", systemImage: "magnifyingglass").font(.headline)
                Text("Rebuilds the Spotlight index for this Mac's startup volume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Rebuild Spotlight index") { taskPhase = .awaitingConfirmation(.rebuildSpotlightIndex) }
                    .disabled(!helperStatus.canRunHelperTasks || taskPhase.isRunning)
            }
        }
    }

    private func refreshHelperStatus() {
        helperStatus = OptionalPrivilegeDetector().detect()
    }

    private func registerHelper() {
        do {
            try OptionalHelperRegistration().register()
            refreshHelperStatus()
            statusMessage = helperStatus.helperState == .requiresApproval
                ? "Approve the helper in System Settings, then return here and refresh its status."
                : helperStatus.helperState.description
        } catch {
            statusMessage = error.localizedDescription
            refreshHelperStatus()
        }
    }

    private func reinstallHelper() {
        do {
            let registration = OptionalHelperRegistration()
            try registration.unregister()
            try registration.register()
            refreshHelperStatus()
            statusMessage = helperStatus.helperState == .requiresApproval
                ? "Approve the reinstalled helper in System Settings, then return here and refresh its status."
                : "Reinstalled. \(helperStatus.helperState.description)"
        } catch {
            statusMessage = error.localizedDescription
            refreshHelperStatus()
        }
    }

    private func run(_ task: MaintenanceTask) {
        let volume = task == .rebuildSpotlightIndex ? startupVolume : nil
        do {
            try MaintenancePreflight().validate(task: task, volume: volume)
        } catch {
            statusMessage = error.localizedDescription
            return
        }

        taskPhase = .running(task)
        statusMessage = "Running \(task.title)…"
        model.recordMaintenanceStarted(task: task, volume: volume)
        Task {
            let outcome: Result<MaintenanceExecutionResult, Error>
            do {
                outcome = .success(try await XPCPrivilegedMaintenanceClient().execute(.init(task: task, volumeUUID: volume?.uuid)))
            } catch {
                outcome = .failure(error)
            }
            taskPhase = .ready
            model.recordMaintenance(result: outcome, task: task, volume: volume)
            switch outcome {
            case .success(let execution):
                statusMessage = execution.succeeded ? "Completed. \(execution.output)" : "macOS reported a problem. \(execution.output)"
            case .failure(let error):
                statusMessage = error.localizedDescription
            }
        }
    }
}

private enum SystemTaskPhase {
    case ready
    case awaitingConfirmation(MaintenanceTask)
    case running(MaintenanceTask)

    var task: MaintenanceTask? {
        switch self {
        case .ready:
            nil
        case .awaitingConfirmation(let task), .running(let task):
            task
        }
    }

    var isAwaitingConfirmation: Bool {
        if case .awaitingConfirmation = self { return true }
        return false
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
