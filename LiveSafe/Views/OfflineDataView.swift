import Observation
import SwiftUI

/// Saves the nationwide evacuation site and shelter lists, hazard maps of chosen areas,
/// and areas of the basemap on the device, and refreshes them.
/// The lists are laid out like Software Update in Settings.
struct OfflineDataView: View {
    var model: MapModel

    private var lists: SavedLists { .shared }

    var body: some View {
        List {
            Section {
                SavedListsHeader(lists: lists)
                NavigationLink("Learn More") {
                    SavedListsDetailView(lists: lists)
                }
            }
            if !lists.isUpToDate {
                Section {
                    Button(lists.isDownloaded ? "Update Now" : "Download Now") {
                        lists.download()
                    }
                    .disabled(lists.isDownloading || Connectivity.shared.isOffline)
                } footer: {
                    if lists.hasFailed {
                        Text("Download Failed")
                            .foregroundStyle(.red)
                    }
                }
            }
            AreaPackSection(model: model)
            BasemapSection(region: model.visibleRegion)
        }
        .navigationTitle("Offline Data")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await lists.check()
        }
    }
}

/// Icon, name, source and size of a kind of saved data, then its status and what it is,
/// laid out like an update in Software Update.
struct DataHeader<Status: View>: View {
    let image: String
    let title: LocalizedStringKey
    let source: LocalizedStringKey
    let byteCount: Int64?
    let description: LocalizedStringKey
    @ViewBuilder let status: Status

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Group {
                        Text(source)
                        if let byteCount {
                            Text(byteCount, format: .byteCount(style: .file))
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            status
                .font(.subheadline)
            Text(description)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

/// A download's bar, with how far along it is beneath.
struct DownloadProgress: View {
    let fraction: Double
    let label: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: fraction)
            label
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// How many areas are saved, or that the last download failed.
struct SavedAreasStatus: View {
    let count: Int
    let hasFailed: Bool

    var body: some View {
        if hasFailed {
            Text("Download Failed")
                .foregroundStyle(.red)
        } else if count > 0 {
            Text("\(count) Saved Areas")
                .foregroundStyle(.secondary)
        } else {
            Text("Not Downloaded")
                .foregroundStyle(.secondary)
        }
    }
}

/// The saved lists' header, with the download's progress.
private struct SavedListsHeader: View {
    let lists: SavedLists

    var body: some View {
        DataHeader(
            image: "OfflineData", title: "Evacuation Sites and Shelters",
            source: "Geospatial Information Authority of Japan", byteCount: lists.byteCount,
            description: "Saves every emergency evacuation site, designated shelter and welfare shelter in Japan, so they show on the map and in search without a connection."
        ) {
            if lists.isDownloading {
                if let total = lists.remoteByteCount {
                    DownloadProgress(
                        fraction: lists.fraction ?? 0,
                        label: Text("Downloading… \(lists.receivedByteCount, format: .byteCount(style: .file)) of \(total, format: .byteCount(style: .file))"))
                } else {
                    DownloadProgress(fraction: 0, label: Text("Downloading…"))
                }
            } else {
                status
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if lists.isUpToDate {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Up to Date")
            }
            .foregroundStyle(.green)
        } else if lists.hasUpdate {
            Text("Update Available")
                .foregroundStyle(.tint)
        } else if let downloadedAt = lists.downloadedAt {
            Text("Downloaded \(downloadedAt, format: .dateTime.year().month().day().hour().minute())")
                .foregroundStyle(.secondary)
        } else {
            Text("Not Downloaded")
                .foregroundStyle(.secondary)
        }
    }
}

/// What the saved lists hold, and what the data is.
private struct SavedListsDetailView: View {
    let lists: SavedLists

    var body: some View {
        List {
            Section {
                LabeledContent("Evacuation Sites") {
                    count(lists.sitesInfo?.count)
                }
                LabeledContent("Designated Shelters") {
                    count(lists.sheltersInfo?.count)
                }
                LabeledContent("Welfare Shelters") {
                    count(lists.sheltersInfo?.welfareCount)
                }
                if let downloadedAt = lists.downloadedAt {
                    LabeledContent("Downloaded") {
                        Text(downloadedAt, format: .dateTime.year().month().day().hour().minute())
                    }
                }
            }
            Section("Notice") {
                Text("This data is what each municipality registered for the sites and shelters its mayor designated under the Basic Act on Disaster Management. It may be out of date or incomplete, so always check the latest details with the municipality.")
                Text("Emergency evacuation sites are where you flee to protect your life from immediate danger, and are designated per disaster type. Designated shelters are temporary places to stay until the danger has passed. In a disaster, go to an emergency evacuation site for that disaster, not a designated shelter.")
                Text("This data is updated from time to time.")
            }
        }
        .navigationTitle("Evacuation Sites and Shelters")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func count(_ value: Int?) -> some View {
        if let value {
            Text(value, format: .number)
        } else {
            Text("Not Downloaded")
        }
    }
}

/// The saved evacuation site and shelter lists, whether GSI has newer ones, and their download.
/// Shared so a download keeps going and stays visible after leaving the screen.
@MainActor @Observable
final class SavedLists {
    static let shared = SavedLists()

    private(set) var sitesInfo = OfflineSites.shared.info
    private(set) var sheltersInfo = OfflineShelters.shared.info
    private(set) var isDownloading = false
    private(set) var hasFailed = false
    /// Both files on the server, once checked.
    private(set) var remote: [GSIFile.Remote]?
    private var received: [Int64] = [0, 0]

    var isDownloaded: Bool { sitesInfo != nil && sheltersInfo != nil }

    /// The older of the two saved copies' dates.
    var downloadedAt: Date? {
        [sitesInfo?.downloadedAt, sheltersInfo?.downloadedAt].compactMap(\.self).min()
    }

    var remoteByteCount: Int64? { remote.map { $0.reduce(0) { $0 + $1.byteCount } } }

    var receivedByteCount: Int64 { received.reduce(0, +) }

    /// The saved size once downloaded, otherwise the size of the download.
    var byteCount: Int64? {
        if isDownloaded, let sites = OfflineSites.savedByteCount, let shelters = OfflineShelters.savedByteCount {
            return sites + shelters
        }
        return remoteByteCount
    }

    var fraction: Double? {
        guard let total = remoteByteCount, total > 0 else { return nil }
        return min(1, Double(receivedByteCount) / Double(total))
    }

    /// Both saved copies are newer than the files on the server.
    var isUpToDate: Bool {
        guard !isDownloading, let downloadedAt, let dates = remote?.map(\.modifiedAt) else { return false }
        return dates.allSatisfy { $0.map { $0 <= downloadedAt } ?? false }
    }

    /// The server has a file newer than the saved copy.
    var hasUpdate: Bool {
        guard isDownloaded, let downloadedAt, let dates = remote?.compactMap(\.modifiedAt) else { return false }
        return dates.contains { $0 > downloadedAt }
    }

    private init() {}

    /// Asks the server for both files' sizes and dates. Leaves them unknown when it cannot be reached.
    func check() async {
        async let sites = try? GSIFile.remote(OfflineSites.source)
        async let shelters = try? GSIFile.remote(OfflineShelters.source)
        if let sites = await sites, let shelters = await shelters {
            remote = [sites, shelters]
        }
    }

    /// Fetches both files. One failing leaves the other saved.
    func download() {
        guard !isDownloading else { return }
        isDownloading = true
        hasFailed = false
        received = [0, 0]
        Task {
            if remote == nil { await check() }
            async let sites = try? OfflineSites.shared.download { bytes in
                Task { @MainActor in SavedLists.shared.received[0] = bytes }
            }
            async let shelters = try? OfflineShelters.shared.download { bytes in
                Task { @MainActor in SavedLists.shared.received[1] = bytes }
            }
            let (newSites, newShelters) = await (sites, shelters)
            if let newSites { sitesInfo = newSites }
            if let newShelters { sheltersInfo = newShelters }
            hasFailed = newSites == nil || newShelters == nil
            isDownloading = false
        }
    }
}
