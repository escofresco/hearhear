import SwiftUI

struct ContentView: View {
    @StateObject private var reachability = PhoneReachabilityViewModel()

    var body: some View {
        VStack(spacing: 12) {
            if reachability.isPhoneReachable {
                Text("iPhone is showing the greeting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Hello, world!")
                    .font(.title3)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
