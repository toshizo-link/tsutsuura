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
    private var captureGeneration = 0

    #if os(iOS) && canImport(AVFoundation) && canImport(Speech)
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recordingFile: VoiceRecordingFile?
    private var ownsRecordingSession = false
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
        guard !isRecording, captureState != .requestingPermission else { return }
        captureGeneration += 1
        let generation = captureGeneration
        errorMessage = nil
        captureState = .requestingPermission

        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TESTING"] == "1",
           ProcessInfo.processInfo.arguments.contains(
            "-tsutsuura-demo-voice-success"
           ) {
            transcript = "今日は家族と散歩をしました"
            do {
                recording = try VoiceRecordingFile.makeTestRecording()
            } catch {
                errorMessage = error.localizedDescription
                captureState = .failed
                return
            }
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
        guard generation == captureGeneration, !Task.isCancelled else { return }
        guard speechAuthorization == .authorized else {
            errorMessage = "音声認識が許可されていません。設定で音声認識を許可してください。"
            captureState = .permissionDenied
            return
        }

        let microphoneAllowed = await requestMicrophonePermission()
        guard generation == captureGeneration, !Task.isCancelled else { return }
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
        captureGeneration += 1
        isRecording = false
        captureState = .idle

        #if os(iOS) && canImport(AVFoundation) && canImport(Speech)
        temporaryRecordingURL = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledAudioTap = false
        }
        let completedFile = recordingFile
        recordingFile = nil
        // Closing the sink waits for an accepted tap callback. Once it returns,
        // a late callback cannot append either audio or speech-recognition data.
        if let completedFile {
            if keepingRecording {
                do {
                    recording = try completedFile.finish()
                } catch {
                    recording = nil
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "録音を保存できませんでした"
                    captureState = .failed
                }
            } else {
                completedFile.discard()
            }
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // stop/reset also runs when the voice page disappears. A second call
        // must not deactivate a playback session started on the next page.
        if ownsRecordingSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsRecordingSession = false
        }
        level = 0.18
        #else
        level = 0.18
        #endif
    }

    #if os(iOS) && canImport(AVFoundation) && canImport(Speech)
    private func beginRecognition() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        recording = nil
        transcript = ""
        cleanupTemporaryRecording()

        AnswerAudioPlayer.stopAll()
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .record,
            mode: .measurement,
            options: [.duckOthers, .allowBluetoothHFP]
        )
        try audioSession.setActive(true)
        ownsRecordingSession = true

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
        let file = try VoiceRecordingFile(url: recordingURL, format: format)
        recordingFile = file
        temporaryRecordingURL = recordingURL
        let generation = captureGeneration

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { [weak self] buffer, _ in
            do {
                try file.append(buffer) { request.append(buffer) }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self, generation == captureGeneration, isRecording else { return }
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
                guard let self, generation == captureGeneration, isRecording else { return }
                level = normalized
            }
        }
        hasInstalledAudioTap = true

        recognitionTask = recognizer.recognitionTask(with: request) {
            [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, generation == captureGeneration else { return }
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
        recordingFile?.discard()
        recordingFile = nil
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
}
