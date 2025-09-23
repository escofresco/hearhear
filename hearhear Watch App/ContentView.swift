//
//  ContentView.swift
//  hearhear Watch App
//
//  Created by Erin Akarice on 9/16/25.
//

import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @StateObject private var connectivity = ConnectivityStatusProvider()

    var body: some View {
        VStack {
            Text(connectivity.isReachable ? "reachable" : "unreachable")
                .font(.headline)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

final class ConnectivityStatusProvider: NSObject, ObservableObject {
    @Published private(set) var isReachable = false

    override init() {
        super.init()
        activateSessionIfNeeded()
    }

    private func activateSessionIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        updateReachability(using: session)
    }

    private func updateReachability(using session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = reachable
        }
    }
}

extension ConnectivityStatusProvider: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        updateReachability(using: session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        updateReachability(using: session)
    }
}
