import MapKit

/// Saved 淡色地図 tiles, drawn in place of Apple's basemap where it cannot be loaded.
final class BasemapTileOverlay: MKTileOverlay {
    let packs: [BasemapPack]
    let isDarkened: Bool
    private let source: BasemapPackSource

    init(packs: [BasemapPack], isDarkened: Bool) {
        self.packs = packs
        self.isDarkened = isDarkened
        source = BasemapPackSource(packs: packs)
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: TileImage.size, height: TileImage.size)
        minimumZ = BasemapPack.zoomRange.lowerBound
        // Past the deepest saved level, tiles are enlarged from that level.
        maximumZ = 21
        canReplaceMapContent = false
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let overzoom = max(0, path.z - BasemapPack.zoomRange.upperBound)
        let z = path.z - overzoom
        let x = path.x >> overzoom
        let y = path.y >> overzoom
        var crop: CGRect?
        if overzoom > 0 {
            let side = CGFloat(TileImage.size) / CGFloat(1 << overzoom)
            crop = CGRect(x: CGFloat(path.x - (x << overzoom)) * side,
                          y: CGFloat(path.y - (y << overzoom)) * side,
                          width: side, height: side)
        }
        let source = source
        let isDarkened = isDarkened
        Task.detached(priority: .userInitiated) {
            // Outside the saved areas the tile stays clear, so whatever Apple's map has shows through.
            guard let data = try? await source.tile(z: z, x: x, y: y) else {
                result(TileImage.empty, nil)
                return
            }
            if crop == nil && !isDarkened {
                result(data, nil)
            } else {
                result(TileImage.render(data, crop: crop, darken: isDarkened, interpolation: .high) ?? TileImage.empty, nil)
            }
        }
    }
}
