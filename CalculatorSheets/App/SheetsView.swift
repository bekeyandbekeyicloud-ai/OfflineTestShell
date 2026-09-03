import SwiftUI
import WebKit

struct SheetsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var browser = SheetsBrowser()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Button { browser.goBack() } label: { Image(systemName: "chevron.backward") }
                    .disabled(!browser.canGoBack)
                Button { browser.goForward() } label: { Image(systemName: "chevron.forward") }
                    .disabled(!browser.canGoForward)
                Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                Spacer()
                Button { browser.openHome() } label: { Image(systemName: "tablecells") }
                Button { session.lock() } label: { Image(systemName: "lock.fill") }
                    .accessibilityLabel("立即锁定")
            }
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(Color(white: 0.08))

            SheetsWebView(browser: browser)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Color.black)
    }
}

@MainActor
final class SheetsBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var canGoBack = false
    @Published var canGoForward = false

    let webView: WKWebView
    private static let homeURL = URL(string: "https://docs.google.com/spreadsheets/u/0/")!

    override init() {
        let configuration = WKWebViewConfiguration()
        // default() is persistent, sandboxed to this app, and does not share Safari cookies.
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.allowsInlineMediaPlayback = true
        // Google otherwise serves a reduced mobile page that often pushes its native app.
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        openHome()
    }

    func openHome() { webView.load(URLRequest(url: Self.homeURL)) }
    func reload() { webView.reload() }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { updateState() }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { updateState() }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    private func updateState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

private struct SheetsWebView: UIViewRepresentable {
    @ObservedObject var browser: SheetsBrowser

    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
