import XCTest
import AVFoundation
@testable import tsutsuura

final class VoiceRecordingFileTests: XCTestCase {
    func testFinalizedAACContainsDecodableSoundAndCorrectDuration() throws {
        let recording = try VoiceRecordingFile.makeTestRecording(duration: 1)
        XCTAssertEqual(recording.mimeType, "audio/mp4")
        XCTAssertEqual(recording.durationMilliseconds, 1_000)
        XCTAssertGreaterThan(recording.data.count, 1_000)
        let metrics = try decode(recording)
        XCTAssertEqual(metrics.duration, 1, accuracy: 0.03)
        XCTAssertGreaterThan(metrics.rms, 0.15)
        XCTAssertLessThan(metrics.rms, 0.3)
        XCTAssertGreaterThan(metrics.peak, 0.25)
        XCTAssertLessThan(metrics.peak, 1)
    }

    func testFinalizationClosesEncoderEvenWhenTapRetainsWriter() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let url = temporaryURL()
        let writer = try VoiceRecordingFile(url: url, format: format)
        let tap = { (buffer: AVAudioPCMBuffer) in try writer.append(buffer) }
        let buffer = try tone(format: format, frames: 24_000)
        try tap(buffer)
        let completed = try writer.finish()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        // Retaining/calling the old tap cannot keep the encoder open or append
        // bytes after the completed upload was returned.
        try tap(buffer)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(completed.durationMilliseconds, 500)
        XCTAssertGreaterThan(try decode(completed).rms, 0.1)
        XCTAssertThrowsError(try writer.finish())
    }

    func testSoundOnSecondChannelIsPreserved() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let writer = try VoiceRecordingFile(url: temporaryURL(), format: format)
        let buffer = try tone(format: format, frames: 24_000, audibleChannel: 1)
        try writer.append(buffer)
        let recording = try writer.finish()
        let metrics = try decode(recording)
        XCTAssertEqual(recording.durationMilliseconds, 500)
        XCTAssertEqual(metrics.channels, 2)
        XCTAssertGreaterThan(metrics.rms, 0.1)
    }

    func testEmptyCaptureAndSilentCaptureAreRejectedAndCleanedUp() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        for includeFrames in [false, true] {
            let url = temporaryURL()
            let writer = try VoiceRecordingFile(url: url, format: format)
            if includeFrames {
                try writer.append(tone(format: format, frames: 4_410, amplitude: 0))
            }
            XCTAssertThrowsError(try writer.finish()) { error in
                guard case VoiceRecordingError.noSound = error else {
                    return XCTFail("Expected a no-sound error, got \(error)")
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testQuietCaptureDoesNotRequireSpeechRecognitionOrLoudness() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let writer = try VoiceRecordingFile(url: temporaryURL(), format: format)
        try writer.append(tone(format: format, frames: 22_050, amplitude: 0.0001))
        let recording = try writer.finish()
        XCTAssertEqual(recording.durationMilliseconds, 500)
        XCTAssertGreaterThan(try decode(recording).peak, 0)
    }

    func testDiscardClosesFileAndIgnoresLateTap() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let url = temporaryURL()
        let writer = try VoiceRecordingFile(url: url, format: format)
        let buffer = try tone(format: format, frames: 4_410)
        try writer.append(buffer)
        writer.discard()
        try writer.append(buffer)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertThrowsError(try writer.finish())
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("voice-file-test-\(UUID().uuidString).m4a")
    }

    private func tone(format: AVAudioFormat, frames: AVAudioFrameCount, amplitude: Float = 0.3, audibleChannel: Int = 0) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(frames) {
                channels[channel][frame] = channel == audibleChannel
                    ? amplitude * sin(2 * .pi * 440 * Float(frame) / Float(format.sampleRate)) : 0
            }
        }
        return buffer
    }

    private func decode(_ recording: AnswerMediaUpload) throws -> (duration: Double, channels: Int, rms: Double, peak: Float) {
        let url = temporaryURL()
        try recording.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        defer { file.close() }
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096))
        var frames = 0
        var sum = 0.0
        var peak: Float = 0
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            let channels = try XCTUnwrap(buffer.floatChannelData)
            for channel in 0..<Int(file.processingFormat.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let sample = channels[channel][frame]
                    XCTAssertTrue(sample.isFinite)
                    sum += Double(sample * sample)
                    peak = max(peak, abs(sample))
                }
            }
            frames += Int(buffer.frameLength)
        }
        XCTAssertGreaterThan(frames, 0)
        let channelCount = Int(file.processingFormat.channelCount)
        return (Double(frames) / file.processingFormat.sampleRate, channelCount,
                sqrt(sum / Double(max(1, frames * channelCount))), peak)
    }
}
