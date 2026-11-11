import MapKit
import Network
import Observation

/// Address suggestions and lookup through MapKit, or from the saved places when MapKit cannot be reached.
@MainActor
@Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet {
            if query.isEmpty { results = [] }
            completer.queryFragment = query
            if isOffline { searchSaved() }
        }
    }
    private(set) var results: [MKLocalSearchCompletion] = []
    /// Matches from the saved places, filled only while offline.
    private(set) var savedResults: [Shelter] = []

    /// Whether results come from the saved places rather than MapKit.
    var isOffline: Bool { !isReachable || hasFailed }
    /// Whether there are saved places to search.
    var hasSavedData: Bool { OfflineSearch.shared.hasData }

    private var isReachable = true
    /// Whether the completer's last answer was an error.
    private var hasFailed = false

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var savedSearch: Task<Void, Never>?

    override init() {
        super.init()
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 36.5, longitude: 137.5),
            span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 26))
        #if DEBUG
        // Stands in for having no connection, which the simulator cannot lose on its own.
        if ProcessInfo.processInfo.arguments.contains("-SimulateOffline") {
            isReachable = false
            return
        }
        #endif
        completer.delegate = self
        monitor.pathUpdateHandler = { [weak self] path in
            let isReachable = path.status == .satisfied
            Task { @MainActor in
                self?.reachabilityChanged(to: isReachable)
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    deinit {
        monitor.cancel()
    }

    func place(for completion: MKLocalSearchCompletion) async -> Place? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let item = try? await search.start().mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        return Place(title: completion.title, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            results = query.isEmpty ? [] : completer.results
            hasFailed = false
            if !isOffline { clearSaved() }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            results = []
            hasFailed = true
            searchSaved()
        }
    }

    private func reachabilityChanged(to isReachable: Bool) {
        guard isReachable != self.isReachable else { return }
        self.isReachable = isReachable
        if isReachable {
            // Ask again, since the completer does not retry a fragment it already failed on.
            hasFailed = false
            clearSaved()
            completer.cancel()
            completer.queryFragment = query
        } else {
            searchSaved()
        }
    }

    private func searchSaved() {
        savedSearch?.cancel()
        guard !query.isEmpty else {
            savedResults = []
            return
        }
        savedSearch = Task { [query] in
            let found = await OfflineSearch.shared.search(query)
            if !Task.isCancelled, isOffline { savedResults = found }
        }
    }

    private func clearSaved() {
        savedSearch?.cancel()
        savedResults = []
    }
}
