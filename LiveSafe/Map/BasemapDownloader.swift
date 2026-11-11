import MapKit
import Observation

/// Saves 淡色地図 tiles for an area, a few at a time so 国土地理院's servers are not loaded heavily.
@MainActor
@Observable
final class BasemapDownloader {
    static let shared = BasemapDownloader()

    /// https://maps.gsi.go.jp/development/ichiran.html
    private static let source = RemoteTileSource(
        template: "https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png")
    /// Tiles requested at once, and the pause after each such group.
    private static let batchSize = 4
    private static let pause = Duration.milliseconds(150)

    /// The share of the current download that is finished, while one is running.
    private(set) var progress: Double?
    private(set) var hasFailed = false

    @ObservationIgnored private var task: Task<Void, Never>?

    func start(region: MKCoordinateRegion) {
        guard task == nil else { return }
        let tiles = BasemapTiles(region: region)
        guard !tiles.isTooLarge else { return }
        progress = 0
        hasFailed = false
        task = Task {
            let id = UUID()
            do {
                async let name = Self.name(for: region.center)
                let byteCount = try await download(tiles.paths, into: id)
                try BasemapPackStore.shared.add(BasemapPack(
                    id: id, name: await name, createdAt: .now,
                    columns: tiles.columns, rows: tiles.rows, byteCount: byteCount))
            } catch {
                BasemapPackStore.discardFolder(for: id)
                hasFailed = !(error is CancellationError)
            }
            progress = nil
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func download(_ paths: [BasemapTiles.Path], into id: UUID) async throws -> Int {
        try BasemapPackStore.prepareFolder(for: id)
        var byteCount = 0
        var finished = 0
        for start in stride(from: 0, to: paths.count, by: Self.batchSize) {
            try Task.checkCancellation()
            let batch = paths[start..<min(start + Self.batchSize, paths.count)]
            byteCount += try await withThrowingTaskGroup(of: Int.self) { group in
                for path in batch {
                    group.addTask { try await Self.save(path, into: id) }
                }
                return try await group.reduce(0, +)
            }
            finished += batch.count
            progress = Double(finished) / Double(paths.count)
            try await Task.sleep(for: Self.pause)
        }
        return byteCount
    }

    /// Saves one tile and returns its size. A tile the server does not have is skipped.
    private nonisolated static func save(_ path: BasemapTiles.Path, into id: UUID) async throws -> Int {
        let data: Data?
        do {
            data = try await source.tile(z: path.z, x: path.x, y: path.y)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            // One more attempt before the whole area is given up.
            try await Task.sleep(for: .seconds(1))
            data = try await source.tile(z: path.z, x: path.x, y: path.y)
        }
        guard let data else { return 0 }
        try BasemapPackStore.write(data, in: id, z: path.z, x: path.x, y: path.y)
        return data.count
    }

    /// The city or ward at a point, to tell saved areas apart.
    private nonisolated static func name(for coordinate: CLLocationCoordinate2D) async -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let items = try? await MKReverseGeocodingRequest(location: location)?.mapItems
        return items?.first?.addressRepresentations?.cityName ?? String(localized: "Map Area")
    }
}
