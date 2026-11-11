import MapKit
import SwiftUI

/// Apple Maps basemap with hazard tile overlays drawn beneath its labels.
/// Without a connection, saved 淡色地図 tiles are drawn over Apple's map wherever an area was saved.
struct HazardMapView: UIViewRepresentable {
    var layers: [HazardLayer]
    var shelterKinds: Set<Shelter.Kind>
    var place: Place?
    var locateRequests: Int
    /// Height at the bottom of the map covered by the sheet.
    var bottomInset: CGFloat
    /// Saved basemap areas to fall back on. Empty while there is a connection.
    var basemapPacks: [BasemapPack]
    /// Called with the region left uncovered by the sheet whenever it changes.
    var onRegionChange: (MKCoordinateRegion) -> Void

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.preservesSuperviewLayoutMargins = false
        mapView.isPitchEnabled = false
        #if DEBUG
        if DebugOptions.hidesAppleBasemap {
            mapView.insertOverlay(BlankTileOverlay(), at: 0, level: .aboveRoads)
        }
        #endif
        mapView.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.681, longitude: 139.767),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onRegionChange = onRegionChange
        if mapView.layoutMargins.bottom != bottomInset {
            mapView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
            // Reported after this update, because it changes the model.
            DispatchQueue.main.async { coordinator.reportRegion(of: mapView) }
        }
        coordinator.layers = layers
        coordinator.isDark = colorScheme == .dark
        coordinator.basemapPacks = basemapPacks
        coordinator.updateOverlays(on: mapView)
        updatePlace(on: mapView, coordinator: context.coordinator)
        if context.coordinator.locateRequests != locateRequests {
            context.coordinator.locateRequests = locateRequests
            context.coordinator.locate(on: mapView)
        }
        if context.coordinator.shelterKinds != shelterKinds {
            context.coordinator.shelterKinds = shelterKinds
            context.coordinator.refreshShelters(on: mapView)
        }
    }

    private func updatePlace(on mapView: MKMapView, coordinator: Coordinator) {
        guard coordinator.place != place else { return }
        coordinator.place = place
        if let pin = coordinator.placePin { mapView.removeAnnotation(pin) }
        coordinator.placePin = nil
        guard let place else { return }
        let annotation = MKPointAnnotation()
        coordinator.placePin = annotation
        annotation.coordinate = place.coordinate
        annotation.title = place.title
        mapView.addAnnotation(annotation)
        mapView.setRegion(
            MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500),
            animated: true)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        /// Shelters are only drawn once the map is zoomed in this far, in degrees of longitude.
        private static let maximumShelterSpan: CLLocationDegrees = 0.12

        /// Clears the balloon a marker grows into when selected.
        private static let calloutGap: CGFloat = 40

        var place: Place?
        var placePin: MKPointAnnotation?
        var shelterKinds: Set<Shelter.Kind> = []
        var locateRequests = 0
        var layers: [HazardLayer] = []
        var isDark = false
        var basemapPacks: [BasemapPack] = []
        var onRegionChange: (MKCoordinateRegion) -> Void = { _ in }
        /// Where hazard overlays currently sit: beneath Apple's labels, or above the fallback basemap that covers them.
        private var hazardLevel = MKOverlayLevel.aboveRoads
        private let locationManager = CLLocationManager()
        private let store = ShelterStore.shared
        private var shelterTask: Task<Void, Never>?
        private var callout: UIHostingController<ShelterCallout>?

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let tileOverlay = overlay as? MKTileOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
            if tileOverlay is HazardTileOverlay {
                renderer.alpha = 0.7
                // Over the fallback basemap, multiplying keeps the labels drawn into its tiles dark.
                if hazardLevel == .aboveLabels { renderer.blendMode = .multiply }
            }
            return renderer
        }

        /// Matches the overlays to the enabled layers, with the saved basemap beneath them where it is needed.
        ///
        /// The saved tiles carry their own labels, so they are drawn above Apple's labels to cover them,
        /// and the hazard overlays move up with them. Two sets of labels would otherwise overlap wherever
        /// Apple's map is still cached.
        func updateOverlays(on mapView: MKMapView) {
            let visible = mapView.visibleMapRect
            let packs = basemapPacks.contains { $0.mapRect.intersects(visible) } ? basemapPacks : []
            let level = packs.isEmpty ? MKOverlayLevel.aboveRoads : .aboveLabels
            let basemap = mapView.overlays.lazy.compactMap { $0 as? BasemapTileOverlay }.first
            if let basemap, basemap.packs != packs || basemap.isDarkened != isDark {
                mapView.removeOverlay(basemap)
            }
            if !packs.isEmpty, !mapView.overlays.contains(where: { $0 is BasemapTileOverlay }) {
                mapView.insertOverlay(BasemapTileOverlay(packs: packs, isDarkened: isDark), at: 0, level: level)
            }

            var current = mapView.overlays.compactMap { $0 as? HazardTileOverlay }
            let stale = current.filter { overlay in
                level != hazardLevel || overlay.isDarkened != isDark || !layers.contains { $0.id == overlay.layerID }
            }
            hazardLevel = level
            mapView.removeOverlays(stale)
            current.removeAll { overlay in stale.contains { $0 === overlay } }
            // Whatever else sits at the bottom of this level stays below the hazard overlays.
            let offset = mapView.overlays(in: level).count { !($0 is HazardTileOverlay) }
            for (index, layer) in layers.enumerated()
            where !(index < current.count && current[index].layerID == layer.id) {
                let overlay = HazardTileOverlay(layer: layer, isDarkened: isDark)
                mapView.insertOverlay(overlay, at: index + offset, level: level)
                current.insert(overlay, at: index)
            }
        }

        func reportRegion(of mapView: MKMapView) {
            let uncovered = mapView.bounds.inset(by: mapView.layoutMargins)
            guard !uncovered.isEmpty else { return }
            onRegionChange(mapView.convert(uncovered, toRegionFrom: mapView))
        }

        /// Shows the user's position and moves the map to it, asking for permission the first time.
        func locate(on mapView: MKMapView) {
            locationManager.requestWhenInUseAuthorization()
            mapView.showsUserLocation = true
            mapView.setUserTrackingMode(.follow, animated: true)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            updateOverlays(on: mapView)
            reportRegion(of: mapView)
            refreshShelters(on: mapView)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: nil)
                view.markerTintColor = .systemGray
                return view
            }
            guard let annotation = annotation as? ShelterAnnotation else { return nil }
            let kind = annotation.kind
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: kind.rawValue) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: kind.rawValue)
            view.annotation = annotation
            view.markerTintColor = kind.pinColor
            view.glyphImage = UIImage(systemName: kind.pinSymbol)
            view.clusteringIdentifier = "shelter"
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? ShelterAnnotation else { return }
            let host = UIHostingController(
                rootView: ShelterCallout(title: annotation.shelters[0].name, detail: annotation.detail))
            host.view.backgroundColor = .clear
            let size = host.sizeThatFits(in: CGSize(width: ShelterCallout.maximumWidth, height: .infinity))
            host.view.frame = CGRect(x: view.bounds.midX - size.width / 2, y: -size.height - Self.calloutGap,
                                     width: size.width, height: size.height)
            view.addSubview(host.view)
            callout = host
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            callout?.view.removeFromSuperview()
            callout = nil
        }

        /// Loads the shelters around the visible region and updates the pins to match.
        func refreshShelters(on mapView: MKMapView) {
            shelterTask?.cancel()
            let region = mapView.region
            guard !shelterKinds.isEmpty, region.span.longitudeDelta <= Self.maximumShelterSpan else {
                show([], on: mapView)
                return
            }
            let latitudes = (region.center.latitude - region.span.latitudeDelta)
                ... (region.center.latitude + region.span.latitudeDelta)
            let longitudes = (region.center.longitude - region.span.longitudeDelta)
                ... (region.center.longitude + region.span.longitudeDelta)
            let xs = ShelterStore.tileX(longitudes.lowerBound)...ShelterStore.tileX(longitudes.upperBound)
            let ys = ShelterStore.tileY(latitudes.upperBound)...ShelterStore.tileY(latitudes.lowerBound)
            let kinds = shelterKinds
            shelterTask = Task { [store] in
                var found: Set<Shelter> = []
                for kind in kinds {
                    for x in xs {
                        for y in ys {
                            found.formUnion(await store.shelters(of: kind, x: x, y: y))
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                show(found.filter { latitudes.contains($0.latitude) && longitudes.contains($0.longitude) },
                     on: mapView)
            }
        }

        private func show(_ shelters: Set<Shelter>, on mapView: MKMapView) {
            // One pin per place: a school is often both an evacuation site and a shelter.
            let places = Set(Dictionary(grouping: shelters) { shelter in
                [shelter.name, String(format: "%.4f,%.4f", shelter.latitude, shelter.longitude)]
            }.values.map { $0.sorted { $0.kind.order < $1.kind.order } })
            let current = mapView.annotations.compactMap { $0 as? ShelterAnnotation }
            mapView.removeAnnotations(current.filter { !places.contains($0.shelters) })
            let shown = Set(current.map(\.shelters))
            mapView.addAnnotations(places.subtracting(shown).map(ShelterAnnotation.init))
        }
    }
}

#if DEBUG
/// Stands in for Apple's map having nothing to draw, for testing without a connection.
private final class BlankTileOverlay: MKTileOverlay {
    init() {
        super.init(urlTemplate: nil)
        canReplaceMapContent = true
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        result(TileImage.empty, nil)
    }
}
#endif

/// The glass card shown above a selected shelter pin.
struct ShelterCallout: View {
    static let maximumWidth: CGFloat = 280

    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}

/// A pin for one place, which can hold more than one designation.
final class ShelterAnnotation: NSObject, MKAnnotation {
    /// Designations at this place, in `Shelter.Kind` order. Never empty.
    let shelters: [Shelter]

    init(shelters: [Shelter]) {
        self.shelters = shelters
    }

    var kind: Shelter.Kind { shelters[0].kind }
    var coordinate: CLLocationCoordinate2D { shelters[0].coordinate }
    var title: String? { shelters[0].name }

    /// Each designation with the disaster types it covers, then address and remarks, one per line.
    var detail: String {
        var lines: [String] = []
        for shelter in shelters {
            lines.append(String(localized: shelter.kind.designation))
            lines.append(shelter.disasters.map { String(localized: $0.name) }
                .formatted(.list(type: .and, width: .narrow)))
        }
        lines.append(shelters[0].address)
        lines += shelters.map(\.remarks)
        var seen: Set<String> = []
        return lines.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: "\n")
    }
}

private extension Shelter.Kind {
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var pinColor: UIColor {
        switch self {
        case .evacuationSite: .systemGreen
        case .shelter: .systemTeal
        case .welfareShelter: .systemPurple
        }
    }

    var pinSymbol: String {
        switch self {
        case .evacuationSite: "figure.run"
        case .shelter: "house.fill"
        case .welfareShelter: "figure.roll"
        }
    }
}
