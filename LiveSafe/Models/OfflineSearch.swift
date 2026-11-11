import Foundation

/// Text search over the places saved on the device, for when MapKit's search cannot be reached.
actor OfflineSearch {
    /// A saved collection of places to search.
    struct Source: Sendable {
        /// When the saved copy was downloaded, which changes whenever it is replaced. Nil when nothing is saved.
        let downloadedAt: @Sendable () -> Date?
        let places: @Sendable () async -> [Shelter]
    }

    /// Searches every saved collection. Another collection of `Shelter` values only needs a line here.
    static let shared = OfflineSearch(sources: [
        Source(downloadedAt: { OfflineSites.shared.info?.downloadedAt }, places: { await OfflineSites.shared.sites() })
    ])

    private let sources: [Source]
    private var building: (versions: [Date?], index: Task<Index, Never>)?

    init(sources: [Source]) {
        self.sources = sources
    }

    /// Whether any collection has been downloaded.
    nonisolated var hasData: Bool {
        sources.contains { $0.downloadedAt() != nil }
    }

    /// Reads the saved places ahead of the first search.
    func prepare() async {
        _ = await index()
    }

    /// Places whose name or address contains the query, best matches first.
    func search(_ query: String, limit: Int = 50) async -> [Shelter] {
        let index = await index()
        guard !Task.isCancelled else { return [] }
        return index.search(query, limit: limit)
    }

    /// The index of what is saved now, built once and again only after a collection is replaced.
    private func index() async -> Index {
        let versions = sources.map { $0.downloadedAt() }
        if let building, building.versions == versions { return await building.index.value }
        let task = Task.detached(priority: .userInitiated) { [sources] in
            var places: [Shelter] = []
            for source in sources {
                places += await source.places()
            }
            return Index(places)
        }
        building = (versions, task)
        return await task.value
    }

    /// Folds away differences that should not affect a match: full-width and half-width forms, letter case,
    /// hiragana and katakana, the various hyphens, and all whitespace.
    static func normalized(_ string: String) -> String {
        var scalars = String.UnicodeScalarView()
        // Compatibility mapping makes full-width letters and digits half-width, and half-width kana full-width.
        for scalar in string.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars {
            switch scalar.value {
            case ...0x20:
                continue
            case 0x3041...0x3096:
                scalars.append(Unicode.Scalar(scalar.value + 0x60)!)
            case 0x2010...0x2015, 0x2212:
                scalars.append("-")
            case 0x80... where scalar.properties.isWhitespace:
                continue
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}

private struct Index: Sendable {
    private static let addressMark: UInt8 = 0x1F
    private static let endMark: UInt8 = 0x1E

    private let places: [Shelter]
    /// Every place's normalized name and address as UTF-8, in one run so a search is a single scan.
    /// A query never contains the marks that end each name and address, so a match never spans two fields.
    private let text: [UInt8]
    /// Where each place's name starts in `text`, with the length of `text` at the end.
    private let starts: [Int]
    /// Where each place's address starts in `text`.
    private let addresses: [Int]

    init(_ places: [Shelter]) {
        var text: [UInt8] = []
        var starts: [Int] = []
        var addresses: [Int] = []
        text.reserveCapacity(places.count * 96)
        starts.reserveCapacity(places.count + 1)
        addresses.reserveCapacity(places.count)
        for place in places {
            starts.append(text.count)
            text.append(contentsOf: OfflineSearch.normalized(place.name).utf8)
            text.append(Self.addressMark)
            addresses.append(text.count)
            text.append(contentsOf: OfflineSearch.normalized(place.address).utf8)
            text.append(Self.endMark)
        }
        starts.append(text.count)
        self.places = places
        self.text = text
        self.starts = starts
        self.addresses = addresses
    }

    func search(_ query: String, limit: Int) -> [Shelter] {
        let needle = Array(OfflineSearch.normalized(query).utf8)
        guard !needle.isEmpty, !places.isEmpty else { return [] }

        /// Rank 0 is a name that starts with the query, 1 a name that contains it, 2 an address that contains it.
        var matches: [(rank: Int, length: Int, place: Int)] = []
        text.withUnsafeBytes { text in
            var offset = 0
            var place = 0
            while offset < text.count,
                  let found = memmem(text.baseAddress! + offset, text.count - offset, needle, needle.count) {
                let position = text.baseAddress!.distance(to: UnsafeRawPointer(found))
                while starts[place + 1] <= position { place += 1 }
                let rank = position == starts[place] ? 0 : position < addresses[place] ? 1 : 2
                matches.append((rank, addresses[place] - starts[place], place))
                // The first match in a place is its best one, so go straight to the next place.
                offset = starts[place + 1]
            }
        }
        // Among equal ranks, a shorter name is the closer match.
        matches.sort { ($0.rank, $0.length, $0.place) < ($1.rank, $1.length, $1.place) }
        return matches.prefix(limit).map { places[$0.place] }
    }
}
