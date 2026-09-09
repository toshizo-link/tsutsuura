# Build 17 release tools — prepared, not dispatched

These adapt the proven build16 workflow and verifier/signing helper. Root must finish the safety tests, select final build17 sources and freeze their manifest before committing or starting a build. Nothing here has committed, pushed, compiled an app, signed an app or uploaded to Apple.

- `supported-build17.yml`: install as the build17 workflow only when source is ready. Trigger is limited to `codex/appstore-build17`. Uses GitHub `macos-26`, Xcode26.6 (17F113), iPhoneOS26.5 (23F81a), a stable macOS26.2–26.x build (`25[A-Z][0-9]+`), pinned checkout/artifact actions and a read-only token. The runner archives unsigned and gets no Apple credentials.
- `tsutsuura-verify-cloud17.py`: `cloud`, `export` and `upload` stages retain the existing exact source/commit, compiler SwiftFileList, app/resource hash, arm64 binary/dSYM UUID, executable-section, API/domain, team, production APNs and receipt checks. Source count is inventory-based and will include the new safety file and bundled notices. Expected bundle `toshizo.link.tsutsuura`, team `34NS8XN5F9`, app ID `6800383132`, version1.0/build17 and API `https://toshizo.link/tsutsuura-api/api`.
- `tsutsuura-local-sign-cloud17.py`: requires a successful `--cloud-verification` JSON and rechecks the exact unsigned app hashes, compiled metadata and source entitlements before copying/signing. Uses a local existing development archive/profile/certificate (default build16 archive); final App Store export stays local. Never edits compiled host/SDK metadata. Only archive ApplicationProperties SigningIdentity/Team reflect the signature actually applied.
- `validate-tools.py`: syntax and reject-before-sign fixtures. Four checks passed; it does not validate an actual build17 archive. Evidence is `tool-preparation-verification.json`.

Additional build17 resource checks require all three files from `tsutsuura/tsutsuura/ThirdPartyNotices/`: `ThirdPartyNotices.txt`, `MaterialDesignIconsLicense.txt`, `KaisotaiNotice.txt`. Exactly one copy of each must exist at bundle root or in its `ThirdPartyNotices` folder, and its bytes must match frozen source hashes.

The frozen manifest must record `snapshotAt` before the archive, `sourceFreezeConfirmed:true`, version/build/API/associatedDomains, and `sources` with the project plus every non-hidden file recursively under `tsutsuura/tsutsuura` (same inventory used in the cloud workflow). It must be outside the source tree. Do not reuse the build16 source manifest or treat the current evolving worktree as frozen.

After root coordinates the exact commit/run and downloads/extracts the artifact safely, use explicit paths (replace COMMIT and RUN_ID with observed values):

```sh
python3 /tmp/tsutsuura-build17-tools/tsutsuura-verify-cloud17.py cloud \
  --root /tmp/tsutsuura-appstore-review-safety \
  --manifest /tmp/tsutsuura-build17-source-manifest.json \
  --expected-commit COMMIT --expected-run-id RUN_ID \
  --cloud-root /tmp/tsutsuura-cloud17 \
  --cloud-tar /tmp/tsutsuura-cloud17-download/tsutsuura-17-unsigned.tar.gz \
  --output /tmp/tsutsuura-cloud17-verification.json

python3 /tmp/tsutsuura-build17-tools/tsutsuura-local-sign-cloud17.py \
  --cloud-verification /tmp/tsutsuura-cloud17-verification.json \
  --unsigned /tmp/tsutsuura-cloud17/tsutsuura-17-unsigned.xcarchive \
  --signed /tmp/tsutsuura-TestFlight-17.xcarchive \
  --development-archive /tmp/tsutsuura-TestFlight-16.xcarchive \
  --source-entitlements /tmp/tsutsuura-cloud17/evidence/source.entitlements \
  --evidence /tmp/tsutsuura-build17-local-signing-verification.json
```

Run the verifier again in `export` mode against actual local distribution app/IPA paths or Xcode export log, then `upload` mode against the actual upload log and signed archive receipt. An accepted upload only proves the upload stage; separately verify Apple processing, TestFlight availability and App Review state. Physical safety recording and real email-inbox proof remain separate outstanding work.
