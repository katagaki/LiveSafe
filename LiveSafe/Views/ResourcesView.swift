import SwiftUI

struct ResourcesView: View {
    @Binding var detent: PresentationDetent

    var body: some View {
        List {
            Section {
                ForEach(EmergencyNumber.all) { number in
                    CallLink(number: number.number, name: number.name, url: number.url)
                }
            } header: {
                Text("Emergency Numbers")
            } footer: {
                Text("Say where you are and what happened.")
            }
            Section("Offline Guides") {
                NavigationLink("Disaster Message Dial (171)") {
                    MessageDialView()
                }
                NavigationLink("What to Do in a Disaster") {
                    DisasterGuideView()
                }
            }
            ForEach(ResourceGroup.all) { group in
                Section(String(localized: group.name)) {
                    ForEach(group.resources) { resource in
                        NavigationLink {
                            BrowserView(url: resource.url, detent: $detent)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(resource.name)
                                if let detail = resource.detail {
                                    Text(detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Useful Resources")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A row that phones a number when tapped.
private struct CallLink: View {
    let number: String
    let name: LocalizedStringResource
    let url: URL

    var body: some View {
        Link(destination: url) {
            Label {
                VStack(alignment: .leading) {
                    Text(verbatim: number)
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
            } icon: {
                Image(systemName: "phone.fill")
            }
        }
    }
}

/// How to leave and hear messages on the 171 disaster message dial.
private struct MessageDialView: View {
    var body: some View {
        List {
            Section {
                Text("171 is a voice call service. You record and play messages by phone, so it needs no data connection.")
                Text("It opens when a disaster makes calls to the area hard to connect.")
                CallLink(number: "171", name: "Disaster Message Dial", url: MessageDial.url)
            }
            Section("Record a Message") {
                StepRows(steps: MessageDial.recording)
            }
            Section("Play Messages") {
                StepRows(steps: MessageDial.playback)
            }
            Section("Notes") {
                ForEach(MessageDial.notes, id: \.key) { Text($0) }
            }
            Section {
                ForEach(MessageDial.web, id: \.key) { Text($0) }
            } header: {
                Text(verbatim: "web171")
            }
        }
        .navigationTitle("Disaster Message Dial (171)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Numbered rows, for steps taken in order.
private struct StepRows: View {
    let steps: [LocalizedStringResource]

    var body: some View {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            Label {
                Text(step)
            } icon: {
                Image(systemName: "\(index + 1).circle")
            }
        }
    }
}

/// What to do in each disaster type the app covers.
private struct DisasterGuideView: View {
    var body: some View {
        List {
            Section("Where to Evacuate") {
                Text("Emergency evacuation sites are where you flee to protect your life from immediate danger, and are designated per disaster type. Designated shelters are temporary places to stay until the danger has passed. In a disaster, go to an emergency evacuation site for that disaster, not a designated shelter.")
            }
            ForEach(DisasterGuide.all) { guide in
                Section(String(localized: guide.name)) {
                    ForEach(guide.steps, id: \.key) { Text($0) }
                }
            }
        }
        .navigationTitle("What to Do in a Disaster")
        .navigationBarTitleDisplayMode(.inline)
    }
}
