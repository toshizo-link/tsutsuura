# Recorded voice fix — build 17 candidate

The code had defects in both playback setup and recording finalization. Playback now activates the playback audio session on each start or resume, verifies that the native player actually started, and displays readable failures. The recorder closes the AAC writer explicitly before reading upload bytes, serializes finalization against microphone callbacks, and checks that the result contains decodable audio. An empty or effectively silent recording prompts another attempt. A new 「録音を聞く」 control lets the user check the saved recording before sending it.

Session ownership prevents an old view's cleanup from silencing a newer player. Starting a recording stops playback first. Interruptions and disconnected headphones pause playback; resuming reconfigures the session. Re-recording clears the old transcript, and late permission, recognition and tap callbacks cannot alter a newer capture.

## Evidence

- `server-audit/`: generated AAC/M4A files pass actual local multipart upload, authenticated GET/HEAD and byte-range retrieval without byte changes. Apple decoding confirms nonzero sample energy. No production endpoint or user recording was accessed.
- `finalization-reproduction/`: clearing the owner reference while a tap closure retains the AAC writer produces a nonempty but undecodable M4A. Explicit close produces complete, decodable files at all three tested durations. The control that releases both references also succeeds. This establishes a possible file-lifetime failure, not that every historical recording is damaged.
- `audio-v2-summary.json`: all 246 unit tests and three of four UI scenarios passed. The draft-preview UI test attempted to use a button below the small-screen viewport.
- `audio-v4-summary.json`: the final run passed all 250 unit tests and both audio UI scenarios, including the four deterministic download-order regressions. Final screenshots confirm the preview has readable dark text on an opaque light card.
- `audio-v3-summary.json`: the affected draft-preview scenario passed after the test explicitly scrolled to the enabled button. It verifies use of actual generated AAC bytes, preview play/pause, and removal.

The 18 added unit tests cover native AAC finalization/decoding, retained and late callbacks, silence and quiet-speech thresholds, stereo audio, real player time progression and nonzero metering, shared-session ownership, resuming, interruptions, and invalid media. UI tests use the actual Simulator app with a demo API and synthetic audio. They do not record a human voice through the Simulator microphone.

Initial test synchronization failures are retained rather than hidden. Final visual checks and the affected contrast retest are recorded in `verification.json` and the final screenshots.

## Limits and release status

This fix is included in the pending build 17 source. It has not been uploaded to TestFlight or submitted to App Review. Physical microphone capture, speaker audibility, Silent-mode playback, and wired/Bluetooth routing still need a real iPhone check. The user deferred connecting the iPhone for the separate review recording. Existing recordings were not inspected or modified; an already incomplete or silent upload may not be recoverable.

The candidate's separate content-safety backend deployment and release checks are recorded in `../preparation-status.json`. These audio changes require no server-code modification.

Apple references: [audio session behavior](https://developer.apple.com/documentation/avfaudio/avaudiosession), [record category](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record), and [explicit audio file close](https://developer.apple.com/documentation/avfaudio/avaudiofile/close%28%29?language=objc).
