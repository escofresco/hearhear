//
//  ContentView.swift
//  hearhear
//
//  Created by Erin Akarice on 9/16/25.
//

import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @StateObject private var viewModel = PhoneReachabilityViewModel()

    var body: some View {
        VStack(spacing: 12) {
            Text(viewModel.statusText)
                .font(.largeTitle)
                .fontWeight(.semibold)
                .accessibilityIdentifier("reachability_status")

            Circle()
                .fill(viewModel.statusColor)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

@MainActor
final class PhoneReachabilityViewModel: NSObject, ObservableObject, WCSessionDelegate {
    enum Status: String {
        case reachable
        case unreachable
    }

    @Published private(set) var status: Status = .unreachable

    var statusText: String { status.rawValue }

    var statusColor: Color { status == .reachable ? .green : .red }

    private var session: WCSession?

    override init() {
        super.init()
        configureSession()
    }

    private func configureSession() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
        updateStatus(using: session)
    }

    private func updateStatus(using session: WCSession) {
        let newStatus: Status = session.isReachable ? .reachable : .unreachable

        if newStatus != status {
            status = newStatus
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        updateStatus(using: session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        updateStatus(using: session)
    }

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        updateStatus(using: session)
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        updateStatus(using: session)
    }
#endif
}
