from pathlib import Path
import hashlib,json,os,shutil,socket,sqlite3,subprocess,tempfile,time,urllib.request,urllib.error,uuid,wave,struct,math

root=Path('/Users/takamimarsh/Developer/Projects/Toshizo/tsutsuura/server')
out=Path(__file__).parent
result={'productionAccessed':False,'sourceModified':False,'fixtures':[],'serverFiles':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [root/'src/App/AnswerMediaService.php',root/'src/Http/Response.php',root/'public/index.php']}}

with tempfile.TemporaryDirectory(prefix='tsutsuura-audio-roundtrip-') as directory:
    temp=Path(directory); base=temp/'server';base.mkdir()
    for name in ['src','public','migrations','seeds']:shutil.copytree(root/name,base/name)
    (base/'bin').mkdir();shutil.copy(root/'bin/migrate.php',base/'bin/migrate.php')
    with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
    origin=f'http://127.0.0.1:{port}'
    env=dict(os.environ);env.update({'APP_ENV':'testing','APP_DEBUG':'false','APP_KEY':'ca'*32,'APP_URL':origin,'APP_TIMEZONE':'Asia/Tokyo','DB_CONNECTION':'sqlite','DB_DATABASE':str(temp/'data.sqlite'),'MEDIA_STORAGE_PATH':str(temp/'media'),'OTP_DRIVER':'disabled','OTP_DEV_EXPOSE':'false','EMAIL_DRIVER':'disabled','EMAIL_DEV_EXPOSE':'false','PUSH_DRIVER':'disabled'})
    subprocess.run(['php',str(base/'bin/migrate.php'),'--seed'],env=env,capture_output=True,check=True)
    log=(out/'localhost-php.log').open('w')
    server=subprocess.Popen(['php','-d','upload_max_filesize=64M','-d','post_max_size=128M','-S',f'127.0.0.1:{port}','-t',str(base/'public'),str(base/'public/index.php')],env=env,stdout=log,stderr=log)
    try:
        for i in range(50):
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.1):break
            except OSError:time.sleep(.1)
        def req(path,method='GET',body=None,token=None,headers=None):
            heads=dict(headers or {})
            if token:heads['Authorization']='Bearer '+token
            if isinstance(body,dict):heads['Content-Type']='application/json';body=json.dumps(body).encode()
            request=urllib.request.Request(origin+path,data=body,headers=heads,method=method)
            try:response=urllib.request.urlopen(request,timeout=15)
            except urllib.error.HTTPError as e:response=e
            with response:return response.status,dict(response.headers),response.read()
        def api(path,method='GET',body=None,token=None):
            status,headers,data=req(path,method,body,token);assert status in [200,201],(path,status,data)
            return json.loads(data)['data']
        for source,mime in [(out/'audible-apple.m4a','audio/mp4'),(out/'audible-adts.aac','audio/aac')]:
            auth=api('/v1/setup/family','POST',{'organizerName':'Local audio fixture','familyName':'Disposable audio fixture'})
            token=auth['token'];question=api('/v1/questions/today',token=token)['question']
            with sqlite3.connect(temp/'data.sqlite') as db:db.execute("UPDATE daily_question_publications SET available_at='2000-01-01 00:00:00'")
            boundary='tsutsuura-'+str(uuid.uuid4());payload=bytearray()
            for name,value in {'questionId':question['id'],'questionDate':question['date'],'body':'Known audible local fixture','audioDurationMilliseconds':'4000'}.items():
                payload.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n{value}\r\n'.encode())
            payload.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="audio"; filename="{source.name}"\r\nContent-Type: {mime}\r\n\r\n'.encode());payload.extend(source.read_bytes());payload.extend(f'\r\n--{boundary}--\r\n'.encode())
            status,headers,data=req('/v1/questions/today/answer','POST',bytes(payload),token,{'Content-Type':'multipart/form-data; boundary='+boundary})
            assert status==200,(status,data)
            media=json.loads(data)['data']['answer']['media'][0];assert media['mimeType']==mime and media['byteCount']==source.stat().st_size and media['durationMilliseconds']==4000
            path=urllib.parse.urlparse(media['url']).path
            status,headers,download=req(path,token=token);assert status==200 and download==source.read_bytes() and headers['Content-Type']==mime and int(headers['Content-Length'])==len(download)
            destination=out/('downloaded-'+source.name);destination.write_bytes(download)
            assert req(path)[0]==401
            head_status,head_headers,head_data=req(path,method='HEAD',token=token);assert head_status==200 and head_data==b'' and int(head_headers['Content-Length'])==len(download)
            ranges=[];reconstructed=b''
            for start in range(0,len(download),997):
                end=min(start+996,len(download)-1)
                code,h,part=req(path,token=token,headers={'Range':f'bytes={start}-{end}'})
                assert code==206 and part==download[start:end+1] and h['Content-Range']==f'bytes {start}-{end}/{len(download)}'
                reconstructed+=part
            assert reconstructed==download
            for header,expected in [('bytes=-512',download[-512:]),('bytes=1024-',download[1024:]),('bytes=0-1',download[:2])]:
                code,h,part=req(path,token=token,headers={'Range':header});assert code==206 and part==expected;ranges.append(header)
            assert req(path,token=token,headers={'Range':f'bytes={len(download)}-'})[0]==416
            probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(destination)]))
            decoded=out/('decoded-'+source.stem+'.wav')
            subprocess.run(['afconvert','-f','WAVE','-d','LEI16',str(destination),str(decoded)],check=True,capture_output=True)
            with wave.open(str(decoded)) as w:
                pcm=w.readframes(w.getnframes());frames=w.getnframes();rate=w.getframerate();channels=w.getnchannels()
            samples=struct.unpack('<'+'h'*(len(pcm)//2),pcm);rms=math.sqrt(sum(x*x for x in samples)/len(samples))/32768;peak=max(abs(x) for x in samples)/32768
            assert rms>.1 and peak>.2 and frames/rate>3.8
            result['fixtures'].append({'name':source.name,'codec':probe['streams'][0]['codec_name'],'sampleRate':rate,'channels':channels,'durationSeconds':frames/rate,'rmsDBFS':20*math.log10(rms),'peakDBFS':20*math.log10(peak),'bytes':len(download),'sha256':hashlib.sha256(download).hexdigest(),'multipartAccepted':True,'storedAndFullDownloadByteIdentical':True,'rangeReconstructionByteIdentical':True,'rangeCount':math.ceil(len(download)/997),'edgeRanges':ranges,'headCorrect':True,'unauthenticatedRejected':True,'unsatisfiableRangeRejected':True,'appleDecoderSucceeded':True})
        result['status']='passed'
    finally:server.terminate();server.wait(timeout=10);log.close()
(out/'results.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
