import MapKit
import Observation

/// Address suggestions and lookup through MapKit.
@MainActor
@Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet {
            if query.isEmpty { results = [] }
            completer.queryFragment = query
        }
    }
    private(set) var results: [MKLocalSearchCompletion] = []

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 36.5, longitude: 137.5),
            span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 26))
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
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            results = []
        }
    }
}
