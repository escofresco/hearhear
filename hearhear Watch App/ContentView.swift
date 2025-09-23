//
//  ContentView.swift
//  hearhear Watch App
//
//  Created by Erin Akarice on 9/16/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = DisplayCoordinator(localDevice: .watch)
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 12) {
            if coordinator.showMessage {
                Text("Hello, world!")
                    .font(.headline)
            } else if coordinator.activeDevice == .phone {
                Text("Check your iPhone for \"Hello, world.\"")
                    .multilineTextAlignment(.center)
            } else {
                Text("Open the app on a device to see \"Hello, world.\"")
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .onChange(of: scenePhase) { coordinator.updateForScenePhase($0) }
        .onAppear { coordinator.updateForScenePhase(scenePhase) }
    }
}

#Preview {
    ContentView()
}
