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

/// A number that connects straight to an emergency service.
struct EmergencyNumber: Identifiable {
    let number: String
    let name: LocalizedStringResource

    var id: String { number }
    var url: URL { URL(string: "tel:\(number)")! }

    static let all: [EmergencyNumber] = [
        EmergencyNumber(number: "110", name: "Police"),
        EmergencyNumber(number: "119", name: "Fire and Ambulance"),
        EmergencyNumber(number: "118", name: "Coast Guard")
    ]
}

/// How to use 災害用伝言ダイヤル (171). Written for this app and checked against NTT East's instructions.
enum MessageDial {
    static let url = URL(string: "tel:171")!

    private static let call: LocalizedStringResource = "Call 171."
    private static let enterNumber: LocalizedStringResource =
        "Enter the phone number of the person in the disaster area. Landline numbers need the area code. If you are in the area, you can use your own number."
    private static let confirm: LocalizedStringResource = "Press 1. On a rotary phone, wait instead."

    static let recording: [LocalizedStringResource] = [
        call,
        "Press 1 to record.",
        enterNumber,
        confirm,
        "After the tone, speak for up to 30 seconds.",
        "Press 9 to finish, or hang up. After 9 your message plays back, and 8 lets you record it again."
    ]

    static let playback: [LocalizedStringResource] = [
        call,
        "Press 2 to play.",
        enterNumber,
        confirm,
        "Messages play from the newest. Press 8 to repeat one, or 9 for the next.",
        "After the last message, press 3 to add your own."
    ]

    static let notes: [LocalizedStringResource] = [
        "NTT sets the limits for each disaster, with at most 20 messages per phone number. Messages are kept until the service closes.",
        "To use a PIN, press 3 to record or 4 to play.",
        "Calls from NTT East and NTT West lines are free. Other carriers set their own call charges."
    ]

    static let web: [LocalizedStringResource] = [
        "web171 is the text version, at www.web171.jp. It needs an internet connection.",
        "It also uses a phone number as the key. Messages left on 171 can be checked on web171, and the other way round."
    ]
}

/// Short steps for one disaster type. Written for this app and checked against government guidance.
struct DisasterGuide: Identifiable {
    let name: LocalizedStringResource
    let steps: [LocalizedStringResource]

    var id: String { name.key }

    static let all: [DisasterGuide] = [
        DisasterGuide(name: "Earthquake", steps: [
            "Protect your head, move away from large furniture and get under a sturdy table.",
            "Don't rush outside. When the shaking stops, put out any flames and open a door to keep an exit.",
            "Outdoors, move away from block walls, vending machines and buildings that can drop glass.",
            "In a lift, stop at the nearest floor and get off.",
            "Before you evacuate, switch off the breaker and close the gas valve."
        ]),
        DisasterGuide(name: "Tsunami", steps: [
            "Near the coast or a river, after strong shaking or weak shaking that lasts a long time, go at once to the highest place you can reach. Don't wait for a warning.",
            "A tsunami advisory also means get out of the sea and away from the shore.",
            "Waves arrive more than once, and later waves can be higher.",
            "Stay away until every warning and advisory is lifted."
        ]),
        DisasterGuide(name: "Flood", steps: [
            "At Alert Level 3, older people and others who need time leave dangerous places. At Alert Level 4, everyone does.",
            "Don't wait for Alert Level 5. It means a disaster has started or is about to.",
            "If going outside is already dangerous, move to an upper floor or the safest place close by.",
            "Keep away from swollen rivers, flooded roads and underpasses."
        ]),
        DisasterGuide(name: "Landslide", steps: [
            "Warning signs: cracks in a slope or the ground, small stones falling, rumbling from the hillside, muddy river or well water, and a river that drops while rain continues.",
            "In a sediment disaster warning zone, leave by Alert Level 4.",
            "If you can't leave, go to the highest floor, on the side away from the slope."
        ]),
        DisasterGuide(name: "Storm Surge", steps: [
            "A typhoon raises the sea level, and the sea can flood the coast.",
            "Storm surge can also happen when it isn't high tide.",
            "Storm surge information uses the same alert levels. Leave early, and by Alert Level 4 at the latest."
        ]),
        DisasterGuide(name: "Large Fire", steps: [
            "If a large fire threatens your area, call out to people nearby and go to an emergency evacuation site for large fires.",
            "In smoke, cover your mouth and nose with a cloth and stay low.",
            "Don't go back once you're out."
        ]),
        DisasterGuide(name: "Volcanic Event", steps: [
            "Volcanic Alert Levels: 1 be aware the volcano is active, 2 keep away from the crater, 3 keep off the mountain, 4 older people evacuate, 5 evacuate.",
            "If it erupts while you're on the mountain, descend at once, or shelter in a hut or behind a rock.",
            "Don't breathe in ash. Wear a dust mask. If ash gets in your eyes, rinse them with water without rubbing."
        ])
    ]
}
