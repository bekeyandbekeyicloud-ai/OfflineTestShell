import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ShipmentListView()
                .tabItem { Label("货物", systemImage: "shippingbox") }

            ReminderListView()
                .tabItem { Label("提醒", systemImage: "bell") }

            MemoListView()
                .tabItem { Label("备忘", systemImage: "note.text") }
        }
    }
}
