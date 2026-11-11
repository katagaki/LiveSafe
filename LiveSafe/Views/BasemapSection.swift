import MapKit
import SwiftUI

/// Saved areas of the fallback basemap, and saving the area now on the map.
struct BasemapSection: View {
    /// The part of the map not covered by the sheet.
    let region: MKCoordinateRegion?

    private var store: BasemapPackStore { .shared }
    private var downloader: BasemapDownloader { .shared }

    var body: some View {
        Section("Offline Map") {
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
            if let progress = downloader.progress {
                ProgressView("Downloading", value: progress)
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
            if downloader.hasFailed {
                Text("Download Failed")
                    .foregroundStyle(.red)
            }
        }
    }
}
