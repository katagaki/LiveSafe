import CoreLocation

/// A place to evacuate to, from 国土地理院's 指定緊急避難場所・指定避難所データ.
/// https://www.gsi.go.jp/bousaichiri/hinanbasho.html
struct Shelter: Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        /// 指定緊急避難場所: where to flee from immediate danger, designated per disaster type.
        case evacuationSite
        /// 指定避難所: where to stay until the danger has passed.
        case shelter
        /// 指定避難所 for people who need care.
        case welfareShelter

        var id: Self { self }

        /// Card label, as "Title (Detail)".
        var name: LocalizedStringResource {
            switch self {
            case .evacuationSite: "Evacuation Sites (Emergency)"
            case .shelter: "Shelters (General)"
            case .welfareShelter: "Shelters (Welfare)"
            }
        }

        /// The designation, as shown on a pin.
        var designation: LocalizedStringResource {
            switch self {
            case .evacuationSite: "Emergency Evacuation Site"
            case .shelter: "Designated Shelter"
            case .welfareShelter: "Welfare Shelter"
            }
        }

        /// Tile set identifiers in 国土地理院's URL template.
        var tileSets: [String] {
            switch self {
            case .evacuationSite: Disaster.allCases.map { "skhb0\($0.rawValue)" }
            case .shelter: ["sih"]
            case .welfareShelter: ["sfh"]
            }
        }
    }

    /// Disaster types an emergency evacuation site can be designated for.
    /// Raw values are the numbers the data uses.
    enum Disaster: Int, CaseIterable {
        case flood = 1, slope, stormSurge, earthquake, tsunami, fire, inlandFlood, volcano

        var name: LocalizedStringResource {
            switch self {
            case .flood: "Flood"
            case .slope: "Slope Failure, Debris Flow and Landslide"
            case .stormSurge: "Storm Surge"
            case .earthquake: "Earthquake"
            case .tsunami: "Tsunami"
            case .fire: "Large Fire"
            case .inlandFlood: "Inland Flood"
            case .volcano: "Volcanic Event"
            }
        }
    }

    let kind: Kind
    /// Shown exactly as registered; it can carry status such as a closure.
    let name: String
    let address: String
    let remarks: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    /// Empty unless this is an emergency evacuation site.
    let disasters: [Disaster]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
