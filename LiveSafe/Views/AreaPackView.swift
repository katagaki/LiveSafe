import SwiftUI

/// Lists the saved hazard map areas, with the download in progress and a way to save another.
struct AreaPackSection: View {
    @Bindable var model: MapModel

    private var library = TilePackLibrary.shared

    init(model: MapModel) {
        self.model = model
    }

    private var byteCount: Int64? {
        library.packs.isEmpty ? nil : Int64(library.packs.reduce(0) { $0 + $1.byteCount })
    }

    var body: some View {
        Section {
            DataHeader(
                image: "HazardMaps", title: "Hazard Maps", source: "Hazard Map Portal", byteCount: byteCount,
                description: "Saves the hazard maps of an area you choose, so they show without a connection."
            ) {
                if let download = library.download {
                    DownloadProgress(
                        fraction: download.fraction,
                        label: Text("Downloading \(download.name)… \(download.fraction, format: .percent.precision(.fractionLength(0)))"))
                } else {
                    SavedAreasStatus(count: library.packs.count, hasFailed: library.hasFailed)
                }
            }
            ForEach(library.packs) { pack in
                NavigationLink {
                    AreaPackView(id: pack.id, model: model)
                } label: {
                    LabeledContent(pack.name) {
                        Text(Int64(pack.byteCount), format: .byteCount(style: .file))
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        library.delete(pack)
                    }
                    .disabled(library.download?.packID == pack.id)
                }
            }
        }
        Section {
            if library.download != nil {
                Button("Cancel", role: .cancel) {
                    library.cancel()
                }
            } else {
                NavigationLink("Save Area") {
                    SaveAreaView(model: model)
                }
            }
        }
    }
}

/// Progress of the download in progress, with a button that cancels it.
private struct DownloadRow: View {
    let download: TilePackLibrary.Download

    var body: some View {
        HStack(spacing: 16) {
            ProgressView(value: download.fraction) {
                Text(download.name)
            } currentValueLabel: {
                Text(download.fraction, format: .percent.precision(.fractionLength(0)))
            }
            Button("Cancel", systemImage: "xmark.circle.fill") {
                TilePackLibrary.shared.cancel()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .imageScale(.large)
            .tint(.secondary)
        }
    }
}

/// Chooses an area, shows what saving it takes, and starts the download.
private struct SaveAreaView: View {
    private enum Choice {
        case map, location
    }

    /// Side of the box saved around the current location.
    private static let locationKilometres = 5.0

    @Bindable var model: MapModel

    @Environment(\.dismiss) private var dismiss
    @State private var choice = Choice.map
    @State private var provider = LocationProvider()
    @State private var locationArea: TileArea?

    private var library = TilePackLibrary.shared
    private let tileSets = HazardLayer.all.map { $0.tileSet.capped(at: TilePack.deepestZ) }

    init(model: MapModel) {
        self.model = model
    }

    private var area: TileArea? {
        switch choice {
        case .map: model.visibleArea
        case .location: locationArea
        }
    }

    var body: some View {
        let area = area
        let isTooLarge = area.map(TilePack.isTooLarge) ?? false
        List {
            Picker("Area", selection: $choice) {
                Text("Map Area").tag(Choice.map)
                Text("Around Current Location").tag(Choice.location)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if let area {
                let count = TilePack.requestCount(area: area, tileSets: tileSets)
                Section {
                    LabeledContent("Tiles") {
                        Text(count, format: .number)
                    }
                    LabeledContent("Size") {
                        Text(Int64(count * TilePack.estimatedTileBytes), format: .byteCount(style: .file))
                    }
                } header: {
                    Text("Estimate")
                } footer: {
                    if isTooLarge {
                        Text("Zoom in to save a smaller area.")
                    }
                }
            } else if provider.isDenied {
                Section {
                    Link("Location Access Needed", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
            }
            Section {
                Button("Download") {
                    guard let area else { return }
                    library.save(area, tileSets: tileSets)
                    dismiss()
                }
                .disabled(area == nil || isTooLarge)
            }
        }
        .navigationTitle("Save Area")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: updateOutline)
        .onDisappear {
            provider.stop()
            model.outline = nil
        }
        .onChange(of: choice) {
            if choice == .location && locationArea == nil { provider.start() }
            updateOutline()
        }
        .onChange(of: provider.location) {
            // The first fix is kept, so the area does not drift while it is being looked at.
            guard locationArea == nil, let coordinate = provider.location?.coordinate else { return }
            locationArea = TileArea(center: coordinate, sideKilometres: Self.locationKilometres)
            provider.stop()
            updateOutline()
        }
    }

    private func updateOutline() {
        switch choice {
        case .map: model.outline = .visible
        case .location: model.outline = locationArea.map(AreaOutline.fixed)
        }
    }
}

/// One saved area: what it holds, and buttons that update or delete it.
private struct AreaPackView: View {
    let id: UUID
    @Bindable var model: MapModel

    @Environment(\.dismiss) private var dismiss

    private var library = TilePackLibrary.shared

    init(id: UUID, model: MapModel) {
        self.id = id
        self.model = model
    }

    var body: some View {
        List {
            if let pack = library.packs.first(where: { $0.id == id }) {
                Section {
                    LabeledContent("Tiles") {
                        Text(pack.tileCount, format: .number)
                    }
                    LabeledContent("Size") {
                        Text(Int64(pack.byteCount), format: .byteCount(style: .file))
                    }
                    LabeledContent("Downloaded") {
                        Text(pack.downloadedAt, format: .dateTime.year().month().day().hour().minute())
                    }
                }
                Section {
                    if let download = library.download, download.packID == id {
                        DownloadRow(download: download)
                    } else {
                        Button("Update") {
                            library.update(pack)
                        }
                        .disabled(library.download != nil)
                    }
                    if library.hasFailed {
                        Text("Download Failed")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Delete", role: .destructive) {
                        library.delete(pack)
                        dismiss()
                    }
                    .disabled(library.download?.packID == id)
                }
                .onAppear {
                    model.outline = .fixed(pack.area)
                }
            }
        }
        .navigationTitle(library.packs.first { $0.id == id }?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            model.outline = nil
        }
    }
}
