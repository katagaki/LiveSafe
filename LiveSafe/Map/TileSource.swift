import Foundation

/// Where a layer's tiles come from. Remote today; an offline pack can conform later.
protocol TileSource: Sendable {
    /// PNG data for the tile, or `nil` when the source has no tile there.
    func tile(z: Int, x: Int, y: Int) async throws -> Data?
}

/// Reads XYZ tiles live from a URL template, relying on HTTP caching only.
struct RemoteTileSource: TileSource {
    let template: String

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20)
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    /// Throws when the network should be treated as unreachable.
    /// Debug builds launched with `-SimulateOffline YES` always throw, to test offline use.
    static func checkConnection() throws {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "SimulateOffline") { throw URLError(.notConnectedToInternet) }
        #endif
    }

    func tile(z: Int, x: Int, y: Int) async throws -> Data? {
        try Self.checkConnection()
        let string = template
            .replacingOccurrences(of: "{z}", with: String(z))
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(y))
        guard let url = URL(string: string) else { return nil }
        let (data, response) = try await Self.session.data(from: url)
        // The portal answers 404 wherever a layer has no data.
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
