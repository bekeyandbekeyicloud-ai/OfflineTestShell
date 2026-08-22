import SwiftUI

@main
struct OfflineTestShellApp: App {
    @StateObject private var store = LocalStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
