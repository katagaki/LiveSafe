import Foundation

/// Downloads the tiles of an area at a pace that is gentle on the tile server.
enum TilePackDownloader {
    private static let concurrency = 4
    private static let requestsPerSecond = 10
    private static let retries = 2

    private static let session: URLSession = {
        // Nothing is cached, so that updating a pack always reads the server's current tiles.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = concurrency
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    /// Saves every tile the server has for the area into `directory`, as `<tile set id>/<z>/<x>/<y>.png`.
    /// `progress` is called with the number of tiles asked for so far.
    /// - Returns: How many tiles were stored, and their size in bytes.
    static func download(
        _ tileSets: [TileSet], in area: TileArea, to directory: URL,
        progress: @escaping @Sendable (Int) -> Void
    ) async throws -> (tileCount: Int, byteCount: Int) {
        var requested = 0
        var tileCount = 0
        var byteCount = 0
        // Each worker starts a request at most this often.
        let interval = Duration.milliseconds(1000 * concurrency / requestsPerSecond)

        try await withThrowingTaskGroup(of: Int?.self) { group in
            func finish(_ size: Int?) {
                requested += 1
                if let size {
                    tileCount += 1
                    byteCount += size
                }
                progress(requested)
            }

            var running = 0
            for tileSet in tileSets {
                for z in tileSet.minimumZ...tileSet.maximumZ {
                    for x in area.columns(z: z) {
                        let folder = directory.appending(path: "\(tileSet.id)/\(z)/\(x)", directoryHint: .isDirectory)
                        for y in area.rows(z: z) {
                            if running == concurrency, let size = try await group.next() {
                                finish(size)
                                running -= 1
                            }
                            guard let url = tileSet.url(z: z, x: x, y: y) else { throw URLError(.badURL) }
                            group.addTask {
                                let start = ContinuousClock.now
                                let data = try await fetch(url)
                                if let data {
                                    try FileManager.default.createDirectory(
                                        at: folder, withIntermediateDirectories: true)
                                    try data.write(to: folder.appending(path: "\(y).png"))
                                }
                                try await Task.sleep(until: start + interval)
                                return data?.count
                            }
                            running += 1
                        }
                    }
                }
            }
            for try await size in group {
                finish(size)
            }
        }
        return (tileCount, byteCount)
    }

    /// The tile's data, or `nil` when the server has no data there.
    private static func fetch(_ url: URL) async throws -> Data? {
        var attempt = 0
        while true {
            do {
                try RemoteTileSource.checkConnection()
                let (data, response) = try await session.data(from: url)
                switch (response as? HTTPURLResponse)?.statusCode {
                case 200 where !data.isEmpty: return data
                // The portal answers 404 wherever a layer has no data.
                case 404: return nil
                default: throw URLError(.badServerResponse)
                }
            } catch where attempt < retries && !Task.isCancelled {
                attempt += 1
                try await Task.sleep(for: .seconds(attempt * 2))
            }
        }
    }
}
