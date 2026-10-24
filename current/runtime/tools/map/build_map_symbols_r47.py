"""Original WWO cartographic artwork. Pillow is an offline dependency only.

One primitive source emits editable SVG and supersampled RGBA PNG. No downloaded
icons, bitmap backgrounds, geographical facts or model geometry are used.
"""
from pathlib import Path
import json
import math
import unicodedata
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/ui/map_symbols'
SOURCE = ROOT / 'tools/map/art_sources/map_symbols_r47'
INK, GOLD, IVORY, SILVER = '#493D2D', '#A88A52', '#D7C7A2', '#D9DDE0'
SCALE = 6


class Symbol:
    def __init__(self): self.shapes = []
    def polygon(self, points, fill=IVORY): self.shapes.append(('polygon', points, fill))
    def line(self, points, fill=None): self.shapes.append(('line', points, fill))
    def ellipse(self, bounds, fill=IVORY): self.shapes.append(('ellipse', bounds, fill))
    def rect(self, bounds, fill=IVORY):
        x,y,a,b=bounds; self.polygon([(x,y),(a,y),(a,b),(x,b)],fill)
    def arc(self, x,y,rx,ry,start=180,end=360):
        self.line([(x+rx*math.cos(math.radians(t)),y+ry*math.sin(math.radians(t))) for t in range(start,end+1,6)])
    def render(self, id):
        image=Image.new('RGBA',(128*SCALE,128*SCALE)); d=ImageDraw.Draw(image)
        svg=['<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">',
             '<title>WWO original map symbol: '+id+'</title>']
        for kind,points,fill in self.shapes:
            if kind=='ellipse':
                coords=tuple(round(x*SCALE) for x in points)
                d.ellipse(coords,fill=fill,outline=SILVER,width=8*SCALE)
                d.ellipse(coords,outline=INK,width=6*SCALE)
                x,y,a,b=points
                svg.append(f'<ellipse cx="{(x+a)/2}" cy="{(y+b)/2}" rx="{(a-x)/2}" ry="{(b-y)/2}" fill="{fill or "none"}" stroke="{INK}" stroke-width="6"/>')
            else:
                coords=[(round(x*SCALE),round(y*SCALE))for x,y in points]
                closed=kind=='polygon'
                if closed and fill: d.polygon(coords,fill=fill)
                edges=coords+[coords[0]] if closed else coords
                d.line(edges,fill=SILVER,width=9*SCALE,joint='curve')
                d.line(edges,fill=INK,width=6*SCALE,joint='curve')
                # Restore filled interior without an unrelated backing plate.
                tag='polygon'if closed else'polyline'
                text=' '.join(f'{x:.2f},{y:.2f}'for x,y in points)
                svg.append(f'<{tag} points="{text}" fill="{fill if closed and fill else "none"}" stroke="{SILVER}" stroke-width="9" stroke-linejoin="round" stroke-linecap="round"/>')
                svg.append(f'<{tag} points="{text}" fill="{fill if closed and fill else "none"}" stroke="{INK}" stroke-width="6" stroke-linejoin="round" stroke-linecap="round"/>')
        svg.append('</svg>')
        (SOURCE/(id+'.svg')).write_text('\n'.join(svg)+'\n',encoding='utf8')
        image=image.resize((128,128),Image.Resampling.LANCZOS)
        # No invisible RGB contamination; Godot fix_alpha_border handles edge
        # colour dilation on import, before its mip/filter sampling.
        p=image.load()
        for y in range(128):
            for x in range(128):
                if p[x,y][3]==0:p[x,y]=(0,0,0,0)
        image.save(OUT/(id+'.png'))
        return image


def house(s,x,y,w,h,roof=12):
    s.rect((x,y,x+w,y+h));s.polygon([(x-3,y),(x+w/2,y-roof),(x+w+3,y)],GOLD)
    if w>=26:s.line([(x+w/2,y+h),(x+w/2,y+h-14)])


def designs():
    result={}
    s=Symbol();s.polygon([(64+(47 if i%2==0 else 21)*math.sin(i*math.pi/5),64-(47 if i%2==0 else 21)*math.cos(i*math.pi/5))for i in range(10)]);s.ellipse((56,56,72,72),GOLD);result['capital']=s
    s=Symbol();s.polygon([(64,17),(108,64),(64,111),(20,64)]);s.polygon([(64,42),(85,64),(64,86),(43,64)],GOLD);result['admin_primary']=s
    s=Symbol();s.ellipse((25,25,103,103));s.ellipse((52,52,76,76),GOLD);result['admin_secondary']=s
    s=Symbol();house(s,18,57,26,45);house(s,49,40,30,62);house(s,84,64,26,38);result['city']=s
    s=Symbol();house(s,24,55,35,47);house(s,69,65,35,37);result['town']=s
    s=Symbol();house(s,32,58,64,44,32);s.line([(79,39),(79,29)]);result['village']=s
    s=Symbol();s.line([(22,104),(106,104)]);s.rect((31,42,50,97));s.polygon([(27,39),(33,25),(51,31),(53,41)],GOLD);s.rect((77,67,96,97));s.line([(68,62),(78,50),(100,50)]);result['historic_site']=s
    s=Symbol();s.polygon([(24,99),(24,44),(34,44),(34,29),(45,29),(45,44),(56,44),(56,29),(71,29),(71,44),(82,44),(82,29),(94,29),(94,44),(104,44),(104,99)]);s.line([(55,99),(55,76),(64,68),(73,76),(73,99)]);result['castle']=s
    s=Symbol();s.rect((30,96,98,108),GOLD);s.rect((43,86,85,97));s.polygon([(49,86),(52,34),(64,17),(76,34),(79,86)]);s.line([(64,35),(64,81)]);result['monument']=s
    s=Symbol();house(s,28,60,69,43,17);s.rect((43,35,68,103));s.polygon([(39,35),(55,17),(72,35)],GOLD);s.line([(55,103),(55,80)]);result['religious']=s
    s=Symbol();s.rect((31,70,97,103));s.polygon([(27,70),(40,65),(49,54),(79,54),(88,65),(102,70)],GOLD);s.polygon([(31,50),(44,46),(53,35),(75,35),(84,46),(97,50)],IVORY);s.polygon([(43,30),(56,24),(64,16),(72,24),(85,30)],GOLD);s.line([(64,103),(64,81)]);result['religious_temple']=s
    s=Symbol();s.rect((29,66,99,103));s.polygon([(28,66)]+[(64+34*math.cos(math.radians(t)),66+34*math.sin(math.radians(t)))for t in range(180,361,12)]+[(100,66)],GOLD);s.line([(64,32),(64,19)]);s.line([(64,103),(64,81)]);result['religious_dome']=s
    s=Symbol();house(s,24,43,80,43,15);s.line([(33,87),(23,111)]);s.line([(94,87),(104,111)]);s.line([(33,98),(95,98)]);s.line([(29,108),(99,108)]);s.ellipse((55,47,73,65),SILVER);result['station']=s
    s=Symbol();s.rect((17,39,111,53),GOLD);s.line([(17,31),(111,31)]);s.line([(24,53),(24,98)]);s.line([(64,53),(64,98)]);s.line([(104,53),(104,98)]);s.arc(44,85,20,25);s.arc(84,85,20,25);s.line([(18,107),(110,107)]);result['bridge']=s
    s=Symbol();s.ellipse((41,41,87,87));s.line([(24,64),(32,64)]);s.line([(96,64),(104,64)]);result['settlement']=s
    return result


def main():
    OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True)
    atlas=Image.new('RGBA',(576,576));items={}
    specs={'capital':(25,100,40000,True),'admin_primary':(22,90,7500,False),'admin_secondary':(19,78,1500,False),'city':(21,75,6500,True),'town':(18,55,1800,False),'village':(16,35,450,False),'historic_site':(21,68,1800,False),'castle':(21,68,1800,False),'monument':(21,70,1800,False),'religious':(21,68,1800,False),'religious_temple':(21,68,1800,False),'religious_dome':(21,68,1800,False),'station':(20,65,700,False),'bridge':(21,64,700,False),'settlement':(18,50,3000,False)}
    for i,(id,symbol)in enumerate(designs().items()):
        image=symbol.render(id);x=(i%4)*144+8;y=(i//4)*144+8;atlas.paste(image,(x,y))
        size,priority,mpp,world=specs[id]
        items[id]=dict(id=id,category=id,png=id+'.png',rect=[x,y,128,128],source_size=[128,128],screen_px=size,anchor=[.5,.5],priority=priority,region_max_mpp=mpp,world=world,world_max_mpp=40000 if id=='capital' else 18000,states=['normal','hover','selected','unavailable'],source='WWO original vector primitives; CC0-1.0')
    atlas.save(OUT/'map_symbols.png')
    document=dict(schema_id='wwo_map_symbols_r47',atlas='res://assets/ui/map_symbols/map_symbols.png',atlas_size=[576,576],cell_padding_px=8,icons=items,palette=dict(ivory=IVORY,gold=GOLD,outline=INK,edge=SILVER),states=dict(normal=[1,1,1,1],hover=[1.15,1.12,1.04,1],selected='small gold underline; no disk',unavailable=[.72,.72,.72,.6]),source='tools/map/build_map_symbols_r47.py')
    (OUT/'symbols.json').write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    # Link explicit dated capital declarations to ALREADY REGISTERED places.
    # A town name alone or rank zero never establishes a capital.
    normal=lambda s:''.join(c for c in unicodedata.normalize('NFKD',s).lower() if c.isalnum())
    places={}
    for p in sorted((ROOT/'data/strategic').glob('*.json')):
        d=json.loads(p.read_text(encoding='utf8'))
        for fact in d.get('evidence_catalog',{}).get('facts',[]):
            v=fact.get('value',{})
            if v.get('kind')=='settlement': places[v['id']]=v
    canonical=json.loads((ROOT/'data/local/paris_northern_france_1900.json').read_text(encoding='utf8'))
    for fact in canonical['evidence_catalog']['facts']:
        v=fact['value']
        if v.get('id')=='place:paris':places[v['id']]=v
    capitals=[]
    for unit in json.loads((ROOT/'data/world_map/historical/political_units_1900.json').read_text(encoding='utf8'))['units']:
        cap=unit.get('capital',{}); found=[]
        if not cap.get('name'):continue
        for id,v in places.items():
            if normal(cap['name'])!=normal(v.get('historical_name',v.get('display_name',''))):continue
            lon,lat=v.get('longitude'),v.get('latitude')
            if lon is None:lon,lat=v['geometry']['coordinates']
            distance=math.hypot((lon-cap['lon'])*111.195*math.cos(math.radians(lat)),(lat-cap['lat'])*111.195)
            if distance<10:found.append((id,lon,lat,v))
        if len(found)!=1:continue
        id,lon,lat,v=found[0]
        capitals.append(dict(place_id=id,source_historical_id=unit['id'],capital_name=cap['name'],icon='capital' if unit.get('relationship') in ['independent_state','belligerent_state'] else 'admin_primary',relationship=unit.get('relationship'),lon_lat=[lon,lat],name=v.get('display_name',cap['name']),valid_from=max(unit['valid_from'],v['valid_from']),valid_to=min(unit['valid_to'],v['valid_to']),source='res://data/world_map/historical/political_units_1900.json#'+unit['id']+'.capital',place_source=v.get('coordinate_source_reference',v.get('source_reference',''))))
    city_links={id:dict(source=v.get('source_reference',''),basis=v.get('importance_basis',''))for id,v in places.items() if v.get('source_id')=='rand_atlas_1899'}
    bindings=dict(schema_id='wwo_map_symbol_bindings_r47',valid_from='1900-01-01',valid_to='1901-01-01',capital_links=capitals,city_links=city_links,place_icons={
        'place:creil':dict(icon='town',source='https://archive.org/details/14thedbaedparis00karl/page/n490/mode/1up',basis='Existing local source OCR, printed page377 explicitly calls Creil a town; no population classification inferred'),
        'landmark:hagia_sophia_reference':dict(icon='religious_dome',source='res://data/local/internal_preview_r41/hagia_sophia.json',basis='Existing Ottoman-period dome/minaret historical reference, not modern museum status'),
        'landmark:temple_heaven_reference':dict(icon='religious_temple',source='res://data/local/internal_preview_r41/temple_heaven.json',basis='Existing 1896 Prayer Hall reconstruction reference'),
        'landmark:pisa_reference':dict(icon='monument',source='res://data/local/internal_preview_r41/pisa.json',basis='Existing medieval bell tower reference; no inferred religious administration')},unknown='settlement or historic_site; no rank-derived administrative or village identity')
    (OUT/'place_bindings.json').write_text(json.dumps(bindings,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    # An offline contact sheet is not packaged into the runtime asset directory.
    sheet=Image.new('RGB',(900,720),'#263230');draw=ImageDraw.Draw(sheet)
    for i,id in enumerate(items):
        x=(i%5)*180;y=(i//5)*230
        draw.rectangle((x+90,y,x+179,y+220),fill='#e6dfc8')
        image=Image.open(OUT/(id+'.png'))
        for size,top in [(64,12),(24,94),(20,134),(16,170)]:
            small=image.resize((size,size),Image.Resampling.LANCZOS)
            for col in [0,1]:sheet.paste(small,(x+col*90+(90-size)//2,y+top),small)
        draw.text((x+4,y+198),id,fill='#b99c61')
    sheet.save(SOURCE/'contact_sheet.png')
    print(f'{len(items)} symbols; RGBA 128x128; atlas 576x576')


if __name__=='__main__':main()
