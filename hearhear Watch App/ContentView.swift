//
//  ContentView.swift
//  hearhear Watch App
//
//  Created by Erin Akarice on 9/16/25.
//

import Combine
import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @StateObject private var viewModel = WatchReachabilityViewModel()

    var body: some View {
        VStack(spacing: 10) {
            Text(viewModel.statusText)
                .font(.title2)
                .fontWeight(.semibold)

            Circle()
                .fill(viewModel.statusColor)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

@MainActor
final class WatchReachabilityViewModel: NSObject, ObservableObject, WCSessionDelegate {
    enum Status: String {
        case reachable
        case unreachable
    }

    @Published private(set) var status: Status = .unreachable

    var statusText: String { status.rawValue }

    var statusColor: Color { status == .reachable ? .green : .red }

    private var session: WCSession?
    private var reachabilityPolling: AnyCancellable?

    override init() {
        super.init()
        configureSession()
    }

    deinit {
        reachabilityPolling?.cancel()
    }

    private func configureSession() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
        updateStatus(using: session)
        startReachabilityPollingIfNeeded()
    }

    private func updateStatus(using session: WCSession) {
        let newStatus: Status = session.isReachable ? .reachable : .unreachable

        if newStatus != status {
            status = newStatus
        }
    }

    private func startReachabilityPollingIfNeeded() {
        guard reachabilityPolling == nil else { return }

        reachabilityPolling = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let session = self?.session else { return }
                self?.updateStatus(using: session)
            }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        updateStatus(using: session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        updateStatus(using: session)
    }
}
