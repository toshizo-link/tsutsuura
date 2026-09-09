# Local backend audio audit

No source file, production endpoint, existing account or user recording was
modified or accessed. `check-audio-roundtrip.py` copies current server source
into a disposable directory, runs PHP on loopback with its own SQLite/media,
and disables all email/SMS/push providers. Test publication time is changed
only in that disposable SQLite fixture.

`results.json` records exact audited server hashes and passing outcomes. The
four-second synthetic tone is generated as mono48kHz PCM, encoded by Apple's
`afconvert` into AAC/M4A, and remuxed into AAC/ADTS by ffmpeg. The multipart body
matches Swift's fields and framing. Real upload and media HTTP routes are used.

- M4A:20,947 bytes;4.0 seconds after Apple decode; RMS−10.39dBFS, peak−7.18dBFS.
- AAC/ADTS:18,181 bytes;4.05 seconds including codec padding; RMS−10.45dBFS.
- Both full downloads equal their input SHA256 and bytes exactly.
- Both reconstruct byte-for-byte from997-byte range chunks; suffix, open-ended,
  and two-byte ranges return206 with correct Content-Range. HEAD gives correct
  length/no body; missing authorization gives401; unsatisfiable range gives416.
- Apple decoding of both downloaded files succeeds and decoded sample energy
  is non-silent. No physical-device speaker output is claimed by this check.

Re-run locally:

```sh
python3 /tmp/tsutsuura-audio-server-audit/check-audio-roundtrip.py
```

The saved generated files are suitable for recorder/player regression tests:
`audible-apple.m4a`, `downloaded-audible-apple.m4a`, `audible-adts.aac`.
No source modification is recommended from the backend round-trip evidence.

## Source observations

Paths below are relative to the root project.

- `server/src/App/AnswerMediaService.php:377` accepts M4A by ftyp/MIME and
  normalizes it to `audio/mp4`; it does not transcode or adjust volume.
- `server/src/App/AnswerMediaService.php:543` copies exactly the uploaded byte
  count and fails/removes the incomplete file if storage copying fails.
- `server/src/App/AnswerMediaService.php:253` enforces family/safety/token
  visibility and actual stored size before returning a file. Failures are404.
- `server/src/Http/Response.php:45` supports authenticated file GET/HEAD with
  single byte ranges, correct MIME and lengths. It streams raw stored bytes.
- `server/public/index.php:624` accepts the same `audio` and
  `audioDurationMilliseconds` parts sent by `APIClient.swift:2411`.
- `tsutsuura/tsutsuura/APIClient.swift:1275` downloads the full media bytes with
  the bearer token; the current loader does not depend on HTTP Range playback.
- `tsutsuura/tsutsuura/AppModels.swift:633` agrees with the server's media JSON
  fields, including `audio/mp4`, byte count and optional duration.

One relevant limitation: server audio validation checks header/MIME/size, not
actual codec decodability, sample energy or decoded duration. Duration metadata
is supplied by the client. A recording already silent or incomplete with a
valid-looking header can therefore be accepted. Existing server smoke tests
(`server/bin/smoke-test.php:339`) intentionally use a synthetic M4A header, so
their prior success did not establish playable audio. This audit closes that
test-evidence gap for valid input; recorder/player checks remain necessary to
determine the actual user's symptom. Production web/proxy behavior is untested.
