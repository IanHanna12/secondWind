import Foundation
import Observation
import SecondWindCore
import SecondWindMacOS

@MainActor
@Observable
final class VolumeCheckState {
    var volumes: [VolumeReference] = []
    var selectedVolumeURL: URL?
    var phase: VolumeCheckPhase = .ready
    var notice = "Choose a local volume and review the verification."

    init() {
        volumes = (FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeUUIDStringKey, .volumeIsLocalKey],
            options: []
        ) ?? []).map(VolumeReference.init).filter(\.isLocal)
        selectedVolumeURL = volumes.first?.url
    }

    var selectedVolume: VolumeReference? {
        volumes.first { $0.url == selectedVolumeURL }
    }

    var statusMessage: String {
        phase.message ?? notice
    }
}

enum VolumeCheckPhase {
    case ready
    case awaitingConfirmation
    case running
    case completed(String)
    case failed(String)

    var message: String? {
        switch self {
        case .ready, .awaitingConfirmation: nil
        case .running: "Verifying the selected local volume…"
        case .completed(let message), .failed(let message): message
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isAwaitingConfirmation: Bool {
        if case .awaitingConfirmation = self { return true }
        return false
    }
}
