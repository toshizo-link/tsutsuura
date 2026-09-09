import Foundation
import AVFoundation
import CryptoKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
    AVNumberOfChannelsKey: Int(format.channelCount), AVEncoderBitRateKey: 96_000,
    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]

final class Owner { var audioFile: AVAudioFile? }
func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func decode(_ url: URL) -> [String: Any] {
    do {
        let file = try AVAudioFile(forReading: url)
        let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
        var frames = 0; var samples = 0; var sum = 0.0; var peak = 0.0
        while file.framePosition < file.length {
            let remaining = file.length - file.framePosition
            try file.read(into: pcm, frameCount: AVAudioFrameCount(min(4096, remaining)))
            guard pcm.frameLength > 0 else { break }
            frames += Int(pcm.frameLength)
            if let channels = pcm.floatChannelData {
                for channel in 0..<Int(pcm.format.channelCount) {
                    for i in 0..<Int(pcm.frameLength) {
                        let value = Double(channels[channel][i]); sum += value * value; peak = max(peak, abs(value)); samples += 1
                    }
                }
            }
        }
        let rms = samples > 0 ? sqrt(sum / Double(samples)) : 0
        return ["decoded": true, "frames": frames, "durationSeconds": Double(frames) / file.processingFormat.sampleRate,
                "rms": rms, "peak": peak, "nonSilent": rms > 0.05 && peak > 0.1]
    } catch {
        let ns = error as NSError
        return ["decoded": false, "errorDomain": ns.domain, "errorCode": ns.code, "error": ns.localizedDescription]
    }
}
func snapshot(_ source: URL, name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: source)
    let url = directory.appendingPathComponent(name + ".m4a")
    try data.write(to: url)
    let prefix = data.prefix(24).map { String(format: "%02x", $0) }.joined()
    let ftyp = data.count >= 12 ? String(data: data[4..<12], encoding: .ascii) ?? "non-ascii" : "absent"
    return ["file": url.path, "bytes": data.count, "sha256": digest(data), "prefixHex": prefix,
            "ftypAndBrand": ftyp, "moovTagPresent": data.range(of: Data("moov".utf8)) != nil,
            "mdatTagPresent": data.range(of: Data("mdat".utf8)) != nil, "appleDecode": decode(url)]
}
func writeTone(_ tap: (AVAudioPCMBuffer) throws -> Void, total: Int) throws {
    let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
    var start = 0
    while start < total {
        let count = min(1024, total - start); pcm.frameLength = AVAudioFrameCount(count)
        for i in 0..<count { pcm.floatChannelData![0][i] = Float(0.4 * sin(2 * Double.pi * 440 * Double(start + i) / 48_000)) }
        try tap(pcm); start += count
    }
}

var cases: [[String: Any]] = []
for frames in [2400, 24000, 192000] {
    let owner = Owner()
    let path = directory.appendingPathComponent("live-\(frames).m4a")
    var retainedTap: ((AVAudioPCMBuffer) throws -> Void)?
    weak var encoder: AVAudioFile?
    do {
        let file = try AVAudioFile(forWriting: path, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        owner.audioFile = file
        encoder = file
        // Same lifetime as the original tap's capture of its local `file`.
        retainedTap = { buffer in try file.write(from: buffer) }
    }
    try writeTone(retainedTap!, total: frames)
    let reportedLength = owner.audioFile!.length
    owner.audioFile = nil
    let retainedAfterOwnerNil = encoder != nil
    let before = try snapshot(path, name: "before-close-\(frames)")
    encoder!.close()
    let retainedAfterClose = encoder != nil
    let after = try snapshot(path, name: "after-close-\(frames)")
    withExtendedLifetime(retainedTap) {}
    retainedTap = nil
    let released = encoder == nil
    cases.append(["inputFrames": frames, "inputDurationSeconds": Double(frames)/48_000,
                  "oldLengthBeforeFinalization": reportedLength, "retainedAfterOwnerNil": retainedAfterOwnerNil,
                  "retainedAfterExplicitClose": retainedAfterClose, "releasedAfterTapNil": released,
                  "beforeExplicitClose": before, "afterExplicitClose": after])
}

// Control: when the tap's closure really has been destroyed, deinit finalizes
// the file. The bug requires a retained/in-flight capture, not every stop call.
let owner = Owner()
let controlPath = directory.appendingPathComponent("live-deinit-control.m4a")
var tap: ((AVAudioPCMBuffer) throws -> Void)?
weak var weakFile: AVAudioFile?
do {
    let file = try AVAudioFile(forWriting: controlPath, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    owner.audioFile = file; weakFile = file; tap = { buffer in try file.write(from: buffer) }
}
try writeTone(tap!, total: 192000)
tap = nil; owner.audioFile = nil
let control = try snapshot(controlPath, name: "deinit-control")
let result: [String: Any] = ["microphoneUsed": false, "userAudioRead": false,
    "simulatorUsed": false, "sourceModified": false, "platform": ProcessInfo.processInfo.operatingSystemVersionString,
    "cases": cases, "control": ["encoderReleased": weakFile == nil, "snapshot": control]]
let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
try json.write(to: directory.appendingPathComponent("results.json"))
print(String(data: json, encoding: .utf8)!)
