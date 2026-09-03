import SwiftUI

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

    func unlock() { isUnlocked = true }
    func lock() { isUnlocked = false }
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        Group {
            if session.isUnlocked {
                SheetsView()
            } else {
                CalculatorView()
            }
        }
        .animation(nil, value: session.isUnlocked)
    }
}

