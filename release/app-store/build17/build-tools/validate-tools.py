#!/usr/bin/env python3
"""Local syntax and reject-before-sign smoke checks. No Apple credentials used."""
import ast
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile

root = Path(__file__).resolve().parent
workflow = json.loads(subprocess.check_output(['ruby', '-ryaml', '-rjson', '-e', 'puts JSON.generate(YAML.load_file(ARGV[0]))', str(root/'supported-build17.yml')], text=True))
checks = []
assert workflow['jobs']['unsigned-archive']['runs-on'] == 'macos-26'
assert workflow['jobs']['unsigned-archive']['env']['DEVELOPER_DIR'] == '/Applications/Xcode_26.6.app/Contents/Developer'
assert workflow['permissions'] == {'contents': 'read'}
for step in workflow['jobs']['unsigned-archive']['steps']:
    if 'run' not in step:
        continue
    run = step['run']
    subprocess.run(['bash', '-n'], input=run, text=True, check=True)
    lines = run.splitlines()
    for index, line in enumerate(lines):
        if line == "python3 - <<'PY'":
            end = lines.index('PY', index + 1)
            ast.parse('\n'.join(lines[index+1:end]))
checks.append('workflow shell and embedded Python syntax valid; exact stable runner/Xcode and read-only token scope')
for name in ['tsutsuura-verify-cloud17.py', 'tsutsuura-local-sign-cloud17.py']:
    ast.parse((root/name).read_text())
    subprocess.run(['python3', str(root/name), '--help'], check=True, stdout=subprocess.DEVNULL)
checks.append('verifier and signing helper syntax/argument parsers valid')
with tempfile.TemporaryDirectory(prefix='tsutsuura-build17-tools-fixture-') as directory:
    d = Path(directory)
    unsigned = d/'unsigned.xcarchive'
    app = unsigned/'Products/Applications/tsutsuura.app'
    app.mkdir(parents=True)
    info = {'CFBundleVersion':'17', 'CFBundleIdentifier':'toshizo.link.tsutsuura', 'DTXcodeBuild':'17F113',
            'BuildMachineOSBuild':'25G83', 'DTXcode':'2660', 'DTSDKBuild':'23F81a', 'DTSDKName':'iphoneos26.5',
            'DTPlatformBuild':'23F81a', 'API_BASE_URL':'https://toshizo.link/tsutsuura-api/api',
            'CFBundleShortVersionString':'1.0', 'MinimumOSVersion':'26.2', 'UIDeviceFamily':[1]}
    (app/'Info.plist').write_bytes(plistlib.dumps(info))
    entitlements=d/'source.entitlements'; entitlements.write_bytes(plistlib.dumps({}))
    verification={'mode':'cloud', 'build':'17', 'failures':[], 'status':'unsigned cloud archive verified; local signing/export pending',
        'artifacts':{'unsignedArchive':str(unsigned)}, 'bundleIdentifier':'toshizo.link.tsutsuura',
        'apiBaseURL':'https://toshizo.link/tsutsuura-api/api', 'cloudAppFiles':{'Info.plist':'0'*64},
        'sources':{'tsutsuura/tsutsuura/tsutsuura.entitlements':hashlib.sha256(entitlements.read_bytes()).hexdigest()}}
    record=d/'verification.json'; record.write_text(json.dumps(verification))
    command=['python3',str(root/'tsutsuura-local-sign-cloud17.py'),'--cloud-verification',str(record),
             '--unsigned',str(unsigned),'--signed',str(d/'signed.xcarchive'),
             '--development-archive',str(d/'does-not-exist.xcarchive'),'--source-entitlements',str(entitlements),
             '--evidence',str(d/'sign-evidence.json')]
    result=subprocess.run(command,capture_output=True,text=True)
    assert result.returncode != 0 and 'Unsigned app changed after cloud verification' in result.stderr
    assert not (d/'signed.xcarchive').exists() and not (d/'sign-evidence.json').exists()
    checks.append('modified unsigned app is rejected before copying or reading a development identity')
    info['CFBundleVersion']='16'; (app/'Info.plist').write_bytes(plistlib.dumps(info))
    result=subprocess.run(command,capture_output=True,text=True)
    assert result.returncode != 0 and "compiled_info['CFBundleVersion'] == '17'" in result.stderr
    assert not (d/'signed.xcarchive').exists()
    checks.append('wrong build is rejected before copying or signing')
result={'verifiedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(), 'build':'17', 'checks':checks,
        'actualBuild17ArchiveTested':False, 'sourceFreezeMade':False, 'cloudBuildDispatched':False,
        'signingPerformed':False, 'uploadPerformed':False,
        'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.iterdir()) if p.is_file() and p.name!='tool-preparation-verification.json'}}
(root/'tool-preparation-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'checksPassed':len(checks),'actualBuild17ArchiveTested':False,'output':str(root/'tool-preparation-verification.json')}))
