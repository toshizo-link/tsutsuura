"""Local temporary-fixture validation only; never imports production secrets."""
from pathlib import Path
import hashlib, json, os, shutil, sqlite3, subprocess, tempfile, zipfile

package = Path(__file__).parent / 'tsutsuura-safety-20260907'
baseline_archive = Path(__file__).with_name('test-baseline.zip')
baseline = json.loads((package/'server/deployment/safety-baseline-manifest.json').read_text())['files']
results=[]
with tempfile.TemporaryDirectory(prefix='tsutsuura-deploy-fixture-') as directory:
    home=Path(directory).resolve(); stage=home/'tsutsuura-safety-20260907'; shutil.copytree(package,stage)
    app=home/'apps/tsutsuura'; old=app/'releases/old'; old.mkdir(parents=True)
    for rel,expected in baseline.items():
        with zipfile.ZipFile(baseline_archive) as archive: data=archive.read(rel)
        assert hashlib.sha256(data).hexdigest()==expected,rel
        dest=old/Path(rel).relative_to('server'); dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(data)
    storage=app/'storage'; media=storage/'answer-media'; media.mkdir(parents=True)
    (media/'fixture-media').write_bytes(b'private original media fixture')
    db=storage/'tsutsuura.sqlite'
    env={'APP_ENV':'production','APP_DEBUG':'false','APP_KEY':'ab'*32,'APP_URL':'https://toshizo.link/tsutsuura-api/api','APP_TIMEZONE':'Asia/Tokyo','CORS_ALLOWED_ORIGINS':'https://toshizo.link','DB_CONNECTION':'sqlite','DB_DATABASE':str(db),'MEDIA_STORAGE_PATH':str(media),'OTP_DRIVER':'disabled','OTP_DEV_EXPOSE':'false','EMAIL_DRIVER':'disabled','EMAIL_DEV_EXPOSE':'false','PUSH_DRIVER':'disabled'}
    (app/'.env').write_text(''.join(f'{k}="{v}"\n' for k,v in env.items()))
    (old/'.env').symlink_to(app/'.env'); (old/'storage').symlink_to(storage); (app/'current').symlink_to(old)
    public=home/'public_html/toshizo.link/tsutsuura-api/api'; public.mkdir(parents=True)
    shutil.copy(old/'public/index.php',public/'index.php'); shutil.copy(old/'public/.htaccess',public/'.htaccess')
    (public/'.app-root').write_text(str(app/'current')+'\n'); (public/'.user.ini').write_text('upload_max_filesize=20M\npost_max_size=64M\n')
    process_env={k:v for k,v in os.environ.items() if k not in env}; process_env.update(env)
    subprocess.run(['php',str(old/'bin/migrate.php'),'--seed'],env=process_env,check=True,capture_output=True)
    with sqlite3.connect(db) as c:
        c.execute("INSERT INTO users(id,display_name) VALUES(1,'Existing one'),(2,'Existing two')")
    env_bytes=(app/'.env').read_bytes(); media_bytes=(media/'fixture-media').read_bytes()
    script=stage/'deploy-safety.php'; text=script.read_text()
    # macOS has no Linux /proc; substitute only the fixed home and process probe
    # in this disposable copy. The upload helper itself is not modified.
    text=text.replace("const EXPECTED_HOME = '/home/c8629971';",f"const EXPECTED_HOME = '{home}';")
    text=text[:text.index('function activeWorkers(')]+"function activeWorkers(string $app): ?int { return 0; }\n"
    script.write_text(text)
    def run(mode,*args,expected=0):
        p=subprocess.run(['php',str(script),mode,*args],capture_output=True,text=True,env=process_env)
        assert p.returncode==expected,(mode,p.returncode,p.stdout,p.stderr)
        results.append({'mode':mode,'expectedExit':expected,'stdout':p.stdout.strip(),'stderr':p.stderr.strip()})
        return p
    run('--check-only')
    damaged=stage/'server/src/App/ContentSafety.php'; original=damaged.read_bytes(); damaged.write_bytes(original+b'\n')
    run('--check-only',expected=1); damaged.write_bytes(original)
    run('--quiesce','--workers-paused'); run('--quiesce','--workers-paused')
    assert b'maintenance' in (public/'index.php').read_bytes()
    run('--deploy','--workers-paused',expected=1)
    state=stage/'deployment-state.json'; data=json.loads(state.read_text()); data['quiescedAt']-=301; state.write_text(json.dumps(data))
    run('--deploy','--workers-paused'); run('--deploy','--workers-paused'); run('--status')
    assert (app/'current').resolve().name=='20260907-safety-011'
    assert (app/'.env').read_bytes()==env_bytes and (media/'fixture-media').read_bytes()==media_bytes
    with sqlite3.connect(db) as c:
        assert c.execute('SELECT id,display_name FROM users ORDER BY id').fetchall()==[(1,'Existing one'),(2,'Existing two')]
        assert c.execute("SELECT COUNT(*) FROM schema_migrations WHERE version='011_content_safety.sql'").fetchone()==(1,)
        c.execute('INSERT INTO user_blocks(blocker_user_id,blocked_user_id) VALUES(1,2)')
    # An unrelated operator's public index is never overwritten by rollback.
    installed_index=(public/'index.php').read_bytes(); (public/'index.php').write_bytes(b'other operator index')
    run('--rollback','--workers-paused',expected=1)
    assert (public/'index.php').read_bytes()==b'other operator index'
    (public/'index.php').write_bytes(installed_index)
    run('--rollback','--workers-paused')
    run('--rollback','--workers-paused',expected=1)
    data=json.loads(state.read_text()); data['rollbackQuiescedAt']-=301; state.write_text(json.dumps(data))
    run('--rollback','--workers-paused',expected=1)
    assert b'maintenance' in (public/'index.php').read_bytes() and (app/'current').resolve().name=='20260907-safety-011'
    # Fixture-only removal permits testing the empty-safety-table rollback branch.
    with sqlite3.connect(db) as c:c.execute('DELETE FROM user_blocks')
    run('--rollback','--workers-paused')
    run('--rollback','--workers-paused')
    assert (app/'current').resolve()==old and (public/'index.php').read_bytes()==(old/'public/index.php').read_bytes()
    assert (app/'.env').read_bytes()==env_bytes and (media/'fixture-media').read_bytes()==media_bytes
    with sqlite3.connect(db) as c:
        assert c.execute("SELECT COUNT(*) FROM schema_migrations WHERE version='011_content_safety.sql'").fetchone()==(1,)
    results.append({'result':'passed','environmentAndMediaPreserved':True,'existingUsersPreserved':True,'rollbackRetainsMigration011':True,'noNetworkEmailAPNs':True,'fixtureSubstitutions':['EXPECTED_HOME','Linux activeWorkers process probe','quiesce timestamp advanced instead of sleeping']})
Path(__file__).with_name('deployment-fixture-results.json').write_text(json.dumps(results,indent=2)+'\n')
print('Deployment fixture passed: preflight/tamper rejection, quiesce/drain gate, migration/backup/activation, repeat, fail-closed rollback, permitted rollback and preservation.')
