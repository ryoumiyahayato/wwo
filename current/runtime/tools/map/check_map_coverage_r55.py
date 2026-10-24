"""Finite R55 offline coverage: actual GDScript selector + native source alpha.

Run after production: python tools/map/check_map_coverage_r55.py --godot PATH
No game, save directory, renderer, stress loop, hash or whole-project test.
"""
from pathlib import Path
import argparse,json,subprocess,struct,zlib
import numpy as np
from scipy.ndimage import map_coordinates
import build_shared_surface_r48 as shared
import build_france_surface_r42 as common

ROOT=common.ROOT;OUT=ROOT/'local-artifacts/r55_coverage'

def alpha(asset,points):
    data=shared.decode(asset);w,s,e,n=asset['bounds_lon_lat']
    x=points[:,0]+360*np.round(((w+e)/2-points[:,0])/360);y=points[:,1]
    samples=map_coordinates(data[:,:,3],[(n-y)/(n-s)*data.shape[0]-.5,(x-w)/(e-w)*data.shape[1]-.5],order=1,mode='nearest')
    enc=asset.get('surface_encoding',0)
    if enc==1:samples=common.smooth(.01,.075,samples)
    elif enc in (2,3,4):samples=np.ones_like(samples)
    samples*=((x>=w)&(x<=e)&(y>=s)&(y<=n))
    for amount,distance in zip(asset.get('surface_feather_degrees',[0]*4),[x-w,y-s,e-x,n-y]):
        if amount:samples*=common.smooth(0,amount,distance)
    return samples

def main(godot):
    OUT.mkdir(parents=True,exist_ok=True)
    target=OUT/'selection.json'
    subprocess.run([godot,'--headless','--path',str(ROOT),'--script','res://tools/map/check_map_coverage_r55.gd','--',str(target)],check=True)
    check=json.loads(target.read_text(encoding='utf8'));assets={}
    global_doc=json.loads((ROOT/'data/presentation/global_physical_relief.json').read_text(encoding='utf8'))
    global_assets=[a for f in global_doc['evidence_catalog']['facts'] for a in f['value']['assets'] if a['id'].split(':',1)[1] in ('world','region')]
    fallback_available=len(global_assets)==2 and all((ROOT/a['path'][6:]).exists() for a in global_assets)
    for name in ['asian_surface_r51.json','northern_surface_r52.json','european_surface_r55.json']:
        d=json.loads((ROOT/'data/presentation'/name).read_text(encoding='utf8'))
        for f in d['evidence_catalog']['facts']:
            assets.update({a['id'].split(':',1)[1]:a for a in f['value']['assets']})
    old=json.loads((ROOT/'data/presentation/arid_surface_r53.json').read_text(encoding='utf8'))
    oldbase=next(a for f in old['evidence_catalog']['facts'] for a in f['value']['assets'] if a['id']=='physical_relief:euro_afro_arabia_r53_base')
    for row in check['windows']:
        points=np.array(row.pop('points'));coverage=np.zeros(len(points),dtype='float32')
        for item in row['selected']:
            if item['role']=='base':
                a=alpha(assets[item['id']],points)
                coverage+=a*(1-coverage)
        row['sample_count']=len(points)
        row['regional_base_min_alpha']=float(coverage.min())
        row['regional_uncovered_samples']=int((coverage<.99).sum())
        row['r53_common_min_alpha']=float(alpha(oldbase,points).min())
        row['regional_base_complete_on_samples']=bool(np.all(coverage>=.99))
        row['source_gap']=not row['regional_base_complete_on_samples']
        row['global_etopo_fallback']=fallback_available
        row['complete_detail_not_claimed']=True
    # Native Mip structure is part of the explicitly requested asset check.
    d=json.loads((ROOT/'data/presentation/european_surface_r55.json').read_text(encoding='utf8'))
    new=d['evidence_catalog']['facts'][-1]['value']['assets'];lengths=[]
    for a in new:
        blob=(ROOT/a['path'][6:]).read_bytes();w,h,length=struct.unpack('<III',blob[8:20]);raw=zlib.decompress(blob[20:])
        expected=0;mw,mh=w,h
        while True:
            expected+=mw*mh*4
            if (mw,mh)==(1,1):break
            mw,mh=max(1,mw//2),max(1,mh//2)
        if (w,h)!=(a['width'],a['height']) or len(raw)!=length or length!=expected or len(blob)!=a['bytes']:raise ValueError('Native mip structure mismatch: '+a['id'])
        lengths.append(len(blob))
    check['new_resources']={'count':len(new),'bytes':sum(lengths),'native_mip_records_checked':len(lengths),'catalogue_bytes':(ROOT/'data/presentation/european_surface_r55.json').stat().st_size}
    target.write_text(json.dumps(check,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    lines=['# R55 finite offline coverage','', 'Actual MapRelief selector and RegionProjection; 1280×720 (wide case2560×1080), bearing0.61rad. 33×19 samples. No GPU installation or game run.','', '| Window | Centre | m/px | Selected base / details (P=prefetch) | Regional alpha min | Gaps | Selected decoded bytes |','|---|---|---:|---|---:|---:|---:|']
    for r in check['windows']:
        ids=', '.join(a['id']+(' (P)' if a['prefetch'] else '') for a in r['selected']) or 'global ETOPO fallback'
        lines.append(f"| {r['name']} | {r['center']} | {r['mpp']} | {ids} | {r['regional_base_min_alpha']:.4f} | {r['regional_uncovered_samples']} | {r['selected_decoded_bytes']} |")
    lines+=['','Africa is a political coverage window outside the constructed North Africa domain; it uses the existing global ETOPO reference. Regional gaps there are not new Russian terrain. This finite sample is not a pixel-render acceptance test.','',f"New native Mip records: {len(lengths)}; {sum(lengths)} bytes."]
    (OUT/'coverage.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
    print('\n'.join(lines))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--godot',required=True);args=parser.parse_args();main(args.godot)
