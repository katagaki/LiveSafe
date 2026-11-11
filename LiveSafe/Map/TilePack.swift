import CoreLocation
import Foundation
import Synchronization

/// An XYZ raster tile set: where its tiles are served and which zoom levels it has.
struct TileSet: Codable, Hashable, Sendable {
    /// Identifies the tile set, and names its folder inside a pack.
    let id: String
    /// URL with `{z}`, `{x}` and `{y}` placeholders.
    let template: String
    let minimumZ: Int
    let maximumZ: Int

    func url(z: Int, x: Int, y: Int) -> URL? {
        URL(string: template
            .replacingOccurrences(of: "{z}", with: String(z))
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(y)))
    }

    /// The same tile set, no deeper than a zoom level.
    func capped(at z: Int) -> TileSet {
        TileSet(id: id, template: template, minimumZ: min(minimumZ, z), maximumZ: min(maximumZ, z))
    }
}

/// A latitude and longitude box.
struct TileArea: Codable, Hashable, Sendable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2)
    }

    init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    /// A square box around a point.
    init(center: CLLocationCoordinate2D, sideKilometres: Double) {
        let kilometresPerDegree = 111.32
        let latitude = sideKilometres / kilometresPerDegree / 2
        let longitude = latitude / cos(center.latitude * .pi / 180)
        self.init(south: center.latitude - latitude, west: center.longitude - longitude,
                  north: center.latitude + latitude, east: center.longitude + longitude)
    }

    /// Tile columns the box touches at a zoom level.
    func columns(z: Int) -> ClosedRange<Int> {
        let scale = Double(1 << z)
        func column(_ longitude: Double) -> Int {
            min(max(Int(floor((longitude + 180) / 360 * scale)), 0), (1 << z) - 1)
        }
        return column(west)...max(column(west), column(east))
    }

    /// Tile rows the box touches at a zoom level.
    func rows(z: Int) -> ClosedRange<Int> {
        let scale = Double(1 << z)
        func row(_ latitude: Double) -> Int {
            let radians = min(max(latitude, -85.0511), 85.0511) * .pi / 180
            let fraction = (1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2
            return min(max(Int(floor(fraction * scale)), 0), (1 << z) - 1)
        }
        return row(north)...max(row(north), row(south))
    }

    func contains(z: Int, x: Int, y: Int) -> Bool {
        columns(z: z).contains(x) && rows(z: z).contains(y)
    }

    func tileCount(z: Int) -> Int {
        columns(z: z).count * rows(z: z).count
    }
}

/// Tiles of one or more tile sets saved for an area. Holds any XYZ tile set, not only hazard layers.
///
/// On disk a pack is a folder named by its `id`, holding this value as `pack.json` and each tile at
/// `<tile set id>/<z>/<x>/<y>.png`. A tile inside the area with no file is one the server had no data for.
struct TilePack: Codable, Identifiable, Hashable, Sendable {
    /// Deepest zoom level saved. Each level deeper quadruples the requests made to the server.
    static let deepestZ = 15
    /// Largest area that can be saved, in tiles at `deepestZ` (each about 1 km across in Japan).
    static let maximumDeepestTiles = 144
    /// Typical bytes per requested tile, counting the ones the server has no data for.
    static let estimatedTileBytes = 4000

    let id: UUID
    var name: String
    let area: TileArea
    /// The saved tile sets, with the zoom levels that were saved.
    let tileSets: [TileSet]
    var downloadedAt = Date.now
    /// Tiles stored on disk.
    var tileCount = 0
    var byteCount = 0

    /// How many tiles saving an area asks the server for.
    static func requestCount(area: TileArea, tileSets: [TileSet]) -> Int {
        tileSets.reduce(0) { total, tileSet in
            total + (tileSet.minimumZ...tileSet.maximumZ).reduce(0) { $0 + area.tileCount(z: $1) }
        }
    }

    static func isTooLarge(_ area: TileArea) -> Bool {
        area.tileCount(z: deepestZ) > maximumDeepestTiles
    }

    func covers(tileSetID: String, z: Int, x: Int, y: Int) -> Bool {
        tileSets.contains { $0.id == tileSetID && ($0.minimumZ...$0.maximumZ).contains(z) }
            && area.contains(z: z, x: x, y: y)
    }
}

/// Reads one tile set's tiles from a folder laid out as `<z>/<x>/<y>.png`.
struct FileTileSource: TileSource {
    let directory: URL

    func tile(z: Int, x: Int, y: Int) async throws -> Data? {
        try? Data(contentsOf: directory.appending(path: "\(z)/\(x)/\(y).png"))
    }
}

/// Reads a tile set from saved packs where they cover the tile, and from the network elsewhere.
struct PackedTileSource: TileSource {
    /// How many zoom levels a saved tile may be enlarged by when the network cannot be reached.
    private static let maximumEnlargement = 4

    let tileSetID: String
    let store: TilePackStore
    let remote: any TileSource

    func tile(z: Int, x: Int, y: Int) async throws -> Data? {
        if let saved = store.source(tileSetID: tileSetID, z: z, x: x, y: y) {
            return try await saved.tile(z: z, x: x, y: y)
        }
        do {
            return try await remote.tile(z: z, x: x, y: y)
        } catch {
            // Deeper than the packs go, or just outside one: enlarge the nearest saved ancestor.
            for levels in 1...Self.maximumEnlargement where levels <= z {
                let ancestorX = x >> levels
                let ancestorY = y >> levels
                guard let saved = store.source(tileSetID: tileSetID, z: z - levels, x: ancestorX, y: ancestorY)
                else { continue }
                guard let data = try await saved.tile(z: z - levels, x: ancestorX, y: ancestorY) else { return nil }
                let side = CGFloat(TileImage.size) / CGFloat(1 << levels)
                let crop = CGRect(x: CGFloat(x - (ancestorX << levels)) * side,
                                  y: CGFloat(y - (ancestorY << levels)) * side,
                                  width: side, height: side)
                return TileImage.render(data, crop: crop, darken: false)
            }
            throw error
        }
    }
}

/// The saved packs in Application Support.
final class TilePackStore: Sendable {
    static let shared = TilePackStore(
        directory: URL.applicationSupportDirectory.appending(path: "TilePacks", directoryHint: .isDirectory))

    private static let manifest = "pack.json"
    private static let stagingPrefix = "staging-"

    private let directory: URL
    /// Newest first.
    private let packs: Mutex<[TilePack]>

    init(directory: URL) {
        self.directory = directory
        let files = FileManager.default
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
        // Packs can be downloaded again, so they stay out of backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = directory
        try? folder.setResourceValues(values)

        var found: [TilePack] = []
        let decoder = JSONDecoder()
        for item in (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            if item.lastPathComponent.hasPrefix(Self.stagingPrefix) {
                // Left behind by a download that was cut short.
                try? files.removeItem(at: item)
            } else if let data = try? Data(contentsOf: item.appending(path: Self.manifest)),
                      let pack = try? decoder.decode(TilePack.self, from: data) {
                found.append(pack)
            }
        }
        packs = Mutex(found.sorted { $0.downloadedAt > $1.downloadedAt })
    }

    var all: [TilePack] {
        packs.withLock { $0 }
    }

    /// A tile set's source that prefers saved packs over `remote`.
    func source(for tileSetID: String, remote: any TileSource) -> PackedTileSource {
        PackedTileSource(tileSetID: tileSetID, store: self, remote: remote)
    }

    /// The saved files to read a tile from, when a pack covers it.
    func source(tileSetID: String, z: Int, x: Int, y: Int) -> FileTileSource? {
        let pack = packs.withLock { packs in
            packs.first { $0.covers(tileSetID: tileSetID, z: z, x: x, y: y) }
        }
        return pack.map { FileTileSource(directory: folder(for: $0.id).appending(path: tileSetID)) }
    }

    /// An empty folder to download a pack into before it is installed.
    func makeStagingDirectory() throws -> URL {
        let staging = directory.appending(path: Self.stagingPrefix + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }

    /// Moves a downloaded pack into place, replacing the pack with the same `id` if there is one.
    func install(_ pack: TilePack, from staging: URL) throws {
        try JSONEncoder().encode(pack).write(to: staging.appending(path: Self.manifest))
        let destination = folder(for: pack.id)
        try packs.withLock { packs in
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
            packs.removeAll { $0.id == pack.id }
            packs.insert(pack, at: 0)
        }
    }

    func remove(_ id: UUID) {
        packs.withLock { $0.removeAll { $0.id == id } }
        try? FileManager.default.removeItem(at: folder(for: id))
    }

    private func folder(for id: UUID) -> URL {
        directory.appending(path: id.uuidString, directoryHint: .isDirectory)
    }
}
