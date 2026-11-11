import ImageIO
import MapKit
import UniformTypeIdentifiers

final class HazardTileOverlay: MKTileOverlay {
    let layerID: String
    let isDarkened: Bool
    private let source: any TileSource
    private let sourceMaximumZ: Int

    init(layer: HazardLayer, isDarkened: Bool) {
        layerID = layer.id
        self.isDarkened = isDarkened
        source = layer.source
        sourceMaximumZ = layer.zoomRange.upperBound
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: TileImage.size, height: TileImage.size)
        minimumZ = layer.zoomRange.lowerBound
        // Past the source's deepest level, tiles are enlarged from that level.
        maximumZ = 21
        canReplaceMapContent = false
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let overzoom = max(0, path.z - sourceMaximumZ)
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
            do {
                guard let data = try await source.tile(z: z, x: x, y: y) else {
                    result(TileImage.empty, nil)
                    return
                }
                if crop == nil && !isDarkened {
                    result(data, nil)
                } else {
                    result(TileImage.render(data, crop: crop, darken: isDarkened) ?? TileImage.empty, nil)
                }
            } catch {
                result(nil, error)
            }
        }
    }
}

enum TileImage {
    static let size = 256

    /// How much black is laid over tile colours in dark mode.
    private static let darkening: CGFloat = 0.4

    static let empty: Data = {
        let context = makeContext()
        return context?.makeImage().flatMap(png) ?? Data()
    }()

    /// Redraws a tile, optionally enlarging a sub-rectangle (top-left origin, in pixels)
    /// to fill it and dimming its colours for dark mode. Transparency is preserved.
    /// Hazard tiles keep hard pixel edges when enlarged; a basemap with text asks for smoothing.
    static func render(
        _ data: Data, crop: CGRect?, darken: Bool, interpolation: CGInterpolationQuality = .none
    ) -> Data? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              var image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let context = makeContext() else { return nil }
        if let crop {
            let scale = CGFloat(image.width) / CGFloat(size)
            let rect = crop.applying(CGAffineTransform(scaleX: scale, y: scale)).integral
            guard let cropped = image.cropping(to: rect) else { return nil }
            image = cropped
        }
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        context.interpolationQuality = interpolation
        context.draw(image, in: bounds)
        if darken {
            context.setBlendMode(.sourceAtop)
            context.setFillColor(CGColor(gray: 0, alpha: darkening))
            context.fill(bounds)
        }
        return context.makeImage().flatMap(png)
    }

    private static func makeContext() -> CGContext? {
        CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
