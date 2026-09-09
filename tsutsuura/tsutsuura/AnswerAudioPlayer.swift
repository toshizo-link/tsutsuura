import Foundation
import Combine

#if canImport(AVFoundation)
import AVFoundation
#endif

/// The shared audio session belongs to the player that most recently started.
/// A disappearing card must never deactivate a newer player or microphone.
@MainActor
final class AnswerAudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    private static weak var activePlayer: AnswerAudioPlayer?
    struct PlaybackIntent: Equatable { fileprivate let id = UUID() }
    private static var latestIntent = PlaybackIntent()
    private var pendingIntent: PlaybackIntent?
    private var observers: [NSObjectProtocol] = []

    #if canImport(AVFoundation)
    private var player: AVAudioPlayer?
    var isReady: Bool { player != nil }
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }
    var meteredPower: Float {
        guard let player else { return -160 }
        player.updateMeters()
        return player.averagePower(forChannel: 0)
    }
    #else
    var isReady: Bool { false }
    var currentTime: TimeInterval { 0 }
    var duration: TimeInterval { 0 }
    var meteredPower: Float { -160 }
    #endif

    override init() {
        super.init()
        #if os(iOS) && canImport(AVFoundation)
        let session = AVAudioSession.sharedInstance()
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in self?.interrupt(message: "音声が中断されました。再生ボタンで続きから聞けます。") }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor [weak self] in self?.interrupt(message: "イヤホンの接続が変わったため、一時停止しました。") }
        })
        #endif
    }

    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    static func stopAll() {
        // Also cancel downloads that have not created a native player yet.
        latestIntent = PlaybackIntent()
        activePlayer?.stop()
    }

    func reservePlaybackIntent() -> PlaybackIntent {
        let intent = PlaybackIntent()
        Self.latestIntent = intent
        pendingIntent = intent
        return intent
    }

    func accepts(_ intent: PlaybackIntent) -> Bool {
        pendingIntent == intent && Self.latestIntent == intent
    }

    func loadAndPlay(_ data: Data) throws {
        _ = try loadAndPlay(data, intent: reservePlaybackIntent())
    }

    @discardableResult
    func loadAndPlay(_ data: Data, intent: PlaybackIntent) throws -> Bool {
        guard accepts(intent) else { return false }
        clearPlayback()
        errorMessage = nil
        #if canImport(AVFoundation)
        let loaded: AVAudioPlayer
        do { loaded = try AVAudioPlayer(data: data) }
        catch { throw fail(.invalidAudio) }
        guard loaded.duration.isFinite, loaded.duration > 0, loaded.numberOfChannels > 0 else {
            throw fail(.invalidAudio)
        }
        loaded.delegate = self
        loaded.isMeteringEnabled = true
        player = loaded
        do {
            try activatePlaybackSession()
            guard loaded.prepareToPlay(), loaded.play() else { throw AudioPlaybackError.cannotStart }
            isPlaying = loaded.isPlaying
            guard isPlaying else { throw AudioPlaybackError.cannotStart }
            return true
        } catch {
            stop()
            throw fail(.cannotStart)
        }
        #else
        throw fail(.cannotStart)
        #endif
    }

    func toggle() throws {
        #if canImport(AVFoundation)
        guard let player else { throw fail(.invalidAudio) }
        _ = reservePlaybackIntent()
        if player.isPlaying { pause(); return }
        errorMessage = nil
        do {
            try activatePlaybackSession()
            if player.currentTime >= player.duration { player.currentTime = 0 }
            guard player.prepareToPlay(), player.play() else { throw AudioPlaybackError.cannotStart }
            isPlaying = player.isPlaying
            guard isPlaying else { throw AudioPlaybackError.cannotStart }
        } catch {
            pause()
            throw fail(.cannotStart)
        }
        #else
        throw fail(.cannotStart)
        #endif
    }

    func pause() {
        #if canImport(AVFoundation)
        player?.pause()
        #endif
        isPlaying = false
        releasePlaybackSession()
    }

    func stop() {
        // A disappearing old card cannot cancel another card's newer download.
        if let pendingIntent, Self.latestIntent == pendingIntent {
            Self.latestIntent = PlaybackIntent()
        }
        pendingIntent = nil
        clearPlayback()
    }

    private func clearPlayback() {
        #if canImport(AVFoundation)
        player?.stop()
        player = nil
        #endif
        isPlaying = false
        errorMessage = nil
        releasePlaybackSession()
    }

    private func interrupt(message: String) {
        guard Self.activePlayer === self, isPlaying else { return }
        pause()
        errorMessage = message
    }

    private func activatePlaybackSession() throws {
        if let previous = Self.activePlayer, previous !== self { previous.stop() }
        #if os(iOS) && canImport(AVFoundation)
        let session = AVAudioSession.sharedInstance()
        // Recording leaves .record/.measurement selected even after deactivation.
        // Playback must also work when the phone's Ring/Silent switch is silent.
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        #endif
        Self.activePlayer = self
    }

    private func releasePlaybackSession() {
        guard Self.activePlayer === self else { return }
        Self.activePlayer = nil
        #if os(iOS) && canImport(AVFoundation)
        let session = AVAudioSession.sharedInstance()
        guard session.category == .playback else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func fail(_ error: AudioPlaybackError) -> AudioPlaybackError {
        errorMessage = error.errorDescription
        return error
    }
}

enum AudioPlaybackError: LocalizedError {
    case invalidAudio
    case cannotStart
    var errorDescription: String? {
        switch self {
        case .invalidAudio: "この音声を読み込めませんでした。"
        case .cannotStart: "音声を再生できませんでした。もう一度お試しください。"
        }
    }
}

#if canImport(AVFoundation)
extension AnswerAudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        let finishedID = ObjectIdentifier(finished)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == finishedID,
                  self.player?.isPlaying == false else { return }
            self.isPlaying = false
            self.releasePlaybackSession()
            if !flag { self.errorMessage = AudioPlaybackError.cannotStart.errorDescription }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ failed: AVAudioPlayer, error: Error?) {
        let failedID = ObjectIdentifier(failed)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == failedID else { return }
            self.stop()
            self.errorMessage = AudioPlaybackError.invalidAudio.errorDescription
        }
    }
}
#endif
