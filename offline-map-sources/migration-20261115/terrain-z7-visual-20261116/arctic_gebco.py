from urllib.parse import urlencode
from urllib.request import urlopen
from pyproj import Transformer
import xml.etree.ElementTree as ET
from pathlib import Path

endpoint = 'https://wms.gebco.net/2024/north-polar/mapserv?'
def fetch(**parameters):
    url = endpoint + urlencode(dict(service='WMS', version='1.3.0', **parameters))
    with urlopen(url, timeout=18) as response:
        return response.read(2_000_000)
doc = ET.fromstring(fetch(request='GetCapabilities'))
for node in doc.findall('.//{*}Layer'):
    name = node.findtext('{*}Name')
    if name:
        print(name, node.attrib.get('queryable'), node.findtext('{*}Title'))
x, y = Transformer.from_crs(4326,3996, always_xy=True).transform(-175.65783355,84.91581543)
print(x,y)
bbox=f'{x-8000},{y-8000},{x+8000},{y+8000}'
for code in ('bed','tid_1','tid_2'):
    name = 'GEBCO_NORTH_POLAR_VIEW_' + code + '_2024'
    options=dict(layers=name,styles='',crs='EPSG:3996',bbox=bbox,format='image/png',width=161,height=161)
    try:
        image=fetch(request='GetMap',**options)
        if image.startswith(b'\x89PNG'):
            (Path(__file__).parent/f'arctic-gebco-{code}.png').write_bytes(image)
            print(code, 'PNG', len(image))
        else: print(code, image[:500])
        print(fetch(request='GetFeatureInfo', query_layers=name,info_format='text/plain',i=80,j=80,**options)[:1500].decode())
    except OSError as err: print(err)

