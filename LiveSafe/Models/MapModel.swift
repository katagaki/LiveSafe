import MapKit
import Observation

struct Place: Equatable {
    let title: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@Observable
final class MapModel {
    private static let defaultsKey = "EnabledHazardLayers"
    private static let shelterDefaultsKey = "EnabledShelterKinds"

    var enabledIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledIDs), forKey: Self.defaultsKey) }
    }
    var enabledShelterKinds: Set<Shelter.Kind> {
        didSet {
            UserDefaults.standard.set(enabledShelterKinds.map(\.rawValue), forKey: Self.shelterDefaultsKey)
        }
    }
    var place: Place?
    /// Counts taps on the current location button; the map moves to the user each time it changes.
    var locateRequests = 0
    /// The part of the map not covered by the sheet, which is the area offered for saving.
    var visibleRegion: MKCoordinateRegion?

    var enabledLayers: [HazardLayer] {
        HazardLayer.all.filter { enabledIDs.contains($0.id) }
    }

    init() {
        let kinds = UserDefaults.standard.stringArray(forKey: Self.shelterDefaultsKey) ?? []
        enabledShelterKinds = Set(kinds.compactMap(Shelter.Kind.init))
        if let saved = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) {
            enabledIDs = Set(saved)
        } else {
            enabledIDs = ["01_flood_l2_shinsuishin_data"]
        }
    }
}
