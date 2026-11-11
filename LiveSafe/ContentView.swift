import SwiftUI

struct ContentView: View {
    static let compactDetent = PresentationDetent.fraction(compactFraction)
    private static let compactFraction: CGFloat = 0.3

    @State private var model = MapModel()
    @State private var detent = compactDetent
    /// Distance from the top of the screen to the top of the sheet, as last measured.
    @State private var sheetTop: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            HazardMapView(
                layers: model.enabledLayers, shelterKinds: model.enabledShelterKinds,
                place: model.place, locateRequests: model.locateRequests,
                bottomInset: bottomInset(in: geometry),
                basemapPacks: Connectivity.shared.isOffline ? BasemapPackStore.shared.packs : [],
                onRegionChange: { model.visibleRegion = $0 })
            .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            Button("Current Location", systemImage: "location") {
                model.locateRequests += 1
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .padding(.horizontal)
        }
        .sheet(isPresented: .constant(true)) {
            SheetView(model: model, detent: $detent)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { sheetTop = $0 }
                .presentationDetents([Self.compactDetent, .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
        }
    }

    /// How much of the map the sheet covers, so the map keeps its centre and legal text clear of it.
    /// Stops growing past the medium detent, where the sheet covers the map anyway.
    private func bottomInset(in geometry: GeometryProxy) -> CGFloat {
        let insets = geometry.safeAreaInsets
        let height = geometry.size.height + insets.top + insets.bottom
        guard let sheetTop else { return height * Self.compactFraction }
        // The map adds the bottom safe area to this itself.
        return min(height - sheetTop, height * 0.55) - insets.bottom
    }
}
