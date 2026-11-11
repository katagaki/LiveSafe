import MapKit
import SwiftUI

struct SheetView: View {
    /// NIED's real-time shaking map, shown as NIED's own page.
    /// The site does not answer on HTTPS, so this is the HTTP address it serves.
    private static let kyoshinMonitor = URL(string: "http://www.kmoni.bosai.go.jp/")!
    /// Fits the page's fixed 352-pixel layout to the screen and darkens its background in dark mode.
    private static let kyoshinMonitorScript = """
        (function () {
            // Runs before the page's own markup exists, so nothing is drawn unstyled first.
            var root = document.head || document.documentElement;
            var viewport = document.createElement('meta');
            viewport.name = 'viewport';
            viewport.content = 'width=368';
            root.appendChild(viewport);
            var style = document.createElement('style');
            style.textContent = '@media (prefers-color-scheme: dark) {'
                + ':root { --ss-bg-color: #2c2c2e; --ss-font-color: #f2f2f7; }'
                + 'html, body { background-color: #1c1c1e !important; color: #f2f2f7 !important; }'
                + 'body *:not(img):not(canvas):not(input):not(button):not(select):not(option)'
                + '{ background-color: transparent !important; color: #f2f2f7 !important; } }';
            root.appendChild(style);
        })();
        """

    /// The list's side margin, which carousels scroll across.
    private static let margin: CGFloat = 16

    @Bindable var model: MapModel
    @Binding var detent: PresentationDetent

    @State private var search = AddressSearch()
    @FocusState private var isSearching: Bool
    @State private var width: CGFloat = 0

    var body: some View {
        NavigationStack {
            List {
                if search.query.isEmpty {
                    layerSections
                    shelterSection
                    Section {
                        NavigationLink {
                            CompassView(detent: $detent)
                        } label: {
                            Label("Nearest Evacuation Sites", systemImage: "location.north.circle")
                        }
                        NavigationLink {
                            OfflineDataView()
                        } label: {
                            Label("Offline Data", systemImage: "arrow.down.circle")
                        }
                    }
                    Section {
                        NavigationLink {
                            BrowserView(url: Self.kyoshinMonitor, detent: $detent, script: Self.kyoshinMonitorScript)
                        } label: {
                            Label("Kyoshin Monitor (NIED)", systemImage: "waveform.path.ecg")
                        }
                        NavigationLink("Useful Resources") {
                            ResourcesView(detent: $detent)
                        }
                    }
                    Section {
                        NavigationLink("Attributions") {
                            AttributionsView()
                        }
                    }
                } else {
                    searchResults
                }
            }
            .scrollDismissesKeyboard(.never)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                        TextField("Search Address", text: $search.query)
                            .focused($isSearching)
                            .submitLabel(.search)
                            .onSubmit {
                                if search.isOffline {
                                    if let first = search.savedResults.first { select(first) }
                                } else if let first = search.results.first {
                                    select(first)
                                }
                            }
                            .autocorrectionDisabled()
                        if !search.query.isEmpty {
                            Button("Clear", systemImage: "xmark.circle.fill") {
                                search.query = ""
                            }
                            .labelStyle(.iconOnly)
                            .tint(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(width: max(0, width - 32), height: 44)
                    .glassEffect()
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: isSearching) {
            if isSearching { detent = .large }
        }
    }

    private var layerSections: some View {
        ForEach(HazardLayer.Category.allCases, id: \.self) { category in
            Section {
                carousel {
                    ForEach(HazardLayer.layers(in: category)) { layer in
                        CardButton(title: layer.title, detail: layer.detail, image: layer.id, isOn: isEnabled(layer))
                    }
                }
            } header: {
                Text(category.name)
                    .padding(.horizontal, Self.margin)
            }
            .listSectionMargins(.horizontal, 0)
        }
    }

    private var shelterSection: some View {
        Section {
            carousel {
                ForEach(Shelter.Kind.allCases) { kind in
                    let name = String(localized: kind.name).qualified
                    CardButton(title: name.title, detail: name.detail, image: kind.rawValue, isOn: isEnabled(kind))
                }
            }
        } header: {
            Text("Shelters")
                .padding(.horizontal, Self.margin)
        }
        .listSectionMargins(.horizontal, 0)
    }

    /// A row of cards that scrolls sideways, out to the edges of the sheet.
    private func carousel(@ViewBuilder _ cards: () -> some View) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                cards()
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, Self.margin, for: .scrollContent)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder private var searchResults: some View {
        if !search.isOffline {
            ForEach(search.results, id: \.self) { completion in
                resultButton(title: completion.title, subtitle: completion.subtitle) {
                    select(completion)
                }
            }
        } else if search.hasSavedData {
            Section("Saved Data") {
                // The data can list the same place twice, so rows are told apart by position.
                ForEach(Array(search.savedResults.enumerated()), id: \.offset) { _, site in
                    resultButton(title: site.name, subtitle: site.address) {
                        select(site)
                    }
                }
            }
        } else {
            Text("Download the data to use it offline.")
                .foregroundStyle(.secondary)
        }
    }

    private func resultButton(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading) {
                Text(title)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)
    }

    private func isEnabled(_ layer: HazardLayer) -> Binding<Bool> {
        Binding {
            model.enabledIDs.contains(layer.id)
        } set: { isOn in
            if isOn {
                model.enabledIDs.insert(layer.id)
            } else {
                model.enabledIDs.remove(layer.id)
            }
        }
    }

    private func isEnabled(_ kind: Shelter.Kind) -> Binding<Bool> {
        Binding {
            model.enabledShelterKinds.contains(kind)
        } set: { isOn in
            if isOn {
                model.enabledShelterKinds.insert(kind)
            } else {
                model.enabledShelterKinds.remove(kind)
            }
        }
    }

    private func select(_ completion: MKLocalSearchCompletion) {
        Task {
            guard let place = await search.place(for: completion) else { return }
            show(place)
        }
    }

    private func select(_ site: Shelter) {
        show(Place(title: site.name, latitude: site.latitude, longitude: site.longitude))
    }

    private func show(_ place: Place) {
        model.place = place
        search.query = ""
        // Clearing the query rebuilds the list, which leaves focus state stale.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        detent = ContentView.compactDetent
    }
}

/// A carousel card that carries a checkmark while its layer is shown.
private struct CardButton: View {
    /// Matches the corner radius of the list's own sections.
    private static let cornerRadius: CGFloat = 26
    private static let width: CGFloat = 160

    let title: String
    let detail: String?
    /// Name of the illustration in the asset catalog.
    let image: String
    @Binding var isOn: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        Button {
            isOn.toggle()
        } label: {
            VStack(alignment: .leading) {
                Image(image)
                    .accessibilityHidden(true)
                SqueezedText(title)
                if let detail {
                    SqueezedText(detail)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .background(.fill.tertiary, in: shape)
            .overlay(alignment: .topTrailing) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.tint, in: .circle)
                        .overlay {
                            Circle().strokeBorder(.white, lineWidth: 2)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .padding(10)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .frame(width: Self.width)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// One line of text that narrows its letterforms, rather than shrinking or wrapping, when it is too long.
private struct SqueezedText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach([Font.Width.standard, .condensed, .compressed], id: \.self) { width in
                Text(text)
                    .fontWidth(width)
                    .fixedSize()
            }
            Text(text)
                .fontWidth(.compressed)
                .lineLimit(1)
        }
    }
}
