import Foundation
import MapKit

/// One saved area of 国土地理院's 淡色地図, held as XYZ tiles on the device.
struct BasemapPack: Codable, Identifiable, Equatable {
    /// Zoom levels saved for an area. Below 9 an area is only a few points wide.
    /// 15 is the deepest level saved: it already shows streets and block names, and each level
    /// past it quadruples the tiles and bytes for one area. Deeper views enlarge level 15.
    static let zoomRange = 9...15
    /// The most tiles one area may hold, which is about 33 km square.
    static let maximumTileCount = 1500
    /// What a city tile weighs at the deepest saved level, and at the shallower, busier ones.
    static let estimatedTileBytes = 45_000
    static let estimatedShallowTileBytes = 75_000

    let id: UUID
    let name: String
    let createdAt: Date
    /// Tile columns and rows covered at the deepest saved zoom level.
    let columns: ClosedRange<Int>
    let rows: ClosedRange<Int>
    var byteCount: Int

    /// Whether the area holds a tile, which is at one of the saved zoom levels.
    func covers(z: Int, x: Int, y: Int) -> Bool {
        guard Self.zoomRange.contains(z) else { return false }
        let shift = Self.zoomRange.upperBound - z
        return (columns.lowerBound >> shift ... columns.upperBound >> shift).contains(x)
            && (rows.lowerBound >> shift ... rows.upperBound >> shift).contains(y)
    }

    var mapRect: MKMapRect {
        let side = MKMapSize.world.width / pow(2, Double(Self.zoomRange.upperBound))
        return MKMapRect(
            x: Double(columns.lowerBound) * side, y: Double(rows.lowerBound) * side,
            width: Double(columns.count) * side, height: Double(rows.count) * side)
    }
}

/// The tiles needed to cover a region at every saved zoom level.
struct BasemapTiles {
    struct Path: Hashable {
        let z: Int
        let x: Int
        let y: Int
    }

    let columns: ClosedRange<Int>
    let rows: ClosedRange<Int>

    init(region: MKCoordinateRegion) {
        let zoom = BasemapPack.zoomRange.upperBound
        let count = pow(2, Double(zoom))
        let limit = Int(count) - 1
        func column(_ longitude: Double) -> Int {
            min(max(Int(floor((longitude + 180) / 360 * count)), 0), limit)
        }
        func row(_ latitude: Double) -> Int {
            let radians = min(max(latitude, -85), 85) * .pi / 180
            return min(max(Int(floor((1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2 * count)), 0), limit)
        }
        columns = column(region.center.longitude - region.span.longitudeDelta / 2)
            ... column(region.center.longitude + region.span.longitudeDelta / 2)
        rows = row(region.center.latitude + region.span.latitudeDelta / 2)
            ... row(region.center.latitude - region.span.latitudeDelta / 2)
    }

    private func ranges(at z: Int) -> (columns: ClosedRange<Int>, rows: ClosedRange<Int>) {
        let shift = BasemapPack.zoomRange.upperBound - z
        return (columns.lowerBound >> shift ... columns.upperBound >> shift,
                rows.lowerBound >> shift ... rows.upperBound >> shift)
    }

    private func count(at z: Int) -> Int {
        let ranges = ranges(at: z)
        return ranges.columns.count * ranges.rows.count
    }

    var count: Int {
        BasemapPack.zoomRange.reduce(0) { $0 + count(at: $1) }
    }

    var isTooLarge: Bool { count > BasemapPack.maximumTileCount }

    var estimatedByteCount: Int {
        let deepest = count(at: BasemapPack.zoomRange.upperBound)
        return deepest * BasemapPack.estimatedTileBytes + (count - deepest) * BasemapPack.estimatedShallowTileBytes
    }

    /// Every tile, shallowest zoom level first.
    var paths: [Path] {
        BasemapPack.zoomRange.flatMap { z in
            let ranges = ranges(at: z)
            return ranges.columns.flatMap { x in ranges.rows.map { y in Path(z: z, x: x, y: y) } }
        }
    }
}

/// Reads saved 淡色地図 tiles. `nil` wherever no saved area holds the tile.
struct BasemapPackSource: TileSource {
    let packs: [BasemapPack]

    func tile(z: Int, x: Int, y: Int) async throws -> Data? {
        for pack in packs where pack.covers(z: z, x: x, y: y) {
            if let data = try? Data(contentsOf: BasemapPackStore.file(in: pack.id, z: z, x: x, y: y)) {
                return data
            }
        }
        return nil
    }
}

/// Keeps saved basemap areas in Application Support, one folder of `z/x/y.png` files and a manifest per area.
/// Deliberately small and self-contained, so a shared tile-pack store can replace it.
@MainActor
@Observable
final class BasemapPackStore {
    static let shared = BasemapPackStore()

    private static let manifestName = "pack.json"

    private(set) var packs: [BasemapPack] = []

    private nonisolated static var root: URL {
        URL.applicationSupportDirectory.appending(path: "BasemapPacks")
    }

    nonisolated static func folder(for id: UUID) -> URL {
        root.appending(path: id.uuidString)
    }

    nonisolated static func file(in id: UUID, z: Int, x: Int, y: Int) -> URL {
        folder(for: id).appending(path: "\(z)/\(x)/\(y).png")
    }

    private init() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: Self.root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            // A folder without a manifest is a download that never finished.
            if let data = try? Data(contentsOf: folder.appending(path: Self.manifestName)),
               let pack = try? JSONDecoder().decode(BasemapPack.self, from: data) {
                packs.append(pack)
            } else {
                try? FileManager.default.removeItem(at: folder)
            }
        }
        packs.sort { $0.createdAt < $1.createdAt }
    }

    /// Makes the folder a new area's tiles are written into. Tiles can be downloaded again, so they stay out of backups.
    nonisolated static func prepareFolder(for id: UUID) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var root = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        try FileManager.default.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
    }

    nonisolated static func write(_ data: Data, in id: UUID, z: Int, x: Int, y: Int) throws {
        let file = file(in: id, z: z, x: x, y: y)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }

    nonisolated static func discardFolder(for id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }

    /// Records a fully downloaded area, which makes it available to the map.
    func add(_ pack: BasemapPack) throws {
        let data = try JSONEncoder().encode(pack)
        try data.write(to: Self.folder(for: pack.id).appending(path: Self.manifestName), options: .atomic)
        packs.append(pack)
    }

    func delete(_ pack: BasemapPack) {
        packs.removeAll { $0.id == pack.id }
        Self.discardFolder(for: pack.id)
    }
}
