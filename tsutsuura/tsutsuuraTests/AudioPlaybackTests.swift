import Foundation
import XCTest
import AVFoundation
@testable import tsutsuura

@MainActor
final class AudioPlaybackTests: XCTestCase {
    override func tearDown() {
        AnswerAudioPlayer.stopAll()
        super.tearDown()
    }

    func testAACFixtureDecodesToNonSilentPCM() throws {
        let recording = try VoiceRecordingFile.makeTestRecording(duration: 1.2)
        let signal = try decodedSignal(recording.data)
        XCTAssertGreaterThan(signal.frames, 40_000)
        XCTAssertEqual(signal.duration, 1.2, accuracy: 0.1)
        XCTAssertGreaterThan(signal.rms, 0.1)
        XCTAssertLessThan(signal.rms, 0.5)
        XCTAssertGreaterThan(signal.peak, 0.2)
        XCTAssertLessThan(signal.peak, 1)
    }

    func testAuthenticatedAACDownloadPlaysAfterRecordOnlySession() async throws {
        let recording = try VoiceRecordingFile.makeTestRecording(duration: 2)
        let transport = AudioBytesTransport(data: recording.data)
        let api = DefaultAppAPI(configuration: try APIConfiguration(baseURL: APIConfiguration.productionBaseURL),
            transport: transport, tokenStore: InMemoryTokenStore(token: "audio-fixture-token"), retryPolicy: .disabled)
        let media = AnswerMedia(id: "audio-fixture", kind: .audio,
            url: APIConfiguration.productionBaseURL.appendingPathComponent("v1/media/audio-fixture"), mimeType: "audio/mp4")
        let content = try await api.fetchAnswerMedia(media)
        XCTAssertEqual(content.data, recording.data)
        let request = await transport.request
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer audio-fixture-token")
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertGreaterThan(try decodedSignal(content.data).rms, 0.1)

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        let player = AnswerAudioPlayer()
        defer { player.stop() }
        try player.loadAndPlay(content.data)
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.mode, .default)
        XCTAssertFalse(session.currentRoute.outputs.isEmpty, "A native output route must be selected")
        try await assertDecodingAdvances(player)
    }

    func testResumeReconfiguresSessionAndAdvancesSamples() async throws {
        let recording = try VoiceRecordingFile.makeTestRecording(duration: 3)
        let player = AnswerAudioPlayer()
        defer { player.stop() }
        try player.loadAndPlay(recording.data)
        try await assertDecodingAdvances(player)
        player.pause()
        XCTAssertFalse(player.isPlaying)
        let pausePosition = player.currentTime
        try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [])
        try player.toggle()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        XCTAssertEqual(AVAudioSession.sharedInstance().mode, .default)
        try await assertDecodingAdvances(player)
        XCTAssertGreaterThan(player.currentTime, pausePosition)
    }

    func testSingleActivePlayerSurvivesStaleCleanupAndDelegate() async throws {
        let recording = try VoiceRecordingFile.makeTestRecording(duration: 3)
        let previous = AnswerAudioPlayer()
        let current = AnswerAudioPlayer()
        defer { current.stop() }
        try previous.loadAndPlay(recording.data)
        try current.loadAndPlay(recording.data)
        XCTAssertFalse(previous.isPlaying)
        XCTAssertFalse(previous.isReady)
        previous.stop()
        // A callback from a replaced AVAudioPlayer must not mutate this player.
        let obsolete = try AVAudioPlayer(data: recording.data)
        current.audioPlayerDidFinishPlaying(obsolete, successfully: true)
        current.audioPlayerDecodeErrorDidOccur(obsolete, error: AudioPlaybackError.invalidAudio)
        await Task.yield()
        XCTAssertNil(current.errorMessage)
        try await assertDecodingAdvances(current)
    }

    func testInterruptionAndHeadphoneDisconnectionPauseUntilUserResumes() async throws {
        let player = AnswerAudioPlayer()
        defer { player.stop() }
        try player.loadAndPlay(VoiceRecordingFile.makeTestRecording(duration: 4).data)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        await Task.yield()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.errorMessage)
        XCTAssertTrue(player.isReady)
        try player.toggle()
        try await assertDecodingAdvances(player)
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(), userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        await Task.yield()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.errorMessage)
    }

    func testInvalidEncodedBytesNeverClaimPlaybackSuccess() {
        let player = AnswerAudioPlayer()
        XCTAssertThrowsError(try player.loadAndPlay(Data("not AAC".utf8)))
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isReady)
        XCTAssertNotNil(player.errorMessage)
    }

    func testIdleRecorderCleanupDoesNotDeactivateActivePlayback() async throws {
        let recorder = SpeechTranscriber()
        let player = AnswerAudioPlayer()
        defer { player.stop() }
        try player.loadAndPlay(VoiceRecordingFile.makeTestRecording(duration: 3).data)
        recorder.stop()
        recorder.reset()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        try await assertDecodingAdvances(player)
    }

    func testStopAllReleasesPlaybackBeforeRecorderTakesSession() throws {
        let player = AnswerAudioPlayer()
        try player.loadAndPlay(VoiceRecordingFile.makeTestRecording(duration: 1).data)
        AnswerAudioPlayer.stopAll()
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isReady)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        player.stop()
        XCTAssertEqual(session.category, .record)
    }

    func testLateFirstDownloadCannotReplaceNewerPlaybackAfterOldCardDisappears() async throws {
        let data = try VoiceRecordingFile.makeTestRecording(duration: 3).data
        let first = AnswerAudioPlayer()
        let second = AnswerAudioPlayer()
        defer { first.stop(); second.stop() }
        let firstDownload = DelayedAudioDownload()
        let secondDownload = DelayedAudioDownload()
        let firstIntent = first.reservePlaybackIntent()
        let firstTask = Task {
            try first.loadAndPlay(await firstDownload.data(), intent: firstIntent)
        }
        await firstDownload.waitUntilRequested()
        let secondIntent = second.reservePlaybackIntent()
        let secondTask = Task {
            try second.loadAndPlay(await secondDownload.data(), intent: secondIntent)
        }
        await secondDownload.waitUntilRequested()

        // The old card disappears while the newer card is still downloading.
        first.stop()
        XCTAssertTrue(second.accepts(secondIntent))
        await secondDownload.finish(with: data)
        let secondStarted = try await secondTask.value
        XCTAssertTrue(secondStarted)
        await firstDownload.finish(with: data)
        let firstStarted = try await firstTask.value
        XCTAssertFalse(firstStarted)
        XCTAssertFalse(first.isPlaying)
        XCTAssertFalse(first.isReady)
        XCTAssertNil(first.errorMessage)
        try await assertDecodingAdvances(second)
    }

    func testNewerPlaybackWinsWhenBothDownloadingCardsRemainVisible() async throws {
        let data = try VoiceRecordingFile.makeTestRecording(duration: 3).data
        let first = AnswerAudioPlayer()
        let second = AnswerAudioPlayer()
        defer { first.stop(); second.stop() }
        let download = DelayedAudioDownload()
        let intent = first.reservePlaybackIntent()
        let task = Task { try first.loadAndPlay(await download.data(), intent: intent) }
        await download.waitUntilRequested()
        try second.loadAndPlay(data)
        await download.finish(with: data)
        let firstStarted = try await task.value
        XCTAssertFalse(firstStarted)
        XCTAssertFalse(first.isReady)
        try await assertDecodingAdvances(second)
    }

    func testRecordingCancelsPendingDownloadWithoutAnActivePlayer() async throws {
        let data = try VoiceRecordingFile.makeTestRecording(duration: 1).data
        let player = AnswerAudioPlayer()
        defer { player.stop() }
        let download = DelayedAudioDownload()
        let intent = player.reservePlaybackIntent()
        let task = Task { try player.loadAndPlay(await download.data(), intent: intent) }
        await download.waitUntilRequested()
        XCTAssertFalse(player.isReady)

        // This is the recorder's handoff, before a download has opened any player.
        AnswerAudioPlayer.stopAll()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        await download.finish(with: data)
        let started = try await task.value
        XCTAssertFalse(started)
        XCTAssertFalse(player.isReady)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.errorMessage)
        XCTAssertEqual(session.category, .record)
        XCTAssertEqual(session.mode, .measurement)
    }

    func testDraftResumeCancelsEarlierPendingPublishedAudio() async throws {
        let data = try VoiceRecordingFile.makeTestRecording(duration: 3).data
        let draft = AnswerAudioPlayer()
        let published = AnswerAudioPlayer()
        defer { draft.stop(); published.stop() }
        try draft.loadAndPlay(data)
        draft.pause()
        let download = DelayedAudioDownload()
        let intent = published.reservePlaybackIntent()
        let task = Task { try published.loadAndPlay(await download.data(), intent: intent) }
        await download.waitUntilRequested()
        try draft.toggle()
        await download.finish(with: data)
        let started = try await task.value
        XCTAssertFalse(started)
        XCTAssertFalse(published.isReady)
        try await assertDecodingAdvances(draft)
    }

    private func assertDecodingAdvances(_ player: AnswerAudioPlayer, file: StaticString = #filePath, line: UInt = #line) async throws {
        let before = player.currentTime
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(player.isPlaying, file: file, line: line)
        XCTAssertGreaterThan(player.currentTime, before + 0.05, file: file, line: line)
        XCTAssertTrue(player.meteredPower.isFinite, file: file, line: line)
        XCTAssertGreaterThan(player.meteredPower, -40, "Decoded output must contain a signal; isPlaying alone proves no sound", file: file, line: line)
    }

    private func decodedSignal(_ data: Data) throws -> (frames: Int, duration: Double, rms: Double, peak: Float) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("playback-fixture-\(UUID().uuidString).m4a")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        defer { file.close() }
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096))
        var frames = 0
        var squares = 0.0
        var peak: Float = 0
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            for index in 0..<Int(buffer.frameLength) {
                XCTAssertTrue(samples[index].isFinite)
                squares += Double(samples[index] * samples[index])
                peak = max(peak, abs(samples[index]))
            }
            frames += Int(buffer.frameLength)
        }
        return (frames, Double(frames) / file.processingFormat.sampleRate, sqrt(squares / Double(max(frames, 1))), peak)
    }
}

/// The test chooses completion order explicitly instead of racing sleep durations.
private actor DelayedAudioDownload {
    private var request: CheckedContinuation<Data, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func data() async -> Data {
        await withCheckedContinuation { continuation in
            request = continuation
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilRequested() async {
        guard request == nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish(with data: Data) {
        precondition(request != nil, "Wait for the download request before completing it")
        request?.resume(returning: data)
        request = nil
    }
}

private actor AudioBytesTransport: HTTPTransport {
    let data: Data
    private(set) var request: URLRequest?
    init(data: Data) { self.data = data }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "audio/mp4"])!)
    }
}
