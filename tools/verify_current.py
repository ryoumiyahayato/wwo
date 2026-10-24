"""Run only the existing, user-requested recovery checks in a cloud-restored copy."""
import argparse,json,pathlib,subprocess,os,re,msvcrt,time,hashlib
P=pathlib.Path
def main():
 a=argparse.ArgumentParser();a.add_argument('--root',type=P,required=True);a.add_argument('--full-checks',action='store_true');x=a.parse_args()
 root=x.root.resolve();rt=root/'runtime';out=root/'run';out.mkdir(exist_ok=True)
 receipt=json.loads((root/'RESTORE_RECEIPT.json').read_text(encoding='utf-8'))
 assert receipt['all_restored_bytes_verified_before_allowed_changes'] and not receipt['old_source_reads']
 if (rt/'.godot').exists():raise RuntimeError('Fresh import requires no previous project .godot cache')
 query="Get-CimInstance Win32_Process -Filter \"Name LIKE '%Godot%' OR Name LIKE '%wwo%' OR Name = 'blender.exe' OR Name = 'ffmpeg.exe'\" | Select-Object ProcessId,Name | ConvertTo-Json -Compress"
 busy=subprocess.check_output(['powershell','-NoProfile','-Command',query],text=True,encoding='utf-8',errors='replace').strip()
 if busy:raise RuntimeError('Restricted engine resource is occupied; no polling or process termination: '+busy[:1200])
 console=P(r'D:\tools\Godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe');native=P(r'D:\tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe')
 lock=P(r'D:\programs\WWO\wwo\builds\.preview-manager.lock')
 stages=[];result={'root':str(root),'full_checks':x.full_checks,'stages':stages,'all_passed':False,'original_delivery_inputs_rewritten':False}
 startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
 def run(name,exe,args):
  log=out/(name+'.log');start=time.time()
  with log.open('wb') as f:
   p=subprocess.Popen([str(exe),*args],stdout=f,stderr=subprocess.STDOUT,cwd=rt,startupinfo=startup)
   print('ENGINE_STAGE_STARTED',name,p.pid,flush=True);code=p.wait()
  text=log.read_text(encoding='utf-8',errors='replace')
  stage={'name':name,'pid':p.pid,'exit_code':code,'wall_seconds':round(time.time()-start,3),'log':log.name,'script_errors':bool(re.search(r'SCRIPT ERROR|Parse Error|Compile Error',text)),'engine_error_lines':[l[:400] for l in text.splitlines() if 'ERROR:' in l][:15]};stages.append(stage)
  if code or stage['script_errors']:raise RuntimeError('Engine stage failed: '+name)
  print('ENGINE_STAGE_EXITED',name,code,flush=True);return text
 with lock.open('a+b') as f:
  if f.tell()==0:f.write(b'0');f.flush()
  f.seek(0);msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,1)
  try:
   version=subprocess.check_output([str(console),'--version'],startupinfo=startup,text=True).strip();assert version.startswith('4.6.3.'),version;result['engine_version']=version
   text=run('fresh_import',console,['--headless','--editor','--import','--path',str(rt),'--quit'])
   if stages[-1]['engine_error_lines']:raise RuntimeError('Fresh import reported engine errors; originals retained')
   success=root/'private_state/authority_success_portable.json';revoked=root/'private_state/authority_revoked_portable.json'
   if x.full_checks:
    run('authority_cold',console,['--headless','--path',str(rt),'--script','res://authority/checks.gd','--','--source='+str(success),'--mode=cold','--report='+str(out/'authority_cold.json')])
    r=json.loads((out/'authority_cold.json').read_text(encoding='utf-8'));assert r['passed'] and all(v['passed'] for v in r['cases']);result['authority_cold']=r
    run('duty_existing',console,['--headless','--path',str(rt),'--script','res://duty/checks.gd','--','--source='+str(root/'private_state/authority_success_formal.json'),'--report='+str(out/'duty_existing.json')])
    r=json.loads((out/'duty_existing.json').read_text(encoding='utf-8'));assert r['passed'];result['duty_existing']=r
    evidence=root/'recovery_evidence';assert (evidence/'private_state/emitted/portable.json').exists()
    run('muzzle_existing_evidence',console,['--headless','--path',str(rt),'--script','res://authority/recovery_checks.gd','--','--root='+str(evidence)])
    r=json.loads((evidence/'recovery_checks.json').read_text(encoding='utf-8'));assert not r['failures'] and all(v['passed'] for v in r['rows']);result['muzzle_existing_evidence']=r
   run('revoked_cold',console,['--headless','--path',str(rt),'--script','res://authority/revocation.gd','--','--source='+str(revoked),'--mode=cold','--report='+str(out/'revoked_cold.json')])
   r=json.loads((out/'revoked_cold.json').read_text(encoding='utf-8'));assert r['passed'] and r['history_and_world_exact_after_denial'] and r['minute']==2 and r['pending_usec']==12402648;result['revoked_cold']=r
   text=run('native_success_cold',native,['--path',str(rt),'--resolution','1280x720','--log-file',str(out/'native_engine.log'),'res://authority/main.tscn','--','--practice-bundle='+str(success),'--authority-tour=cold','--authority-output='+str(out/'native_success_cold.json')])
   r=json.loads((out/'native_success_cold.json').read_text(encoding='utf-8'));assert r['snapshot_exact_on_cold'] and r['nonmilitary_world_exact'] and r['minute']==2 and r['pending_usec']==12402648 and r['results']['saved'] and not r['results']['admission']['ok'] and not r['portable_error'];result['native_success_cold']=r
   for rel,expected in receipt['critical_input_sha256'].items():assert hashlib.sha256((root/rel).read_bytes()).hexdigest()==expected,'Restored delivery input changed: '+rel
   result['critical_restored_inputs_unchanged']=True;result['all_passed']=True;receipt['status']='CLOUD_ONLY_RESTORE_PASSED';receipt['engine_version']=version
  finally:
   (out/'RECOVERY_VERIFICATION.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
   (root/'RESTORE_RECEIPT.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8');f.seek(0);msvcrt.locking(f.fileno(),msvcrt.LK_UNLCK,1)
 print('CLOUD_ONLY_RESTORE_PASSED',str(root),flush=True)
if __name__=='__main__':main()
