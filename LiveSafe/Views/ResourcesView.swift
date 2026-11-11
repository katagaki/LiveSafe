import SwiftUI

struct ResourcesView: View {
    @Binding var detent: PresentationDetent

    var body: some View {
        List(ResourceGroup.all) { group in
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
        .navigationTitle("Useful Resources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
