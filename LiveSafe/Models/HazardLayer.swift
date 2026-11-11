import Foundation

/// A hazard map raster layer published by ハザードマップポータルサイト.
/// https://disaportal.gsi.go.jp/hazardmap/copyright/opendata.html
struct HazardLayer: Identifiable {
    enum Category: CaseIterable {
        case flood, inundation, slope

        var name: LocalizedStringResource {
            switch self {
            case .flood: "Flood"
            case .inundation: "Inundation"
            case .slope: "Landslide and Avalanche"
            }
        }
    }

    /// Tile set identifier in the portal's URL template. Also names the layer's icon asset.
    let id: String
    let name: LocalizedStringResource
    let category: Category
    /// Zoom levels the portal serves tiles for.
    let zoomRange: ClosedRange<Int>

    var source: any TileSource {
        RemoteTileSource(template: "https://disaportaldata.gsi.go.jp/raster/\(id)/{z}/{x}/{y}.png")
    }

    /// The name without its bracketed qualifier.
    var title: String { String(localized: name).qualified.title }
    /// The bracketed qualifier in the name, without the brackets.
    var detail: String? { String(localized: name).qualified.detail }

    static func layers(in category: Category) -> [HazardLayer] {
        all.filter { $0.category == category }
    }

    /// Nationwide integrated layers, in map stacking order (first is lowest).
    static let all: [HazardLayer] = [
        .init(id: "01_flood_l2_shinsuishin_data",
              name: "Flood Depth (Maximum Scale)", category: .flood, zoomRange: 2...17),
        .init(id: "01_flood_l1_shinsuishin_newlegend_data",
              name: "Flood Depth (Planned Scale)", category: .flood, zoomRange: 2...17),
        .init(id: "01_flood_l2_keizoku_data",
              name: "Flood Duration (Maximum Scale)", category: .flood, zoomRange: 2...17),
        .init(id: "01_flood_l2_kaokutoukai_hanran_data",
              name: "House Collapse (Overflow)", category: .flood, zoomRange: 4...17),
        .init(id: "01_flood_l2_kaokutoukai_kagan_data",
              name: "House Collapse (Bank Erosion)", category: .flood, zoomRange: 4...17),
        .init(id: "02_naisui_data",
              name: "Inland Flooding (Stormwater)", category: .inundation, zoomRange: 2...17),
        .init(id: "03_hightide_l2_shinsuishin_data",
              name: "Storm Surge (Maximum Scale)", category: .inundation, zoomRange: 2...17),
        .init(id: "04_tsunami_newlegend_data",
              name: "Tsunami (Inundation Depth)", category: .inundation, zoomRange: 2...17),
        .init(id: "05_dosekiryukeikaikuiki",
              name: "Debris Flow (Warning Zone)", category: .slope, zoomRange: 2...17),
        .init(id: "05_kyukeishakeikaikuiki",
              name: "Steep Slope Failure (Warning Zone)", category: .slope, zoomRange: 2...17),
        .init(id: "05_jisuberikeikaikuiki",
              name: "Landslide (Warning Zone)", category: .slope, zoomRange: 2...17),
        .init(id: "05_nadarekikenkasyo",
              name: "Avalanche (Hazard Site)", category: .slope, zoomRange: 2...17)
    ]
}

extension String {
    /// Splits "Title (Detail)" into its parts. Accepts full-width brackets.
    var qualified: (title: String, detail: String?) {
        guard let open = firstIndex(where: { "(（".contains($0) }),
              let close = self[open...].firstIndex(where: { ")）".contains($0) }) else {
            return (self, nil)
        }
        let title = self[..<open] + self[index(after: close)...]
        return (title.trimmingCharacters(in: .whitespaces), String(self[index(after: open)..<close]))
    }
}
