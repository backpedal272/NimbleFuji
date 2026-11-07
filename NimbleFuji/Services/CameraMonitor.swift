import Foundation
import Observation

/// Tracks whether fujicli can see a camera.
@Observable
final class CameraMonitor {
    enum Status: Equatable {
        case unknown
        case checking
        case connected(String)
        case notConnected
        case toolMissing
        case error(String)

        var isConnected: Bool {
            if case .connected = self { true } else { false }
        }
    }

    private(set) var status: Status = .unknown
    private(set) var toolVersion: String?
    private var checkTask: Task<Void, Never>?

    func refresh(using cli: FujiCLI?) {
        guard let cli else {
            status = .toolMissing
            toolVersion = nil
            return
        }
        checkTask?.cancel()
        status = .checking
        checkTask = Task {
            let version = await cli.version()
            let newStatus: Status
            do {
                let cameras = try await cli.connectedCameras()
                newStatus = cameras.first.map(Status.connected) ?? .notConnected
            } catch {
                newStatus = .error(error.localizedDescription)
            }
            guard !Task.isCancelled else { return }
            toolVersion = version
            status = newStatus
        }
    }

    /// Waits for a pending refresh to finish.
    func waitForRefresh() async {
        await checkTask?.value
    }
}
