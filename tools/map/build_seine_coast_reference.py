"""Finite modern coastal windows in the existing physical shards.

Source: offline-map-sources/seine_coast_reference/osm-coast-estuary.json,
from Overpass way[natural=coastline](49.1,-0.65,50.05,1.4);out geom.
OSM ODbL-1.0. Original acquisition remains alongside this estuary extension.
Seine uses the acquired OSM source. Other explicitly selected windows acquire
IGN high-water boundaries. Benelux uses the bounded, cached OpenMapTiles
ocean polygons. BD CARTO generalisation bounds regional payload;
Marseille retains its BD TOPO reference. No historical coastline is inferred.
Only closed differences bounded by actual intersections with the old shoreline
are replaced. Components touching the acquisition frame remain unchanged.
No rectangular closure becomes coastline. Historical ownership is not extended.
Run with the existing offline Shapely environment, then compile the affected IDs
using tools/map/compile_political_display.gd. No gameplay state is read or written.
"""
import argparse
import json
import shutil
import urllib.parse
import urllib.request
import zlib
from pathlib import Path
from shapely import constrained_delaunay_triangles, set_precision
from shapely import force_2d
from shapely.geometry import shape, mapping, box, LineString, Point, Polygon
from shapely.ops import unary_union, polygonize

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT.parent / 'offline-map-sources/seine_coast_reference'
IDS = ['physical_1_4_mid_5_1', 'physical_2_4_mid_0_1']
WINDOW = box(-.6, 49.15, 1.35, 50.0)
COORDINATE_DECIMALS = 6
COORDINATE_GRID = 10 ** -COORDINATE_DECIMALS


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf-8')


def parts(geometry, kind):
    if geometry.is_empty:
        return []
    if geometry.geom_type == kind:
        return [geometry]
    return [p for child in getattr(geometry, 'geoms', []) for p in parts(child, kind)]


def triangles(geometry):
    return [[[list(c) for c in t.exterior.coords]]
            for p in parts(set_precision(geometry, COORDINATE_GRID), 'Polygon')
            for t in parts(constrained_delaunay_triangles(p), 'Polygon') if t.area > 1e-16]


def packed(path, value):
    def compact_coordinates(item):
        if isinstance(item, float):
            return round(item, COORDINATE_DECIMALS)
        if isinstance(item, (list, tuple)):
            return [compact_coordinates(child) for child in item]
        if isinstance(item, dict):
            return {key: compact_coordinates(child) for key, child in item.items()}
        return item

    # Six decimal places keep positions to about 0.11 m at the equator.
    data = json.dumps(compact_coordinates(value), ensure_ascii=False, separators=(',', ':')).encode()
    path.write_bytes(zlib.compress(data, 9))
    return dict(path='res://'+path.relative_to(ROOT).as_posix(), encoding='ZLIB_JSON_UTF8',
                bytes=path.stat().st_size, decoded_bytes=len(data))


def cached_east_spain_ocean():
    """Build the missing east-coast windows from the retained Iberian tiles."""
    from build_benelux_city_context import decode, tile_bounds

    root = ROOT.parent/'offline-map-sources'
    cache = root/'iberian_settlement_reference'
    # Only the connected Spanish Mediterranean shore and the border coast.
    scope = unary_union([box(-.79,38.62,.87,40.60), box(.70,40.37,3.57,42.56)])
    tile_url = read(cache/'tilejson.json')['tiles'][0]
    occupied = unary_union([
        shape(raw['coverage'])
        for directory in ('tarragona_harbour', 'iberia_city_harbours', 'southeastern_spain_harbours')
        for raw in [read(root/(directory+'_coast_reference')/'coastal_sea.geojson')]
        if raw['tile_url'] == tile_url
    ])
    coast = []
    coverage = []
    count = 0
    higher = occupied
    for zoom in (13,9):
        cells = []
        for path in sorted(cache.glob(f'{zoom}-*.pbf')):
            key = tuple(map(int,path.stem.split('-')))
            cell = box(*tile_bounds(*key))
            if not cell.intersects(scope): continue
            patch = cell.intersection(scope).difference(higher)
            if patch.is_empty or patch.area==0: continue
            sea = [geometry for properties,geometry in decode(path,*key,['water'])['water'] if properties.get('class')=='ocean']
            if not sea: continue
            coast.append(unary_union(sea).intersection(patch))
            cells.append(patch)
            count += 1
        coverage.extend(cells)
        higher = higher.union(unary_union(cells))
    if not count: raise ValueError('No retained east Spain ocean tiles')
    return dict(geometry=mapping(unary_union(coast)),coverage=mapping(unary_union(coverage)),
                source_tiles=count,source_z=9,tile_url=tile_url,license='ODbL-1.0',
                basis='MODERN_OSM_SEA_POLYGONS_NOT_1900_COAST')


def main():
    global SOURCE, IDS, WINDOW
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--area',choices=['seine','brittany','marseille','marseille_west','nice_toulon','gironde','loire','benelux','iberia','belfast','east_spain'],default='seine')
    parser.add_argument('--ocean-window',help='Use cached coastal_sea.geojson in the named coastal reference directory.')
    args=parser.parse_args()
    area=args.ocean_window or args.area
    if args.ocean_window and (not area.isascii() or not area.replace('_','').isalnum()):
        parser.error('--ocean-window requires an ASCII area name')
    index_path=ROOT/'data/strategic/index.json'
    index=read(index_path)
    descriptors={row['id']:row for parent in index['coast_regions'] for row in parent.get('medium_regions',[])}
    ign=False
    tiled_ocean=bool(args.ocean_window) or area in ('benelux','iberia','belfast','east_spain')
    cached_ocean=None
    if tiled_ocean:
        SOURCE=ROOT.parent/f'offline-map-sources/{area}_coast_reference';SOURCE.mkdir(exist_ok=True)
        settlement={'iberia':'iberian','belfast':'british'}.get(area,area)
        raw_path=SOURCE/'coastal_sea.geojson' if args.ocean_window else ROOT.parent/f'offline-map-sources/{settlement}_settlement_reference/coastal_sea.geojson'
        if area=='east_spain' and not args.ocean_window: cached_ocean=cached_east_spain_ocean()
        elif not raw_path.exists():raise ValueError('Prepare bounded coastal source tiles first')
        WINDOW=shape((cached_ocean or read(raw_path))['coverage'])
        IDS=[row['id'] for row in descriptors.values() if box(row['bounds'][0],row['bounds'][2],row['bounds'][1],row['bounds'][3]).intersects(WINDOW)]
    elif area!='seine':
        bounds={'brittany':[-5.3,47.15,-1.6,49.15],'marseille':[4.85,42.95,5.8,43.65],'marseille_west':[4.68,43.22,5.02,43.60],'nice_toulon':[5.65,42.95,7.65,43.95],'gironde':[-1.4,44.6,-.25,45.7],'loire':[-2.7,46.8,-1.1,47.6]}[area]
        SOURCE=ROOT.parent/('offline-map-sources/'+area+'_coast_reference');SOURCE.mkdir(exist_ok=True)
        WINDOW=box(*bounds)
        IDS=[row['id'] for row in descriptors.values() if box(row['bounds'][0],row['bounds'][2],row['bounds'][1],row['bounds'][3]).intersects(WINDOW)]
        ign=True
        raw_path=(SOURCE.parent/'marseille_coast_reference' if area=='marseille_west' else SOURCE)/'ign-high-water-coast.json'
        if not raw_path.exists():
            if area=='marseille_west': raise ValueError('Missing retained Marseille high-water lines')
            w,s,e,n=bounds
            # The regional Brittany view does not need BD TOPO's coastal
            # survey density. BD CARTO is the admitted generalised source.
            layer='BDTOPO_V3:limite_terre_mer' if area=='marseille' else 'BDCARTO_V5:limite_terre_mer'
            query=dict(service='WFS',version='2.0.0',request='GetFeature',typenames=layer,outputFormat='application/json',srsName='EPSG:4326',bbox=f'{s-.1},{w-.1},{n+.1},{e+.1},urn:ogc:def:crs:EPSG::4326',count=1000,sortBy='cleabs')
            features=[];total=None
            for offset in range(0,50000,1000):
                page=SOURCE/f'ign-{layer.split(":")[0]}-coast-{offset:06d}.json'
                if not page.exists():
                    request=urllib.request.Request('https://data.geopf.fr/wfs/ows?'+urllib.parse.urlencode(query|{'startIndex':offset}),headers={'User-Agent':'WWO bounded offline physical reference'})
                    with urllib.request.urlopen(request,timeout=100) as response:payload=response.read(12*1024*1024+1)
                    if len(payload)>12*1024*1024:raise ValueError('Coast page exceeds 12MiB')
                    doc=json.loads(payload)
                    if 'features' not in doc:raise ValueError('Missing IGN coast page')
                    page.write_bytes(payload)
                doc=read(page);total=int(doc['numberMatched']);features.extend(doc['features'])
                print(area,'source coast',len(features),'/',total,flush=True)
                if len(features)>=total:break
            if len(features)!=total or len({f['id'] for f in features})!=total:raise ValueError('Incomplete coast reference')
            write(raw_path,dict(type='FeatureCollection',features=features,source='IGN '+layer,retrieved_on='2026-11-08'))
    baseline = SOURCE / 'baseline'
    baseline.mkdir(exist_ok=True)
    documents={}
    geometry_paths={}
    ink_paths={}
    for id in IDS:
        descriptor=descriptors[id]
        document_path=ROOT/descriptor['path'].removeprefix('res://')
        documents[id]=read(document_path)
        asset=next(f['value']['geometry_asset']['path'] for f in documents[id]['evidence_catalog']['facts'] if f['value']['kind']=='land_reference')
        geometry_paths[id]=ROOT/asset.removeprefix('res://')
        ink_paths[id]=ROOT/descriptor['ink_asset']['path'].removeprefix('res://')
        for suffix,installed in (('.json',document_path),('.geom',geometry_paths[id]),('.ink.geom',ink_paths[id])):
            destination = baseline / (id+suffix)
            if not destination.exists():
                shutil.copyfile(installed, destination)
    raw = cached_ocean or read(raw_path if tiled_ocean or ign else SOURCE/'osm-coast-estuary.json')
    lines = [] if tiled_ocean else ([force_2d(shape(f['geometry'])) for f in raw['features'] if f['properties'].get('niveau')=='Plus hautes eaux'] if ign else [LineString([(p['lon'], p['lat']) for p in row['geometry']])
             for row in raw['elements'] if len(row.get('geometry', [])) >= 2])
    lines=[p for line in lines for p in parts(line,'LineString')]
    geometries = {id: json.loads(zlib.decompress(geometry_paths[id].read_bytes())) for id in IDS}
    original = unary_union([shape(g['land_reference:'+id]['geometry']) for id, g in geometries.items()])
    # OSM coastline is directed with land on the left. Classify each closed
    # polygon by a real incident segment, not by proximity to a country.
    land_faces = [WINDOW.difference(shape(raw['geometry']))] if tiled_ocean else []
    ambiguous_faces = []
    faces = [] if tiled_ocean else polygonize(unary_union([WINDOW.boundary]+[line.intersection(WINDOW) for line in lines]))
    for face in faces:
        if ign:
            # IGN's lines are not declared to carry OSM's left-land direction.
            # The old admitted physical land labels the two large faces. An
            # ambiguous face stays unchanged; small unanchored islands are
            # not promoted to newly known land.
            overlap=face.intersection(original).area/max(face.area,1e-20)
            if .4<overlap<.6:
                ambiguous_faces.append(list(face.bounds));land_faces.append(face.intersection(original));continue
            if overlap>=.6:land_faces.append(face)
            continue
        classification = None
        for line in lines:
            if face.boundary.intersection(line).length < 1e-6:
                continue
            for a, b in zip(line.coords, list(line.coords)[1:]):
                mid = Point((a[0]+b[0])/2, (a[1]+b[1])/2)
                if face.boundary.distance(mid) > 1e-9 or not WINDOW.contains(mid):
                    continue
                dx, dy = b[0]-a[0], b[1]-a[1]
                length = (dx*dx+dy*dy)**.5
                if length == 0:
                    continue
                classification = face.covers(Point(mid.x-dy/length*1e-6, mid.y+dx/length*1e-6))
                break
            if classification is not None:
                break
        if classification is None:
            raise ValueError('Source coastline does not classify a closed face')
        if classification:
            land_faces.append(face)
    fine = set_precision(unary_union(land_faces).simplify(8/111195, preserve_topology=True), 1e-9)
    restore_dry_land = tiled_ocean and raw.get('restore_dry_land_only', False)
    dry_land_bounds = raw.get('dry_land_bounds') if restore_dry_land else None
    if restore_dry_land:
        difference = fine.difference(original)
        if dry_land_bounds:
            dry_land_scope = box(*dry_land_bounds)
            if not WINDOW.contains(dry_land_scope) or dry_land_scope.distance(WINDOW.boundary) <= 1e-8:
                raise ValueError('Dry land display patch must be inside the source coverage')
            difference = difference.intersection(dry_land_scope)
    else:
        difference = original.intersection(WINDOW).symmetric_difference(fine)
    differences = parts(difference, 'Polygon')
    closed = [p for p in differences if p.distance(WINDOW.boundary) > 1e-8]
    correction = set_precision(unary_union(closed), 1e-9)
    updated = set_precision(original.difference(correction).union(fine.intersection(correction)), 1e-9)
    historic = read(ROOT/'data/world_map/historical/cshapes_1900_snapshot.json')['features']
    source = dict(source_id='osm_seine_coast_reference' if area=='seine' else 'osm_'+area+'_coast_reference', title='Modern '+area+' high-water coast',
                  publisher='© OpenStreetMap contributors', version=raw.get('osm3s',{}).get('timestamp_osm_base','2026-11-08'),
                  locator='https://www.openstreetmap.org/copyright', license='ODbL-1.0',
                  access_metadata=dict(source_type='PHYSICAL_REFERENCE', source_scale='Mixed OSM source scale; accuracy unquantified',
                    bounds_lon_lat=[WINDOW.bounds[0],WINDOW.bounds[2],WINDOW.bounds[1],WINDOW.bounds[3]], retrieved_on='2026-11-08',
                    historical_applicability='Modern high-water reference, not 1900 port/coast reconstruction',
                    data_transformation='Directed-source polygonisation; 8m display simplification; only closed shoreline differences at real NE/OSM intersections. Acquisition-edge differences excluded.'))
    if ign:
        source.update(source_id='ign_'+area+'_coast_reference',publisher='© IGN',version=('BD TOPO V3' if area in ('marseille','marseille_west') else 'BD CARTO V5 generalised')+' source read 2026-11-08',locator='https://data.geopf.fr/wfs/ows',license='Etalab-Open-Licence-2.0')
        source['access_metadata']['data_transformation']='IGN high-water lines polygonised; old admitted land labels dominant closed faces; 8m display simplification. Only closed shoreline differences replaced. Ambiguous labels and acquisition-edge differences are not invented.'
    elif tiled_ocean:
        source['title']='Modern '+area+' OSM coastline reference'
        source['version']='OpenFreeMap snapshot '+raw['tile_url'].split('/planet/')[1].split('/')[0]
        source['access_metadata']['retrieved_on']=raw.get('retrieved_on','2026-11-08')
        source['access_metadata']['historical_applicability']='Modern OSM coast; tidal datum and 1900 engineering not established.'
        if area=='benelux':source['access_metadata']['historical_applicability']+=' Existing near-1900 Zuiderzee overlay retained separately.'
        source['access_metadata'].update(source_type='OpenMapTiles ocean polygons from OSM coastline',source_zoom=raw['source_z'],tile_url=raw['tile_url'],source_tiles=raw['source_tiles'],data_transformation='Complete admitted coastal tile coverage minus source ocean polygons; only closed differences away from coverage edges replace old land/sea/coast together.')
        if restore_dry_land:
            source['access_metadata'].update(
                source_type='OpenMapTiles estuary water polygons from OSM',
                data_transformation='Restore closed dry land omitted by the legacy coast. Retain existing land and render estuary channels in the city ground layer.',
            )
            if dry_land_bounds:
                source['access_metadata'].update(
                    dry_land_bounds=dry_land_bounds,
                    data_transformation='Restore source dry land in a bounded town display patch within the admitted coastal coverage.',
                )
    summaries = []
    for id in IDS:
        # Reuse the installed shard so a cached rerun preserves coast work
        # from other windows. Baselines remain recovery inputs, not live ink.
        doc = documents[id]
        bounds = next(f['value']['bounds_lon_lat'] for f in doc['evidence_catalog']['facts'] if f['value']['kind']=='land_reference')
        cell = box(bounds[0], bounds[2], bounds[1], bounds[3])
        if tiled_ocean and not correction.intersects(cell):
            continue
        land = set_precision(unary_union(parts(updated.intersection(cell), 'Polygon')), COORDINATE_GRID)
        geo = geometries[id]
        for kind, geometry in [('land_reference', land), ('ocean_reference', cell.difference(land))]:
            geo[kind+':'+id] = dict(geometry=dict(type='MultiPolygon', coordinates=[mapping(p)['coordinates'] for p in parts(geometry, 'Polygon')]),
                                    lod_geometry=dict(medium=triangles(geometry) if kind=='land_reference' else []))
        coast = set_precision(land.boundary.difference(cell.boundary), COORDINATE_GRID)
        xy = [list(map(list, line.coords)) for line in parts(coast, 'LineString')]
        geo['coast:'+id] = dict(geometry=dict(type='MultiLineString', coordinates=xy), lod_geometry=dict(medium=xy))
        geom_asset = packed(ROOT/'data/strategic'/(id+'.geom'), geo)
        ink = json.loads(zlib.decompress(ink_paths[id].read_bytes()))
        rows, indices = [], []
        for triangle, reference in zip(ink['triangles'], ink['indices']):
            polygon = Polygon(triangle[0])
            if not polygon.intersects(correction):
                rows.append(triangle); indices.append(reference)
            else:
                remaining = triangles(polygon.difference(correction))
                rows.extend(remaining); indices.extend([reference]*len(remaining))
        remaining = land.intersection(correction)
        for feature in reversed(historic):
            polygon = shape(feature['geometry'])
            if not polygon.intersects(remaining):
                continue
            overlap = remaining.intersection(polygon)
            added = triangles(overlap)
            if added:
                if feature['id'] not in ink['references']:
                    ink['references'].append(feature['id'])
                rows.extend(added); indices.extend([ink['references'].index(feature['id'])]*len(added))
            remaining = remaining.difference(overlap)
        added = triangles(remaining)
        rows.extend(added); indices.extend([0]*len(added))
        ink.update(triangles=rows, indices=indices,
                   method='Original partition retained outside finite closed '+area+' coast corrections; changed physical land intersected with original historical sources. Unassigned land stays neutral.',
                   license='Physical NE public domain / '+source['license']+'; historical contribution retains CC BY-NC-SA 4.0')
        ink_asset = packed(ROOT/'data/strategic'/(id+'.ink.geom'), ink)
        doc['source_registry']['sources']=[s for s in doc['source_registry']['sources'] if s['source_id']!=source['source_id']]+[source]
        for fact in doc['evidence_catalog']['facts']:
            value=fact['value']
            previous_path=value.get('geometry_asset',{}).get('path','').removeprefix('res://')
            if previous_path and ROOT/previous_path==geometry_paths[id]:
                value['geometry_asset'] = geom_asset
            if value['kind'] not in ('land_reference','ocean_reference','coast'):
                continue
            fact['methodology'] += ' Finite modern '+area+' coast correction; matching land/water/coast. Other coast unchanged.'
            fact['generator'] = 'tools/map/build_seine_coast_reference.py'
            fact['value']['coast_detail_source'] = source['source_id']
            details=[s for s in doc['source_registry']['sources'] if s['source_id'].startswith(('osm_','ign_')) and 'coast_reference' in s['source_id']]
            fact['value']['coast_detail_sources']=[s['source_id'] for s in details]
            fact.update(source_id=source['source_id'], source_version=source['version'], source_locator=source['locator'], license=source['license'])
            fact['value']['source_id'] = source['source_id']
        document_output=ROOT/'data/strategic'/(id+'.json')
        write(document_output, doc)
        descriptor=descriptors[id]
        descriptor.update(path='res://'+document_output.relative_to(ROOT).as_posix(),bytes=document_output.stat().st_size,ink_asset=ink_asset)
        summaries.append(dict(id=id, ink_asset=ink_asset, geometry_bytes=geom_asset['bytes'], triangles=len(rows), unknown_added_area_deg2=remaining.area))
    write(index_path, index)
    local_path = ROOT/'data/local/paris_northern_france_1900.json'
    local = read(local_path) if area=='seine' else None
    sea = WINDOW.difference(updated)
    clipped_lines = 0
    for fact in local['evidence_catalog']['facts'] if local is not None else []:
        feature = fact['value']
        if feature.get('kind') != 'river':
            continue
        original_line = shape(feature['geometry'])
        display = original_line.difference(sea)
        if display.equals(original_line):
            continue
        feature.update(display_geometry=dict(type='MultiLineString', coordinates=[list(map(list, p.coords)) for p in parts(display, 'LineString')]),
                       display_geometry_role='RIVER_STROKE_CLIPPED_AT_INSTALLED_MODERN_SEA', display_geometry_source=source['source_id'], display_geometry_license='ODbL-1.0; original Sandre Etalab-2.0 retained')
        clipped_lines += 1
    if local is not None:
        local_sources = local['source_registry']['sources']
        local['source_registry']['sources'] = [s for s in local_sources if s['source_id']!=source['source_id']]+[source]
        write(local_path, local)
    write(SOURCE/'source.json', dict(source=source, ways=len(lines), vertices=sum(len(line.coords) for line in lines),
          closed_corrections=len(closed), excluded_edge_components=len(differences)-len(closed),
          ambiguous_faces_preserved=ambiguous_faces,
          excluded_edge_bounds=[list(p.bounds) for p in differences if p.distance(WINDOW.boundary)<=1e-8],
          clipped_river_strokes=clipped_lines, outputs=summaries))
    print(json.dumps(dict(closed_corrections=len(closed), outputs=summaries), ensure_ascii=False))


if __name__ == '__main__':
    main()
