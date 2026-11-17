from urllib.request import urlopen
from urllib.parse import urlencode
import json
from pathlib import Path
from shapely.geometry import Point, shape

root = Path(__file__).parent
points = json.loads((root / 'source-points-local.json').read_text(encoding='utf-8'))
queries = {
    'greenland': [(-48.613627, 68.195896)],
    'sahara': [(1.195277, 33.007653), (1.409981, 32.836037), (1.430881, 32.759237)],
    'bosten': [(88.954954, 41.941362)],
}
server = 'https://maps.fsc.org/server/rest/services/Hosted/Optimized_Hyrdo/FeatureServer/0/query'
for name, coords in queries.items():
    for k, (lon, lat) in enumerate(coords):
        envelope = lon-.02,lat-.02,lon+.02,lat+.02
        url = server+'?'+urlencode(dict(
            where='1=1', f='geojson', geometryType='esriGeometryEnvelope',
            geometry=','.join(map(str,envelope)), inSR=4326, outSR=4326,
            spatialRel='esriSpatialRelIntersects', outFields='*',
        ))
        try:
            with urlopen(url, timeout=22) as response:
                raw = response.read(1_000_000)
            data = json.loads(raw)
            if 'features' not in data:
                print(name, data)
                continue
            (root/f'hydro-screen-{name}-{k}.geojson').write_bytes(raw)
            pt = Point(lon,lat)
            for d, ft in sorted(((pt.distance(shape(ft['geometry'])),ft) for ft in data['features']), key=lambda r:r[0])[:4]:
                print(name, k, round(d,6), {key:v for key,v in ft['properties'].items() if key.lower() not in ('objectid','shape__length')})
            if not data['features']: print(name,k,'no features')
        except (ValueError, OSError) as exc: print(name,k,exc)

