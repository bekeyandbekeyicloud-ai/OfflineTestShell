import SwiftUI
import WebKit

@main
struct CalculatorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                session.lock()
            }
        }
    }
}

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var isUnlocked = false
    // Retained while the process is alive, so a brief background trip keeps the
    // in-memory Google session. Force-quitting the app destroys it completely.
    let browser = SheetsBrowser()

    init() {
        Self.purgeLegacyPersistentWebData()
    }

    func unlock() { isUnlocked = true }
    func lock() { isUnlocked = false }

    private static func purgeLegacyPersistentWebData() {
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        let store = WKWebsiteDataStore.default()
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {}
    }
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        Group {
            if session.isUnlocked {
                SheetsView(browser: session.browser)
            } else {
                CalculatorView()
            }
        }
        .animation(nil, value: session.isUnlocked)
    }
}
