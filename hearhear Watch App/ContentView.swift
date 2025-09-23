//
//  ContentView.swift
//  hearhear Watch App
//
//  Created by Erin Akarice on 9/16/25.
//

import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @StateObject private var viewModel = ReachabilityViewModel()

    var body: some View {
        VStack {
            Text(viewModel.status)
                .font(.title)
                .fontWeight(.semibold)
                .padding()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

final class ReachabilityViewModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status: String = "unreachable"

    override init() {
        super.init()
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        session.delegate = self
        session.activate()
        updateStatus(for: session)
    }

    private func updateStatus(for session: WCSession) {
        DispatchQueue.main.async {
            self.status = session.isReachable ? "reachable" : "unreachable"
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        updateStatus(for: session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        updateStatus(for: session)
    }
}
