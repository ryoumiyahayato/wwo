"""Caucasus/Nordic water on the existing optional hydro shard contract.

HydroRIVERS provides a routed modern reference, not surveyed1900 river banks.
Natural Earth retains natural lake outlines; N250 supplies observed fjord water.
"""
from pathlib import Path
import sys,json,zlib,collections
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'local-artifacts/gis-python'))
import fiona
import numpy as np
from pyproj import CRS,Transformer
from shapely.geometry import shape,box,Polygon,mapping
from shapely.ops import transform,unary_union,linemerge
from shapely import make_valid
import build_british_hydro_r43 as shared
import build_siberian_hydro_r50 as sources

ROOT=shared.ROOT;WORK=ROOT/'local-artifacts/caucasus-nordic-r52';OUT=ROOT/'data/strategic'
CAUCASUS=Polygon([(36,42),(38,40),(40,38),(43,37),(48,37),(52,39),(52,44),(50,46),(46,47),(38,46)])
NORDIC=unary_union([Polygon([(2,54),(18,54),(24,59),(38,59),(38,74),(2,74)]),box(-26,62,-12,69),box(-9,61,-5,64),box(8,74,38,84),box(-76,58,-10,85)])
HYDRO_ATTRIBUTION=('This product WWO incorporates data from the HydroSHEDS version 1 database which is © World Wildlife Fund, Inc. (2006-2022) and has been used herein under license. WWF has not evaluated the data as altered and incorporated within WWO, and therefore gives no warranty regarding its accuracy, completeness, currency or suitability for any particular purpose. Portions of the HydroSHEDS v1 database incorporate data which are the intellectual property rights of © USGS (2006-2008), NASA (2000-2005), ESRI (1992-1998), CIAT (2004-2006), UNEP-WCMC (1993), WWF (2004), Commonwealth of Australia (2007), and Her Royal Majesty and the British Crown and are used under license. The HydroSHEDS v1 database and more information are available at https://www.hydrosheds.org.')

def registry():
    ne=dict(sources.registry()[0],source_id='ne_northern_hydro_r52',title='Natural Earth retained natural lake references for Caucasus and Nordic regions')
    hyd=dict(source_id='hydrorivers_northern_r52',title='HydroRIVERS v1.0 Europe and Middle East routed river reaches',publisher='WWF / HydroSHEDS; Bernhard Lehner and Günther Grill',version='HydroRIVERS_v10_eu',license='HydroSHEDS-v1-license-commercial-derived-use',locator='https://www.hydrosheds.org/products/hydrorivers',access_metadata=dict(horizontal_crs='EPSG:4326',vertical_datum='Not applicable to two-dimensional axes',sampling='Network extracted from15arcsec HydroSHEDS; coarser Hydro1k north of60N. No true river width.',source_epoch='SRTM mainly2000 plus composite ancillary/higher-latitude data; v1 modern reference, not1900',license_url='https://data.hydrosheds.org/file/technical-documentation/HydroSHEDS_TechDoc_v1_4.pdf',attribution='HydroRIVERS © WWF; Lehner B., Grill G.(2013), Global river hydrography and network routing, Hydrological Processes27:2171–2186; https://doi.org/10.1002/hyp.9740',distribution='Clipped/simplified derivatives integrated in WWO internal preview only; original regional shapefile excluded. Full licence retained with preview, no standalone redistribution.'))
    sea=dict(source_id='kartverket_n250_fjords_r52',title='Kartverket N250 Havflate, modern sea surface reference',publisher='Kartverket',version='N25020230401 schema; downloaded2026-10-19, catalogue update2026-10-10',license='CC-BY-4.0',locator='https://kartkatalog.geonorge.no/metadata/n250-kartdata/442cae64-b447-478d-b384-545bc1d9ab48',access_metadata=dict(horizontal_crs='SourceEPSG:25833 EUREF89 UTM33 metres; displayEPSG:4326',scale='Cartographic1:100000–1:300000, not cadastral shore survey',source_epoch='Continuously updated modern cartographic reference; individual feature dates retained in sourceFGDB',attribution='© Kartverket, N250 Kartdata, CC BY4.0. Modified sea reference for WWO.',license_url='https://creativecommons.org/licenses/by/4.0/',use='Only actual Havflate intersecting retained NE physical land; no inferred water or historical claim. Island holes preserved.'))
    hyd['access_metadata']['required_attribution']=HYDRO_ATTRIBUTION
    ice=dict(source_id='natt_is50v_lakes_r52',title='Iceland IS50V Vatnafar, selected pre-existing natural lake references',publisher='Náttúrufræðistofnun / former Landmælingar Íslands',version='IS50V29.01.2025, accessed2026-10-19',license='CC-BY-4.0',locator='https://geoportal.gis.is/geonetwork/srv/api/records/83E61CBF-8498-4259-A40C-3B628EA34FB7',access_metadata=dict(horizontal_crs='WFS EPSG:4326',scale='1:50000 cartographic water polygons, individual source dates retained',categories='yfirbordsvatn3=lake/pond; ahrifmanna3=artificial excluded. No glacier or river polygon mistaken for lake.',codebook='https://www-gamli.lmi.is/wp-content/uploads/2012/09/700vatnafar_1.2utg2012.pdf',license_url='https://creativecommons.org/licenses/by/4.0/',attribution='© Náttúrufræðistofnun / Landmælingar Íslands, IS50V Vatnafar, CC BY4.0. Modified for WWO.',historical_applicability='Modern outlines of selected pre-existing lakes only, not surveyed1900 shores; glacier-retreat lakes are not added wholesale.'))
    return [ne,hyd,sea,ice]

def configure(stage):
    centre=(44,42) if stage=='caucasus' else (15,66)
    metric=CRS.from_proj4(f'+proj=laea +lat_0={centre[1]} +lon_0={centre[0]} +datum=WGS84 +units=m +no_defs')
    shared.TO_METRES=Transformer.from_crs(4326,metric,always_xy=True).transform
    shared.TO_DEGREES=Transformer.from_crs(metric,4326,always_xy=True).transform

def lakes(stage,domain):
    result=[];excluded=[]
    existing_lakes=[]
    if stage=='nordic':
        p=OUT/'german_hydro_overview_r44.geom'
        old=json.loads(zlib.decompress(p.read_bytes()))
        existing_lakes=[(k,shape(v['geometry'])) for k,v in old.items() if k.startswith('lake:')]
    regulated=[];to_utm=None
    if stage=='nordic':
        database=next((WORK/'source/n250_norway').rglob('*.gdb'))
        with fiona.open(database,layer='N250_Arealdekke_omrade') as src:
            regulated=[shape(f.geometry) for f in src.filter(where="objtype = 'InnsjøRegulert'")]
        from shapely.strtree import STRtree
        regulated=STRtree(regulated);to_utm=Transformer.from_crs(4326,25833,always_xy=True).transform
    for i,f in enumerate(json.loads(sources.LAKES.read_text(encoding='utf8'))['features']):
        p=f['properties'];g=shape(f['geometry'])
        if not domain.contains(g.representative_point()):continue
        if p['featurecla'] not in ['Lake','Alkaline Lake']:
            excluded.append(dict(ne_id=p['ne_id'],name=p.get('name'),category=p['featurecla']));continue
        consumers=[ident for ident,old in existing_lakes if old.intersects(g) and old.intersection(g).area>g.area*.6]
        if consumers:
            excluded.append(dict(ne_id=p['ne_id'],name=p.get('name'),reason='Reused existing R44 water display',existing_display_ids=consumers));continue
        if stage=='nordic' and g.representative_point().x>33.5 and p['ne_id']!=1159113251:
            # Do not silently build all eastern Karelia/European Russia when
            # the expected R49 assets do not actually exist.
            continue
        if stage=='nordic' and 4<g.representative_point().x<32 and 57<g.representative_point().y<72:
            gm=transform(to_utm,g)
            overlap=sum(gm.intersection(regulated.geometries[j]).area for j in regulated.query(gm,predicate='intersects'))
            if overlap>gm.area*.25:
                excluded.append(dict(ne_id=p['ne_id'],name=p.get('name'),category=p['featurecla'],reason='Official N250 modern regulated water overlap; no1900 natural extent recovered'));continue
        if stage=='nordic' and g.representative_point().x<-30:
            # Greenland source land support only, never neighbouring Canada.
            from build_northern_surface_r52 import nordic
            q=g.representative_point()
            if float(nordic(q.x,q.y))<.5:continue
        ident=p['ne_id']
        e=dict(id=f'lake:northern_ne10m_{ident}',kind='lake',name=p.get('name') or f'Natural Earth lake {ident}',source='ne_northern_hydro_r52',geometry_ll=g,main=float(p.get('scalerank',9))<=6,rank=p.get('scalerank'),source_date='Natural Earth v5.1.2 composite',observation_period={'from':'1990-01-01','to':'2022-12-31'},source_notes=dict(ne_id=ident,original_record=i,source_category=p['featurecla'],water_level='Modern extent;1900 level not reconstructed'))
        if ident==1159113095:e['display_replaces']=['lake:lakeladoga']
        if ident==1159113251:e['display_replaces']=['lake:lakeonega']
        result.append(e)
    return result,excluded

def rivers(stage,domain):
    shp=next((WORK/'source/hydrorivers_eu').rglob('*.shp'));groups=collections.defaultdict(list);records=collections.defaultdict(list)
    frame=domain.bounds
    if stage=='nordic':domain=domain.intersection(box(-180,56.3,180,90))
    with fiona.open(shp) as src:
        for f in src.filter(bbox=frame):
            p=dict(f.properties)
            if p['ORD_STRA']<5 and not (stage=='caucasus' and p['DIS_AV_CMS']>=15):continue
            g=shape(f.geometry).intersection(domain)
            if g.is_empty:continue
            main=p['ORD_STRA']>=6 or p['DIS_AV_CMS']>=100
            key=(p['MAIN_RIV'],main,1.2 if p['ORD_STRA']>=7 else .9 if main else .6)
            groups[key].append(g);records[key].append(dict(hyriv_id=p['HYRIV_ID'],next_down=p['NEXT_DOWN'],order_strahler=p['ORD_STRA'],discharge_reference_cms=p['DIS_AV_CMS']))
    if stage in ['caucasus','nordic']:
        # Select the actual Caucasus coastal/lake basins, not the portions of
        # Volga, Don, Tigris or Euphrates incidentally inside a large rectangle.
        basin_ids=sorted({k[0] for k in groups});keep=set()
        with fiona.open(shp) as src:
            for f in src.filter(where='HYRIV_ID IN ('+','.join(map(str,basin_ids))+')'):
                q=shape(f.geometry).representative_point()
                if domain.contains(q) and not (stage=='caucasus' and q.x>44 and q.y>45.6):keep.add(f.properties['HYRIV_ID'])
        groups={k:v for k,v in groups.items() if k[0] in keep}
    entries=[]
    for (basin,main,stroke),geoms in sorted(groups.items()):
        # Dissolve only source-coincident reach endpoints; no artificial gap link.
        g=unary_union(geoms)
        if g.geom_type=='MultiLineString':g=linemerge(g)
        entries.append(dict(id=f'river:hydrorivers_r52_{basin}_{"main" if main else "minor"}_{int(stroke*10)}',kind='river',name=f'HydroRIVERS basin {basin}',source='hydrorivers_northern_r52',geometry_ll=g,main=main,rank=5 if main else 8,stroke_scale=stroke,source_date='HydroRIVERS v1.0 modern network',observation_period={'from':'1970-01-01','to':'2013-12-31'},source_notes=dict(main_riv=basin,original_reaches=records[(basin,main,stroke)],name_status='Source has no river names; no invented name or political identity',historical_channel='Not a1900 bank survey; regulated reaches may differ')))
    return entries

def write(name,entries,bounds,overview):
    pairs=[]
    for e,g in entries:
        if g.is_empty:continue
        item=dict(e,geometry=transform(shared.TO_METRES,g))
        pairs.append((item,item['geometry']))
    d=shared.write_shard(name,pairs,bounds,overview,registry(),'tools/map/build_northern_hydro_r52.py')
    if d:
        p=OUT/(name+'.json');doc=json.loads(p.read_text(encoding='utf8'))
        for fact in doc['evidence_catalog']['facts']:
            feature=fact['value']
            if feature['source_id']=='kartverket_n250_fjords_r52':
                feature.update(water_class='modern_sea_reference',geometry_role='MODERN_N250_SEA_DISPLAY_OVER_NE_LAND_NOT_TERRITORY',uncertainty='Modern N250 sea reference, not1900 coast. Coarse physical land, picking and sovereignty are unchanged.')
                fact['methodology']='Official Havflate intersected with retained modern NE land, no height threshold or arbitrary fjord width. Source island holes retained; precomputed constrained triangles.'
        p.write_text(json.dumps(doc,ensure_ascii=False,separators=(',',':')),encoding='utf8');d['bytes']=p.stat().st_size
    return d

def publish(prefix,descriptors):
    p=OUT/'index.json';idx=json.loads(p.read_text(encoding='utf8'))
    idx['hydro_regions']=[x for x in idx.get('hydro_regions',[]) if not x['id'].startswith(prefix)]+descriptors
    p.write_text(json.dumps(idx,ensure_ascii=False,separators=(',',':')),encoding='utf8')

def build(stage):
    configure(stage);domain=CAUCASUS if stage=='caucasus' else NORDIC
    lake_items,excluded=lakes(stage,domain);river_items=rivers(stage,domain);items=lake_items+river_items;descriptors=[]
    regions=[('caucasus',[36,54,36,48])] if stage=='caucasus' else [('scandes',[2,38,54,74]),('iceland',[-26,-12,62,69]),('faroe',[-9,-5,61,64]),('svalbard',[8,38,74,84]),('greenland',[-76,-10,58,85])]
    for region,b in regions:
        core=box(b[0],b[2],b[1],b[3]);major=[(e,e['geometry_ll'].intersection(core)) for e in items if e['main'] and e['geometry_ll'].intersects(core)]
        d=write(f'northern_hydro_{region}_overview_r52',major,b,True)
        if d:descriptors.append(d)
        for y in range((b[2]//4)*4,b[3],4):
            for x in range((b[0]//4)*4,b[1],4):
                frame=[max(x,b[0]),min(x+4,b[1]),max(y,b[2]),min(y+4,b[3])];cut=box(frame[0],frame[2],frame[1],frame[3])
                entries=[(e,e['geometry_ll'].intersection(cut)) for e in items if not e['main'] and e['geometry_ll'].intersects(cut)]
                d=write(f'northern_hydro_{region}_{y}_{x:+d}_r52',entries,frame,False) if entries else None
                if d:d['max_mpp']=500.;descriptors.append(d)
    prefixes=['northern_hydro_caucasus_'] if stage=='caucasus' else ['northern_hydro_scandes_','northern_hydro_iceland_','northern_hydro_faroe_','northern_hydro_svalbard_','northern_hydro_greenland_']
    p=OUT/'index.json';idx=json.loads(p.read_text(encoding='utf8'));idx['hydro_regions']=[x for x in idx.get('hydro_regions',[]) if not any(x['id'].startswith(s) for s in prefixes)]+descriptors;p.write_text(json.dumps(idx,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    summary=dict(stage=stage,river_groups=len(river_items),river_reaches=sum(len(x['source_notes']['original_reaches']) for x in river_items),lakes=len(lake_items),excluded=excluded,descriptors=descriptors,bytes=sum(d['bytes']+d['geometry_bytes'] for d in descriptors),objects=[{k:v for k,v in e.items() if k not in ['geometry_ll','geometry']} for e in items])
    (WORK/f'{stage}_hydro_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8');print(stage,'groups',summary['river_groups'],'reaches',summary['river_reaches'],'lakes',summary['lakes'],'shards',len(descriptors),'bytes',summary['bytes'],flush=True)

def fjords():
    """Actual N250 sea that the old generalised physical land does not expose.

    No rectangular water mask: only source-sea/old-land intersections are drawn.
    A complete coarse layer remains until all intersecting detail cores fit.
    """
    configure('nordic');cache=WORK/'source/n250_sea_delta.geojson'
    if cache.exists():delta=shape(json.loads(cache.read_text(encoding='utf8'))['features'][0]['geometry'])
    else:
        gdb=next((WORK/'source/n250_norway').rglob('*.gdb'))
        with fiona.open(gdb,layer='N250_Arealdekke_omrade') as src:
            parts=[shape(f.geometry) for f in src.filter(where="objtype = 'Havflate'")]
        print('N250 sea source polygons',len(parts),flush=True)
        sea=unary_union(parts)
        ll_to_utm=Transformer.from_crs(4326,25833,always_xy=True).transform
        utm_to_ll=Transformer.from_crs(25833,4326,always_xy=True).transform
        land_path=ROOT/'local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson'
        frame=box(4,57,32,72)
        land=unary_union([shape(f['geometry']).intersection(frame) for f in json.loads(land_path.read_text(encoding='utf8'))['features'] if shape(f['geometry']).intersects(frame)])
        diff=make_valid(sea.intersection(transform(ll_to_utm,land)))
        parts=shared.parts(diff,'Polygon');parts=[g for g in parts if g.area>=10000]
        print('Sea differences retained >=1ha',len(parts),'area_km2',sum(g.area for g in parts)/1e6,flush=True)
        delta=transform(utm_to_ll,unary_union(parts))
        cache.write_text(json.dumps(dict(type='FeatureCollection',source='Kartverket N250 Havflate CC BY4.0; modified display reference, not1900',features=[dict(type='Feature',properties=dict(minimum_component_area_m2=10000),geometry=mapping(delta))]),separators=(',',':')),encoding='utf8')
    descriptors=[];overview_ids=[]
    for y in [56,62,68]:
        name=f'northern_fjords_overview_{y}_r52';ident=f'lake:n250_sea_delta_{y}'
        e=dict(id=ident,kind='lake',name='挪威峡湾：N250现代海水面参考',source='kartverket_n250_fjords_r52',main=True,rank=1,source_date='N250 modern2026-10 download',observation_period={'from':'2001-01-01','to':'2026-10-19'},source_notes=dict(source_objtype='Havflate',source_geometry='Actual sea intersected with original NE land; not an inferred water mask'),overview_tolerance_m=250)
        g=delta.intersection(box(4,y,32,y+6));d=write(name,[(e,g)],[4,32,y,y+6],True)
        if d:descriptors.append(d);overview_ids.append(ident+':'+name)
    for y in range(56,72,4):
        for x in range(4,32,4):
            g=delta.intersection(box(x,y,x+4,y+4))
            if g.is_empty:continue
            e=dict(id='lake:n250_sea_delta_detail',kind='lake',name='挪威峡湾：N250现代海水面参考',source='kartverket_n250_fjords_r52',main=False,rank=1,source_date='N250 modern2026-10 download',observation_period={'from':'2001-01-01','to':'2026-10-19'},display_replaces=overview_ids,source_notes=dict(source_objtype='Havflate',core_edges='Internal clipping only, never rendered as a coastline'),detail_tolerance_m=35)
            d=write(f'northern_fjords_{y}_{x:+d}_r52',[(e,g)],[x,x+4,y,y+4],False)
            if d:d['max_mpp']=500.;descriptors.append(d)
    publish('northern_fjords_',descriptors)
    summary=dict(descriptors=descriptors,bytes=sum(d['bytes']+d['geometry_bytes'] for d in descriptors),minimum_retained_area_m2=10000,source_count=12001)
    (WORK/'fjords_summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8');print('Fjord shards',len(descriptors),'bytes',summary['bytes'],flush=True)

def iceland_lakes():
    configure('nordic')
    path=WORK/'source/is50v_large_water.geojson'
    if not path.exists():
        import requests
        r=requests.get('https://gis.lmi.is/geoserver/wfs',params=dict(service='WFS',version='2.0.0',request='GetFeature',typeNames='IS_50V:vatnafar_flakar',outputFormat='application/json',srsName='EPSG:4326',count=2000,CQL_FILTER='area(geom)>0.0002'),timeout=120);r.raise_for_status();path.write_bytes(r.content)
    doc=json.loads(path.read_text(encoding='utf8'))
    if doc['numberMatched']!=doc['numberReturned']:raise ValueError('Incomplete official water response')
    from shapely.geometry import Point
    anchors=[('Þingvallavatn',-21.10,64.18),('Mývatn',-17.0,65.60),('Öskjuvatn',-16.75,65.03),('Kleifarvatn',-21.96,63.93),('Lagarfljót',-14.60,65.25)]
    entries=[];missing=[];objects=[]
    for name,x,y in anchors:
        matches=[f for f in doc['features'] if f['properties']['yfirbordsvatn']==3 and f['properties']['ahrifmanna']!=3 and shape(f['geometry']).covers(Point(x,y))]
        if len(matches)!=1:missing.append(dict(name=name,anchor=[x,y],matches=len(matches)));continue
        f=matches[0];p=f['properties'];g=shape(f['geometry']);uid=p['uuid']
        e=dict(id='lake:is50v_'+uid,kind='lake',name=name,source='natt_is50v_lakes_r52',main=True,rank=4,source_date=p.get('dagsheimildar') or 'ModernIS50V composite',observation_period={'from':'2000-01-01','to':'2025-01-29'},source_notes=dict(uuid=uid,objectid=p['objectid'],source_feature_id=f['id'],yfirbordsvatn=p['yfirbordsvatn'],ahrifmanna=p['ahrifmanna'],source_imagery=p['heimild'],source_date=p['dagsheimildar'],reference_anchor=[x,y],name_method='Named geographic anchor contained by the official lake polygon; no nearest-feature guess',historical_shore='Modern reference;1900 level not reconstructed'))
        entries.append((e,g));objects.append(dict(id=e['id'],name=name,source_uuid=uid,bounds=list(g.bounds),holes=sum(len(v.interiors) for v in shared.parts(g,'Polygon'))))
    d=write('northern_iceland_lakes_overview_r52',entries,[-26,-12,62,69],True)
    descriptors=[d] if d else [];publish('northern_iceland_lakes_',descriptors)
    summary=dict(objects=objects,missing=missing,descriptors=descriptors,bytes=sum(x['bytes']+x['geometry_bytes'] for x in descriptors))
    (WORK/'iceland_lakes_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8');print('Iceland lakes',len(objects),'missing',missing,'bytes',summary['bytes'],flush=True)

def finish():
    # Publish the two construction phases serially from their completed outputs.
    # Source/GIS generation can run separately, never race on the runtime index.
    descriptors=[]
    for name in ['caucasus_hydro_summary.json','nordic_hydro_summary.json','fjords_summary.json','iceland_lakes_summary.json']:
        path=WORK/name;summary=json.loads(path.read_text(encoding='utf8'))
        for d in summary['descriptors']:
            p=ROOT/d['path'][6:];doc=json.loads(p.read_text(encoding='utf8'))
            for s in doc['source_registry']['sources']:
                if s['source_id']=='hydrorivers_northern_r52':s['access_metadata']['required_attribution']=HYDRO_ATTRIBUTION
            p.write_text(json.dumps(doc,ensure_ascii=False,separators=(',',':')),encoding='utf8');d['bytes']=p.stat().st_size
        summary['bytes']=sum(d['bytes']+d['geometry_bytes'] for d in summary['descriptors'])
        path.write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8');descriptors.extend(summary['descriptors'])
    publish('northern_',descriptors)
    print('R52 hydro published',len(descriptors),'shards',sum(d['bytes']+d['geometry_bytes'] for d in descriptors),'bytes',flush=True)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8')
    if sys.argv[1]=='fjords':fjords()
    elif sys.argv[1]=='iceland_lakes':iceland_lakes()
    elif sys.argv[1]=='finish':finish()
    else:build(sys.argv[1])
