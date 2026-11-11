import CoreLocation
import SwiftUI

/// Points the way to nearby emergency evacuation sites, without needing the map.
struct CompassView: View {
    private static let limit = 20

    @Binding var detent: PresentationDetent

    @State private var provider = LocationProvider()
    @State private var disaster: Shelter.Disaster?
    @State private var sites: [Shelter] = []
    @State private var target: Shelter?
    @State private var hasLoaded = false
    @State private var offline = OfflineSites.shared.info

    /// Changes when the list needs working out again: on a new filter, or after moving about 50 metres.
    private var refreshKey: [Int] {
        guard let coordinate = provider.location?.coordinate else { return [] }
        return [Int(coordinate.latitude * 2000), Int(coordinate.longitude * 2000), disaster?.rawValue ?? 0]
    }

    var body: some View {
        List {
            if provider.isDenied {
                ContentUnavailableView {
                    Label("Location Access Needed", systemImage: "location.slash")
                } actions: {
                    Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
            } else if let location = provider.location {
                if let target {
                    Section {
                        heading(to: target, from: location)
                    } footer: {
                        if let offline {
                            Text("Downloaded \(offline.downloadedAt.formatted(date: .abbreviated, time: .omitted))")
                        } else {
                            Text("Live Data")
                        }
                    }
                    Section {
                        ForEach(sites, id: \.self) { site in
                            row(site, from: location)
                        }
                    }
                } else if hasLoaded {
                    ContentUnavailableView(
                        "No Evacuation Site Data", systemImage: "wifi.slash",
                        description: Text("Download the data to use it offline."))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView("Locating…", systemImage: "location")
            }
        }
        .navigationTitle("Nearest Evacuation Sites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Disaster Type", systemImage: "line.3.horizontal.decrease") {
                    Picker("Disaster Type", selection: $disaster) {
                        Text("All").tag(Shelter.Disaster?.none)
                        ForEach(Shelter.Disaster.allCases, id: \.self) { disaster in
                            Text(disaster.name).tag(Shelter.Disaster?.some(disaster))
                        }
                    }
                }
            }
        }
        .onAppear {
            detent = .large
            provider.start()
        }
        .onDisappear {
            provider.stop()
        }
        .task(id: refreshKey) {
            await refresh()
        }
    }

    private func heading(to site: Shelter, from location: CLLocation) -> some View {
        let north = -(provider.heading ?? 0)
        return VStack {
            ZStack {
                Circle()
                    .strokeBorder(.quaternary, lineWidth: 6)
                Text("N")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(12)
                    .rotationEffect(.degrees(north))
                Image(systemName: "arrow.up")
                    .font(.system(size: 80, weight: .bold))
                    .foregroundStyle(.tint)
                    .rotationEffect(.degrees(north + Self.bearing(from: location.coordinate, to: site.coordinate)))
                    .accessibilityHidden(true)
            }
            .frame(width: 200, height: 200)
            .padding(.vertical)
            Text(Self.distance(from: location, to: site))
                .font(.largeTitle)
                .bold()
            Text(site.name)
                .font(.headline)
            Group {
                Text(site.disasters.map { String(localized: $0.name) }.formatted(.list(type: .and, width: .narrow)))
                Text(site.address)
                Text(site.remarks)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func row(_ site: Shelter, from location: CLLocation) -> some View {
        Button {
            target = site
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(site.name)
                    Text(site.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Self.distance(from: location, to: site))
                    .foregroundStyle(.secondary)
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .opacity(site == target ? 1 : 0)
            }
        }
        .tint(.primary)
    }

    /// Uses the saved copy when there is one, and live data around the user otherwise.
    private func refresh() async {
        guard let coordinate = provider.location?.coordinate else { return }
        offline = OfflineSites.shared.info
        let found: [Shelter]
        if offline != nil {
            found = await OfflineSites.shared.nearest(to: coordinate, disaster: disaster, limit: Self.limit)
        } else {
            let live = await ShelterStore.shared.shelters(of: .evacuationSite, around: coordinate)
            found = OfflineSites.nearest(in: live, to: coordinate, disaster: disaster, limit: Self.limit)
        }
        guard !Task.isCancelled else { return }
        sites = found
        if target.map({ !found.contains($0) }) ?? true {
            target = found.first
        }
        hasLoaded = true
    }

    private static func distance(from location: CLLocation, to site: Shelter) -> String {
        let metres = location.distance(from: CLLocation(latitude: site.latitude, longitude: site.longitude))
        return Measurement(value: metres, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    /// Degrees clockwise from true north.
    private static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let delta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(delta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude) - sin(startLatitude) * cos(endLatitude) * cos(delta)
        return atan2(y, x) * 180 / .pi
    }
}
