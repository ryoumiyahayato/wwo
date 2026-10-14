"""Build the reviewed Paris R1 display shard from cached, cited source artifacts.

No modern population, administrative boundary or railway opening date is inferred.
Rail centerlines are bounded corridor references, explicitly not a 1900 survey.
"""
from __future__ import annotations
import argparse, json, math, re, unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path
from shapely.geometry import LineString, Point
from shapely.ops import transform

ROOT = Path(__file__).resolve().parents[2]
ANCHOR = (2.3522, 48.8566)
PERIOD = {"from": "1900-01-01", "to": "1900-12-31"}
# Curated from the contemporary guide's routes and maps, not population ranks.
# slug, coordinate lookup name, historical spelling, display prominence.
SETTLEMENTS = [
    ("paris", "Paris", "Paris", 0),
    ("lille", "Lille", "Lille", 1), ("rouen", "Rouen", "Rouen", 1),
    ("le_havre", "Le Havre", "Le Havre", 1), ("calais", "Calais", "Calais", 1),
    ("amiens", "Amiens", "Amiens", 1), ("reims", "Reims", "Rheims", 1),
    ("orleans", "Orléans", "Orleans", 1), ("tours", "Tours", "Tours", 1),
    ("caen", "Caen", "Caen", 1), ("le_mans", "Le Mans", "Le Mans", 1),
    ("saint_denis", "Saint-Denis", "St. Denis", 2),
    ("versailles", "Versailles", "Versailles", 1),
    ("chantilly", "Chantilly", "Chantilly", 2), ("creil", "Creil", "Creil", 2),
    ("compiegne", "Compiègne", "Compiegne", 1), ("beauvais", "Beauvais", "Beauvais", 1),
    ("pontoise", "Pontoise", "Pontoise", 2), ("mantes", "Mantes-la-Jolie", "Mantes", 2),
    ("rambouillet", "Rambouillet", "Rambouillet", 2),
    ("fontainebleau", "Fontainebleau", "Fontainebleau", 2), ("melun", "Melun", "Melun", 2),
    ("meaux", "Meaux", "Meaux", 2), ("etampes", "Étampes", "Etampes", 2),
    ("vernon", "Vernon", "Vernon", 2), ("evreux", "Évreux", "Evreux", 2),
    ("chartres", "Chartres", "Chartres", 1), ("dreux", "Dreux", "Dreux", 2),
    ("arras", "Arras", "Arras", 1), ("douai", "Douai", "Douai", 1),
    ("longueau", "Longueau", "Longueau", 2), ("abbeville", "Abbeville", "Abbeville", 1),
    ("boulogne_sur_mer", "Boulogne-sur-Mer", "Boulogne", 1),
    ("dunkerque", "Dunkirk", "Dunkirk", 1), ("dieppe", "Dieppe", "Dieppe", 1),
    ("fecamp", "Fécamp", "Fecamp", 2), ("saint_quentin", "Saint-Quentin", "St. Quentin", 1),
    ("laon", "Laon", "Laon", 1), ("soissons", "Soissons", "Soissons", 1),
    ("chateau_thierry", "Château-Thierry", "Chateau-Thierry", 2),
    ("epernay", "Épernay", "Epernay", 2),
    ("chalons_sur_marne", "Châlons-en-Champagne", "Chalons-sur-Marne", 1),
    ("troyes", "Troyes", "Troyes", 1), ("sens", "Sens", "Sens", 2),
    ("auxerre", "Auxerre", "Auxerre", 1), ("montargis", "Montargis", "Montargis", 2),
    ("blois", "Blois", "Blois", 1), ("bourges", "Bourges", "Bourges", 1),
    ("valenciennes", "Valenciennes", "Valenciennes", 1),
    ("cambrai", "Cambrai", "Cambrai", 2), ("lisieux", "Lisieux", "Lisieux", 2),
    ("bernay", "Bernay", "Bernay", 2), ("argentan", "Argentan", "Argentan", 2),
]
CORRIDORS = [
    ("272000", "Paris-Nord – Lille", "Nord", ["paris", "saint_denis", "chantilly", "creil", "longueau", "arras", "douai", "lille"], "1, 9, 11"),
    ("311000", "Longueau – Amiens – Boulogne", "Nord", ["longueau", "amiens", "abbeville", "boulogne_sur_mer"], 1),
    ("314000", "Boulogne – Calais", "Nord", ["boulogne_sur_mer", "calais"], 1),
    ("340000", "Paris-Saint-Lazare – Rouen – Le Havre", "Ouest", ["paris", "mantes", "vernon", "rouen", "le_havre"], "4, 6"),
    ("420000", "Paris-Montparnasse – Chartres – Le Mans", "Ouest", ["paris", "versailles", "rambouillet", "chartres", "le_mans"], 28),
    ("570000", "Paris – Orléans – Tours corridor", "Paris-Orléans", ["paris", "etampes", "orleans", "blois", "tours"], 35),
    ("070000", "Noisy-le-Sec – Meaux – Épernay – Châlons-sur-Marne (Paris-Est corridor)", "Est", ["meaux", "chateau_thierry", "epernay", "chalons_sur_marne"], 19),
    ("001000", "Paris-Est – Troyes", "Est", ["paris", "troyes"], 39),
    ("830000", "Paris – Melun – Fontainebleau – Sens", "Paris-Lyon-Méditerranée", ["paris", "melun", "fontainebleau", "sens"], 52),
]

def norm(s):
    return ''.join(c for c in unicodedata.normalize('NFKD', s).lower() if not unicodedata.combining(c))

def metric(x, y, z=None):
    return ((x-ANCHOR[0])*111195*math.cos(math.radians(ANCHOR[1])), (y-ANCHOR[1])*111195)

def inverse(x, y, z=None):
    return (x/(111195*math.cos(math.radians(ANCHOR[1])))+ANCHOR[0], y/111195+ANCHOR[1])

def distance(p):
    a,b=map(math.radians,ANCHOR); c,d=map(math.radians,p)
    return 6371008.8*math.acos(min(1,max(-1,math.sin(b)*math.sin(d)+math.cos(b)*math.cos(d)*math.cos(a-c))))

def clipped_lines(points, tolerance):
    line=transform(metric,LineString(points))
    # Geographic spherical-disc clipping; the metric approximation is used only
    # to simplify. Outside runs are removed rather than bridged with invented lines.
    if not line.is_valid or line.length == 0: return []
    simple=transform(inverse,line.simplify(tolerance))
    parts=[]; current=[]
    for p in simple.coords:
        p=[round(p[0],6),round(p[1],6)]
        if distance(p)<=300000:
            if not current or p!=current[-1]: current.append(p)
        elif current:
            if len(current)>1: parts.append(current)
            current=[]
    if len(current)>1: parts.append(current)
    return parts

def source(id,title,publisher,date,license,url,applicability,files,method,raw):
    assets=[]
    for f in files:
        p=raw/f
        assets.append({"file":f,"bytes":p.stat().st_size})
    return {"source_id":id,"title":title,"publisher":publisher,"version":date,"license":license,"locator":url,
        "access_metadata":{"source_date":date,"retrieved_on":"2026-10-06","source_type":applicability,
            "retrieval_information":url,"data_transformation":method,"historical_applicability":applicability,
            "uncertainty":"See each fact; no contemporary population or political membership inferred.","source_assets":assets}}

def build(raw: Path):
    books={key: json.loads((raw/(ident+'.pages.json')).read_text(encoding='utf-8')) for key,ident in [('baedeker_north_1899','northernfrance00karl'),('baedeker_paris_1900','14thedbaedparis00karl')]}
    sources=[
        source('baedeker_north_1899','Northern France: from Belgium and the English Channel to the Loire, excluding Paris and its environs. 3rd edition; maps France Nord et Est and France Ouest (1:1,500,000).','Karl Baedeker, Leipzig; digitized by University of Toronto / Internet Archive','1899','PUBLIC_DOMAIN','https://archive.org/details/northernfrance00karl','HISTORICAL_EVIDENCE',['northernfrance00karl.metadata.json','northernfrance00karl_djvu.xml','northeast1899-front.jpg','northwest1899.jpg'],'Named city and station/corridor identities reviewed against guide routes and folded maps. Map shapes are corroboration only, not GPS survey.',raw),
        source('baedeker_paris_1900','Paris and environs with routes from London to Paris. 14th revised edition; Banlieue de Paris, 1:800,000, facing p.342.','Karl Baedeker, Leipzig; University of California Libraries / Internet Archive','1900','PUBLIC_DOMAIN','https://archive.org/details/14thedbaedparis00karl','HISTORICAL_EVIDENCE',['14thedbaedparis00karl.metadata.json','14thedbaedparis00karl_djvu.xml','paris1900-remote.jpg'],'Existing settlements and rail corridors; excludes new Exposition/Metro lines whose opening is later in 1900. OCR is only a finding aid; maps and described routes corroborate identity.',raw),
        source('sncf_rfn_2026','Fichier de formes des lignes du Réseau Ferré National','SNCF Réseau','2026-02-19','ODbL-1.0','https://ressources.data.sncf.com/explore/dataset/formes-des-lignes-du-rfn/','BOUNDED_ASSUMPTION',['sncf.geojson','sncf.metadata.json'],'Select traditional line codes independently evidenced by 1899 guide, clip to Paris 300km and simplify at 35m. Current centerline is a physical locator for the evidenced corridor, NOT proof of every 1900 alignment. Do not use as historical engineering survey.',raw),
        source('sandre_topage_current','BD TOPAGE Métropole, CoursEau and LimiteTerreEau; current WFS snapshot','Sandre / OFB / IGN','2026-10-06','Etalab-2.0','https://services.sandre.eaufrance.fr/geo/topage','PHYSICAL_REFERENCE',['rivers-selected.gml','rivers-selected.request.json','coast.gml','topage-capabilities.xml'],'Select named principal natural rivers; exclude canals, clip to spherical 300km radius, simplify river 35m/coast 45m. Modern river axis and low-water coastline; no reconstruction of 1900 banks, ports, dredging, marshes or channel engineering.',raw),
    ]
    geonames=[]
    for path in sorted((ROOT/'data/world_map/city_detail/france').glob('*.json')):
        geonames.extend(json.loads(path.read_text(encoding='utf-8'))['cities'])
    geoindex=json.loads((ROOT/'data/world_map/city_detail/index.json').read_text(encoding='utf-8'))
    sources.append({"source_id":"geonames_locator_2026","title":"GeoNames FR place coordinates, existing WWO modern_city_detail snapshot","publisher":"GeoNames","version":geoindex['generated_at'],"license":"CC-BY-4.0","locator":"https://download.geonames.org/export/dump/",
        "access_metadata":{"source_date":"2026-07-22","retrieved_on":"2026-10-06","retrieval_information":"Existing repository snapshot; individual GeoNames IDs retained in features.","source_type":"REFERENCE_ONLY","license_url":"https://creativecommons.org/licenses/by/4.0/","attribution":"Contains GeoNames geographical data, licensed under CC BY 4.0.","data_transformation":"Only coordinates and record ID copied for separately evidenced settlements; no population, rank or administration imported.","historical_applicability":"Modern approximate point locator only; independent Baedeker evidence is mandatory.","uncertainty":"City representative point, not built-up footprint or historical station location."}})
    facts=[]; features=[]; review=[]
    original=json.loads((ROOT/'data/world_map/cities.json').read_text(encoding='utf-8'))['cities']
    existing={r['id']:r for r in original}
    def add(f,primary,status,confidence,method):
        f.update(valid_from='1900-01-01',valid_to='1901-01-01',confidence=confidence,source_id=primary,source_date=next(s['version'] for s in sources if s['source_id']==primary),source_type=status)
        features.append(f)
        s=next(s for s in sources if s['source_id']==primary)
        facts.append({"fact_id":"local_spatial:"+f['id'],"domain":"local_spatial_content","subject_id":f['id'],"value":f,"unit":"display_geography","source_id":primary,"source_version":s['version'],"source_locator":s['locator'],"observation_period":PERIOD,"spatial_scope":{"kind":"content_shard","id":"paris_northern_france_1900"},"methodology":method,"confidence":confidence,"lower_bound":None,"upper_bound":None,"license":s['license'],"review_status":"HISTORICAL_EVIDENCE" if status=='HISTORICAL_EVIDENCE' else 'BOUNDED_ESTIMATE',"generator":"tools/map/build_paris_local.py:R1"})
    for slug,modern,historical,rank in SETTLEMENTS:
        candidates=[r for r in geonames if r['name']==modern and r['record_type']=='city' and distance(r['lon_lat'])<=300000]
        assert candidates,(slug,modern)
        point=candidates[0]['lon_lat']
        if slug in existing: point=existing[slug]['lon_lat']
        book='baedeker_paris_1900' if slug in ['paris','saint_denis','pontoise','versailles','chantilly','rambouillet','fontainebleau','creil'] else 'baedeker_north_1899'
        words=norm(historical).replace('st.','st\\.?').replace('-','[ -]').replace(' ','\\s+')
        pattern=re.compile(r'\b'+words+r'\b')
        matches=[]
        for leaf,text in enumerate(books[book]):
            if leaf<45 or 'INDEX.' in text[:80] or 'CONTENTS' in text[:100]: continue
            hit=pattern.search(norm(text))
            if hit:
                vicinity=norm(text)[max(0,hit.start()-60):hit.end()+400]
                score=10*sum(k in vicinity for k in ['inhab','town','station','railway','capital','situated'])+min(len(text),3000)/10000
                matches.append((score,leaf,hit.start(),text))
        assert matches,(slug,'missing historical existence evidence')
        _,leaf,position,text=max(matches)
        ident='northernfrance00karl' if book=='baedeker_north_1899' else '14thedbaedparis00karl'
        locator=f'https://archive.org/details/{ident}/page/n{leaf}/mode/1up'
        display=historical if slug in ['mantes','chalons_sur_marne'] else modern
        f={"id":"place:"+slug,"kind":"settlement","historical_name":historical,"display_name":display,"geometry":{"type":"Point","coordinates":point},"rank":rank,"max_mpp":200 if rank<2 else 115,
            "latitude":point[1],"longitude":point[0],"source_reference":locator,"source_leaf":leaf,"coordinate_source":"geonames_locator_2026","coordinate_record_id":candidates[0]['id'],"parent_country_id":"country_fra",
            "political_reference_basis":"Contemporary French guide identifies this named French settlement; existing country_fra reference reused. No polygon/ISO inference.",
            "uncertainty":"Representative city point, estimated 0.5–2km identity-location uncertainty; not a station or historical built-up extent.","identity_status":"REUSED" if slug in existing else "NEW_CONTENT_PLACE"}
        f['coordinate_transformation']='Reuse existing WWO locator, with GeoNames identity/location cross-check' if slug in existing else 'Copy reviewed GeoNames city locator'
        if slug in ['le_havre','calais']: f['related_existing_port_id']='place:port_'+slug
        add(f,book,'HISTORICAL_EVIDENCE',.9,'Curated city or named railway/port town in a contemporary guide. Valid interval is a bounded 1900 snapshot, not a founding/closure date. Coordinate evidence is independent modern locator only.')
        review.append({'id':f['id'],'historical_name':historical,'source_reference':locator,'ocr_context':text[max(0,position-100):position+550]})
    byid={f['id']:f for f in features}
    rails=json.loads((raw/'sncf.geojson').read_text(encoding='utf-8'))['features']
    for code,name,operator,places,route in CORRIDORS:
        # Contemporary descriptions establish the route, not current track count,
        # electricity, speed, stations or present-day operator.
        for idx,r in enumerate(f for f in rails if f['properties']['code_ligne']==code):
            for part,coords in enumerate(clipped_lines(r['geometry']['coordinates'],35)):
                shape=transform(metric,LineString(coords))
                connected=[]; distances={}
                for place in places:
                    id='place:'+place
                    d=shape.distance(transform(metric,Point(byid[id]['geometry']['coordinates'])))
                    if d<6500: connected.append(id); distances[id]=round(d)
                # Truncate the reviewed eastern route cores. Unseen continuation
                # remains outside this R1 even when a current line extends there.
                if code in ['001000','830000','070000']:
                    end=transform(metric,Point(byid['place:'+places[-1]]['geometry']['coordinates']))
                    along=shape.project(end)
                    from shapely.ops import substring
                    shape=substring(shape,0,along)
                    coords=[[round(x,6),round(y,6)] for x,y in transform(inverse,shape).coords]
                f={"id":f'rail:rfn_{code}:r{r["properties"]["rg_troncon"]}:p{part}',"line_id":'rail:rfn_'+code,"kind":"rail","display_name":name,"geometry":{"type":"LineString","coordinates":coords},"operator_1900":operator,"operator_source":"baedeker_north_1899","places":connected,"place_distance_m":distances,"max_mpp":200,"historical_source":"baedeker_north_1899","source_reference":f'https://archive.org/details/northernfrance00karl (route {route}; folded maps n7/n578)',"geometry_source":"sncf_rfn_2026","upstream_code":code,"upstream_pk_from":r['properties']['pk_debut_r'],"upstream_pk_to":r['properties']['pk_fin_r'],"geometry_status":"BOUNDED_HISTORICAL_CORRIDOR_REFERENCE","georeference_method":"No scan-to-vector georeferencing. Historical maps/routes identify corridor and station order; modern official centerline provides approximate physical placement.","estimated_spatial_error_m":1500,"uncertainty":"1500m historical alignment estimate is not a measured error bound. Modern junctions/terminal moves unverified; no station spurs fabricated. Geometry must not support engineering or precise 1900 routing.","license":"ODbL-1.0"}
                add(f,'sncf_rfn_2026','BOUNDED_ASSUMPTION',.65,'Contemporary corridor identity plus current official centerline, visually checked against 1899 northern/eastern and western maps and 1900 Banlieue map. Independent alignment uncertainty remains explicit.')
    ns={'s':'http://xml.sandre.eaufrance.fr/','g':'http://www.opengis.net/gml'}
    for filename,tag,kind,tolerance in [('rivers-selected.gml','CoursEau_FXX','river',35),('coast.gml','LimiteTerreEau_FXX','coast',45)]:
        tree=ET.parse(raw/filename)
        records=tree.findall('.//s:'+tag,ns)
        for record in records:
            upstream=record.findtext('s:CdOH','',ns)
            name=record.findtext('s:TopoOH','',ns) or 'Channel coast (modern low-water reference)'
            for line_index,coordinates in enumerate(record.findall('.//g:LineString/g:coordinates',ns)):
                points=[tuple(map(float,token.split(',')[:2])) for token in coordinates.text.split()]
                for part,coords in enumerate(clipped_lines(points,tolerance)):
                    if transform(metric,LineString(coords)).length<300: continue
                    f={"id":f'{kind}:sandre_{upstream}:l{line_index}:p{part}',"kind":kind,"display_name":name,"geometry":{"type":"LineString","coordinates":coords},"max_mpp":200,"upstream_id":upstream,"source_reference":'https://services.sandre.eaufrance.fr/geo/topage',"upstream_modified":record.findtext('s:DateMajOH','unknown',ns),"historical_applicability":"PHYSICAL_REFERENCE: durable regional river/coast structure is useful in 1900, but detailed modern channel/port engineering and tidal datum cannot establish 1900 geometry.","estimated_spatial_error_m":1000,"uncertainty":"35/45m display simplification is not historical accuracy; localized 1900 differences may exceed 1km in ports, estuaries or engineered channels.","license":"Etalab-2.0"}
                    add(f,'sandre_topage_current','PHYSICAL_REFERENCE',.65,f'Modern physical reference only. Clip named principal natural geography to Paris radius; simplify {tolerance}m. Does not create any political or simulation ownership.')
    doc={"metadata":{"schema_id":"local_spatial_content_r1","shard_id":"paris_northern_france_1900","anchor_place_id":"place:paris","anchor_lon_lat":list(ANCHOR),"radius_km":300,"valid_from":"1900-01-01","valid_to":"1901-01-01","status":"PARTIAL_DATA","admin_status":"ADMIN_BOUNDARY_DATA_GAP","roads_status":"DEFER","counts":{k:sum(f['kind']==k for f in features) for k in ['settlement','rail','river','coast']},"scope":"Paris-centred 300km spherical disc; selected French corridors/settlements and French physical hydrography/coast only, not modern administrative clipping.","data_gaps":["Historical railway microalignment and station spurs unverified; only nine principal corridors included.","1900 administrative geometry absent; modern admin1 never substituted.","1900 major roads deferred.","Belgian/Luxembourg/German local content within disc not yet admitted.","1900 bank/coast/port engineering not reconstructed; physical reference is modern."],"license_notice":"Contains GeoNames geographical data CC BY 4.0; SNCF Réseau 2026 centerline subset adapted under ODbL 1.0 (rail facts form the derived database, obtainable from this JSON); Sandre/OFB/IGN BD TOPAGE current WFS adapted under Etalab Open Licence 2.0; Baedeker 1899/1900 original works public domain. Licences apply to respective records, not simulation code.","license_urls":["https://creativecommons.org/licenses/by/4.0/","https://opendatacommons.org/licenses/odbl/1-0/","https://www.etalab.gouv.fr/licence-ouverte-open-licence/"]},"source_registry":{"schema_id":"historical_source_registry_v2","sources":sources},"evidence_catalog":{"schema_id":"historical_fact_evidence_catalog_v2","facts":facts}}
    target=ROOT/'data/local/paris_northern_france_1900.json'; target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(doc,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8')
    (raw.parent/'settlement-evidence-review.json').write_text(json.dumps(review,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(doc['metadata'],ensure_ascii=False,indent=2)); print('Runtime bytes',target.stat().st_size)
    return doc

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--source-dir',type=Path,default=ROOT/'local-artifacts/paris-local-r1/source'); args=parser.parse_args(); build(args.source_dir)
