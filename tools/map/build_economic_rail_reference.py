"""Display-only rail derivatives; never routes, capacity or cargo positions.

Existing northern-France references are retained. RFN 830000 gives a modern
alignment reference for the historical Paris-Lyon-Marseille corridor. The
1858 PLM report and Lyon regional inventory establish the old corridor, not
the precise present-day track, stations or operating capacity.
"""
import json
from pathlib import Path
import shapely
from shapely.geometry import shape,Point
from shapely.ops import transform,substring
from pyproj import Transformer

ROOT=Path(__file__).resolve().parents[2]
RAW=ROOT.parent/'offline-map-sources/france_mainland_reference'
HISTORY='https://wikiplm.anciensreseaux.fr/index.php?title=Rapport_du_Conseil_d%E2%80%99administration_du_PLM_aux_actionnaires_du_30_avril_1858'
INVENTORY='https://patrimoine.auvergnerhonealpes.fr/dossier/IA69000240'
SNCF='https://ressources.data.sncf.com/api/explore/v2.1/catalog/datasets/formes-des-lignes-du-rfn/exports/geojson?where=code_ligne%3D%27830000%27'


def main():
    local=json.loads((ROOT/'data/local/paris_northern_france_1900.json').read_text(encoding='utf-8'))
    fields=['id','line_id','source_id','source_type','source_reference','geometry_status','places','geometry_source','license','estimated_spatial_error_m','uncertainty']
    rails=[];stations=[]
    for fact in local['evidence_catalog']['facts']:
        source=fact['value']
        if source.get('kind')=='rail' and source.get('line_id')!='rail:rfn_830000':
            row={k:source[k] for k in fields if k in source};row['coordinates']=source['geometry']['coordinates'];rails.append(row)
        if source.get('display_kind')=='transport_node' and source.get('transport_symbol')=='station':
            stations.append(dict(id=source['id'],name=source['display_name'],coordinates=source['geometry']['coordinates'],source_id=source['source_id']))
    raw=json.loads((RAW/'rfn_830000.geojson').read_text(encoding='utf-8'))
    if len(raw['features'])!=1 or raw['features'][0]['properties']['code_ligne']!='830000':
        raise ValueError('RFN reference differs from the declared line')
    to_metric=Transformer.from_crs(4326,2154,always_xy=True).transform
    to_ll=Transformer.from_crs(2154,4326,always_xy=True).transform
    line=transform(to_metric,shape(raw['features'][0]['geometry']))
    at=line.project(transform(to_metric,Point(4.8357,45.764)))
    for suffix,geometry,places in [('north',substring(line,0,at),['place:paris','place:lyon']),('south',substring(line,at,line.length),['place:lyon','place:marseille'])]:
        row=dict(id='rail:rfn_830000:'+suffix,line_id='rail:rfn_830000_'+suffix,code_ligne='830000',
                 source_id='sncf_rfn_2026',source_type='BOUNDED_ASSUMPTION',source_reference=HISTORY,
                 historical_reference=[HISTORY,INVENTORY],geometry_source=SNCF,
                 geometry_status='HISTORICAL_CORRIDOR_MODERN_ALIGNMENT_NOT_1900_TRACK',places=places,license='ODbL-1.0',
                 uncertainty='Modern alignment includes later engineering. Split at the nearest line position to the existing Lyon city anchor, not a surveyed station or new transport node.')
        levels={}
        for level,tolerance in [('near',8),('district',35),('overview',140)]:
            levels[level]=[list(p) for p in transform(to_ll,geometry.simplify(tolerance,preserve_topology=True)).coords]
        row.update(coordinates=levels['near'],lod_coordinates=levels)
        rails.append(row)
    result=dict(schema='economic_rail_display_reference_v1',source='res://data/local/paris_northern_france_1900.json',
                basis='HISTORICAL_CORRIDORS_WITH_MODERN_RFN_ALIGNMENT_REFERENCE_NOT_1900_SURVEY',valid_from='1900-01-01',valid_to='1901-01-01',
                rails=rails,stations=stations,corridor_lines={'rail_paris_lyon':['rail:rfn_830000_north'],'rail_lyon_marseille':['rail:rfn_830000_south'],
                  'rail_paris_rouen':['rail:rfn_340000'],'rail_rouen_le_havre':['rail:rfn_340000']})
    destination=ROOT/'data/presentation/economic_rail_reference.json'
    destination.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8')
    print('Rail display',len(rails),'segments',sum(len(r['coordinates']) for r in rails),'near vertices',destination.stat().st_size,'bytes')


if __name__=='__main__':main()
