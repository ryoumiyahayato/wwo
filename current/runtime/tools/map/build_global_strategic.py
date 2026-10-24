"""Offline strategic derivatives. Modern locators never establish historical identity."""
from pathlib import Path
import json, math, unicodedata, argparse

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'local-artifacts/global-strategic-r1/source'
OUT = ROOT / 'data/strategic'
ATLAS = 'https://archive.org/details/philadelphiapubl00rand'
DATE = '2026-10-07'
LOCATOR_BOUNDS = {'vancouver':[-125,-120,48,51], 'rosario':[-62,-60,-34,-32], 'cordoba':[-66,-63,-33,-30], 'santiago':[-72,-70,-34,-32]}

# id | 1899 name | modern locator | geographic shard | printed atlas page | rank
# Rank is a curated Presentation choice from the contemporary chief-city/map
# evidence. No modern population or administrative field is used.
CITY_ROWS = '''
paris|Paris|Paris|europe|106|0
lille|Lille|Lille|europe|106|1
rouen|Rouen|Rouen|europe|106|1
le_havre|Le Havre|Le Havre|europe|106|1
calais|Calais|Calais|europe|106|2
lyon|Lyon|Lyon|europe|107|1
marseille|Marseille|Marseille|europe|107|1
bordeaux|Bordeaux|Bordeaux|europe|107|1
nantes|Nantes|Nantes|europe|107|2
toulouse|Toulouse|Toulouse|europe|107|2
brest|Brest|Brest|europe|106|2
london|London|London|europe|99|0
dover|Dover|Dover|europe|99|2
manchester|Manchester|Manchester|europe|99|1
liverpool|Liverpool|Liverpool|europe|99|1
birmingham|Birmingham|Birmingham|europe|99|1
york|York|York|europe|99|2
newcastle|Newcastle|Newcastle|europe|99|2
edinburgh|Edinburgh|Edinburgh|europe|100|1
glasgow|Glasgow|Glasgow|europe|100|1
brussels|Brussels|Brussels|europe|109|0
antwerp|Antwerp|Antwerp|europe|109|1
ghent|Ghent|Ghent|europe|109|2
kortrijk|Courtrai|Kortrijk|europe|109|2
tournai|Tournai|Tournai|europe|109|2
amsterdam|Amsterdam|Amsterdam|europe|108|1
berlin|Berlin|Berlin|europe|112|0
hamburg|Hamburg|Hamburg|europe|112|1
cologne|Cologne|Cologne|europe|112|1
frankfurt|Frankfort|Frankfurt|europe|112|1
leipzig|Leipzig|Leipzig|europe|112|1
munich|Munich|Munich|europe|112|1
vienna|Vienna|Vienna|europe|114|0
budapest|Budapest|Budapest|europe|114|1
prague|Prague|Prague|europe|114|1
rome|Rome|Rome|europe|116|0
milan|Milan|Milan|europe|116|1
turin|Turin|Turin|europe|116|1
venice|Venice|Venice|europe|116|2
zurich|Zurich|Zurich|europe|118|1
istanbul|Constantinople|Istanbul|europe|123|0
st_petersburg|St. Petersburg|Saint Petersburg|eurasia|125|0
moscow|Moscow|Moscow|eurasia|125|0
warsaw|Warsaw|Warsaw|eurasia|125|1
kiev|Kiev|Kyiv|eurasia|125|1
odessa|Odessa|Odessa|eurasia|125|1
riga|Riga|Riga|eurasia|125|1
nizhny_novgorod|Nijni Novgorod|Nizhny Novgorod|eurasia|125|2
samara|Samara|Samara|eurasia|125|2
kazan|Kasan|Kazan|eurasia|125|2
omsk|Omsk|Omsk|eurasia|132|2
irkutsk|Irkutsk|Irkutsk|eurasia|133|2
beijing|Pekin|Beijing|east_asia|138|0
tianjin|Tiensin|Tianjin|east_asia|138|1
shanghai|Shanghai|Shanghai|east_asia|138|1
canton|Canton|Guangzhou|east_asia|138|1
hong_kong|Hongkong|Hong Kong|east_asia|138|1
nanking|Nanking|Nanjing|east_asia|138|1
hankow|Hankow|Wuhan|east_asia|138|1
singan|Singan|Xi'an|east_asia|138|2
moukden|Moukden|Shenyang|east_asia|138|2
hanoi|Hanoy|Hanoi|east_asia|139|2
saigon|Saigon|Ho Chi Minh City|east_asia|139|2
tokyo|Tokyo|Tokyo|japan|142|0
yokohama|Yokohama|Yokohama|japan|142|1
nagoya|Nagoya|Nagoya|japan|142|1
kyoto|Kyoto|Kyoto|japan|142|1
osaka|Osaka|Osaka|japan|142|1
kobe|Kobe|Kobe|japan|142|1
hiroshima|Hiroshima|Hiroshima|japan|142|2
kolkata|Calcutta|Kolkata|india|140|0
bombay|Bombay|Mumbai|india|140|1
madras|Madras|Chennai|india|140|1
delhi|Delhi|New Delhi|india|140|1
lahore|Lahore|Lahore|india|140|1
allahabad|Allahabad|Allahabad|india|140|2
benares|Benares|Varanasi|india|140|2
lucknow|Lucknow|Lucknow|india|140|2
agra|Agra|Agra|india|140|2
poona|Poona|Pune|india|140|2
karachi|Kurrachee|Karachi|india|140|1
washington|Washington|Washington, D.C.|north_america|14|0
new_york|New York|New York|north_america|16|0
boston|Boston|Boston|north_america|10|1
philadelphia|Philadelphia|Philadelphia|north_america|22|1
chicago|Chicago|Chicago|north_america|39|1
st_louis|St. Louis|St. Louis|north_america|49|1
new_orleans|New Orleans|New Orleans|north_america|54|1
san_francisco|San Francisco|San Francisco|north_america|70|1
denver|Denver|Denver|north_america|65|2
omaha|Omaha|Omaha|north_america|58|2
salt_lake_city|Salt Lake City|Salt Lake City|north_america|64|2
ogden|Ogden|Ogden|north_america|64|2
oakland|Oakland|Oakland|north_america|69|2
sacramento|Sacramento|Sacramento|north_america|69|2
toronto|Toronto|Toronto|north_america|75|1
montreal|Montreal|Montreal|north_america|76|1
winnipeg|Winnipeg|Winnipeg|north_america|78|2
vancouver|Vancouver|Vancouver|north_america|79|2
buenos_aires|Buenos Aires|Buenos Aires|south_america|93|0
rosario|Rosario|Rosario|south_america|93|1
cordoba|Cordoba|Cordoba|south_america|93|2
rio_de_janeiro|Rio de Janeiro|Rio de Janeiro|south_america|90|0
sao_paulo|Sao Paulo|Sao Paulo|south_america|90|1
santos|Santos|Santos|south_america|90|2
lima|Lima|Lima|south_america|95|1
santiago|Santiago|Santiago|south_america|93|0
valparaiso|Valparaiso|Valparaiso|south_america|93|1
montevideo|Montevideo|Montevideo|south_america|93|0
cairo|Cairo|Cairo|africa|148|0
alexandria|Alexandria|Alexandria|africa|148|1
port_said|Port Said|Port Said|africa|148|2
algiers|Algiers|Algiers|africa|150|1
oran|Oran|Oran|africa|150|2
tunis|Tunis|Tunis|africa|150|1
cape_town|Cape Town|Cape Town|africa|145|0
kimberley|Kimberley|Kimberley|africa|145|2
johannesburg|Johannesburg|Johannesburg|africa|145|1
pretoria|Pretoria|Pretoria|africa|145|1
bloemfontein|Bloemfontein|Bloemfontein|africa|145|2
durban|Durban|Durban|africa|145|2
sydney|Sydney|Sydney|oceania|153|1
melbourne|Melbourne|Melbourne|oceania|153|1
adelaide|Adelaide|Adelaide|oceania|153|2
'''

# These are named, approximate topology corridors, never surveyed track.
# Only pre-1900 established trunks are candidates. Each must survive the
# independent per-corridor source review in the source notes before admission.
RAIL_ROWS = [
 ('london_manchester','europe',99,'london birmingham manchester'),
 ('london_edinburgh','europe',99,'london york newcastle edinburgh'),
 ('manchester_liverpool','europe',99,'manchester liverpool'),
 ('berlin_hamburg','europe',112,'berlin hamburg'),
 ('berlin_cologne','europe',112,'berlin cologne'),
 ('berlin_munich','europe',112,'berlin leipzig munich'),
 ('vienna_budapest','europe',114,'vienna budapest'),
 ('vienna_prague','europe',114,'vienna prague'),
 ('milan_rome','europe',116,'milan rome'),
 ('turin_milan_venice','europe',116,'turin milan venice'),
 ('moscow_petersburg','eurasia',125,'moscow st_petersburg'),
 ('moscow_nizhny','eurasia',125,'moscow nizhny_novgorod'),
 ('bombay_calcutta','india',140,'bombay allahabad benares kolkata'),
 ('delhi_calcutta','india',140,'delhi agra allahabad kolkata'),
 ('bombay_madras','india',140,'bombay poona madras'),
 ('lahore_delhi','india',140,'lahore delhi'),
 ('tokaido','japan',143,'tokyo yokohama nagoya kyoto osaka kobe'),
 ('sanyo_hiroshima','japan',142,'kobe hiroshima'),
 ('new_york_chicago','north_america',8,'new_york philadelphia chicago'),
 ('boston_new_york','north_america',8,'boston new_york'),
 ('new_york_washington','north_america',8,'new_york philadelphia washington'),
 ('chicago_st_louis','north_america',8,'chicago st_louis'),
 ('transcontinental_1869','north_america',8,'omaha ogden sacramento oakland'),
 ('buenos_aires_rosario_cordoba','south_america',93,'buenos_aires rosario cordoba'),
 ('sao_paulo_santos','south_america',90,'sao_paulo santos'),
 ('santiago_valparaiso','south_america',93,'santiago valparaiso'),
 ('cairo_alexandria','africa',148,'cairo alexandria'),
 ('algiers_oran','africa',150,'algiers oran'),
 ('cape_kimberley','africa',145,'cape_town kimberley'),
 ('cape_bloemfontein_pretoria','africa',145,'cape_town bloemfontein johannesburg pretoria'),
]

REGIONS = {
 'europe':([-25,32,30,72],[7,49]),
 'eurasia':([20,145,35,76],[55,55]),
 'east_asia':([95,133,8,54],[114,34]),
 'japan':([128,149,28,47],[137,37]),
 'india':([60,95,4,38],[78,23]),
 'north_america':([-145,-50,12,72],[-96,40]),
 'south_america':([-84,-30,-57,14],[-59,-23]),
 'africa':([-20,55,-36,38],[21,4]),
 'oceania':([110,180,-48,-9],[139,-28]),
}
RIVERS = {
 'seine':('europe',['Seine']), 'loire':('europe',['Loire']),
 'rhine':('europe',['Rhein','Rhin','Rhine']), 'danube':('europe',['Donau','Danube']),
 'po':('europe',['Po']), 'rhone':('europe',['Rhône']),
 'volga':('eurasia',['Volga']), 'dnieper':('eurasia',['Dnepre']),
 'ob':('eurasia',['Ob']), 'lena':('eurasia',['Lena']),
 'yangtze':('east_asia',['Jinsha','Chang Jiang','Yangtze']),
 'yellow_river':('east_asia',['Huang']), 'mekong':('east_asia',['Lancang','Mekong']),
 'ganges':('india',['Ganges']), 'indus':('india',['Indus']),
 'brahmaputra':('india',['Brahmaputra']),
 'mississippi':('north_america',['Mississippi']), 'missouri':('north_america',['Missouri']),
 'st_lawrence':('north_america',['St. Lawrence']), 'ohio':('north_america',['Ohio']),
 'amazon':('south_america',['Amazonas','Ucayali']), 'parana':('south_america',['Paraná']),
 'orinoco':('south_america',['Orinoco']),
 'nile':('africa',['Nile','El Bahr el Abyad','El Bahr el Azraq','Bahr el Jebel','Albert Nile','Victoria Nile']),
 'congo':('africa',['Congo','Lualaba']), 'niger':('africa',['Niger']),
 'zambezi':('africa',['Zambezi']), 'limpopo':('africa',['Limpopo']),
 'murray':('oceania',['Murray']), 'darling':('oceania',['Darling']),
}
LAKES = {
 'europe':['Lake Geneva','Bodensee','Vänern'],
 'eurasia':['Lake Baikal','Lake Ladoga','Lake Onega','Caspian Sea'],
 'east_asia':['Qinghai Hu','Tai Hu'],
 'north_america':['Lake Superior','Lake Michigan','Lake Huron','Lake Erie','Lake Ontario','Lake Winnipeg'],
 'south_america':['Lago Titicaca'],
 'africa':['Lake Victoria','Lake Tanganyika','Lake Malawi'],
}

def norm(s):
 return ''.join(c for c in unicodedata.normalize('NFKD',s).lower() if c.isalnum())

def source(source_id,title,publisher,version,locator,kind,license='PUBLIC_DOMAIN'):
 assets=[]
 for p in SOURCE.glob('philadelphiapubl00rand*' if source_id=='rand_atlas_1899' else 'ne_*.geojson'):
  if p.is_file():assets.append({'file':p.name,'bytes':p.stat().st_size})
 return {'source_id':source_id,'title':title,'publisher':publisher,'version':version,'locator':locator,'license':license,'access_metadata':{'source_date': '1899' if source_id=='rand_atlas_1899' else '2022-05-13','retrieved_on':DATE,'source_type':kind,'historical_applicability':kind,'usage_status':'Public-domain source; research scans/complete GIS excluded from release','retrieval_information':locator,'data_transformation':'Curated identities/topology and offline finite strategic LOD; no modern population/admin/rail import','uncertainty':'See per-feature evidence; contemporary atlas can contain dated/error-prone plates; no political assertions imported','source_assets':assets,'edition_date_note':'Natural Earth tag commit 2022-05-13 (not observation date)' if source_id!='rand_atlas_1899' else '1899 edition; several plates copyright1894/1895; bounded circa1900 applicability'}}

def atlas_reference(page):
 pages=json.loads((SOURCE/'atlas-pages.json').read_text(encoding='utf8'))
 leaf=max(p['leaf'] for p in pages if str(p['print_page'])==str(page))
 return ATLAS+'/page/n'+str(leaf-2)+'/mode/1up'

def bbox(points):
 return [min(p[0] for p in points),max(p[0] for p in points),min(p[1] for p in points),max(p[1] for p in points)]

def simple(points,tolerance):
 if len(points)<3:return points
 a,b=points[0],points[-1];latitude=sum(p[1] for p in points)/len(points)
 sx=111195*max(.1,math.cos(math.radians(latitude)));sy=111195
 keep={0,len(points)-1};stack=[(0,len(points)-1)]
 while stack:
  lo,hi=stack.pop();ax,ay=points[lo];bx,by=points[hi];dx=(bx-ax)*sx;dy=(by-ay)*sy;den=dx*dx+dy*dy
  far=-1;maximum=tolerance*tolerance
  for j in range(lo+1,hi):
   x=(points[j][0]-ax)*sx;y=(points[j][1]-ay)*sy;r=max(0,min(1,(x*dx+y*dy)/den)) if den else 0
   distance=(x-r*dx)**2+(y-r*dy)**2
   if distance>maximum:maximum=distance;far=j
  if far>=0:keep.add(far);stack.extend([(lo,far),(far,hi)])
 return [[round(float(x),5),round(float(y),5)] for j,(x,y) in enumerate(points) if j in keep]

def fact(feature,region,src,method,review='HISTORICAL_EVIDENCE'):
 feature.update({'valid_from':'1900-01-01','valid_to':'1901-01-01','source_id':src['source_id'],'source_date':src['access_metadata']['source_date'],'confidence':.85 if review=='HISTORICAL_EVIDENCE' else .7})
 return {'fact_id':'strategic_spatial:'+feature['id'],'domain':'strategic_spatial_content','subject_id':feature['id'],'value':feature,'unit':'display_geography','source_id':src['source_id'],'source_version':src['version'],'source_locator':src['locator'],'observation_period':{'from':'1900-01-01','to':'1900-12-31'},'spatial_scope':{'kind':'content_shard','id':region},'methodology':method,'confidence':feature['confidence'],'lower_bound':None,'upper_bound':None,'license':src['license'],'review_status':review,'generator':'tools/map/build_global_strategic.py:R1'}

def main():
 OUT.mkdir(exist_ok=True)
 atlas=source('rand_atlas_1899',"Philadelphia Public Ledger's Unrivaled Atlas of the World",'Rand McNally & Co., Chicago/New York; Allen County Public Library Genealogy Center / Internet Archive','1899',ATLAS,'HISTORICAL_EVIDENCE')
 physical=source('natural_earth_physical_5_1_2','Natural Earth rivers (50m), lakes and Caspian ocean polygon (50m); repository v5.1.2','Natural Earth / NACIS; Tom Patterson and Nathaniel Vaughn Kelso','v5.1.2','https://github.com/nvkelso/natural-earth-vector/tree/v5.1.2','PHYSICAL_REFERENCE')
 china=source('weller_china_1898','Sketch map of China and adjoining regions: existing and projected railways','F.S. Weller; Royal Geographical Society, London; Library of Congress Geography and Map Division','1898','https://www.loc.gov/item/2006458350/','HISTORICAL_EVIDENCE')
 china['access_metadata'].update({'source_date':'1898','call_number':'G7820 1898 .W4','digital_id':'g7820.ct005339','usage_status':'LOC free to use and reuse; no restrictive Rights Advisory; 1898 public-domain work','source_assets':[{'file':'china-weller-1898.jpg'}]})
 siberia=source('siberia_pocket_atlas_1900','Pocket Atlas of the Complete Steam Route Through Asia to the Pacific Ocean','Russian State Library; Library of Congress / World Digital Library','1900','https://www.loc.gov/item/2018694173/','HISTORICAL_EVIDENCE')
 siberia['access_metadata'].update({'source_date':'1900','usage_status':'LOC World Digital Library free to use and reuse absent restrictions; circa1900 public-domain source','uncertainty':'Catalog explicitly distinguishes railway as far as Irkutsk, unfinished route to Vladivostok and Amur steamship routes; no continuous1900 railway asserted','source_assets':[]})
 locator=source('natural_earth_locator_5_1_2','Natural Earth 10m populated places — locator only','Natural Earth / NACIS','v5.1.2','https://www.naturalearthdata.com/about/terms-of-use/','REFERENCE_ONLY')
 places=json.loads((SOURCE/'ne_10m_populated_places_simple.geojson').read_text())['features']
 legacy=json.loads((ROOT/'data/world_map/cities.json').read_text())['cities']
 legacy_by_id={p['id']:p for p in legacy}
 local=json.loads((ROOT/'data/local/paris_northern_france_1900.json').read_text())
 local_places={f['subject_id']:f['value'] for f in local['evidence_catalog']['facts'] if f['value']['kind']=='settlement'}
 city={};per_region={key:[] for key in REGIONS}
 atlas_pages=json.loads((SOURCE/'atlas-pages.json').read_text())
 evidence_review=[]
 approval=json.loads((ROOT/'docs/data/global-strategic-source-review.json').read_text(encoding='utf8'))
 for line in CITY_ROWS.strip().splitlines():
  slug,name,lookup,region,page,rank=line.split('|');page=int(page);rank=int(rank)
  candidates=[(j,p) for j,p in enumerate(places) if norm(lookup) in {norm(str(p['properties'].get(k) or '')) for k in ['name','nameascii','namealt']}]
  bounds=LOCATOR_BOUNDS.get(slug,REGIONS[region][0])
  candidates=[(j,p) for j,p in candidates if bounds[0]<=p['geometry']['coordinates'][0]<=bounds[1] and bounds[2]<=p['geometry']['coordinates'][1]<=bounds[3]]
  if 'place:'+slug in local_places:coords=local_places['place:'+slug]['geometry']['coordinates'];location_ref='paris_canonical:'+slug
  elif len(candidates)==1:coords=candidates[0][1]['geometry']['coordinates'];location_ref='natural_earth:'+str(candidates[0][0])
  elif slug in legacy_by_id:coords=legacy_by_id[slug]['lon_lat'];location_ref='existing_prototype_locator:'+slug
  else:raise ValueError((slug,lookup,len(candidates)))
  source_pages=[p for p in atlas_pages if str(p['print_page'])==str(page)]
  observed=any(norm(name) in norm(p['text']) or norm(lookup) in norm(p['text']) for p in source_pages)
  assert slug in approval['settlements'], 'Unreviewed settlement '+slug
  evidence_review.append({'place_id':'place:'+slug,'name':name,'printed_page':page,'ocr_match':observed,'scan_review_required':False,'review_basis':approval['settlements'][slug]})
  f={'id':'place:'+slug,'kind':'settlement','historical_name':name,'display_name':name,'geometry':{'type':'Point','coordinates':coords},'latitude':coords[1],'longitude':coords[0],'rank':rank,'max_mpp':8000 if rank==0 else 6000 if rank==1 else 2600,'coordinate_source':location_ref,'coordinate_source_id':locator['source_id'],'importance_basis':'Curated strategic display rank from the contemporary atlas named-map/chief-city evidence; no modern population used','source_reference':atlas_reference(page),'source_printed_page':page,'source_type':'HISTORICAL_EVIDENCE','uncertainty':'Representative city locator (0.5–5km, up to15km for historical town/modern metropolitan locator aliases); no built-up extent, station location, population or administration inferred','identity_status':'REUSED' if slug in legacy_by_id or 'place:'+slug in local_places else 'NEW'}
  f['coordinate_evidence_type']='REFERENCE_ONLY'
  if location_ref.startswith('paris_canonical:'):
   f['coordinate_source_id']='geonames_locator_2026'
   f['coordinate_source_reference']='res://data/local/paris_northern_france_1900.json#local_spatial:place:'+slug
  elif location_ref.startswith('existing_prototype_locator:'):
   f['coordinate_source_id']=None
   f['coordinate_source_reference']='res://data/world_map/cities.json#'+slug
  if 'place:'+slug in local_places:f['canonical_ref']='local_spatial:place:'+slug
  if slug=='hankow':
   f['source_id']=china['source_id'];f['source_reference']=china['locator'];f['source_date']='1898';f['source_printed_page']=None
  city[slug]=f
  per_region[region].append(fact(f,region,china if slug=='hankow' else atlas,'Named settlement and its prominence are evidenced independently by the 1899 atlas. Validity is a bounded circa1900 display snapshot, not foundation/closure dates. Modern coordinates are locating aids only.'))
 for slug,region,page,nodes in RAIL_ROWS:
  assert slug in approval['railways'],'Unreviewed railway '+slug
  ids=nodes.split();coords=[city[n]['geometry']['coordinates'] for n in ids]
  f={'id':'rail:historic_'+slug,'kind':'rail','display_name':' — '.join(city[n]['historical_name'] for n in ids),'places':['place:'+n for n in ids],'geometry':{'type':'LineString','coordinates':coords},'lod_geometry':{'coarse':coords,'medium':coords},'rank':1,'source_type':'HISTORICAL_EVIDENCE','geometry_evidence_type':'BOUNDED_ASSUMPTION','geometry_role':'APPROXIMATE_STRATEGIC_CORRIDOR','source_printed_page':page,'source_reference':atlas_reference(page),'operator':None,'uncertainty':'Topology corridor through named cities, not actual track alignment. Position error can be tens to hundreds of km; not admissible as simulation transport/military geometry.'}
  per_region[region].append(fact(f,region,atlas,'Historical corridor existence from contemporary atlas rail mapping; Presentation polyline uses representative endpoints/intermediate cities only. No rail geometry copied from modern networks.','APPROXIMATE'))
 for slug,region,nodes,src in [('pekin_tientsin','east_asia',['beijing','tianjin'],china),('siberian_omsk_irkutsk','eurasia',['omsk','irkutsk'],siberia)]:
  coords=[city[n]['geometry']['coordinates'] for n in nodes]
  feature={'id':'rail:historic_'+slug,'kind':'rail','display_name':' — '.join(city[n]['historical_name'] for n in nodes),'places':['place:'+n for n in nodes],'geometry':{'type':'LineString','coordinates':coords},'lod_geometry':{'coarse':coords,'medium':coords},'rank':1,'source_type':'HISTORICAL_EVIDENCE','geometry_evidence_type':'BOUNDED_ASSUMPTION','geometry_role':'APPROXIMATE_STRATEGIC_CORRIDOR','source_reference':src['locator'],'operator':None,'uncertainty':'Dated operating macro-link only. Representative endpoints joined as a dashed strategic corridor, not actual track; Siberian continuation beyond Irkutsk omitted, not a claim of completed Trans-Siberian.'}
  per_region[region].append(fact(feature,region,src,'Weller existing-vs-projected legend reviewed for Pekin–Tientsin; Siberian1900 catalog explicitly states railway as far as Irkutsk. Topology only, no routing input.','APPROXIMATE'))
 rivers=json.loads((SOURCE/'ne_50m_rivers_lake_centerlines.geojson').read_text())['features']
 for slug,(region,aliases) in RIVERS.items():
  raw=[];ne_ids=[]
  for j,feature in enumerate(rivers):
   if feature['properties'].get('name') in aliases and feature['properties']['featurecla']=='River':
    g=feature['geometry'];raw.extend(g['coordinates'] if g['type']=='MultiLineString' else [g['coordinates']]);ne_ids.append(j)
  if not raw:raise ValueError('missing river '+slug)
  f={'id':'river:'+slug,'kind':'river','display_name':slug.replace('_',' ').title(),'geometry':{'type':'MultiLineString','coordinates':raw},'lod_geometry':{lod:[simple(p,tol) for p in raw] for lod,tol in [('coarse',5000),('medium',1500)]},'source_type':'PHYSICAL_REFERENCE','natural_earth_records':ne_ids,'rank':0,'uncertainty':'Generalized modern drainage reference only. Modern reservoir lake-centerlines excluded; dams, engineering, channel migration and incomplete/suspect alignment can limit circa1900 applicability. No navigability or historical bank position claim.'}
  per_region[region].append(fact(f,region,physical,'Curated major river-axis reference, not historical channel reconstruction. Offline Douglas-Peucker coarse5000m/medium1500m; same feature/fact identity at each LOD.','APPROXIMATE'))
 lakes=json.loads((SOURCE/'ne_50m_lakes.geojson').read_text())['features']
 ocean=json.loads((SOURCE/'ne_50m_ocean.geojson').read_text())['features'][0]['geometry']['coordinates']
 caspian=[poly for poly in ocean if 40<min(c[0] for c in poly[0])<52 and 32<min(c[1] for c in poly[0])<48]
 assert len(caspian)==1
 lakes.append({'properties':{'name':'Caspian Sea','featurecla':'Lake'},'geometry':{'type':'Polygon','coordinates':caspian[0]}})
 for region,names in LAKES.items():
  for name in names:
   found=[(j,f) for j,f in enumerate(lakes) if f['properties'].get('name')==name and f['properties'].get('featurecla') in ['Lake','Alkaline Lake']]
   if len(found)!=1:raise ValueError(('lake',name,len(found)))
   j,entry=found[0];g=entry['geometry'];polygons=g['coordinates'] if g['type']=='MultiPolygon' else [g['coordinates']]
   lods={}
   for lod,tol in [('coarse',5000),('medium',1500)]:
    result=[]
    for polygon in polygons:
     rings=[]
     for ring in polygon:
      # Split a closed ring into two arcs to retain its actual area.
      half=len(ring)//2;p=simple(ring[:half+1],tol)+simple(ring[half:],tol)[1:]
      if len(p)>=4:rings.append(p)
     if rings:result.append(rings)
    lods[lod]=result
   f={'id':'lake:'+norm(name),'kind':'lake','display_name':name,'geometry':{'type':'MultiPolygon','coordinates':polygons},'lod_geometry':lods,'rank':0,'source_type':'PHYSICAL_REFERENCE','natural_earth_record':0 if name=='Caspian Sea' else j,'source_geometry_file':'ne_50m_ocean.geojson' if name=='Caspian Sea' else 'ne_50m_lakes.geojson','source_geometry_component':0 if name=='Caspian Sea' else None,'uncertainty':'Modern generalized natural-lake shoreline; circa1900 levels, shore works and dams are not reconstructed. Reservoirs, the modern Aral remnant, IJsselmeer and Salton Sea are excluded.'}
   per_region[region].append(fact(f,region,physical,'Natural water-body physical reference; finite offline shoreline LOD, not sovereignty or historical water-level evidence.','APPROXIMATE'))
 descriptors=[];counts={};coordinates=0
 for region,facts in per_region.items():
  for f in facts:
   kind=f['value']['kind'];counts[kind]=counts.get(kind,0)+1
  metadata={'schema_id':'global_strategic_content_r1','shard_id':region,'valid_from':'1900-01-01','valid_to':'1901-01-01','content_level':'strategic','local_support':False,'admin_status':'ADMIN_BOUNDARY_DATA_GAP','coastline_status':'DEFER','presentation_lods':['coarse','medium'],'rail_geometry_role':'APPROXIMATE_STRATEGIC_CORRIDOR'}
  coordinate_sources=[src for src in local['source_registry']['sources'] if src['source_id']=='geonames_locator_2026'] if region=='europe' else []
  doc={'metadata':metadata,'source_registry':{'schema_id':'historical_source_registry_v2','sources':[atlas,physical,locator,china,siberia]+coordinate_sources},'evidence_catalog':{'schema_id':'historical_fact_evidence_catalog_v2','facts':facts}}
  p=OUT/(region+'.json');p.write_text(json.dumps(doc,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
  descriptors.append({'id':region,'bounds':REGIONS[region][0],'anchor':REGIONS[region][1],'path':'res://data/strategic/'+p.name,'bytes':p.stat().st_size,'feature_count':len(facts)})
 index={'schema_id':'global_strategic_index_r1','valid_from':'1900-01-01','valid_to':'1901-01-01','regions':descriptors,'counts':counts,'scope':'Curated circa1900 strategic backbone only; no global Local support, owner, controller, administration or simulation routing facts','admin_status':'ADMIN_BOUNDARY_DATA_GAP','coastline_status':'DEFER','canonical_references':{'paris_rails':'res://data/local/paris_northern_france_1900.json#evidence_catalog — sole9 corridor identities/11parts','paris_settlements':'shared place IDs with canonical_ref; no parallel local namespace'},'data_gaps':['Trans-Siberian discontinuities and construction stages require separate dated review; no continuous1900 line fabricated.','Chinese backbone limited to dated Pekin–Tientsin; proposed trunk lines excluded.','Global medium physical coastline deferred; existing Relief/Paris coast and political geometry remain separate.','Dnieper only named upper natural river record; lower reservoir-connected reaches omitted. Volga has similar regulated-reach discontinuities.']}
 (OUT/'index.json').write_text(json.dumps(index,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
 (SOURCE.parent/'settlement-review.json').write_text(json.dumps(evidence_review,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps({'counts':counts,'runtime_bytes':sum(p.stat().st_size for p in OUT.glob('*.json')),'unmatched_ocr':[r for r in evidence_review if not r['ocr_match']]},ensure_ascii=False))

if __name__=='__main__':main()
