import Foundation

/// An external disaster information site the app links to but does not display itself.
struct Resource: Identifiable {
    let name: LocalizedStringResource
    var detail: LocalizedStringResource?
    let url: URL

    var id: URL { url }

    init(_ name: LocalizedStringResource, detail: LocalizedStringResource? = nil, _ url: String) {
        self.name = name
        self.detail = detail
        self.url = URL(string: url)!
    }
}

struct ResourceGroup: Identifiable {
    let name: LocalizedStringResource
    let resources: [Resource]

    var id: String { name.key }

    static let all: [ResourceGroup] = [
        ResourceGroup(name: "Warnings and Monitoring", resources: [
            Resource("JMA Disaster Information", "https://www.jma.go.jp/bosai/"),
            Resource("JMA Earthquake Activity", "https://www.data.jma.go.jp/eqev/data/"),
            Resource("NIED", detail: "Earth science and disaster research institute", "https://www.bosai.go.jp/"),
            Resource("River Disaster Information", "https://www.river.go.jp/")
        ]),
        ResourceGroup(name: "Government", resources: [
            Resource("Disaster Management Agency", "https://www.bousai.go.jp/"),
            Resource("Prime Minister's Office Disaster Guide", "https://www.kantei.go.jp/jp/headline/bousai/"),
            Resource("Fire and Disaster Management Agency", "https://www.fdma.go.jp/"),
            Resource("MLIT Disaster Information", "https://www.mlit.go.jp/saigai/"),
            Resource("Self-Defense Forces Joint Staff", "https://www.mod.go.jp/js/")
        ]),
        ResourceGroup(name: "Maps", resources: [
            Resource("Hazard Map Portal", "https://disaportal.gsi.go.jp/"),
            Resource("GSI Maps", "https://maps.gsi.go.jp/")
        ]),
        ResourceGroup(name: "Family and Relief", resources: [
            Resource("Disaster Message Board (web171)", "https://www.web171.jp/"),
            Resource("Yahoo! Weather and Disaster", "https://weather.yahoo.co.jp/weather/"),
            Resource("Japanese Red Cross Society", "https://www.jrc.or.jp/")
        ]),
        ResourceGroup(name: "Power Outages", resources: [
            Resource("Hokkaido", "https://teiden-info.hepco.co.jp/"),
            Resource("Tohoku", "https://nw.tohoku-epco.co.jp/teideninfo/"),
            Resource("Kanto", "https://teideninfo.tepco.co.jp/"),
            Resource("Chubu", "https://teiden.powergrid.chuden.co.jp/p/index.html"),
            Resource("Hokuriku", "https://www.rikuden.co.jp/nw/teiden/otj010.html"),
            Resource("Kansai", "https://www.kansai-td.co.jp/teiden-info/index.php"),
            Resource("Chugoku", "https://www.teideninfo.energia.co.jp/"),
            Resource("Shikoku", "https://www.yonden.co.jp/nw/teiden-info/"),
            Resource("Kyushu", "https://www.kyuden.co.jp/td_teiden/kyushu.html"),
            Resource("Okinawa", "https://www.okidenmail.jp/bosai/info/")
        ]),
        ResourceGroup(name: "Roads", resources: [
            Resource("JARTIC Road Traffic", "https://www.jartic.or.jp/"),
            Resource("NEXCO East", "https://www.e-nexco.co.jp/"),
            Resource("NEXCO Central", "https://www.c-nexco.co.jp/"),
            Resource("NEXCO West", "https://www.w-nexco.co.jp/")
        ]),
        ResourceGroup(name: "Nuclear and Health", resources: [
            Resource("Nuclear Regulation Authority", "https://www.nra.go.jp/"),
            Resource("Radiation Monitoring", "https://www.ramis.nra.go.jp/"),
            Resource("Ministry of Health, Labour and Welfare", "https://www.mhlw.go.jp/")
        ]),
        ResourceGroup(name: "News and Visitors", resources: [
            Resource("NHK Weather and Disaster", "https://news.web.nhk/kishou-saigai/"),
            Resource("NHK WORLD-JAPAN News", "https://www3.nhk.or.jp/nhkworld/news/"),
            Resource("JNTO Safety Tips", "https://www.jnto.go.jp/safety-tips/eng/")
        ])
    ]
}
