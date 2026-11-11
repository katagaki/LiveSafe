import CoreLocation

/// Emergency evacuation sites saved from 国土地理院's nationwide CSV, for use without a connection.
/// https://hinanmap.gsi.go.jp/index.html
actor OfflineSites {
    struct Info: Equatable {
        let downloadedAt: Date
        let count: Int
    }

    static let shared = OfflineSites()

    private static let source = URL(
        string: "https://hinanmap.gsi.go.jp/hinanjocp/defaultFtpData/csv/mergeFromCity_2.csv")!
    private static let dateKey = "OfflineSitesDownloadedAt"
    private static let countKey = "OfflineSitesCount"

    private var cached: [Shelter]?

    private static var file: URL {
        URL.applicationSupportDirectory.appending(path: "EvacuationSites.csv")
    }

    /// When the saved copy was downloaded and how many sites it holds, if there is one.
    nonisolated var info: Info? {
        guard let date = UserDefaults.standard.object(forKey: Self.dateKey) as? Date else { return nil }
        return Info(downloadedAt: date, count: UserDefaults.standard.integer(forKey: Self.countKey))
    }

    /// Downloads the current file and replaces the saved copy with it.
    func download() async throws -> Info {
        let (temporary, response) = try await URLSession.shared.download(from: Self.source)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let sites = Self.parse(try Data(contentsOf: temporary))
        guard !sites.isEmpty else { throw URLError(.cannotParseResponse) }
        try FileManager.default.createDirectory(
            at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try FileManager.default.replaceItemAt(Self.file, withItemAt: temporary)
        cached = sites
        let info = Info(downloadedAt: .now, count: sites.count)
        UserDefaults.standard.set(info.downloadedAt, forKey: Self.dateKey)
        UserDefaults.standard.set(info.count, forKey: Self.countKey)
        return info
    }

    /// Every saved site. Empty when nothing has been downloaded.
    func sites() -> [Shelter] {
        if let cached { return cached }
        let sites = (try? Data(contentsOf: Self.file)).map(Self.parse) ?? []
        cached = sites
        return sites
    }

    /// Saved sites inside a latitude and longitude box.
    func sites(latitudes: ClosedRange<Double>, longitudes: ClosedRange<Double>) -> [Shelter] {
        sites().filter { latitudes.contains($0.latitude) && longitudes.contains($0.longitude) }
    }

    /// The saved sites closest to a point, nearest first.
    func nearest(to coordinate: CLLocationCoordinate2D, disaster: Shelter.Disaster?, limit: Int) -> [Shelter] {
        Self.nearest(in: sites(), to: coordinate, disaster: disaster, limit: limit)
    }

    static func nearest(
        in sites: some Sequence<Shelter>, to coordinate: CLLocationCoordinate2D,
        disaster: Shelter.Disaster?, limit: Int
    ) -> [Shelter] {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return sites
            .filter { disaster == nil || $0.disasters.contains(disaster!) }
            .map { ($0, origin.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Reads the nationwide CSV, whose columns are: NO, 共通ID, 都道府県名及び市町村名, 施設・場所名, 住所,
    /// the eight disaster types, 指定避難所との住所同一, 緯度, 経度, 備考.
    private static func parse(_ data: Data) -> [Shelter] {
        var sites: [Shelter] = []
        CSV.rows(in: data) { fields in
            guard fields.count >= 17,
                  let latitude = Double(String(decoding: fields[14], as: UTF8.self)),
                  let longitude = Double(String(decoding: fields[15], as: UTF8.self)) else { return }
            sites.append(Shelter(
                kind: .evacuationSite,
                name: String(decoding: fields[3], as: UTF8.self),
                address: String(decoding: fields[4], as: UTF8.self),
                remarks: String(decoding: fields[16], as: UTF8.self),
                latitude: latitude, longitude: longitude,
                disasters: Shelter.Disaster.allCases.filter { fields[4 + $0.rawValue] == [UInt8(ascii: "1")] }))
        }
        return sites
    }
}

/// Designated shelters, general and welfare, saved from 国土地理院's nationwide CSV.
/// https://hinanmap.gsi.go.jp/index.html
actor OfflineShelters {
    struct Info: Equatable {
        let downloadedAt: Date
        let count: Int
        let welfareCount: Int
    }

    static let shared = OfflineShelters()

    private static let source = URL(
        string: "https://hinanmap.gsi.go.jp/hinanjocp/defaultFtpData/csv/mergeFromCity_1.csv")!
    private static let dateKey = "OfflineSheltersDownloadedAt"
    private static let countKey = "OfflineSheltersCount"
    private static let welfareCountKey = "OfflineWelfareSheltersCount"

    private var cached: [Shelter]?

    private static var file: URL {
        URL.applicationSupportDirectory.appending(path: "Shelters.csv")
    }

    /// When the saved copy was downloaded and how many shelters of each kind it holds, if there is one.
    nonisolated var info: Info? {
        let defaults = UserDefaults.standard
        guard let date = defaults.object(forKey: Self.dateKey) as? Date else { return nil }
        return Info(
            downloadedAt: date, count: defaults.integer(forKey: Self.countKey),
            welfareCount: defaults.integer(forKey: Self.welfareCountKey))
    }

    /// Downloads the current file and replaces the saved copy with it.
    func download() async throws -> Info {
        let (temporary, response) = try await URLSession.shared.download(from: Self.source)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let shelters = Self.parse(try Data(contentsOf: temporary))
        guard !shelters.isEmpty else { throw URLError(.cannotParseResponse) }
        try FileManager.default.createDirectory(
            at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try FileManager.default.replaceItemAt(Self.file, withItemAt: temporary)
        cached = shelters
        let welfareCount = shelters.count { $0.kind == .welfareShelter }
        let info = Info(downloadedAt: .now, count: shelters.count - welfareCount, welfareCount: welfareCount)
        UserDefaults.standard.set(info.downloadedAt, forKey: Self.dateKey)
        UserDefaults.standard.set(info.count, forKey: Self.countKey)
        UserDefaults.standard.set(info.welfareCount, forKey: Self.welfareCountKey)
        return info
    }

    /// Saved shelters of a kind inside a latitude and longitude box.
    func shelters(
        of kind: Shelter.Kind, latitudes: ClosedRange<Double>, longitudes: ClosedRange<Double>
    ) -> [Shelter] {
        if cached == nil {
            cached = (try? Data(contentsOf: Self.file)).map(Self.parse) ?? []
        }
        return cached!.filter {
            $0.kind == kind && latitudes.contains($0.latitude) && longitudes.contains($0.longitude)
        }
    }

    /// Reads the nationwide CSV, whose columns are: NO, 共通ID, 都道府県名及び市町村名, 施設・場所名, 住所,
    /// 指定緊急避難場所との住所同一, その他市町村長が必要と認める事項, 受入対象者, 緯度, 経度, 備考.
    ///
    /// No column names the kind. The second to last digit of 共通ID does: 1 is a general shelter and
    /// 2 a welfare shelter, which matches the live `sih` and `sfh` tiles. 受入対象者 does not, because
    /// many welfare shelters leave it empty.
    private static func parse(_ data: Data) -> [Shelter] {
        var shelters: [Shelter] = []
        CSV.rows(in: data) { fields in
            guard fields.count >= 11, fields[1].count >= 2,
                  let latitude = Double(String(decoding: fields[8], as: UTF8.self)),
                  let longitude = Double(String(decoding: fields[9], as: UTF8.self)) else { return }
            let kind: Shelter.Kind
            switch fields[1][fields[1].count - 2] {
            case UInt8(ascii: "1"): kind = .shelter
            case UInt8(ascii: "2"): kind = .welfareShelter
            default: return
            }
            shelters.append(Shelter(
                kind: kind,
                name: String(decoding: fields[3], as: UTF8.self),
                address: String(decoding: fields[4], as: UTF8.self),
                remarks: String(decoding: fields[10], as: UTF8.self),
                latitude: latitude, longitude: longitude, disasters: []))
        }
        return shelters
    }
}

private enum CSV {
    /// Calls `body` with the fields of every row after the header.
    static func rows(in data: Data, _ body: ([[UInt8]]) -> Void) {
        var fields: [[UInt8]] = [[]]
        var isQuoted = false
        var isHeader = true

        func endRow() {
            defer { fields = [[]] }
            if isHeader {
                isHeader = false
                return
            }
            body(fields)
        }

        var previous: UInt8 = 0
        for byte in data {
            defer { previous = byte }
            if isQuoted {
                if byte == UInt8(ascii: "\"") { isQuoted = false } else { fields[fields.count - 1].append(byte) }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""):
                // A doubled quote inside a quoted field is one literal quote.
                if previous == UInt8(ascii: "\"") { fields[fields.count - 1].append(byte) }
                isQuoted = true
            case UInt8(ascii: ","):
                fields.append([])
            case UInt8(ascii: "\n"):
                endRow()
            case UInt8(ascii: "\r"):
                break
            default:
                fields[fields.count - 1].append(byte)
            }
        }
        if fields.count > 1 { endRow() }
    }
}
