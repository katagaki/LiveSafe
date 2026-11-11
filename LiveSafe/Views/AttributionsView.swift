import SwiftUI

struct AttributionsView: View {
    private static let portal = URL(string: "https://disaportal.gsi.go.jp/")!
    private static let portalTerms = URL(
        string: "https://disaportal.gsi.go.jp/hazardmapportal/hazardmap/copyright/copyright.html")!
    private static let openData = URL(string: "https://disaportal.gsi.go.jp/hazardmap/copyright/opendata.html")!
    private static let nlniTerms = URL(string: "https://nlftp.mlit.go.jp/ksj/other/agreement.html")!
    private static let shelters = URL(string: "https://www.gsi.go.jp/bousaichiri/hinanbasho.html")!
    private static let siteDownloads = URL(string: "https://hinanmap.gsi.go.jp/index.html")!
    private static let tileList = URL(string: "https://maps.gsi.go.jp/development/ichiran.html")!
    private static let gsiTerms = URL(string: "https://www.gsi.go.jp/kikakuchousei/kikakuchousei40182.html")!
    private static let appleMaps = URL(string: "https://gspe21-ssl.ls.apple.com/html/attribution.html")!

    var body: some View {
        List {
            Section("Hazard Data") {
                Link("出典：「ハザードマップポータルサイト」", destination: Self.portal)
                Text("Processed from 「ハザードマップポータルサイト」: darkened in dark mode and enlarged past zoom level 17. Not produced by the government.")
                Link("Open Data", destination: Self.openData)
                Link("Terms of Use (PDL1.0)", destination: Self.portalTerms)
            }
            Section("Data Sources") {
                source("Flood", "国土交通省各地方整備局等、都道府県")
                source("Inland Flooding", "市町村（流域下水道、一部事務組合を含む）")
                source("Storm Surge and Tsunami", "都道府県")
                source("Sediment Disaster Warning Areas",
                       "国土交通省政策統括官付地理空間情報課「国土数値情報（令和７年度土砂災害警戒区域）」をもとに国土地理院が加工")
                source("Avalanche",
                       "国土交通省国土政策局「国土数値情報（平成22年度土砂災害危険箇所）」をもとに国土地理院が加工（青森県及び広島県は都道府県データ）")
                Link("National Land Numerical Information Terms", destination: Self.nlniTerms)
            }
            Section("Notice") {
                Text("Check the hazard map made by your municipality for the latest and most detailed information.")
                Text("Real estate brokers cannot use this data for the explanation of important matters.")
            }
            Section("Shelter Data") {
                Link("出典：国土地理院ウェブサイト", destination: Self.shelters)
                Text("Processed from 「指定緊急避難場所・指定避難所データ」（国土地理院）: shown as pins with LiveSafe's own icons and as a list sorted by distance. Not produced by the Geospatial Information Authority of Japan.")
                Text("This data is what each municipality registered for the sites and shelters its mayor designated under the Basic Act on Disaster Management. It may be out of date or incomplete, so always check the latest details with the municipality.")
                Text("Emergency evacuation sites are where you flee to protect your life from immediate danger, and are designated per disaster type. Designated shelters are temporary places to stay until the danger has passed. In a disaster, go to an emergency evacuation site for that disaster, not a designated shelter.")
                Text("This data is updated from time to time.")
                Link("Data Download Site", destination: Self.siteDownloads)
                Link("GSI Tile List", destination: Self.tileList)
                Link("Terms of Use (GSI)", destination: Self.gsiTerms)
            }
            Section("Offline Map") {
                Link("出典：国土地理院（地理院タイル）", destination: Self.tileList)
                Text("Processed from 「淡色地図」（国土地理院）: saved on the device, darkened in dark mode and enlarged past zoom level 15. Not produced by the Geospatial Information Authority of Japan.")
                Link("Terms of Use (GSI)", destination: Self.gsiTerms)
            }
            Section("Map and Search") {
                Link("Apple Maps", destination: Self.appleMaps)
            }
        }
        .navigationTitle("Attributions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func source(_ title: LocalizedStringKey, _ credit: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Text(verbatim: credit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
