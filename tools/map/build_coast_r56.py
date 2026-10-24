"""Crete only: matched physical fill, water, coast, query and political ink.

GSHHG2.3.7 full source replaces complete island components, not a water decal.
No historical sovereignty or formal LandTopology record is generated.
"""
import copy,json,struct,sys,zlib,zipfile,contextlib
from pathlib import Path
from shapely.geometry import shape,box,Polygon,mapping
from shapely.ops import unary_union
from shapely import constrained_delaunay_triangles,set_precision,make_valid
import build_geographic_foundation as base

ROOT=base.ROOT;WORK=ROOT/'local-artifacts/terrain-r56/coast'
ID='physical_2_4_mid_1_0';NAME=ID+'_r56';AREA=box(23.2,34.6,26.6,35.95)

def read(p):return json.loads(p.read_text(encoding='utf8'))
def packed(p,data):
    raw=json.dumps(data,ensure_ascii=False,separators=(',',':')).encode();p.write_bytes(zlib.compress(raw,9))
    return dict(path='res://'+p.relative_to(ROOT).as_posix(),encoding='ZLIB_JSON_UTF8',bytes=p.stat().st_size,decoded_bytes=len(raw))

def triangulate(g):
    return [[[list(c) for c in t.exterior.coords]] for p in base.parts(set_precision(g,1e-9),'Polygon') for t in base.parts(constrained_delaunay_triangles(p),'Polygon') if t.area>0]

def main():
    source=[];levels={};binary_records=[]
    with contextlib.ExitStack() as stack:
        subset=WORK/'crete_gshhg_f.b'
        if subset.exists():f=stack.enter_context(subset.open('rb'))
        else:
            archive=stack.enter_context(zipfile.ZipFile(WORK/'gshhg-bin-2.3.7.zip'))
            f=stack.enter_context(archive.open('gshhs_f.b'))
        while h:=f.read(44):
            row=struct.unpack('>11i',h);id,n,flag,w,e,s,north,*_=row
            coords=f.read(n*8)
            bounds=box(w/1e6,s/1e6,e/1e6,north/1e6)
            if not AREA.covers(bounds):continue
            binary_records.append(h+coords)
            xy=[(x/1e6,y/1e6) for x,y in struct.iter_unpack('>ii',coords)]
            g=make_valid(Polygon(xy));level=flag&255
            if not g.is_empty:
                source.append(dict(type='Feature',properties=dict(gshhg_id=id,level=level,version='2.3.7',resolution='full'),geometry=mapping(g)))
                levels.setdefault(level,[]).append(g)
    if not subset.exists():subset.write_bytes(b''.join(binary_records))
    assert levels.get(1),'No Crete source polygons'
    islands=unary_union(levels[1])
    if 2 in levels:islands=islands.difference(unary_union(levels[2]))
    if 3 in levels:islands=islands.union(unary_union(levels[3]))
    base.write(WORK/'crete_gshhg_2.3.7_source.geojson',dict(type='FeatureCollection',features=source,license='LGPL-3.0-or-later',source='https://github.com/GenericMappingTools/gshhg-gmt/releases/tag/2.3.7'))
    doc=read(ROOT/f'data/strategic/{ID}.json')
    geo=json.loads(zlib.decompress((ROOT/f'data/strategic/{ID}.geom').read_bytes()))
    previous=shape(geo['land_reference:'+ID]['geometry'])
    removed=[p for p in base.parts(previous,'Polygon') if AREA.covers(p)]
    assert max(p.area for p in removed)>0.7
    # Entire closed components are replaced. The selection rectangle itself
    # never contributes a coast edge or changes unrelated mainland polygons.
    land=set_precision(previous.difference(unary_union(removed)).union(islands),1e-9)
    cell=box(15,30,30,40);water=cell.difference(land)
    coast=land.boundary.difference(cell.boundary)
    for kind,g in [('land_reference',land),('ocean_reference',water)]:
        geo[kind+':'+ID]=dict(geometry=dict(type='MultiPolygon',coordinates=[mapping(p)['coordinates'] for p in base.parts(g,'Polygon')]),lod_geometry=dict(medium=triangulate(g) if kind=='land_reference' else []))
    lines=[list(map(list,p.coords)) for p in base.parts(coast,'LineString')]
    geo['coast:'+ID]=dict(geometry=dict(type='MultiLineString',coordinates=lines),lod_geometry=dict(medium=lines))
    desc=next(c for p in read(ROOT/'data/strategic/index.json')['coast_regions'] for c in p['medium_regions'] if c['id']==ID)
    old_ink=json.loads(zlib.decompress((ROOT/f'data/strategic/{ID}.ink.geom').read_bytes()))
    # Keep the original historical partition away from the replaced islands.
    # Within Crete re-intersect exact existing historical geometry. New land
    # outside those historical sources stays neutral, never nearest-owned.
    oldpolys=[Polygon(t[0]) for t in old_ink['triangles']]
    refs=old_ink['references'];triangles=[];indices=[]
    for p,ref in zip(oldpolys,old_ink['indices']):
        remaining=p.difference(AREA)
        tris=triangulate(remaining);triangles.extend(tris);indices.extend([ref]*len(tris))
    remaining=islands
    features=[]
    for filename in ['cshapes_1900_snapshot.json','arabia_gulf_geography_1900.json']:
        features.extend(read(ROOT/'data/world_map/historical'/filename)['features'])
    for feature in reversed(features):
        g=shape(feature['geometry'])
        if not g.intersects(remaining):continue
        overlap=remaining.intersection(g)
        tris=triangulate(overlap)
        if tris:
            if feature['id'] not in refs:refs.append(feature['id'])
            triangles.extend(tris);indices.extend([refs.index(feature['id'])]*len(tris))
        remaining=remaining.difference(overlap)
    tris=triangulate(remaining);triangles.extend(tris);indices.extend([0]*len(tris))
    out=ROOT/'data/strategic'
    geom_asset=packed(out/(NAME+'.geom'),geo)
    old_ink.update(triangles=triangles,indices=indices,references=refs,method='Existing R27 partition retained outside finite Crete component envelope; new modern physical island source intersected with unchanged historical sources. No source ownership extension.',license='Physical Crete geometry LGPL-3.0-or-later; historical source contribution CC BY-NC-SA4.0; source notices accompany preview.')
    ink_asset=packed(out/(NAME+'.ink.geom'),old_ink)
    source_id='gshhg_237_crete_r56'
    src=dict(source_id=source_id,title='GSHHG2.3.7 finite Crete full-resolution physical coast',publisher='Paul Wessel; Walter H.F.Smith; University of Hawaii / NOAA',version='2.3.7',locator='https://github.com/GenericMappingTools/gshhg-gmt/releases/tag/2.3.7',license='LGPL-3.0-or-later',access_metadata=dict(source_date='2017-06-15',retrieved_on='2026-10-19',horizontal_crs='WGS84 geographic degrees, integer microdegrees in source',source_scale='Full WVS shoreline, heterogeneous legacy survey scale; metre accuracy not warranted',source_epoch='Mixed legacy WVS, compiled2017; not1900',bounds_lon_lat=[23.2,34.6,26.6,35.95],data_transformation='Complete closed Crete/island components, no synthetic closure coast. Original source vertices retained at1e-9degree quantization; constrained triangles.',historical_applicability='Modern physical display reference only; no historical land, political identity, ownership, control or economic assertion.'))
    doc['source_registry']['sources'].append(src)
    src['license']='LGPL-3.0-or-later + retained Natural Earth public domain'
    for f in doc['evidence_catalog']['facts']:
        f['value']['geometry_asset']=geom_asset
        f['methodology']+=' R56 finite Crete GSHHG full component replacement; other R27 physical geometry retained.'
        f['generator']='tools/map/build_coast_r56.py'
        f.update(source_id=source_id,source_version='2.3.7',source_locator=src['locator'],license='LGPL-3.0-or-later + retained Natural Earth public domain')
        f['value'].update(source_id=source_id,source_date='2017-06-15')
        if f['value']['kind']=='coast':f['value']['source_geometry_file']='GSHHG2.3.7 finite Crete full + retained Natural Earth5.1.2 outside envelope'
    # Descriptors retain the stable shard ID and its existing bounded owner.
    base.write(out/(NAME+'.json'),doc)
    desc.update(path='res://data/strategic/'+NAME+'.json',bytes=(out/(NAME+'.json')).stat().st_size,ink_asset=ink_asset)
    desc.pop('compiled_asset',None)
    base.write(WORK/'descriptor.json',desc)
    base.write(WORK/'geometry_comparison.geojson',dict(type='FeatureCollection',features=[dict(type='Feature',properties=dict(role=label),geometry=mapping(g)) for label,g in [('R55_NE_medium',unary_union(removed)),('R56_GSHHG_full',islands)]]))
    base.write(WORK/'summary.json',dict(source_components=len(source),old_vertices=sum(len(p.exterior.coords) for p in removed),new_vertices=sum(len(p.exterior.coords) for p in base.parts(islands,'Polygon')),old_area_deg2=unary_union(removed).area,new_area_deg2=islands.area,unassigned_new_land_deg2=remaining.area,geometry_bytes=geom_asset['bytes'],ink_bytes=ink_asset['bytes']))
    print(read(WORK/'summary.json'))

if __name__=='__main__':main()
