import SwiftUI
import SecondWindCore
import SecondWindPlatform

struct VolumeCheckView: View {
    let model: SecondWindViewModel
    @State private var state = VolumeCheckState()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(
                eyebrow: "LOCAL VOLUME CHECK",
                title: "Verify a local volume",
                detail: "Read-only filesystem verification. No helper, shell text, or arbitrary path is involved."
            ) { EmptyView() }

            Picker("Local volume", selection: $state.selectedVolumeURL) {
                ForEach(state.volumes, id: \.url) { Text($0.url.path).tag(Optional($0.url)) }
            }

            SoftCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("What will happen", systemImage: "checklist").font(.headline)
                    Text(MaintenanceTask.verifyVolume.explanation)
                    Text("macOS receives the selected local volume only after it passes local-volume validation. The check does not modify files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(state.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Button(state.phase.isRunning ? "Verifying…" : "Review and verify") {
                do {
                    try MaintenancePreflight().validate(task: .verifyVolume, volume: state.selectedVolume)
                    state.phase = .awaitingConfirmation
                } catch {
                    state.phase = .failed(error.localizedDescription)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.phase.isRunning || state.selectedVolume == nil)

            Text("Not included: LaunchServices resets, RAM cleaning, permission repair, or generic “speed up” actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(30)
        .confirmationDialog(
            "Verify \(state.selectedVolume?.url.path ?? "this volume")?",
            isPresented: Binding(
                get: { state.phase.isAwaitingConfirmation },
                set: { if !$0, state.phase.isAwaitingConfirmation { state.phase = .ready } }
            ),
            titleVisibility: .visible
        ) {
            Button("Verify volume") { run() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This runs macOS's read-only local-volume verification task.")
        }
    }

    private func run() {
        state.phase = .running
        let task = MaintenanceTask.verifyVolume
        let volume = state.selectedVolume
        model.recordMaintenanceStarted(task: task, volume: volume)
        Task {
            let outcome: Result<MaintenanceExecutionResult, Error>
            do {
                outcome = .success(try await Task.detached { try LocalMaintenanceRunner().run(task: task, volume: volume) }.value)
            } catch {
                outcome = .failure(error)
            }
            model.recordMaintenance(result: outcome, task: task, volume: volume)
            switch outcome {
            case .success(let result):
                state.phase = result.succeeded ? .completed("Completed. \(result.output)") : .failed("macOS reported a problem. \(result.output)")
            case .failure(let error):
                state.phase = .failed(error.localizedDescription)
            }
        }
    }
}
