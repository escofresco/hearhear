import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class BackgroundAudioRecorder: NSObject, ObservableObject {
    enum RecorderError: LocalizedError {
        case permissionDenied
        case configurationFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone access has been denied. Please enable recording permissions in Settings."
            case .configurationFailed(let message):
                return "Recording failed to start: \(message)"
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var lastError: Error?
    @Published private(set) var recordedChunks: [URL] = []

    private let session = AVAudioSession.sharedInstance()
    private var audioRecorder: AVAudioRecorder?
    private var chunkIndex = 0
    #if canImport(UIKit)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif

    private let chunkDuration: TimeInterval = 30
    private let recordingsDirectory: URL

    override init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chunks", isDirectory: true)
        self.recordingsDirectory = directory
        super.init()
        createRecordingsDirectoryIfNeeded()
        refreshRecordedChunksFromDisk()
    }

    func startRecording() {
        guard !isRecording else { return }
        lastError = nil
        session.requestRecordPermission { [weak self] allowed in
            guard let self else { return }
            DispatchQueue.main.async {
                guard allowed else {
                    self.lastError = RecorderError.permissionDenied
                    return
                }
                self.beginRecordingFlow()
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        audioRecorder?.stop()
        audioRecorder = nil
        endBackgroundTask()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func beginRecordingFlow() {
        do {
            try configureSession()
            chunkIndex = 0
            isRecording = true
            try startNewChunk()
            beginBackgroundTask()
        } catch {
            handleFailure(with: error)
        }
    }

    private func configureSession() throws {
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: [])
        } catch {
            throw RecorderError.configurationFailed(error.localizedDescription)
        }
    }

    private func startNewChunk() throws {
        let url = nextChunkURL()
        let recorder = try AVAudioRecorder(url: url, settings: recorderSettings())
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.record(forDuration: chunkDuration) else {
            throw RecorderError.configurationFailed("Unable to start recording.")
        }
        audioRecorder = recorder
    }

    private func recorderSettings() -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }

    private func nextChunkURL() -> URL {
        chunkIndex += 1
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "chunk_\(timestamp)_\(chunkIndex).m4a"
        return recordingsDirectory.appendingPathComponent(filename)
    }

    private func createRecordingsDirectoryIfNeeded() {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: recordingsDirectory.path) else { return }
        try? manager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
    }

    private func refreshRecordedChunksFromDisk() {
        let manager = FileManager.default
        do {
            let urls = try manager.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let audioFiles = urls.filter { $0.pathExtension.lowercased() == "m4a" }
            recordedChunks = audioFiles.sorted { lhs, rhs in
                let lhsValues = try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                let rhsValues = try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                let lhsDate = lhsValues?.contentModificationDate ?? .distantPast
                let rhsDate = rhsValues?.contentModificationDate ?? .distantPast
                return lhsDate > rhsDate
            }
        } catch {
            lastError = error
        }
    }

    private func handleFailure(with error: Error) {
        lastError = error
        isRecording = false
        audioRecorder?.stop()
        audioRecorder = nil
        endBackgroundTask()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func beginBackgroundTask() {
        #if canImport(UIKit)
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "BackgroundAudioRecording") { [weak self] in
            self?.endBackgroundTask()
        }
        #endif
    }

    private func endBackgroundTask() {
        #if canImport(UIKit)
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
        #endif
    }
}

extension BackgroundAudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if flag {
                self.refreshRecordedChunksFromDisk()
            } else {
                self.lastError = RecorderError.configurationFailed("Recording ended unexpectedly.")
            }

            guard self.isRecording else { return }

            do {
                try self.startNewChunk()
            } catch {
                self.lastError = error
                self.stopRecording()
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                self.lastError = error
            }
            self.stopRecording()
        }
    }
}
