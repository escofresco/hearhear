import SwiftUI

struct ContentView: View {
    @StateObject private var reachability = WatchReachabilityViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)

            if reachability.isWatchReachable {
                Text("Hello, world!")
                    .font(.title2)
            } else {
                Text("Look at your Apple Watch for the greeting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
