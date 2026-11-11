import SwiftUI
import WebKit

/// A minimal browser pushed inside the sheet. The title is always the page's real host.
struct BrowserView: View {
    let url: URL
    @Binding var detent: PresentationDetent

    @State private var page: WebPage
    @State private var isRevealed = false
    @Environment(\.openURL) private var openURL

    private var currentURL: URL { page.url ?? url }

    /// - Parameter script: JavaScript run in each page as it starts loading.
    init(url: URL, detent: Binding<PresentationDetent>, script: String? = nil) {
        self.url = url
        _detent = detent
        let configuration = WebPage.Configuration()
        if let script {
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        _page = State(initialValue: WebPage(configuration: configuration))
    }

    private func reveal() {
        withAnimation { isRevealed = true }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Keeps the page from sliding under the title, where its colours could hide the host.
            Divider()
            // Hidden until the first page has something to show, so it does not flash white.
            WebView(page)
                .opacity(isRevealed ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if !isRevealed {
                        ProgressView()
                    }
                }
        }
        .onChange(of: page.estimatedProgress) {
            if page.estimatedProgress > 0.5 { reveal() }
        }
        .onChange(of: page.isLoading) {
            if !page.isLoading && page.url != nil { reveal() }
        }
        .navigationTitle(currentURL.host() ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Back", systemImage: "chevron.backward") {
                    if let item = page.backForwardList.backList.last { page.load(item) }
                }
                .disabled(page.backForwardList.backList.isEmpty)
                if let item = page.backForwardList.forwardList.first {
                    Button("Forward", systemImage: "chevron.forward") {
                        page.load(item)
                    }
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItemGroup(placement: .bottomBar) {
                ShareLink(item: currentURL)
                if page.isLoading {
                    Button("Stop", systemImage: "xmark") {
                        page.stopLoading()
                    }
                } else {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        page.reload()
                    }
                }
                Button("Open in Safari", systemImage: "safari") {
                    openURL(currentURL)
                }
            }
        }
        .onAppear {
            detent = .large
            if page.url == nil { page.load(url) }
        }
    }
}
