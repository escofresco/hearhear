//
//  ContentView.swift
//  hearhear
//
//  Created by Erin Akarice on 9/16/25.
//

import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @StateObject private var viewModel = ReachabilityViewModel()

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
final class ReachabilityViewModel: NSObject, ObservableObject, WCSessionDelegate {
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
        refreshStatus(propagate: true)
    }

    private func refreshStatus(propagate: Bool) {
        guard let session else { return }
        setStatus(session.isReachable ? .reachable : .unreachable, propagate: propagate)
    }

    private func setStatus(_ newStatus: Status, propagate: Bool) {
        let oldStatus = status
        if oldStatus != newStatus {
            status = newStatus
        }

        guard propagate, let session else { return }
        sendStatus(newStatus, via: session)
    }

    private func sendStatus(_ status: Status, via session: WCSession) {
        let payload = ["status": status.rawValue]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.setStatus(.unreachable, propagate: false)
                }
            }
        } else {
            do {
                try session.updateApplicationContext(payload)
            } catch {
                // Ignore context propagation errors; status will refresh on the next callback.
            }
        }
    }

    private func handleRemotePayload(_ payload: [String: Any]) {
        guard let rawValue = payload["status"] as? String,
              let remoteStatus = Status(rawValue: rawValue) else { return }

        setStatus(remoteStatus, propagate: false)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        refreshStatus(propagate: true)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        refreshStatus(propagate: true)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleRemotePayload(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleRemotePayload(applicationContext)
    }

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        refreshStatus(propagate: true)
    }
#endif
}
