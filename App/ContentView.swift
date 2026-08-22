import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            Text("测试成功")
                .font(.system(size: 28, weight: .semibold))
        }
    }
}
