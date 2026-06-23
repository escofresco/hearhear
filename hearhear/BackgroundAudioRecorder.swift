import Foundation
import AVFoundation
import CoreMedia
#if canImport(Speech)
import Speech
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class BackgroundAudioRecorder: NSObject, ObservableObject {
    struct RecordedChunk: Identifiable, Hashable {
        let url: URL
        let hasSpeaker: Bool
        let modificationDate: Date

        var id: URL { url }
    }

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
    @Published private(set) var recordedChunks: [RecordedChunk] = []

    private let session = AVAudioSession.sharedInstance()
    private var audioRecorder: AVAudioRecorder?
    private var chunkIndex = 0
    #if canImport(UIKit)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif

    private let chunkDuration: TimeInterval = 30
    private let recordingsDirectory: URL
    private static let rmsPresenceThreshold: Double = 0.01
    private static let speakerDetectionQueue = DispatchQueue(label: "com.hearhear.speaker-detection")
#if canImport(Speech)
    private var hasRequestedSpeechAuthorization = false
#endif

    override init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chunks", isDirectory: true)
        self.recordingsDirectory = directory
        super.init()
        createRecordingsDirectoryIfNeeded()
        loadExistingChunks()
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
                self.requestSpeechAuthorizationIfNeeded {
                    self.beginRecordingFlow()
                }
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

    private func loadExistingChunks() {
        let manager = FileManager.default
        do {
            let urls = try manager.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let audioFiles = urls.filter { $0.pathExtension.lowercased() == "m4a" }
            let sortedFiles = audioFiles.sorted { lhs, rhs in
                let lhsValues = try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                let rhsValues = try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                let lhsDate = lhsValues?.contentModificationDate ?? .distantPast
                let rhsDate = rhsValues?.contentModificationDate ?? .distantPast
                return lhsDate < rhsDate
            }
            updateRecordedChunks(from: sortedFiles)
        } catch {
            lastError = error
        }
    }

    private func updateRecordedChunks(from urls: [URL]) {
        guard !urls.isEmpty else {
            recordedChunks = []
            return
        }

        Self.speakerDetectionQueue.async { [weak self] in
            let chunks = urls.map(Self.makeRecordedChunk(for:))
                .sorted { $0.modificationDate < $1.modificationDate }
            DispatchQueue.main.async {
                self?.recordedChunks = chunks
            }
        }
    }

    private func processRecordedChunk(at url: URL) {
        Self.speakerDetectionQueue.async { [weak self] in
            let chunk = Self.makeRecordedChunk(for: url)
            DispatchQueue.main.async {
                self?.appendRecordedChunk(chunk)
            }
        }
    }

    private func appendRecordedChunk(_ chunk: RecordedChunk) {
        recordedChunks.append(chunk)
        recordedChunks.sort { $0.modificationDate < $1.modificationDate }
    }

    private static func makeRecordedChunk(for url: URL) -> RecordedChunk {
        let hasSpeaker = detectSpeakerPresence(at: url)
        let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let modificationDate = resourceValues?.contentModificationDate ?? .distantPast
        return RecordedChunk(url: url, hasSpeaker: hasSpeaker, modificationDate: modificationDate)
    }

    private static func detectSpeakerPresence(at url: URL) -> Bool {
        #if canImport(Speech)
        if #available(iOS 10, macOS 10.15, *) {
            if let result = detectSpeakerPresenceWithSpeech(at: url) {
                return result
            }
        }
        #endif

        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else { return false }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            return false
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        guard reader.canAdd(output) else { return false }
        reader.add(output)

        guard reader.startReading() else { return false }
        defer { reader.cancelReading() }

        var sumSquares: Double = 0
        var sampleCount: Int = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { destination in
                guard let baseAddress = destination.baseAddress else { return }
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
            }

            let floatCount = length / MemoryLayout<Float>.size
            data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                let floatBuffer = buffer.bindMemory(to: Float.self)
                for sample in floatBuffer {
                    sumSquares += Double(sample * sample)
                }
            }

            sampleCount += floatCount
            CMSampleBufferInvalidate(sampleBuffer)
        }

        guard sampleCount > 0 else { return false }
        let rms = sqrt(sumSquares / Double(sampleCount))
        return rms > rmsPresenceThreshold
    }

    #if canImport(Speech)
    @available(iOS 10, macOS 10.15, *)
    private static func detectSpeakerPresenceWithSpeech(at url: URL) -> Bool? {
        let authorizationStatus = SFSpeechRecognizer.authorizationStatus()
        guard authorizationStatus == .authorized else { return nil }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return nil }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        if #available(iOS 13, macOS 10.15, *) {
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        var detectedSpeech = false
        var encounteredError = false

        guard let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !transcript.isEmpty {
                    detectedSpeech = true
                }
                if result.isFinal {
                    semaphore.signal()
                }
            } else if error != nil {
                encounteredError = true
                semaphore.signal()
            }
        } else {
            return nil
        }

        let waitResult = semaphore.wait(timeout: .now() + 15)
        task.cancel()

        if waitResult == .timedOut {
            return detectedSpeech ? true : nil
        }

        if encounteredError && !detectedSpeech {
            return nil
        }

        return detectedSpeech
    }
    #endif

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
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            processRecordedChunk(at: recorder.url)
        } else {
            lastError = RecorderError.configurationFailed("Recording ended unexpectedly.")
        }

        guard isRecording else { return }

        do {
            try startNewChunk()
        } catch {
            lastError = error
            stopRecording()
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            lastError = error
        }
        stopRecording()
    }
}

extension BackgroundAudioRecorder {
    private func requestSpeechAuthorizationIfNeeded(completion: @escaping () -> Void) {
        #if canImport(Speech)
        if #available(iOS 10, macOS 10.15, *) {
            let status = SFSpeechRecognizer.authorizationStatus()
            switch status {
            case .notDetermined:
                if hasRequestedSpeechAuthorization {
                    completion()
                } else {
                    hasRequestedSpeechAuthorization = true
                    SFSpeechRecognizer.requestAuthorization { _ in
                        DispatchQueue.main.async {
                            completion()
                        }
                    }
                }
                return
            default:
                break
            }
        }
        #endif
        completion()
    }
}
