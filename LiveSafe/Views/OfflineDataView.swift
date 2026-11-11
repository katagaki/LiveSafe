import SwiftUI

/// Saves the nationwide evacuation site list on the device, and refreshes it.
struct OfflineDataView: View {
    @State private var info = OfflineSites.shared.info
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
                if let info {
                    LabeledContent("Downloaded") {
                        Text(info.downloadedAt, format: .dateTime.year().month().day().hour().minute())
                    }
                }
                Button {
                    download()
                } label: {
                    HStack {
                        Text(info == nil ? "Download" : "Update")
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
            Section("Notice") {
                Text("This data is what each municipality registered for the sites and shelters its mayor designated under the Basic Act on Disaster Management. It may be out of date or incomplete, so always check the latest details with the municipality.")
                Text("Emergency evacuation sites are where you flee to protect your life from immediate danger, and are designated per disaster type. Designated shelters are temporary places to stay until the danger has passed. In a disaster, go to an emergency evacuation site for that disaster, not a designated shelter.")
                Text("This data is updated from time to time.")
            }
        }
        .navigationTitle("Offline Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func download() {
        isDownloading = true
        hasFailed = false
        Task {
            do {
                info = try await OfflineSites.shared.download()
            } catch {
                hasFailed = true
            }
            isDownloading = false
        }
    }
}
