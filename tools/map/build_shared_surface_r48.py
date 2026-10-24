"""Geographic overview and overlapping-detail composites from R42–R46 assets.
No new DEM, coverage classification, country or historical fact is generated.
The existing MapRelief owns these resources; originals and canonical IDs stay.
"""
import json,struct,zlib,collections
from pathlib import Path
import numpy as np
from scipy.ndimage import map_coordinates
import build_france_surface_r42 as shared
ROOT=Path(__file__).resolve().parents[2]
BOUNDS=(-12.,34.,24.,62.)
PACKS=['german_r44','spain_r45','france_r42','benelux_r46','british_r43','canary_r45']

def smooth(a,b,x):
    t=np.clip((x-a)/(b-a),0,1)
    return t*t*(3-2*t)

def decode(asset):
    blob=(ROOT/asset['path'][6:]).read_bytes()
    w,h,size=struct.unpack('<III',blob[8:20]);raw=zlib.decompress(blob[20:])
    if len(raw)!=size:raise ValueError('Invalid existing mip pack')
    return np.frombuffer(raw[:w*h*4],dtype=np.uint8).reshape(h,w,4).astype(np.float32)/255

def compose(bounds,width,height,assets,canonical_output=False):
    west,south,east,north=bounds
    x,y=np.meshgrid(west+(np.arange(width,dtype=np.float32)+.5)*(east-west)/width,
                    north-(np.arange(height,dtype=np.float32)+.5)*(north-south)/height)
    total=np.zeros((height,width,4),dtype=np.float32);weight=np.zeros((height,width),dtype=np.float32)
    coverage=np.zeros_like(weight)
    for asset in assets:
        pixels=decode(asset);w,s,e,n=asset['bounds_lon_lat']
        if canonical_output:
            # Decode colour, shade and support before interpolation. The old
            # mixed channel packed shade*coverage back into A, then decoded
            # that product as shade at the next stage: dark rectangular rims.
            from build_surface_r56 import canonical
            pixels=canonical(pixels,asset.get('surface_encoding',0))
        coordinates=[(n-y)/(n-s)*pixels.shape[0]-.5,(x-w)/(e-w)*pixels.shape[1]-.5]
        field=np.stack([map_coordinates(pixels[:,:,i],coordinates,order=1,mode='nearest') for i in range(4)],axis=-1)
        encoding=asset.get('surface_encoding',0)
        if canonical_output:
            alpha=field[:,:,3].copy()
        elif encoding==0:
            t=smooth(.2,.95,field[:,:,0])[:,:,None]
            colour=np.array([.57,.57,.46])*(1-t)+np.array([.70,.68,.62])*t
            trees=(field[:,:,2]*.78)[:,:,None]
            colour=colour*(1-trees)+np.array([.27,.38,.27])*trees
            alpha=field[:,:,3].copy();field=np.concatenate([colour,field[:,:,1:2]],axis=-1)
        else:alpha=smooth(.01,.075,field[:,:,3])
        alpha*=(x>=w)&(x<=e)&(y>=s)&(y<=n)
        feather=asset.get('surface_feather_degrees',[0,0,0,0])
        if asset['surface_role']=='detail':feather=[asset['core_inset_degrees']]*4
        for amount,distance in zip(feather,[x-w,y-s,e-x,n-y]):
            if amount:alpha*=smooth(0,amount,distance)
        total+=field*alpha[:,:,None];weight+=alpha;coverage=np.maximum(coverage,alpha)
    result=np.divide(total,weight[:,:,None],out=np.zeros_like(total),where=weight[:,:,None]>0)
    if canonical_output:result[:,:,3]=coverage
    else:result[:,:,3]*=coverage
    return np.clip(result,0,1)

def main():
    sources={};assets={};upstream=[];citations=[]
    for pack in PACKS:
        path=ROOT/'data/presentation'/(pack.replace('_r','_surface_r')+'.json')
        doc=json.loads(path.read_text(encoding='utf8'))
        fact=next(f for f in doc['evidence_catalog']['facts'] if f['fact_id']=='physical_relief:'+pack)
        upstream.append(fact);citations.append(dict(catalogue=str(path.relative_to(ROOT)),fact_id=fact['fact_id']))
        for source in doc['source_registry']['sources']:sources[source['source_id']]=source
        for a in fact['value']['assets']:
            ident=a['id'].split(':',1)[1]
            if ident in assets and assets[ident]['path']!=a['path']:raise ValueError('Conflicting shared geographic asset')
            assets[ident]=a
    overview=[assets[pack+'_base'] for pack in PACKS if pack!='canary_r45']
    base=shared.write_asset('europe_r48_base',compose(BOUNDS,1728,1344,overview),BOUNDS,'base')
    base.update(surface_group='europe_r48',surface_encoding=1,surface_feather_degrees=[.5,.5,.5,.5])
    generated=[base];groups=collections.defaultdict(list)
    for a in assets.values():
        if a['surface_role']!='detail':continue
        w,s,e,n=a['core_bounds_lon_lat'];groups[(int((w+e)//4),int((s+n)//4))].append(a)
    for (cx,cy),group in sorted(groups.items()):
        if len(group)<2:continue
        core=[cx*2,cy*2,cx*2+2,cy*2+2];pad=32/512
        bounds=[core[0]-pad,core[1]-pad,core[2]+pad,core[3]+pad]
        a=shared.write_asset(f'shared_r48_{cy*2}_{cx*2:+d}',compose(bounds,1088,1088,group),bounds,'detail')
        a.update(surface_group='europe_r48',surface_encoding=1,core_bounds_lon_lat=core,
                 upstream_asset_ids=[v['id'] for v in group])
        generated.append(a)
        # Upstream metadata is admitted, but duplicate alternatives do not
        # compete for GPU slots. This changes this catalogue only.
        for v in group:v['surface_role']='source_detail'
        print(a['id'],len(group),'sources',flush=True)
    source=dict(source_id='shared_surface_r48',title='Geographic composite of existing R42–R46 physical-reference materials',
        publisher='WWO derivative of Copernicus / ESA WorldCover',version='R48-existing-reference-composite',license='Copernicus-DEM-GLO90+CC-BY-4.0',
        locator='https://copernicus-dem-90m.s3.amazonaws.com/readme.html',access_metadata=dict(upstream=citations,no_new_data=True,
        scope='Existing geographic support only',sampling='1/48-degree overview; shared detail 1/512 degree, 32-pixel real-data collars',
        historical_applicability='Modern physical reference, not 1900 survey'))
    sources[source['source_id']]=source
    for a in generated:a['channels']='Canonical linear RGB and fixed DSM hillshade minus .4; zero alpha outside existing source support.'
    fact=dict(upstream[0],fact_id='physical_relief:europe_r48',subject_id='physical_relief:shared_europe_reference',
        value=dict(status='PHYSICAL_REFERENCE',assets=generated),source_id=source['source_id'],source_version=source['version'],source_locator=source['locator'],
        methodology='Decode original channel encodings before geographic weighted compositing and offline mip generation. Source coverage retained; no new DEM or land geometry.',
        generator='tools/map/build_shared_surface_r48.py')
    out=dict(source_registry=dict(schema_id='historical_source_registry_v2',sources=list(sources.values())),
             evidence_catalog=dict(schema_id='historical_fact_evidence_catalog_v2',facts=upstream+[fact]))
    (ROOT/'data/presentation/europe_surface_r48.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print('Generated',len(generated),'packs;',sum(a['bytes'] for a in generated),'bytes;',sum(a['decoded_bytes'] for a in generated),'decoded bytes on disk, not simultaneous residency')
if __name__=='__main__':main()
