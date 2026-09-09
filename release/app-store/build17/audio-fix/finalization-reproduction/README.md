# Retained AAC writer finalization reproduction

The old recorder captures a local `AVAudioFile` strongly in its audio tap, then
its stop path clears the owner's `audioFile` reference and immediately reads the
M4A bytes without explicit close. This standalone macOS AVFoundation reproduction
models a tap closure that remains retained/in flight. It uses generated mono
48kHz PCM tone data, the original AAC96kbps/high-quality settings and1024-frame
write buffers. It uses no microphone, user audio, app source edits or Simulator.

## Confirmed results

| Input duration | Before close bytes | Before Apple decode | After close bytes | After Apple decode |
| --- | ---: | --- | ---: | --- |
|0.05s /2400 frames|61,628|Fails1685348671|62,263|Exactly2400 frames, non-silent|
|0.5s /24000 frames|62,925|Fails1685348671|63,482|Exactly24000 frames, non-silent|
|4s /192000 frames|74,325|Fails1685348671|74,867|Exactly192000 frames, non-silent|

Before close, each copied upload snapshot has an `ftypM4A` header and an `mdat` section
but no `moov` metadata. PHP Fileinfo still recognizes it as `audio/x-m4a`, which
is allowed by the server's header/MIME validation. Clearing the owner's reference
does not finalize a file still retained by the closure. The old reported writer
length also trails the input:2048/23552/191488 frames, respectively.

Calling `close()` explicitly while the closure still retains the encoder adds
the final metadata/data. All copied snapshots then decode through AVAudioFile
to the exact input frame count, with RMS~0.283 and peak~0.408. This confirms the
file-lifetime mechanism can produce a successfully accepted but unplayable upload.

The control drops both closure and owner references without explicit close.
Encoder deinitialization finalizes it, and the control decodes correctly. The
failure therefore depends on a retained/in-flight writer; this experiment does
not prove that AVAudioEngine.removeTap retains the writer on every stop/device.
It also does not reproduce a concurrent write, so serialization of writing and
close remains a separate correctness requirement in the app fix.

## Reproduce

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -O -framework AVFoundation /tmp/tsutsuura-audio-finalization-repro/finalization.swift -o /tmp/tsutsuura-audio-finalization-repro/finalization
/tmp/tsutsuura-audio-finalization-repro/finalization /tmp/tsutsuura-audio-finalization-repro
```

`results.json` includes lifecycle booleans, byte counts, hashes, header checks,
and actual Apple decode/sample-energy outcomes. Before/after M4As are preserved.
`withExtendedLifetime` makes retained-closure lifetime explicit under optimization.
The decoder reads only remaining frames, avoiding an extra EOF read that this
host's AVAudioFile implementation throws on. Host:macOS27.0 Build26A5425a;
the local `/Applications/Xcode.app` toolchain is selected explicitly. `close()` is available
on macOS15+/iOS18+ in the installed SDK.
