#!/usr/bin/env python3
"""Bounded Actions-only Formal suite. No map/resource-volume restoration."""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import shutil
import subprocess
import sys
import tarfile
import time
from economy_cloud_check import Check, ROOT, REPOSITORY, RELEASE

BASELINE_SHA256 = '608049331aca2b44f9f216f78d5804cb23e11713bc4fce09e072917100b8f5c9'

def stage(check):
    archive = check.scratch/'baseline.tar.gz'
    check.command(['gh','release','download',RELEASE,'--repo',REPOSITORY,'--pattern','baseline.tar.gz','--dir',str(check.scratch)],'small-data-download',credentials=True,timeout=120)
    assert hashlib.sha256(archive.read_bytes()).hexdigest()==BASELINE_SHA256
    project=check.scratch/'formal-algorithm'
    project.mkdir()
    data_manifest={}
    with tarfile.open(archive) as bundle:
        for item in bundle:
            if not item.isfile() or not item.name.startswith('candidate_nodes/data/'): continue
            rel=Path(item.name).relative_to('candidate_nodes')
            assert '..' not in rel.parts
            blob=bundle.extractfile(item).read()
            dest=project/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(blob)
            data_manifest[str(rel)]=hashlib.sha256(blob).hexdigest()
    sources={p:p.read_text() for p in (ROOT/'scripts').rglob('*.gd')}
    classes={m[1]:p for p,s in sources.items() if (m:=re.search(r'^class_name\s+(\w+)',s,re.M))}
    selected=set();pending=[ROOT/'merchant/production_network_check.gd']
    while pending:
        p=pending.pop()
        if p in selected:continue
        selected.add(p);s=p.read_text()
        for word in set(re.findall(r'\b\w+\b',s)):
            if word in classes:pending.append(classes[word])
        for ref in re.findall(r'(?:preload|load)\("res://([^"\n]+\.gd)"\)',s):pending.append(ROOT/ref)
    for p in selected:
        dest=project/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dest)
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Formal algorithm only"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    (check.output/'provenance.json').write_text(json.dumps({'sha':check.metadata['sha'],'data_archive':RELEASE+'/baseline.tar.gz','data_archive_sha256':BASELINE_SHA256,'data_files':data_manifest,'source_files':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(selected)},'large_resource_bytes':0},indent=2))
    print("NETWORK_PROVENANCE "+(check.output/"provenance.json").read_text().replace("\n", ""),flush=True)
    return project

def run(output):
    assert os.environ.get('GITHUB_ACTIONS')=='true', 'Economic execution is authorized on GitHub Actions only'
    check=Check('production-network',output)
    assert os.environ['GITHUB_REPOSITORY']==REPOSITORY and os.environ['GITHUB_REF']=='refs/heads/sandbox/main'
    project=stage(check)
    engine=check.install_godot()
    env={'HOME':str(check.scratch/'engine-user')}
    version=check.command([str(engine),'--headless','--version'],'engine-version',env=env).strip()
    assert version.startswith('4.6.3.stable.'),version
    imported=check.command([str(engine),'--headless','--editor','--path',str(project),'--import'],'algorithm-import',timeout=120,env=env)
    assert not re.search(r'(?m)(SCRIPT ERROR:|ERROR:|Parse Error:)',imported),imported[-3000:]
    rows=[]
    cases=['scale10','legacy','normal','materials','labor','transport','demand','productivity','equipment','materials_efficiency','wage','upstream_price','cash','process_cycle','unavailable','scale20','scale30','fixed_base','fixed_productivity','fixed_equipment','fixed_materials','fixed_rejects','capacity_base','capacity_high','same_output_base','same_output_productivity','same_output_materials','technology_no_materials','technology_low_demand']
    scope=os.environ.get('NETWORK_SCOPE','full')
    assert scope in {'full','read-contract','price-check'}
    if scope=='read-contract': cases=['normal','materials','cash']
    if scope=='price-check': cases=['paid_price_base','paid_price_high']
    for case in cases:
        before=resource.getrusage(resource.RUSAGE_CHILDREN)
        began=time.monotonic()
        result=check.output/(case+'.json')
        usage=check.output/(case+'-usage.json')
        try:
            log=check.command(['/usr/bin/time','-f','{"peak_rss_kib":%M,"cpu_user_s":%U,"cpu_system_s":%S,"cpu_percent":"%P","wall_s":%e}','-o',str(usage),str(engine),'--headless','--path',str(project),'--script','res://merchant/production_network_check.gd','--',str(result),case],case,timeout=180,env=env)
        except Exception:
            diagnostic=check.output/(case+'.log')
            if diagnostic.exists(): print(diagnostic.read_text()[:16000],flush=True)
            raise
        assert not re.search(r'(?m)(SCRIPT ERROR:|ERROR:|Parse Error:)',log),log[:12000]
        assert result.is_file() and 'NETWORK_PASS' in log
        row=json.loads(result.read_text());row['resources']=json.loads(usage.read_text());row['wall_s']=round(time.monotonic()-began,5)
        rows.append(row)
        print('NETWORK_CASE '+json.dumps(row,ensure_ascii=False,separators=(',',':')),flush=True)
    report={'sha':check.metadata['sha'],'run_url':check.metadata['run_url'],'engine':version,'check_scope':scope,'status':'PASS','cases':rows,'scope':'FINITE_FORMAL_DEVELOPMENT_NETWORK_NO_MAP_NO_GPU_NO_USER_SAVES'}
    (check.output/'network-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    # All small evidence also in Summary; artifact availability is not assumed.
    summary={**report,'cases':[{k:v for k,v in row.items() if k not in {'initial_stock','readonly_sample','result','evidence','actual_customer_consumption'}} | {'economy':{k:v for k,v in row.get('result',{}).items() if k!='firms'}} for row in rows]}
    (check.output/'summary.md').write_text('# Production network evidence\n\nFull evidence is in the NETWORK_CASE job log records.\n\n```json\n'+json.dumps(summary,ensure_ascii=False,indent=2)+'\n```\n')
    print('NETWORK_SUITE_PASS',flush=True)

if __name__=='__main__': run(Path(sys.argv[1]))
