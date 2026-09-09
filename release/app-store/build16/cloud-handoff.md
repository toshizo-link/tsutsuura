# Build 16 unsigned archive verified

Branch: `codex/appstore-build16`  
Commit: `46395223386f9ca11be87dd2de4d4a3f2ca98396`  
Run: https://github.com/toshizo-link/tsutsuura/actions/runs/33994819669  
Artifact ID: `9977746549`  
Artifact name: `tsutsuura-16-unsigned-46395223386f9ca11be87dd2de4d4a3f2ca98396`

Cloud host: macOS 26.6.2 (25G83), Xcode 26.6 (17F113), iOS SDK 26.5 (23F81a).

The complete frozen inventory contains 46 shipping inputs, including 27 Swift sources, plus 18 test files recorded separately. Root, isolated worktree, committed source, cloud source inventory and compiled Swift lists match. Source resources, app file hashes, arm64 binary/dSYM UUIDs and code/data sections verified. The frozen root remains unchanged apart from the authorized build-number bump, made before freezing the manifest.

Downloaded tar: `/tmp/tsutsuura-cloud16-download/tsutsuura-16-unsigned.tar.gz`  
SHA-256: `7c8e6e777d34d9f95fee79c9e832df7aff7736759c92a0692ef43d1246b2a185`  
Unsigned archive: `/tmp/tsutsuura-cloud16/tsutsuura-16-unsigned.xcarchive`  
Clean release worktree: `/tmp/tsutsuura-appstore-build16`

Exact successful verification command:

```sh
python3 /tmp/tsutsuura-build16-tools/tsutsuura-verify-cloud16.py cloud \
  --expected-commit 46395223386f9ca11be87dd2de4d4a3f2ca98396 \
  --expected-run-id 33994819669 \
  --cloud-tar /tmp/tsutsuura-cloud16-download/tsutsuura-16-unsigned.tar.gz \
  --output /tmp/tsutsuura-cloud16-verification.json
```

Exit code: 0. Output:

```json
{"status": "unsigned cloud archive verified; local signing/export pending", "failures": [], "saved": "/tmp/tsutsuura-cloud16-verification.json"}
```

Stopped before local signing and upload. The prepared signing helper is `/tmp/tsutsuura-build16-tools/tsutsuura-local-sign-cloud16.py`; its defaults point to the verified unsigned archive, a new `/tmp/tsutsuura-TestFlight-16.xcarchive`, and the immutable build 15 development profile. Preserve the cloud archive unchanged. After export/upload, run the prepared verifier's `export` or `upload` mode against the same commit/run and actual distribution log/receipt.

Durable QA evidence is in this build16 directory. Include `ios-push-validation/` in the signed archive's QA Verification directory: the final full unit bundle passed 217/217 and the finalized combined targeted/UI bundle passed 25/25, including four onboarding scenarios. Only simulator testing is claimed; this archive check does not establish APNs delivery or physical-device haptics.
