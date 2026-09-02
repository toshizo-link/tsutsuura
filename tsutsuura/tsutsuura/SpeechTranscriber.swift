import Foundation
import Combine
import SwiftUI

#if os(iOS) && canImport(AVFoundation) && canImport(Speech)
import AVFoundation
import Speech
#endif

enum SpeechCaptureState: Equatable {
    case idle
    case requestingPermission
    case recording
    case permissionDenied
    case failed
}

@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var level: CGFloat = 0.18
    @Published private(set) var errorMessage: String?
    @Published private(set) var recording: AnswerMediaUpload?
    @Published private(set) var captureState: SpeechCaptureState = .idle
    private var notificationObservers: [NSObjectProtocol] = []

    #if os(iOS) && canImport(AVFoundation) && canImport(Speech)
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var temporaryRecordingURL: URL?
    private var hasInstalledAudioTap = false
    #endif

    init() {
        removeStaleTemporaryRecordings()
        #if os(iOS) && canImport(AVFoundation) && canImport(Speech)
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                let interruptionType = notification.userInfo?[
                    AVAudioSessionInterruptionTypeKey
                ] as? UInt
                Task { @MainActor [weak self] in
                    self?.handleAudioInterruption(type: interruptionType)
                }
            }
        )
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                let routeChangeReason = notification.userInfo?[
                    AVAudioSessionRouteChangeReasonKey
                ] as? UInt
                Task { @MainActor [weak self] in
                    self?.handleAudioRouteChange(reason: routeChangeReason)
                }
            }
        )
        #endif
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        #if os(iOS) && canImport(AVFoundation) && canImport(Speech)
        if let temporaryRecordingURL {
            try? FileManager.default.removeItem(at: temporaryRecordingURL)
        }
        #endif
    }

    func start() async {
        guard !isRecording else { return }
        errorMessage = nil
        captureState = .requestingPermission

        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TESTING"] == "1",
           ProcessInfo.processInfo.arguments.contains(
            "-tsutsuura-demo-voice-success"
           ) {
            transcript = "今日は家族と散歩をしました"
            recording = AnswerMediaUpload(
                data: Data("demo-audio".utf8),
                fileName: "voice-answer.m4a",
                mimeType: "audio/mp4",
                durationMilliseconds: 2_400
            )
            level = 0.72
            isRecording = false
            captureState = .idle
            return
        }
        if ProcessInfo.processInfo.environment["UI_TESTING"] == "1",
           ProcessInfo.processInfo.arguments.contains(
            "-tsutsuura-demo-voice-denied"
           ) {
            errorMessage = "音声認識が許可されていません。設定で音声認識を許可してください。"
            isRecording = false
            captureState = .permissionDenied
            return
        }
        #endif

        #if os(iOS) && canImport(AVFoundation) && canImport(Speech)
        let speechAuthorization = await requestSpeechAuthorization()
        guard speechAuthorization == .authorized else {
            errorMessage = "音声認識が許可されていません。設定で音声認識を許可してください。"
            captureState = .permissionDenied
            return
        }

        let microphoneAllowed = await requestMicrophonePermission()
        guard microphoneAllowed else {
            errorMessage = "マイクが許可されていません。設定でマイクを許可してください。"
            captureState = .permissionDenied
            return
        }

        do {
            try beginRecognition()
        } catch {
            errorMessage = "録音を開始できませんでした"
            finishCapture(keepingRecording: false)
            captureState = .failed
        }
        #else
        errorMessage = "この端末では音声入力を利用できません"
        captureState = .failed
        #endif
    }

    func stop() {
        finishCapture(keepingRecording: true)
    }

    /// Transfers the completed recording to the answer draft without keeping
    /// a second long-lived reference to its bytes in the transcriber.
    func takeRecording() -> AnswerMediaUpload? {
        defer { recording = nil }
        return recording
    }

    func reset(keepingTranscript: Bool = false) {
        finishCapture(keepingRecording: false)
        recording = nil
        if !keepingTranscript {
            transcript = ""
        }
        errorMessage = nil
        captureState = .idle
    }

    private func finishCapture(keepingRecording: Bool) {
        isRecording = false
        captureState = .idle

        #if os(iOS) && canImport(AVFoundation) && canImport(Speech)
        let completedURL = temporaryRecordingURL
        temporaryRecordingURL = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledAudioTap = false
        }
        let completedFrameLength = audioFile?.length
        let completedSampleRate = audioFile?.processingFormat.sampleRate
        audioFile = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        level = 0.18

        guard let completedURL else { return }
        defer { try? FileManager.default.removeItem(at: completedURL) }
        guard keepingRecording,
              let completedFrameLength,
              let completedSampleRate else { return }

        do {
            let data = try Data(contentsOf: completedURL)
            guard !data.isEmpty else {
                throw SpeechTranscriberError.emptyRecording
            }
            guard data.count <= AnswerDraft.maximumAudioByteCount else {
                throw AnswerMediaValidationError.audioTooLarge(
                    maximumBytes: AnswerDraft.maximumAudioByteCount
                )
            }
            let durationMilliseconds = completedSampleRate > 0
                ? Int(
                    (Double(completedFrameLength) / completedSampleRate * 1_000)
                        .rounded()
                )
                : nil
            recording = AnswerMediaUpload(
                data: data,
                fileName: "voice-answer.m4a",
                mimeType: "audio/mp4",
                durationMilliseconds: durationMilliseconds
            )
        } catch {
            recording = nil
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "録音を保存できませんでした"
        }
        #else
        level = 0.18
        #endif
    }

    #if os(iOS) && canImport(AVFoundation) && canImport(Speech)
    private func beginRecognition() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        recording = nil
        cleanupTemporaryRecording()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .record,
            mode: .measurement,
            options: [.duckOthers, .allowBluetoothHFP]
        )
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        guard let recognizer, recognizer.isAvailable else {
            throw SpeechTranscriberError.recognizerUnavailable
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechTranscriberError.invalidAudioFormat
        }

        let recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "tsutsuura-voice-\(UUID().uuidString).m4a",
                isDirectory: false
            )
        let recordingSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let file = try AVAudioFile(
            forWriting: recordingURL,
            settings: recordingSettings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        audioFile = file
        temporaryRecordingURL = recordingURL

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            do {
                try file.write(from: buffer)
            } catch {
                Task { @MainActor [weak self] in
                    guard let self, isRecording else { return }
                    errorMessage = "録音を保存できませんでした"
                    finishCapture(keepingRecording: false)
                }
            }

            guard let channel = buffer.floatChannelData?.pointee else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            var sum: Float = 0
            for frame in 0..<frameLength {
                let sample = channel[frame]
                sum += sample * sample
            }
            let rootMeanSquare = sqrt(sum / Float(frameLength))
            let normalized = max(0.18, min(1, CGFloat(rootMeanSquare) * 12))
            Task { @MainActor [weak self] in
                self?.level = normalized
            }
        }
        hasInstalledAudioTap = true

        recognitionTask = recognizer.recognitionTask(with: request) {
            [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        stop()
                    }
                }
                if error != nil, isRecording {
                    let recognitionFailed = transcript.isEmpty
                    stop()
                    if recognitionFailed {
                        errorMessage = "音声を認識できませんでした"
                        captureState = .failed
                    }
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        captureState = .recording
    }

    private func cleanupTemporaryRecording() {
        guard let temporaryRecordingURL else { return }
        try? FileManager.default.removeItem(at: temporaryRecordingURL)
        self.temporaryRecordingURL = nil
        audioFile = nil
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    private func handleAudioInterruption(type rawValue: UInt?) {
        guard isRecording,
              let rawValue,
              AVAudioSession.InterruptionType(rawValue: rawValue) == .began else {
            return
        }
        finishCapture(keepingRecording: true)
        errorMessage = "録音が中断されました。内容を確認して、必要なら録音し直してください。"
        captureState = .failed
    }

    private func handleAudioRouteChange(reason rawValue: UInt?) {
        guard isRecording,
              let rawValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawValue),
              reason == .oldDeviceUnavailable else {
            return
        }
        finishCapture(keepingRecording: true)
        errorMessage = "マイクまたはイヤホンの接続が変わったため、録音を停止しました。"
        captureState = .failed
    }
    #endif

    private func removeStaleTemporaryRecordings() {
        #if os(iOS) && canImport(AVFoundation) && canImport(Speech)
        let directory = FileManager.default.temporaryDirectory
        let staleFiles = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for url in staleFiles ?? []
        where url.lastPathComponent.hasPrefix("tsutsuura-voice-")
            && url.pathExtension == "m4a" {
            try? FileManager.default.removeItem(at: url)
        }
        #endif
    }
}

private enum SpeechTranscriberError: Error {
    case recognizerUnavailable
    case invalidAudioFormat
    case emptyRecording
}
