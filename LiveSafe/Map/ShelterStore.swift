import CoreLocation

/// Reads shelters live from 国土地理院's GeoJSON tiles, which exist at one zoom level only.
actor ShelterStore {
    static let shared = ShelterStore()
    static let zoom = 10

    private struct Key: Hashable {
        let kind: Shelter.Kind
        let x: Int
        let y: Int
    }

    private var cache: [Key: [Shelter]] = [:]

    /// Every shelter of a kind in one tile. An emergency evacuation site appears once,
    /// however many disaster types it is designated for. Without a connection,
    /// shelters come from the saved copy if there is one.
    func shelters(of kind: Shelter.Kind, x: Int, y: Int) async -> [Shelter] {
        let key = Key(kind: kind, x: x, y: y)
        if let cached = cache[key] { return cached }
        let loaded = await withTaskGroup(of: [Shelter]?.self) { group in
            for tileSet in kind.tileSets {
                group.addTask { await Self.load(tileSet, kind: kind, x: x, y: y) }
            }
            return await group.reduce(into: [[Shelter]]()) { if let shelters = $1 { $0.append(shelters) } }
        }
        guard !loaded.isEmpty else {
            let bounds = Self.bounds(x: x, y: y)
            switch kind {
            case .evacuationSite:
                return await OfflineSites.shared.sites(latitudes: bounds.latitudes, longitudes: bounds.longitudes)
            case .shelter, .welfareShelter:
                return await OfflineShelters.shared.shelters(
                    of: kind, latitudes: bounds.latitudes, longitudes: bounds.longitudes)
            }
        }
        let shelters = Array(Set(loaded.joined()))
        if cache.count > 64 { cache.removeAll() }
        cache[key] = shelters
        return shelters
    }

    /// Shelters in the tile holding a point and the eight tiles around it.
    func shelters(of kind: Shelter.Kind, around coordinate: CLLocationCoordinate2D) async -> [Shelter] {
        let x = Self.tileX(coordinate.longitude)
        let y = Self.tileY(coordinate.latitude)
        var found: Set<Shelter> = []
        for tileX in (x - 1)...(x + 1) {
            for tileY in (y - 1)...(y + 1) {
                found.formUnion(await shelters(of: kind, x: tileX, y: tileY))
            }
        }
        return Array(found)
    }

    static func tileX(_ longitude: CLLocationDegrees) -> Int {
        Int(floor((longitude + 180) / 360 * pow(2, Double(zoom))))
    }

    static func tileY(_ latitude: CLLocationDegrees) -> Int {
        let radians = latitude * .pi / 180
        let fraction = (1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2
        return Int(floor(fraction * pow(2, Double(zoom))))
    }

    private static func bounds(x: Int, y: Int) -> (latitudes: ClosedRange<Double>, longitudes: ClosedRange<Double>) {
        let count = pow(2, Double(zoom))
        func latitude(_ y: Int) -> Double { atan(sinh(.pi * (1 - 2 * Double(y) / count))) * 180 / .pi }
        return (latitude(y + 1)...latitude(y),
                (Double(x) / count * 360 - 180)...(Double(x + 1) / count * 360 - 180))
    }

    /// `nil` when the tile could not be reached, as opposed to holding nothing.
    private static func load(_ tileSet: String, kind: Shelter.Kind, x: Int, y: Int) async -> [Shelter]? {
        #if DEBUG
        // Lets the saved copy be tested without turning the network off.
        if ProcessInfo.processInfo.arguments.contains("-SimulateOfflineShelters") { return nil }
        #endif
        let source: any TileSource = RemoteTileSource(
            template: "https://cyberjapandata.gsi.go.jp/xyz/\(tileSet)/{z}/{x}/{y}.geojson")
        let data: Data?
        do {
            data = try await source.tile(z: zoom, x: x, y: y)
        } catch {
            return nil
        }
        guard let data, let collection = try? JSONDecoder().decode(FeatureCollection.self, from: data) else {
            return []
        }
        return collection.features.compactMap { feature in
            guard feature.geometry.coordinates.count >= 2, let name = feature.properties.name else { return nil }
            return Shelter(
                kind: kind, name: name,
                address: feature.properties.address ?? "", remarks: feature.properties.remarks ?? "",
                latitude: feature.geometry.coordinates[1], longitude: feature.geometry.coordinates[0],
                disasters: feature.properties.disasters)
        }
    }
}

private struct FeatureCollection: Decodable {
    let features: [Feature]

    struct Feature: Decodable {
        let geometry: Geometry
        let properties: Properties
    }

    struct Geometry: Decodable {
        let coordinates: [Double]
    }

    struct Properties: Decodable {
        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        let name: String?
        let address: String?
        let remarks: String?
        let disasters: [Shelter.Disaster]

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            func string(_ key: String) -> String? {
                try? container.decode(String.self, forKey: Key(stringValue: key))
            }
            name = string("name")
            address = string("address")
            remarks = string("remarks")
            // A site is designated for disaster N when "disasterN" is 1.
            disasters = Shelter.Disaster.allCases.filter {
                (try? container.decode(Int.self, forKey: Key(stringValue: "disaster\($0.rawValue)"))) == 1
            }
        }
    }
}
