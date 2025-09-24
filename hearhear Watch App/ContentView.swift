//
//  ContentView.swift
//  hearhear Watch App
//
//  Created by Erin Akarice on 9/16/25.
//

import SwiftUI
import Combine
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

    private var session: WCSession?
    private var reachabilityPolling: AnyCancellable?

    override init() {
        super.init()
        activateSessionIfNeeded()
    }

    deinit {
        reachabilityPolling?.cancel()
    }

    private func activateSessionIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
        updateReachability(using: session)
        startReachabilityPollingIfNeeded()
    }

    private func startReachabilityPollingIfNeeded() {
#if os(watchOS)
        guard reachabilityPolling == nil else { return }
        reachabilityPolling = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let session = self?.session else { return }
                self?.updateReachability(using: session)
            }
#endif
    }

    private func updateReachability(using session: WCSession) {
        let reachable = session.activationState == .activated && session.isReachable
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
