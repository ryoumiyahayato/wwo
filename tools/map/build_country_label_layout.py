"""Finite interior label candidates, derived offline from canonical dated polygons."""
from pathlib import Path
import json,math
from shapely.geometry import shape,box
from shapely.ops import polylabel,transform
ROOT=Path(__file__).resolve().parents[2];source_path=ROOT/'data/world_map/historical/cshapes_1900_snapshot.json'
source=json.loads(source_path.read_text(encoding='utf8'))
names={
 'gw_220':('République française','fr','https://www.assemblee-nationale.fr/histoire/amendement_wallon_1875.asp','Historical French republican identity'),
 'gw_255':('Deutsches Reich','de','https://www.bundestag.de/besuche/ausstellungen/verfassung/tafel12','Historical constitutional name, 1871'),
 'gw_200':('United Kingdom','en','https://www.parliament.uk/about/living-heritage/evolutionofparliament/legislativescrutiny/parliamentandireland/collections/ireland/act-of-union-1800/','Short label for United Kingdom of Great Britain and Ireland; not the post-1922 state'),
 'gw_300':('Österreich-Ungarn','de','https://alex.onb.ac.at/cgi-content/alex?aid=rgb&datum=1901&iv=1&size=45','German cartographic form for the dual monarchy; not an assertion that German was its sole official language'),
 'gw_365':('Российская империя','ru','https://www.statmuseum.ru/ru/results/1897/','Historical imperial identity in normalized modern Cyrillic orthography; not Soviet Union'),
 'gw_640':('Devlet-i Osmaniye','tr-Latn','https://cdn.tbmm.gov.tr/TbmmWeb/Yayinlar/Dosya/37e7ee6c-8e27-4799-9c66-9156c92d92b0.pdf','1876 constitution Article 1; parliamentary Latin transcription of Ottoman Turkish, not Republic of Türkiye'),
 'gw_710':('大清','zh-Hant','https://www.loc.gov/resource/lcnclscd.2012402285.1A001/?st=brief','1893 printed imperial title; Han-script short label, not an exclusive language claim for the multiethnic empire'),
 'gw_230':('España','es','https://www.congreso.es/constitucion/ficheros/historicas/cons_1876.pdf','Geographic short name within the 1876 constitutional monarchy; not a republic'),
}
layouts={}
for feature in source['features']:
 geometry=shape(feature['geometry']);polygons=list(geometry.geoms) if geometry.geom_type=='MultiPolygon' else [geometry]
 largest=max(polygons,key=lambda p:p.area*max(.15,math.cos(math.radians(p.centroid.y))))
 candidates=[largest]
 if largest.bounds[2]-largest.bounds[0]>15 or largest.bounds[3]-largest.bounds[1]>15:
  west,south,east,north=largest.bounds
  for x in range(math.floor(west/20),math.ceil(east/20)):
   for y in range(math.floor(south/15),math.ceil(north/15)):
    clipped=largest.intersection(box(x*20,y*15,(x+1)*20,(y+1)*15))
    parts=list(clipped.geoms) if hasattr(clipped,'geoms') else [clipped]
    candidates.extend(p for p in parts if p.geom_type=='Polygon' and p.area>3)
 positions=[]
 for polygon in candidates:
  sx=111.195*max(.15,math.cos(math.radians(polygon.centroid.y)))
  metric=transform(lambda x,y:(x*sx,y*111.195),polygon)
  point=polylabel(metric,tolerance=2.0)
  lon,lat=point.x/sx,point.y/111.195
  if not geometry.contains(shape({'type':'Point','coordinates':[lon,lat]})):continue
  positions.append({'lon_lat':[round(lon,6),round(lat,6)],'clearance_km':round(metric.boundary.distance(point),3)})
 row={'positions':positions,'placement':'Interior of main connected component; extra fixed interior candidates for large territories. No capital coordinates reused.'}
 if feature['id'] in names:
  name,language,locator,policy=names[feature['id']];row.update({'name':name,'language':language,'source_locator':locator,'language_policy':policy})
 layouts[feature['id']]=row
document={'schema_id':'country_label_layout_r3','geometry_role':'PRESENTATION_ONLY','fallback_language':'Existing Chinese UI name where a native historical form is unverified','layouts':layouts}
(ROOT/'data/presentation/country_label_layout_r3.json').write_text(json.dumps(document,ensure_ascii=False,separators=(',',':')),encoding='utf8')
print(len(layouts),sum(len(row['positions']) for row in layouts.values()))
