import Foundation
import Network
import Observation

/// Whether the device has a network connection.
@MainActor
@Observable
final class Connectivity {
    static let shared = Connectivity()

    private(set) var isOffline = DebugOptions.simulatesOffline

    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        guard !DebugOptions.simulatesOffline else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOffline = path.status != .satisfied
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }
}

/// Launch arguments for testing without a connection. Always off in release builds.
enum DebugOptions {
    /// `-SimulateOffline YES`: remote tiles come from the HTTP cache only, and the app acts as if it has no connection.
    static let simulatesOffline: Bool = {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "SimulateOffline")
        #else
        false
        #endif
    }()

    /// `-HideAppleBasemap YES`: Apple's map is blanked, as it is without a connection or cached tiles.
    static let hidesAppleBasemap: Bool = {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "HideAppleBasemap")
        #else
        false
        #endif
    }()
}
