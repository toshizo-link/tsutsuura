#!/usr/bin/env python3
"""Copy a verified unsigned cloud archive and sign it locally for Xcode export.
No upload, no credential export, no changes to compiler/SDK/host provenance.
The source unsigned archive is preserved. Run only after cloud verification passes.
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

p = argparse.ArgumentParser()
p.add_argument('--unsigned', type=Path, required=True)
p.add_argument('--signed', type=Path, required=True)
p.add_argument('--development-archive', type=Path, default=Path('/tmp/tsutsuura-TestFlight-14.xcarchive'))
p.add_argument('--source-entitlements', type=Path, required=True)
p.add_argument('--evidence', type=Path, required=True)
a = p.parse_args()
assert a.unsigned.is_dir() and not a.signed.exists()
assert a.unsigned.resolve() != a.signed.resolve()

def plist(path):
    return plistlib.loads(path.read_bytes())

def capture(*args):
    r = subprocess.run(args, capture_output=True)
    if r.returncode:
        raise RuntimeError(Path(args[0]).name + ' failed; source unsigned archive is preserved')
    return r.stdout

app_relative = Path('Products/Applications/tsutsuura.app')
source_app = a.unsigned / app_relative
old_app = a.development_archive / app_relative
compiled_info_bytes = (source_app / 'Info.plist').read_bytes()
compiled_info = plistlib.loads(compiled_info_bytes)
assert compiled_info['CFBundleVersion'] == '15'
assert compiled_info['CFBundleIdentifier'] == 'toshizo.link.tsutsuura'
assert compiled_info['DTXcodeBuild'] == '17F113'
assert compiled_info['BuildMachineOSBuild'].startswith('25')
assert not (source_app / 'embedded.mobileprovision').exists()
# This app has no nested code bundles. Stop if future builds introduce them.
assert not any(source_app.rglob('*.framework'))
assert not any(source_app.rglob('*.appex'))
assert not any(source_app.rglob('*.dylib'))
assert subprocess.run(['codesign', '--verify', str(source_app)], capture_output=True).returncode != 0

old_archive_info = plist(a.development_archive / 'Info.plist')
identity = old_archive_info['ApplicationProperties']['SigningIdentity']
assert identity.startswith('Apple Development: ')
assert old_archive_info['ApplicationProperties']['Team'] == '34NS8XN5F9'
profile_path = old_app / 'embedded.mobileprovision'
profile = plistlib.loads(capture('security', 'cms', '-D', '-i', str(profile_path)))
capture('codesign', '--verify', '--deep', '--strict', str(old_app))
with tempfile.TemporaryDirectory(prefix='tsutsuura-public-signing-cert-') as temp:
    prefix = str(Path(temp) / 'certificate-')
    capture('codesign', '-d', '--extract-certificates=' + prefix, str(old_app))
    development_certificate = Path(prefix + '0').read_bytes()
assert development_certificate in profile['DeveloperCertificates'], 'Development certificate is absent from profile'
assert profile['ExpirationDate'].replace(tzinfo=dt.timezone.utc) > dt.datetime.now(dt.timezone.utc)
assert '34NS8XN5F9' in profile['TeamIdentifier']
assert profile['Entitlements']['application-identifier'] == '34NS8XN5F9.toshizo.link.tsutsuura'
entitlements_bytes = capture('codesign', '-d', '--entitlements', ':-', str(old_app))
entitlements = plistlib.loads(entitlements_bytes)
assert entitlements['application-identifier'] == '34NS8XN5F9.toshizo.link.tsutsuura'
assert entitlements['com.apple.developer.team-identifier'] == '34NS8XN5F9'
assert entitlements.get('get-task-allow') is True
for key, value in plist(a.source_entitlements).items():
    assert entitlements.get(key) == value, 'Development entitlements differ from verified source: ' + key

capture('ditto', str(a.unsigned), str(a.signed))
app = a.signed / app_relative
shutil.copy2(profile_path, app / 'embedded.mobileprovision')
entitlement_file = a.signed.parent / (a.signed.name + '.development-entitlements.plist')
entitlement_file.write_bytes(entitlements_bytes)
entitlement_file.chmod(0o600)
capture('codesign', '--force', '--sign', identity, '--entitlements', str(entitlement_file), str(app))
capture('codesign', '--verify', '--deep', '--strict', str(app))
with tempfile.TemporaryDirectory(prefix='tsutsuura-public-signing-cert-') as temp:
    prefix = str(Path(temp) / 'certificate-')
    capture('codesign', '-d', '--extract-certificates=' + prefix, str(app))
    assert Path(prefix + '0').read_bytes() == development_certificate, 'Different development identity selected'
# These two fields describe the signature genuinely applied above, not compilation.
archive_info = plist(a.signed / 'Info.plist')
archive_info['ApplicationProperties']['SigningIdentity'] = identity
archive_info['ApplicationProperties']['Team'] = '34NS8XN5F9'
(a.signed / 'Info.plist').write_bytes(plistlib.dumps(archive_info))
assert (app / 'Info.plist').read_bytes() == compiled_info_bytes
result = {'signedAt': dt.datetime.now(dt.timezone.utc).isoformat(),
          'unsignedArchive': str(a.unsigned), 'signedArchive': str(a.signed),
          'signatureVerified': True, 'compiledInfoUnchanged': True,
          'compiledInfoSHA256': hashlib.sha256(compiled_info_bytes).hexdigest(),
          'developmentProfileUUID': profile['UUID'], 'developmentProfileExpiration': profile['ExpirationDate'].isoformat(),
          'buildMetadata': {key: compiled_info.get(key) for key in ['BuildMachineOSBuild', 'DTXcode', 'DTXcodeBuild', 'DTSDKBuild', 'DTSDKName', 'DTPlatformBuild', 'DTPlatformVersion']}}
a.evidence.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: value for key, value in result.items() if key != 'developmentProfileUUID'}, indent=2))
