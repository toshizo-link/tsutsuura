#!/usr/bin/env python3
"""Read-only audit of the supported-host build 17 and its local distribution.

No signing, extraction, compilation, upload, network, source edits, or archive edits.
Only --output is written. Keep the downloaded cloud archive immutable; sign a copy.

cloud: verify extracted cloud artifact against frozen sources and exact git commit.
export: additionally verify a signed distribution app and its IPA against cloud code.
upload: additionally verify Xcode's successful Apple upload receipt.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import struct
import subprocess
import sys
import zipfile

BUNDLE='toshizo.link.tsutsuura'
TEAM='34NS8XN5F9'
ADAM='6800383132'
API='https://toshizo.link/tsutsuura-api/api'
DOMAINS=['applinks:toshizo.link']
APP_SOURCE=Path('tsutsuura/tsutsuura')
PROJECT=Path('tsutsuura/tsutsuura.xcodeproj/project.pbxproj')
TOOL_FIELDS=('BuildMachineOSBuild','DTCompiler','DTPlatformBuild','DTPlatformName','DTPlatformVersion','DTSDKBuild','DTSDKName','DTXcode','DTXcodeBuild')


def sha(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''): h.update(chunk)
    return h.hexdigest()


def digest(data): return hashlib.sha256(data).hexdigest()


def load_json(path): return json.loads(Path(path).read_text())


def load_plist(path): return plistlib.loads(Path(path).read_bytes())


def command(args):
    p=subprocess.run([str(a) for a in args],capture_output=True,timeout=60)
    if p.returncode: raise RuntimeError(Path(str(args[0])).name+' read-only verification command failed')
    return p.stdout


def date(value):
    result=value if isinstance(value,dt.datetime) else dt.datetime.fromisoformat(value.replace('Z','+00:00'))
    return result if result.tzinfo else result.replace(tzinfo=dt.timezone.utc)


def source_hashes(root):
    paths=[PROJECT]
    paths += [p.relative_to(root) for p in (root/APP_SOURCE).rglob('*') if p.is_file() and not any(x.startswith('.') for x in p.relative_to(root/APP_SOURCE).parts)]
    return {str(p):sha(root/p) for p in sorted(paths)}


def file_hashes(root):
    return {str(p.relative_to(root)):sha(p) for p in sorted(root.rglob('*')) if p.is_file()}


def uuids(text):
    return {(u.upper(),a) for u,a in re.findall(r'UUID: ([A-Fa-f0-9-]+) \(([^)]+)\)',text)}


def macho_sections(data):
    """Hash all file-backed Mach-O sections, excluding only zero-fill sections.

    Signing/stripSwiftSymbols can change load commands and __LINKEDIT tables;
    executable code and runtime data sections must remain byte-for-byte identical.
    """
    if len(data)<32 or struct.unpack_from('<I',data)[0]!=0xfeedfacf:
        raise RuntimeError('Expected a single 64-bit little-endian Mach-O')
    cpu=struct.unpack_from('<I',data,4)[0]
    if cpu!=0x0100000c: raise RuntimeError('Expected arm64 Mach-O')
    ncmds,sizeofcmds=struct.unpack_from('<II',data,16)
    pos=32; end=32+sizeofcmds; result={}
    if end>len(data): raise RuntimeError('Truncated Mach-O load commands')
    for _ in range(ncmds):
        if pos+8>end: raise RuntimeError('Truncated Mach-O command')
        cmd,size=struct.unpack_from('<II',data,pos)
        if size<8 or pos+size>end: raise RuntimeError('Invalid Mach-O command size')
        if cmd==0x19:
            if size<72: raise RuntimeError('Truncated Mach-O segment')
            nsects=struct.unpack_from('<I',data,pos+64)[0]
            if 72+nsects*80>size: raise RuntimeError('Truncated Mach-O sections')
            for index in range(nsects):
                at=pos+72+index*80
                name=data[at:at+16].split(b'\0',1)[0].decode()
                segment=data[at+16:at+32].split(b'\0',1)[0].decode()
                length=struct.unpack_from('<Q',data,at+40)[0]
                offset=struct.unpack_from('<I',data,at+48)[0]
                flags=struct.unpack_from('<I',data,at+64)[0]
                if flags&0xff in (1,12,18): continue
                if offset+length>len(data): raise RuntimeError('Mach-O section exceeds file')
                key=segment+','+name
                if key in result: raise RuntimeError('Duplicate Mach-O section')
                result[key]={'size':length,'sha256':digest(data[offset:offset+length])}
        pos+=size
    if '__TEXT,__text' not in result: raise RuntimeError('Missing Mach-O executable text section')
    return result


def compile_sources(lines,checkout):
    root=PurePosixPath(checkout)
    generated=root/'build/DerivedData/Build/Intermediates.noindex/ArchiveIntermediates/tsutsuura/IntermediateBuildFilesPath/tsutsuura.build/Release-iphoneos/tsutsuura.build/DerivedSources/GeneratedAssetSymbols.swift'
    result=set(); ignored=[]
    for line in lines.splitlines():
        if not line.strip(): continue
        p=PurePosixPath(line.strip().strip('"'))
        if p==generated: ignored.append(str(p)); continue
        try: relative=p.relative_to(root)
        except ValueError: raise RuntimeError('Compiler source lies outside recorded cloud checkout')
        if '..' in relative.parts: raise RuntimeError('Compiler source escapes recorded checkout')
        result.add(str(relative))
    return result,ignored


class Audit:
    def __init__(self,mode):
        self.failures=[]
        self.data={'verifiedAt':dt.datetime.now(dt.timezone.utc).isoformat(),'mode':mode,'version':'1.0','build':'17','bundleIdentifier':BUNDLE,'apiBaseURL':API,'associatedDomains':DOMAINS}
    def check(self,condition,label):
        if not condition: self.failures.append(label)
        return condition
    def require(self,condition,label):
        if not condition: raise RuntimeError(label)


def verify_cloud(args,a):
    manifest=load_json(args.manifest)
    expected=manifest['sources']; local=source_hashes(args.root)
    a.require(isinstance(expected,dict) and bool(expected),'Frozen source manifest must contain a nonempty shipping-file inventory')
    a.require(all(isinstance(p,str) and isinstance(h,str) and re.fullmatch(r'[a-f0-9]{64}',h) for p,h in expected.items()),'Frozen source manifest contains malformed paths or SHA-256 hashes')
    a.require(str(PROJECT) in expected and any(p.endswith('.swift') for p in expected),'Frozen source manifest is missing its project or Swift sources')
    if 'sourceCount' in manifest:
        a.check(manifest['sourceCount']==len(expected),'Frozen source manifest count differs from its inventory')
    a.check(manifest.get('build')=='17' and manifest.get('version')=='1.0','Frozen source manifest version/build differs')
    a.check(manifest.get('apiBaseURL')==API and manifest.get('associatedDomains')==DOMAINS,'Frozen source configuration differs')
    a.check(local==expected,'Local shipping sources changed after freeze')
    commit=args.expected_commit.lower()
    a.require(re.fullmatch(r'[0-9a-f]{40}',commit) is not None,'Expected commit must be a full 40-character git SHA')
    resolved=command(['git','-C',args.root,'rev-parse',commit+'^{commit}']).decode().strip()
    a.check(resolved==commit,'Expected git revision does not resolve exactly')
    git_sources={p:digest(command(['git','-C',args.root,'show',commit+':'+p])) for p in expected}
    a.check(git_sources==expected,'Committed shipping sources differ from frozen manifest')
    versions=re.findall(r'CURRENT_PROJECT_VERSION\s*=\s*([^;]+);',(args.root/PROJECT).read_text())
    a.check(len(versions)==6 and all(v.strip()=='17' for v in versions),'Project target build numbers differ')
    evidence=args.cloud_root/'evidence'
    env=load_json(evidence/'source-and-environment.json')
    record=load_json(evidence/'archive-verification.json')
    a.check(env.get('gitCommit')==commit,'Cloud git commit differs from requested commit')
    a.check(env.get('sources')==expected,'Cloud source hashes differ from frozen manifest')
    a.check(env.get('sourceCount')==len(expected),'Cloud source count differs from frozen manifest inventory')
    a.check(env.get('build')=='17' and env.get('version')=='1.0','Cloud record version/build differs')
    os_version=tuple(int(p) for p in env['osVersion'].split('.'))
    a.check(os_version[0]==26 and os_version>=(26,2),'Cloud host is outside supported macOS 26.2–26.x')
    a.check(re.fullmatch(r'25[A-Z][0-9]+',env['osBuild']) is not None,'Cloud host is not a stable macOS 26 build')
    a.check(env.get('xcode')=='Xcode 26.6\nBuild version 17F113','Cloud Xcode is not pinned release 26.6 (17F113)')
    a.check(env.get('sdkVersion')=='26.5','Cloud SDK is not the pinned iOS 26.5 SDK')
    a.check(env.get('sdkBuild')=='23F81a','Cloud SDK is not the pinned iOS 26.5 build 23F81a')
    a.check(bool(re.fullmatch(r'[0-9]+',str(env.get('githubRunId','')))),'Cloud GitHub run ID missing')
    a.check(bool(re.fullmatch(r'[0-9]+',str(env.get('githubRunAttempt','')))),'Cloud GitHub run attempt missing')
    if args.expected_run_id: a.check(str(env.get('githubRunId'))==args.expected_run_id,'Cloud GitHub run ID differs')
    checkout=env.get('checkoutRoot')
    a.require(isinstance(checkout,str) and checkout.startswith('/'),'Cloud checkoutRoot missing or non-absolute')
    a.check(record.get('sourceHashesUnchanged') is True and record.get('compilerSourcesMatch') is True,'Cloud archive checks did not pass')
    a.check(record.get('unsigned') is True,'Cloud archive did not record disabled signing')
    archive=args.cloud_root/'tsutsuura-17-unsigned.xcarchive'
    app=archive/'Products/Applications/tsutsuura.app'
    archive_info=load_plist(archive/'Info.plist'); info=load_plist(app/'Info.plist')
    a.check(date(manifest['snapshotAt'])<=date(env['snapshotAt'])<=date(archive_info['CreationDate']),'Source snapshots were not made before cloud archive creation')
    a.check(load_plist(evidence/'compiled-app-info.plist')==info,'Copied cloud app Info.plist differs from unsigned archive')
    a.check(load_plist(evidence/'unsigned-archive-info.plist')==archive_info,'Copied cloud archive Info.plist differs')
    properties=archive_info.get('ApplicationProperties',{})
    a.check(properties.get('CFBundleVersion')=='17','Unsigned archive metadata build differs')
    a.check(properties.get('CFBundleIdentifier')==BUNDLE,'Unsigned archive bundle ID differs')
    a.check(info.get('CFBundleVersion')=='17' and info.get('CFBundleShortVersionString')=='1.0','Unsigned app version/build differs')
    a.check(info.get('CFBundleIdentifier')==BUNDLE and info.get('API_BASE_URL')==API,'Unsigned app identity/API differs')
    a.check(info.get('BuildMachineOSBuild')==env['osBuild'],'Compiled app host build differs from stable cloud host')
    a.check(info.get('DTXcode')=='2660' and info.get('DTXcodeBuild')=='17F113','Compiled app Xcode metadata differs')
    a.check(info.get('DTSDKName')=='iphoneos26.5' and info.get('DTSDKBuild')==env['sdkBuild'],'Compiled app SDK metadata differs')
    a.check(info.get('DTPlatformBuild')==env['sdkBuild'] and info.get('DTPlatformName')=='iphoneos','Compiled app platform metadata differs')
    a.check(info.get('MinimumOSVersion')=='26.2','Minimum iOS version differs')
    a.check(info.get('UIDeviceFamily')==[1],'App device families differ')
    a.check(not (app/'embedded.mobileprovision').exists() and not (app/'_CodeSignature').exists(),'Cloud archive must remain unsigned and unmodified')
    signature=subprocess.run(['/usr/bin/codesign','--verify',str(app)],capture_output=True,timeout=45)
    a.check(signature.returncode!=0,'Cloud archive unexpectedly has a valid signature')
    appfiles=file_hashes(app)
    a.require(isinstance(record.get('appFiles'),dict),'Cloud appFiles hash inventory missing')
    a.check(record['appFiles']==appfiles,'Unsigned archive app file hashes differ from cloud evidence')
    for source,target in [('PrivacyInfo.xcprivacy','PrivacyInfo.xcprivacy'),('Fonts/Kaisotai-Next-UP-B.otf','Kaisotai-Next-UP-B.otf')]:
        a.check(expected[str(APP_SOURCE/source)]==sha(app/target),'Archived source resource differs: '+target)
    for name in ['ThirdPartyNotices.txt','MaterialDesignIconsLicense.txt','KaisotaiNotice.txt']:
        copied=[p for p in [app/name,app/'ThirdPartyNotices'/name] if p.is_file()]
        a.require(len(copied)==1,'Missing or duplicate bundled notice: '+name)
        a.check(expected[str(APP_SOURCE/'ThirdPartyNotices'/name)]==sha(copied[0]),'Archived notice differs from frozen source: '+name)
    a.check((app/'Assets.car').is_file(),'Compiled asset catalog missing')
    a.check(sha(evidence/'source.entitlements')==expected[str(APP_SOURCE/'tsutsuura.entitlements')],'Cloud source entitlements differ')
    source_entitlements=load_plist(evidence/'source.entitlements')
    a.check(source_entitlements.get('com.apple.developer.associated-domains')==DOMAINS,'Source associated domains differ')
    a.check(source_entitlements.get('aps-environment') in ('development','production'),'Source APNs entitlement absent')
    expected_swift={p for p in expected if p.endswith('.swift')}
    lists=list(evidence.glob('*-tsutsuura.SwiftFileList'))
    a.require(bool(lists),'Cloud SwiftFileList missing')
    compiler_evidence=[]
    for p in lists:
        actual,ignored=compile_sources(p.read_text(),checkout)
        a.check(actual==expected_swift,'Cloud compiled source list differs: '+p.name)
        compiler_evidence.append({'file':str(p),'sha256':sha(p),'sourceCount':len(actual),'generatedFiles':ignored})
    binary=app/info['CFBundleExecutable']; dsym=archive/'dSYMs/tsutsuura.app.dSYM'
    binary_ids=uuids(command(['/usr/bin/dwarfdump','--uuid',binary]).decode())
    dsym_ids=uuids(command(['/usr/bin/dwarfdump','--uuid',dsym]).decode())
    a.check(bool(binary_ids) and binary_ids==dsym_ids and {arch for _,arch in binary_ids}=={'arm64'},'Unsigned binary/dSYM arm64 UUIDs differ')
    a.check(uuids(record.get('binaryUUIDs',''))==binary_ids and uuids(record.get('dSYMUUIDs',''))==dsym_ids,'UUIDs differ from cloud evidence')
    sections=macho_sections(binary.read_bytes())
    if args.cloud_tar:
        sidecar=Path(str(args.cloud_tar)+'.sha256')
        expected_tar=sidecar.read_text().split()[0]
        a.check(re.fullmatch(r'[a-f0-9]{64}',expected_tar) is not None and sha(args.cloud_tar)==expected_tar,'Downloaded cloud tar SHA-256 differs')
        a.data['cloudTar']={'path':str(args.cloud_tar),'sha256':sha(args.cloud_tar)}
    a.data.update({'expectedGitCommit':commit,'sourceManifest':str(args.manifest),'sourceManifestSHA256':sha(args.manifest),'sources':expected,'sourceCount':len(expected),'cloudEnvironment':{k:v for k,v in env.items() if k!='sources'},'cloudEvidenceSHA256':sha(evidence/'source-and-environment.json'),'cloudArchiveEvidenceSHA256':sha(evidence/'archive-verification.json'),'cloudAppFiles':appfiles,'compiledSwiftFiles':compiler_evidence,'binaryUUIDs':sorted(binary_ids),'binarySections':sections,'cloudToolMetadata':{k:info.get(k) for k in TOOL_FIELDS},'artifacts':{'cloudRoot':str(args.cloud_root),'unsignedArchive':str(archive),'unsignedApp':str(app)}})
    return app,info,sections,binary_ids


def distribution_paths(args,a):
    if args.distribution_app and args.ipa: return args.distribution_app,args.ipa
    a.require(args.upload_log is not None,'Provide --distribution-app and --ipa, or --upload-log')
    log=args.upload_log.read_text()
    dirs=re.findall(r'Created bundle at path "([^"]+\.xcdistributionlogs)"',log)
    a.require(bool(dirs),'Xcode distribution-log directory missing')
    logs=Path(dirs[-1]); pipeline=(logs/'IDEDistributionPipeline.log').read_text()
    apps=re.findall(r"'([^'\n]+/Root/Payload/tsutsuura\.app)'",pipeline)
    ipas=re.findall(r"'([^'\n]+/Packages/tsutsuura\.ipa)'",pipeline)
    a.require(bool(apps) and bool(ipas),'Actual signed app/IPA paths missing from distribution logs')
    a.data['artifacts'].update({'distributionLogs':str(logs),'exportOrUploadLog':str(args.upload_log)})
    return Path(apps[-1]),Path(ipas[-1])


def verify_export(args,a,cloud):
    unsigned,original,sections,binary_ids=cloud
    app,ipa=distribution_paths(args,a); info=load_plist(app/'Info.plist')
    a.check(all(info.get(k)==v for k,v in original.items()),'Local export changed compiled app metadata')
    command(['/usr/bin/codesign','--verify','--deep','--strict',app])
    ent=plistlib.loads(command(['/usr/bin/codesign','-d','--entitlements',':-',app]))
    checks={'application-identifier':TEAM+'.'+BUNDLE,'com.apple.developer.associated-domains':DOMAINS,'aps-environment':'production','get-task-allow':False,'beta-reports-active':True}
    for key,value in checks.items(): a.check(ent.get(key)==value,'Distribution entitlement differs: '+key)
    profile=plistlib.loads(command(['/usr/bin/security','cms','-D','-i',app/'embedded.mobileprovision']))
    a.check(profile.get('TeamIdentifier')==[TEAM],'Distribution provisioning team differs')
    a.check(date(profile['ExpirationDate'])>dt.datetime.now(dt.timezone.utc),'Distribution profile expired')
    a.check('ProvisionedDevices' not in profile and not profile.get('ProvisionsAllDevices'),'Distribution profile is not an App Store profile')
    p_ent=profile.get('Entitlements',{})
    a.check(p_ent.get('application-identifier')==TEAM+'.'+BUNDLE and p_ent.get('get-task-allow') is False and p_ent.get('aps-environment')=='production','Distribution profile app/debug/APNs differs')
    runtime_files=lambda root:{k:v for k,v in file_hashes(root).items() if k not in ('Info.plist',original['CFBundleExecutable'],'embedded.mobileprovision') and not k.startswith('_CodeSignature/')}
    a.check(runtime_files(app)==runtime_files(unsigned),'Distribution app resources differ from verified cloud app')
    binary=app/info['CFBundleExecutable']
    a.check(macho_sections(binary.read_bytes())==sections,'Distribution executable code/data differs from cloud binary')
    a.check(uuids(command(['/usr/bin/dwarfdump','--uuid',binary]).decode())==binary_ids,'Distribution executable UUID differs from cloud binary')
    disk=file_hashes(app)
    with zipfile.ZipFile(ipa) as z:
        a.check(z.testzip() is None,'IPA has corrupt ZIP entries')
        prefix='Payload/tsutsuura.app/'
        entries=[n for n in z.namelist() if n.startswith(prefix) and not n.endswith('/')]
        a.check(len(entries)==len(set(entries)),'IPA contains duplicate app entries')
        payload={n[len(prefix):]:digest(z.read(n)) for n in entries}
        a.check(payload==disk,'IPA payload differs from verified distribution app')
    a.data.update({'distributionSignatureVerified':True,'distributionEntitlements':{k:ent.get(k) for k in checks},'distributionProfileExpiration':date(profile['ExpirationDate']).isoformat(),'compiledMetadataPreserved':all(info.get(k)==v for k,v in original.items()),'distributionBinarySectionsMatch':macho_sections(binary.read_bytes())==sections,'ipaSHA256':sha(ipa),'uploadedIPAFileContentMatches':payload==disk})
    a.data['artifacts'].update({'distributionApp':str(app),'ipa':str(ipa)})


def verify_upload(args,a):
    a.require(args.upload_log is not None and args.signed_archive is not None,'Upload verification requires --upload-log and --signed-archive')
    log=args.upload_log.read_text()
    a.check('** EXPORT SUCCEEDED **' in log and 'Upload succeeded.' in log,'Upload log lacks successful completion')
    info=load_plist(args.signed_archive/'Info.plist')
    receipts=[r for r in info.get('Distributions',[]) if str(r.get('uploadedBuildNumber'))=='17' and str(r.get('adamId'))==ADAM]
    a.require(bool(receipts),'Matching Apple build 17 receipt missing')
    receipt=receipts[-1]; event=receipt.get('uploadEvent',{})
    a.check(receipt.get('teamID')==TEAM and receipt.get('destination')=='upload','Apple receipt team/destination differs')
    a.check(event.get('state')=='success' and event.get('title')=='Uploaded to Apple','Apple receipt does not confirm successful upload')
    a.check(event.get('errors')==[] and event.get('warnings')==[],'Apple upload receipt contains errors/warnings')
    a.check(event.get('date') is not None,'Apple upload receipt date missing')
    a.data['upload']={'adamId':ADAM,'build':'17','event':{k:(v.isoformat() if isinstance(v,dt.datetime) else v) for k,v in event.items() if k in ('date','state','title','errors','warnings')},'processingReported':'Uploaded package is processing.' in log,'testerAvailabilityVerified':False,'appReviewAcceptanceVerified':False}
    a.data['artifacts']['signedArchive']=str(args.signed_archive)


def main():
    parser=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('mode',choices=('cloud','export','upload'))
    parser.add_argument('--root',type=Path,default=Path('/tmp/tsutsuura-appstore-build17'))
    parser.add_argument('--manifest',type=Path,default=Path('/tmp/tsutsuura-build17-source-manifest.json'))
    parser.add_argument('--expected-commit',required=True)
    parser.add_argument('--expected-run-id')
    parser.add_argument('--cloud-root',default=Path('/tmp/tsutsuura-cloud17'),type=Path,help='Extracted tar root containing evidence/ and tsutsuura-17-unsigned.xcarchive/')
    parser.add_argument('--cloud-tar',type=Path,help='Optional downloaded tar.gz with adjacent .sha256 sidecar')
    parser.add_argument('--distribution-app',type=Path)
    parser.add_argument('--ipa',type=Path)
    parser.add_argument('--upload-log',type=Path,help='Xcode export/upload log; can locate actual distribution app/IPA automatically')
    parser.add_argument('--signed-archive',type=Path,default=Path('/tmp/tsutsuura-TestFlight-17.xcarchive'),help='Locally signed archive copy containing upload receipt')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(); a=Audit(args.mode)
    try:
        output=args.output.resolve()
        protected=[args.root.resolve(),args.cloud_root.resolve(),args.manifest.resolve()]
        if args.signed_archive: protected.append(args.signed_archive.resolve())
        if any(output==p or p in output.parents for p in protected): raise RuntimeError('Output must be outside source/manifest/archive directories')
        cloud=verify_cloud(args,a)
        if args.mode in ('export','upload'): verify_export(args,a,cloud)
        if args.mode=='upload': verify_upload(args,a)
        a.check(source_hashes(args.root)==a.data['sources'],'Shipping sources changed during verification')
    except Exception as error:
        a.failures.append(str(error) if isinstance(error,RuntimeError) else type(error).__name__+': verification input missing or malformed')
    a.data['status']='failed' if a.failures else {'cloud':'unsigned cloud archive verified; local signing/export pending','export':'signed export verified; upload pending','upload':'upload verified; Apple processing/review pending'}[args.mode]
    a.data['failures']=a.failures
    # Report path is the only writable artifact. Source/archives are never modified.
    if args.output.resolve() in (args.manifest.resolve(),):
        print(json.dumps({'status':'failed','failures':['Refusing to overwrite source manifest']})); return 1
    if any(p.resolve() in args.output.resolve().parents for p in (args.root,args.cloud_root) ) or (args.signed_archive and args.signed_archive.resolve() in args.output.resolve().parents):
        print(json.dumps({'status':'failed','failures':['Report path must be outside protected directories']})); return 1
    pending=args.output.with_suffix(args.output.suffix+'.pending')
    with pending.open('w') as f: json.dump(a.data,f,indent=2,ensure_ascii=False); f.write('\n')
    os.chmod(pending,0o600); pending.replace(args.output)
    print(json.dumps({'status':a.data['status'],'failures':a.failures,'saved':str(args.output)}))
    return 1 if a.failures else 0

if __name__=='__main__': sys.exit(main())
