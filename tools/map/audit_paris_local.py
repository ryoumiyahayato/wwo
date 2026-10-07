"""Offline structural/geometry audit of the admitted display data, no world edits."""
import json, math, hashlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'data/local/paris_northern_france_1900.json'

def distance(a,b):
    x,y,u,v=map(math.radians,(*a,*b))
    return 6371008.8*math.acos(min(1,max(-1,math.sin(y)*math.sin(v)+math.cos(y)*math.cos(v)*math.cos(x-u))))

def audit(document):
    sources={s['source_id']:s for s in document['source_registry']['sources']}
    facts=document['evidence_catalog']['facts']
    ids=[f['subject_id'] for f in facts]
    assert len(ids)==len(set(ids))
    features={f['value']['id']:f['value'] for f in facts}
    assert len(features)==len(ids)
    counts={k:0 for k in ['settlement','rail','river','coast']}
    invalid=0; point_count=0; max_distance=0
    for fact in facts:
        f=fact['value']; counts[f['kind']]+=1
        s=sources[fact['source_id']]
        assert (fact['source_version'],fact['source_locator'],fact['license'])==(s['version'],s['locator'],s['license'])
        assert f['id']==fact['subject_id'] and f['source_id']==fact['source_id']
        assert f['valid_from']=='1900-01-01' and f['valid_to']=='1901-01-01'
        coords=[f['geometry']['coordinates']] if f['kind']=='settlement' else f['geometry']['coordinates']
        for coord in coords:
            assert len(coord)==2 and all(math.isfinite(n) for n in coord)
            assert abs(coord[0])<=180 and abs(coord[1])<=90
            d=distance(coord,document['metadata']['anchor_lon_lat'])
            max_distance=max(max_distance,d)
            assert d<=300050,(f['id'],d)
            point_count+=1
        if f['kind']=='settlement':
            assert fact['source_id'].startswith('baedeker_')
            assert '/page/n' in f['source_reference']
            assert f['id'].startswith('place:') and not f['id'].startswith('place:local')
            assert 'population' not in f
        else:
            assert not any(k in f for k in ['parent_country_id','owner','polity_id','controller_id'])
            assert f['geometry']['type']=='LineString' and len(coords)>=2
            assert all(a!=b for a,b in zip(coords,coords[1:]))
        if f['kind']=='rail':
            assert f['geometry_status']=='BOUNDED_HISTORICAL_CORRIDOR_REFERENCE'
            assert f['historical_source'] in sources and f['geometry_source'] in sources
            assert set(f['places'])==set(f['place_distance_m'])
            assert all(features[p]['kind']=='settlement' for p in f['places'])
            assert all(d<6500 for d in f['place_distance_m'].values())
    assert counts==document['metadata']['counts']
    assert document['metadata']['admin_status']=='ADMIN_BOUNDARY_DATA_GAP'
    assert document['metadata']['roads_status']=='DEFER'
    old=json.loads((ROOT/'data/world_map/cities.json').read_text(encoding='utf-8'))['cities']
    old_ids={'place:'+r['id'] for r in old}
    places=[f for f in features.values() if f['kind']=='settlement']
    reused=[f['id'] for f in places if f['id'] in old_ids]
    new=[f['id'] for f in places if f['id'] not in old_ids]
    return {'counts':counts,'duplicate_ids':0,'invalid_geometry':invalid,'points':point_count,'maximum_anchor_distance_m':round(max_distance,2),'reused_places':reused,'new_places':new,'rail_lines':len({f['line_id'] for f in features.values() if f['kind']=='rail'}),'runtime_bytes':PATH.stat().st_size,'sha256':hashlib.sha256(PATH.read_bytes()).hexdigest()}

if __name__=='__main__':
    output=audit(json.loads(PATH.read_text(encoding='utf-8')))
    target=ROOT/'local-artifacts/paris-local-r1/data-audit.json'
    target.write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(output,ensure_ascii=False,indent=2))
