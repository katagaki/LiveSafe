import MapKit
import Observation
import UIKit

/// The saved packs and the download in progress, for the interface.
@MainActor @Observable
final class TilePackLibrary {
    struct Download {
        let packID: UUID
        let name: String
        var completed = 0
        let total: Int

        var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    }

    static let shared = TilePackLibrary()

    private(set) var packs: [TilePack]
    private(set) var download: Download?
    private(set) var hasFailed = false

    @ObservationIgnored private let store = TilePackStore.shared
    @ObservationIgnored private var task: Task<Void, Never>?

    private init() {
        packs = store.all
    }

    /// Downloads a new pack, named after the place at the middle of the area.
    func save(_ area: TileArea, tileSets: [TileSet]) {
        guard download == nil else { return }
        let tileSets = tileSets.map { $0.capped(at: TilePack.deepestZ) }
        start(TilePack(id: UUID(), name: String(localized: "Saved Area"), area: area, tileSets: tileSets),
              isNew: true)
    }

    /// Downloads a pack's tiles again and replaces the saved ones.
    func update(_ pack: TilePack) {
        guard download == nil else { return }
        start(pack, isNew: false)
    }

    func cancel() {
        task?.cancel()
    }

    func delete(_ pack: TilePack) {
        store.remove(pack.id)
        packs = store.all
    }

    private func start(_ pack: TilePack, isNew: Bool) {
        var pack = pack
        download = Download(packID: pack.id, name: pack.name,
                            total: TilePack.requestCount(area: pack.area, tileSets: pack.tileSets))
        hasFailed = false
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task {
            var staging: URL?
            do {
                if isNew, let name = await Self.placeName(at: pack.area.center) {
                    pack.name = name
                    download = Download(packID: pack.id, name: name, total: download?.total ?? 0)
                }
                let folder = try store.makeStagingDirectory()
                staging = folder
                let result = try await TilePackDownloader.download(pack.tileSets, in: pack.area, to: folder) { count in
                    Task { @MainActor in
                        guard let completed = self.download?.completed, count > completed else { return }
                        self.download?.completed = count
                    }
                }
                try Task.checkCancellation()
                pack.downloadedAt = .now
                pack.tileCount = result.tileCount
                pack.byteCount = result.byteCount
                try store.install(pack, from: folder)
                packs = store.all
            } catch {
                if let staging { try? FileManager.default.removeItem(at: staging) }
                hasFailed = !Task.isCancelled
            }
            download = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private static func placeName(at coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let item = try? await MKReverseGeocodingRequest(location: location)?.mapItems.first else { return nil }
        return item.addressRepresentations?.cityWithContext ?? item.name
    }
}
