import Foundation
import Combine
import WatchConnectivity
#if canImport(SwiftUI)
import SwiftUI
#endif

final class DisplayCoordinator: NSObject, ObservableObject {
    enum Device: String {
        case phone
        case watch
    }

    @Published private(set) var activeDevice: Device?
    @Published private(set) var showMessage: Bool = false

    private let localDevice: Device
    private var isPhoneActive: Bool = false
    private var isWatchActive: Bool = false
    private var session: WCSession?

    init(localDevice: Device) {
        self.localDevice = localDevice
        super.init()
        configureSessionIfNeeded()
        updateVisibility()
    }

    func setLocalActive(_ isActive: Bool) {
        switch localDevice {
        case .phone:
            if isPhoneActive == isActive { return }
            isPhoneActive = isActive
        case .watch:
            if isWatchActive == isActive { return }
            isWatchActive = isActive
        }
        updateVisibility()
        broadcastLocalState(isActive: isActive)
    }

    private func configureSessionIfNeeded() {
        guard WCSession.isSupported() else { return }
        let currentSession = WCSession.default
        currentSession.delegate = self
        currentSession.activate()
        session = currentSession
    }

    private func broadcastLocalState(isActive: Bool) {
        guard let session, session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "source": localDevice.rawValue,
            "isActive": isActive
        ]
        do {
            try session.updateApplicationContext(payload)
        } catch {
            // Silently ignore failures; the counterpart will receive the next update.
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func handleIncomingState(_ payload: [String: Any]) {
        guard let sourceRaw = payload["source"] as? String,
              let source = Device(rawValue: sourceRaw),
              let isActive = payload["isActive"] as? Bool,
              source != localDevice else { return }

        switch source {
        case .phone:
            isPhoneActive = isActive
        case .watch:
            isWatchActive = isActive
        }
        updateVisibility()
    }

    private func updateVisibility() {
        let newActiveDevice: Device?
        if isPhoneActive {
            newActiveDevice = .phone
        } else if isWatchActive {
            newActiveDevice = .watch
        } else {
            newActiveDevice = nil
        }
        let shouldShow = newActiveDevice == localDevice

        if Thread.isMainThread {
            activeDevice = newActiveDevice
            showMessage = shouldShow
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.activeDevice = newActiveDevice
                self?.showMessage = shouldShow
            }
        }
    }
}

extension DisplayCoordinator: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let currentlyActive: Bool = {
            switch localDevice {
            case .phone:
                return isPhoneActive
            case .watch:
                return isWatchActive
            }
        }()
        if activationState == .activated {
            broadcastLocalState(isActive: currentlyActive)
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleIncomingState(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleIncomingState(applicationContext)
    }
}

#if canImport(SwiftUI)
extension DisplayCoordinator {
    func updateForScenePhase(_ phase: ScenePhase) {
        setLocalActive(phase == .active)
    }
}
#endif
