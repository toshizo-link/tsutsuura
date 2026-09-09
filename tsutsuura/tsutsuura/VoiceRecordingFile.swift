import Foundation

#if os(iOS) && canImport(AVFoundation)
import AVFoundation

/// Serializes the microphone tap and finalization so upload bytes are read only
/// after the AAC encoder has flushed its samples and written the M4A header.
final class VoiceRecordingFile: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let sampleRate: Double
    private var file: AVAudioFile?
    private var writeFailure: Error?
    private var frameCount: AVAudioFramePosition = 0
    private var peak: Float = 0
    private var isFinished = false

    init(url: URL, format: AVAudioFormat) throws {
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceRecordingError.invalidAudio
        }
        self.url = url
        sampleRate = format.sampleRate
        file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    }

    deinit { discard() }

    func append(_ buffer: AVAudioPCMBuffer, onAccepted: (() -> Void)? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        // A tap callback already queued when Stop was pressed must not write
        // into a finalized file, or turn a successful stop into an error.
        guard !isFinished, let file else { return }
        if let writeFailure { throw writeFailure }
        do {
            try file.write(from: buffer)
            frameCount += AVAudioFramePosition(buffer.frameLength)
            peak = max(peak, Self.peakLevel(buffer))
            onAccepted?()
        } catch {
            writeFailure = error
            throw error
        }
    }

    func finish() throws -> AnswerMediaUpload {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, let file else { throw VoiceRecordingError.invalidAudio }
        isFinished = true
        file.close()
        self.file = nil
        defer { try? FileManager.default.removeItem(at: url) }
        if let writeFailure { throw writeFailure }
        guard frameCount > 0 else { throw VoiceRecordingError.noSound }
        // Reject silence, without using speech-recognition success as a gate:
        // a quiet voice, a laugh, or an unrecognized word can still be valid.
        guard peak > 0.00001 else { throw VoiceRecordingError.noSound }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else { throw VoiceRecordingError.invalidAudio }
        guard size <= AnswerDraft.maximumAudioByteCount else {
            throw AnswerMediaValidationError.audioTooLarge(maximumBytes: AnswerDraft.maximumAudioByteCount)
        }

        // Reopen the finalized file through the decoder, rather than accepting
        // a nonempty M4A header as proof that there are playable samples.
        let decoded = try AVAudioFile(forReading: url)
        defer { decoded.close() }
        guard decoded.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: decoded.processingFormat, frameCapacity: 4_096) else {
            throw VoiceRecordingError.invalidAudio
        }
        try decoded.read(into: buffer)
        guard buffer.frameLength > 0 else { throw VoiceRecordingError.invalidAudio }
        return AnswerMediaUpload(
            data: try Data(contentsOf: url),
            fileName: "voice-answer.m4a",
            mimeType: "audio/mp4",
            durationMilliseconds: max(1, Int((Double(frameCount) / sampleRate * 1_000).rounded()))
        )
    }

    func discard() {
        lock.lock()
        defer { lock.unlock() }
        isFinished = true
        file?.close()
        file = nil
        try? FileManager.default.removeItem(at: url)
    }

    private static func peakLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        var peak: Float = 0
        for audioBuffer in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            guard let data = audioBuffer.mData else { continue }
            switch buffer.format.commonFormat {
            case .pcmFormatFloat32:
                for sample in UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size) where sample.isFinite {
                    peak = max(peak, abs(sample))
                }
            case .pcmFormatFloat64:
                for sample in UnsafeBufferPointer(start: data.assumingMemoryBound(to: Double.self), count: Int(audioBuffer.mDataByteSize) / MemoryLayout<Double>.size) where sample.isFinite {
                    peak = max(peak, Float(abs(sample)))
                }
            case .pcmFormatInt16:
                for sample in UnsafeBufferPointer(start: data.assumingMemoryBound(to: Int16.self), count: Int(audioBuffer.mDataByteSize) / MemoryLayout<Int16>.size) {
                    peak = max(peak, abs(Float(sample)) / 32_768)
                }
            case .pcmFormatInt32:
                for sample in UnsafeBufferPointer(start: data.assumingMemoryBound(to: Int32.self), count: Int(audioBuffer.mDataByteSize) / MemoryLayout<Int32>.size) {
                    peak = max(peak, abs(Float(sample)) / 2_147_483_648)
                }
            default: break
            }
        }
        return peak
    }

    #if DEBUG
    static func makeTestRecording(duration: TimeInterval = 2.4) throws -> AnswerMediaUpload {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tsutsuura-voice-\(UUID().uuidString).m4a")
        let writer = try VoiceRecordingFile(url: url, format: format)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)!
        let totalFrames = Int(duration * format.sampleRate)
        for start in stride(from: 0, to: totalFrames, by: 1_024) {
            let count = min(1_024, totalFrames - start)
            buffer.frameLength = AVAudioFrameCount(count)
            for index in 0..<count {
                buffer.floatChannelData![0][index] = 0.3 * sin(2 * .pi * 440 * Float(start + index) / Float(format.sampleRate))
            }
            try writer.append(buffer)
        }
        return try writer.finish()
    }
    #endif
}
#endif

enum VoiceRecordingError: LocalizedError {
    case noSound
    case invalidAudio

    var errorDescription: String? {
        switch self {
        case .noSound: "音声が入っていません。マイクに向かって話し、もう一度録音してください。"
        case .invalidAudio: "録音した音声を確認できませんでした。もう一度録音してください。"
        }
    }
}
