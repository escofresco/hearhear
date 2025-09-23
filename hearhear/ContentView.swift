//
//  ContentView.swift
//  hearhear
//
//  Created by Erin Akarice on 9/16/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = DisplayCoordinator(localDevice: .phone)
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)

            Group {
                if coordinator.showMessage {
                    Text("Hello, world!")
                        .font(.title2)
                        .bold()
                } else if coordinator.activeDevice == .watch {
                    Text("\"Hello, world\" is showing on your Apple Watch.")
                        .multilineTextAlignment(.center)
                        .font(.headline)
                } else {
                    Text("Open the app on a device to see \"Hello, world.\"")
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .onChange(of: scenePhase) { coordinator.updateForScenePhase($0) }
        .onAppear { coordinator.updateForScenePhase(scenePhase) }
    }
}

#Preview {
    ContentView()
}
