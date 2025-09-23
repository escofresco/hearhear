//
//  ContentView.swift
//  hearhear
//
//  Created by Erin Akarice on 9/16/25.
//

import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @StateObject private var recorder = BackgroundAudioRecorder()
    @StateObject private var connectivity = ConnectivityStatusProvider()

    var body: some View {
        VStack(spacing: 24) {
            Text(connectivity.isReachable ? "reachable" : "unreachable")
                .font(.subheadline)

            Text(recorder.isRecording ? "Recording in 30-second chunks" : "Recorder is idle")
                .font(.headline)
                .multilineTextAlignment(.center)

            Button(action: toggleRecording) {
                Text(recorder.isRecording ? "Stop Recording" : "Start Background Recording")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(recorder.isRecording ? Color.red : Color.blue)
                    .cornerRadius(12)
            }

            if !recorder.recordedChunks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recorded Chunks")
                        .font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(recorder.recordedChunks, id: \.self) { url in
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            if let error = recorder.lastError {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stopRecording()
        } else {
            recorder.startRecording()
        }
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

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}
