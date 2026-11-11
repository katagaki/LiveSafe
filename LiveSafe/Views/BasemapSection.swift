import MapKit
import SwiftUI

/// Saved areas of the fallback basemap, and saving the area now on the map.
struct BasemapSection: View {
    /// The part of the map not covered by the sheet.
    let region: MKCoordinateRegion?

    private var store: BasemapPackStore { .shared }
    private var downloader: BasemapDownloader { .shared }

    private var byteCount: Int64? {
        store.packs.isEmpty ? nil : Int64(store.packs.reduce(0) { $0 + $1.byteCount })
    }

    var body: some View {
        Section {
            DataHeader(
                image: "OfflineMap", title: "Offline Map",
                source: "Geospatial Information Authority of Japan", byteCount: byteCount,
                description: "Saves GSI's map of the area on screen, to show under the hazard maps without a connection."
            ) {
                if let progress = downloader.progress {
                    DownloadProgress(
                        fraction: progress,
                        label: Text("Downloading… \(progress, format: .percent.precision(.fractionLength(0)))"))
                } else {
                    SavedAreasStatus(count: store.packs.count, hasFailed: downloader.hasFailed)
                }
            }
            ForEach(store.packs) { pack in
                LabeledContent(pack.name) {
                    Text(Int64(pack.byteCount), format: .byteCount(style: .file))
                }
            }
            .onDelete { offsets in
                for pack in offsets.map({ store.packs[$0] }) {
                    store.delete(pack)
                }
            }
        }
        Section {
            if downloader.progress != nil {
                Button("Cancel", role: .cancel) {
                    downloader.cancel()
                }
            } else if let region {
                let tiles = BasemapTiles(region: region)
                Button {
                    downloader.start(region: region)
                } label: {
                    LabeledContent("Save Area on Map") {
                        if tiles.isTooLarge {
                            Text("Area Too Large")
                        } else {
                            Text("About \(Int64(tiles.estimatedByteCount), format: .byteCount(style: .file))")
                        }
                    }
                }
                .disabled(tiles.isTooLarge || Connectivity.shared.isOffline)
            }
        }
    }
}
