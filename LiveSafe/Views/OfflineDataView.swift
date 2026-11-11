import SwiftUI

/// Saves the nationwide evacuation site and shelter lists and areas of the basemap on the device, and refreshes them.
struct OfflineDataView: View {
    var model: MapModel

    @State private var info = OfflineSites.shared.info
    @State private var shelterInfo = OfflineShelters.shared.info
    @State private var isDownloading = false
    @State private var hasFailed = false

    var body: some View {
        List {
            Section {
                LabeledContent("Evacuation Sites") {
                    if let info {
                        Text(info.count, format: .number)
                    } else {
                        Text("Not Downloaded")
                    }
                }
                LabeledContent("Designated Shelters") {
                    if let shelterInfo {
                        Text(shelterInfo.count, format: .number)
                    } else {
                        Text("Not Downloaded")
                    }
                }
                LabeledContent("Welfare Shelters") {
                    if let shelterInfo {
                        Text(shelterInfo.welfareCount, format: .number)
                    } else {
                        Text("Not Downloaded")
                    }
                }
                if let downloadedAt {
                    LabeledContent("Downloaded") {
                        Text(downloadedAt, format: .dateTime.year().month().day().hour().minute())
                    }
                }
                Button {
                    download()
                } label: {
                    HStack {
                        Text(info == nil || shelterInfo == nil ? "Download" : "Update")
                        Spacer()
                        if isDownloading {
                            ProgressView()
                        }
                    }
                }
                .disabled(isDownloading)
                if hasFailed {
                    Text("Download Failed")
                        .foregroundStyle(.red)
                }
            }
            BasemapSection(region: model.visibleRegion)
            Section("Notice") {
                Text("This data is what each municipality registered for the sites and shelters its mayor designated under the Basic Act on Disaster Management. It may be out of date or incomplete, so always check the latest details with the municipality.")
                Text("Emergency evacuation sites are where you flee to protect your life from immediate danger, and are designated per disaster type. Designated shelters are temporary places to stay until the danger has passed. In a disaster, go to an emergency evacuation site for that disaster, not a designated shelter.")
                Text("This data is updated from time to time.")
            }
        }
        .navigationTitle("Offline Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The older of the two saved copies' dates.
    private var downloadedAt: Date? {
        [info?.downloadedAt, shelterInfo?.downloadedAt].compactMap(\.self).min()
    }

    /// Fetches both files. One failing leaves the other saved.
    private func download() {
        isDownloading = true
        hasFailed = false
        Task {
            async let sites = try? OfflineSites.shared.download()
            async let shelters = try? OfflineShelters.shared.download()
            let (newInfo, newShelterInfo) = await (sites, shelters)
            if let newInfo { info = newInfo }
            if let newShelterInfo { shelterInfo = newShelterInfo }
            hasFailed = newInfo == nil || newShelterInfo == nil
            isDownloading = false
        }
    }
}
