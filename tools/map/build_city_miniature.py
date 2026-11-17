"""Offline historical footprint generalisation. No world or economic state.

Requires Shapely, rasterio, pyproj, numpy and Pillow. The corrected GeoPackage
stays outside res://. Intermediate numeric meshes are converted by the paired
Godot producer; only compressed ArrayMesh resources and the small index ship.
"""
import argparse
import json
import math
import sqlite3
import struct
import zlib
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import shapely
from shapely.geometry import Polygon, LineString, box, shape
from shapely.ops import transform, unary_union
from PIL import Image, ImageFilter
from pyproj import Transformer
from rasterio.features import rasterize, shapes
from rasterio.transform import from_origin


class Mesh:
    def __init__(self):
        self.positions = [[], []]
        self.indices = [[], []]
        self.lookup = [{}, {}]
        self.colors = [[], []]

    def vertex(self, p, surface):
        p = tuple(round(float(v), 3) for v in p)
        table = self.lookup[surface]
        if p not in table:
            table[p] = len(table)
            self.positions[surface].extend(p)
        return table[p]

    def polygon(self, polygon, height, walls=False, cut=None):
        for tri in shapely.get_parts(shapely.constrained_delaunay_triangles(polygon)):
            points = list(tri.exterior.coords)[:3]
            # X/east, Y/up, -north. Disable culling in the shared map material.
            self.indices[0].extend(self.vertex((x, height, -y), 0) for x, y in points)
        if walls:
            for ring in [polygon.exterior, *polygon.interiors]:
                coords = list(ring.coords)
                for a, b in zip(coords, coords[1:]):
                    if cut is not None and any(abs(a[k]-v)<.05 and abs(b[k]-v)<.05 for k, v in [(0, cut[0]), (0, cut[2]), (1, cut[1]), (1, cut[3])]):
                        continue  # Partition edges are not historical facades.
                    ids = [self.vertex((a[0], height, -a[1]), 1), self.vertex((b[0], height, -b[1]), 1), self.vertex((b[0], 1, -b[1]), 1), self.vertex((a[0], 1, -a[1]), 1)]
                    self.indices[1].extend([ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]])

    def geometry(self, geometry, height, walls=False, cut=None):
        for p in shapely.get_parts(geometry):
            if p.geom_type == 'Polygon' and p.area > 1:
                self.polygon(p, height, walls, cut)

    def write(self, path):
        with path.open('wb') as f:
            colored = any(self.colors)
            f.write(b'CITYMSH2' if colored else b'CITYMSH1')
            for surface, (positions, indices) in enumerate(zip(self.positions, self.indices)):
                f.write(struct.pack('<II', len(positions)//3, len(indices)))
                f.write(np.asarray(positions, dtype='<f4').tobytes())
                f.write(np.asarray(indices, dtype='<u4').tobytes())
                if colored:
                    colors = self.colors[surface] or [1., 1., 1., 1.] * (len(positions)//3)
                    f.write(np.asarray(colors, dtype='<f4').tobytes())
        return sum(len(p)//3 for p in self.positions), sum(len(i)//3 for i in self.indices)


def polygons(g):
    return [p for p in shapely.get_parts(g) if p.geom_type == 'Polygon' and p.area > 1]


def open_spaces(cfg, structure_path):
    """Read sourced polygon rings, including holes; legacy sketches stay explicit."""
    if cfg.get('open_spaces_source'):
        doc = json.loads((structure_path.parent/cfg['open_spaces_source']).read_text(encoding='utf-8'))
        rows = doc['features']
        reference = {k:doc[k] for k in ['basis','sources','bounds'] if k in doc}
    else:
        rows = cfg['open_spaces']
        reference = {'basis':cfg.get('open_spaces_basis','MANUALLY_GENERALISED_REFERENCE'),
                     'sources':cfg.get('open_spaces_sources',[])}
    geometry = unary_union([shapely.make_valid(shape(r['geometry']) if 'geometry' in r else Polygon(r['points'])) for r in rows])
    return geometry, reference


def build_parks(args):
    """Replace only the green-space foundation; leave buildings and river LODs intact."""
    cfg = json.loads(args.structure.read_text(encoding='utf-8'))
    anchor = cfg['anchor']
    sx, sy = 111195*math.cos(math.radians(anchor[1])), 111195
    def local(x, y, z=None): return (np.asarray(x)-anchor[0])*sx, (np.asarray(y)-anchor[1])*sy
    geometry, reference = open_spaces(cfg,args.structure)
    water_doc = json.loads(args.water.read_text(encoding='utf-8'))
    parks = transform(local,geometry).difference(transform(local,shape(water_doc['geometry'])))
    mesh = Mesh()
    mesh.geometry(parks.simplify(1.5,preserve_topology=True),.5)
    args.scratch.mkdir(parents=True,exist_ok=True)
    vertices, triangles = mesh.write(args.scratch/'parks.bin')
    if not vertices: raise ValueError('No sourced park geometry')
    index_path = args.output/'index.json'
    index = json.loads(index_path.read_text(encoding='utf-8'))
    index['foundation'] = [r for r in index['foundation'] if r['id']!='parks']
    index['foundation'].append({'id':'parks','path':f'res://{args.output.as_posix()}/parks.res',
                                'vertices':vertices,'triangles':triangles})
    index['open_spaces_reference'] = reference
    index_path.write_text(json.dumps(index,separators=(',',':')),encoding='utf-8')
    print('parks',vertices,'vertices',triangles,'triangles',flush=True)


def build_water_lods(args):
    """Same acquired polygon, bounded cartographic generalisation, no new shores."""
    cfg = json.loads(args.structure.read_text(encoding='utf-8'))
    doc = json.loads(args.water.read_text(encoding='utf-8'))
    index_path = args.output/'index.json'
    index = json.loads(index_path.read_text(encoding='utf-8'))
    anchor = cfg['anchor']
    sx, sy = 111195*math.cos(math.radians(anchor[1])), 111195
    def local(x, y, z=None): return (np.asarray(x)-anchor[0])*sx, (np.asarray(y)-anchor[1])*sy
    original = transform(local, shape(doc['geometry']))
    # Cuts lie beyond the admissible camera background and never become banks.
    b = doc['camera_background_bounds']
    window = transform(local, box(*b)).buffer(200, join_style=2)
    source = original.intersection(window)
    args.scratch.mkdir(parents=True, exist_ok=True)
    levels = []
    tone_range = cfg.get('water_color_transition_longitudes', [])
    sea_reference = None
    sea_paths = cfg.get('water_color_sea_reference', [])
    if sea_paths:
        seas = []
        project = Path(__file__).resolve().parents[2]
        for relative in sea_paths:
            bundle = json.loads(zlib.decompress((project/relative.removeprefix('res://')).read_bytes()))
            seas.extend(shape(row['geometry']) for key,row in bundle.items() if key.startswith('ocean_reference:'))
        sea_reference = transform(local,unary_union(seas).intersection(box(*b)))
    if cfg.get('water_color_coastal_reference',False) and doc.get('coastal_water_geometry'):
        # This admitted coastal palette uses sourced estuary/port polygons.
        # It does not reclassify land/ocean, salinity or navigability.
        coastal_water = transform(local,shape(doc['coastal_water_geometry']))
        sea_reference = unary_union([coastal_water] if sea_reference is None else [sea_reference,coastal_water])
    for name, mpp, tolerance in [('near',8.,2.), ('district',16.,5.), ('overview',32.,10.)]:
        water = source.simplify(tolerance, preserve_topology=True)
        # The main component always survives. Tiny separate pools may disappear
        # below one screen pixel; no main-channel widening or invented link.
        pieces = polygons(water)
        main = max(pieces, key=lambda p:p.area)
        water = unary_union([p for p in pieces if p.equals(main) or p.area>=mpp*mpp])
        marine_tone = None
        if sea_reference is not None:
            # A dock/outer-harbour polygon is still water. Its seaward portion
            # shares the admitted sea palette instead of painting a green band.
            marine = [p for p in polygons(water) if p.intersection(sea_reference).area>p.area*.5]
            marine_tone = unary_union([sea_reference,*marine])
        true_shores = water.boundary.difference(window.boundary.buffer(tolerance+1))
        fringe_width = mpp*.4
        fringe = true_shores.buffer(fringe_width, quad_segs=2).difference(water)
        mesh = Mesh()
        mesh.geometry(water,2.)
        # A single narrow exterior strip, alpha=1 at water and 0 at its edge.
        # Map-space width stays below half a pixel at each intended LOD.
        for polygon in polygons(fringe):
            for tri in shapely.get_parts(shapely.constrained_delaunay_triangles(polygon)):
                for x,y in list(tri.exterior.coords)[:3]:
                    mesh.indices[1].append(mesh.vertex((x,2.,-y),1))
        if mesh.positions[1]:
            # Distance to a union is the minimum distance to its components.
            # The exact nearest-polygon query avoids scanning every distant
            # pond for every shore-strip vertex in a larger source window.
            coordinates = np.asarray(mesh.positions[1]).reshape(-1,3)
            points = shapely.points(coordinates[:,0],-coordinates[:,2])
            tree = shapely.STRtree(polygons(water))
            distances = shapely.distance(points,tree.geometries[tree.nearest(points)])
            colors = np.ones((len(points),4))
            colors[:,3] = np.clip(1.-distances/fringe_width,0.,1.)
            mesh.colors[1] = colors.ravel().tolist()
        if len(tone_range)==2 and tone_range[1]!=tone_range[0] or marine_tone is not None:
            # Colour only: the existing source-overlap strip meets the sea
            # palette without drawing a false bank at the source cut.
            for surface in [0,1]:
                positions = np.asarray(mesh.positions[surface]).reshape(-1,3)
                colors = np.asarray(mesh.colors[surface]).reshape(-1,4) if mesh.colors[surface] else np.ones((len(positions),4))
                t = np.zeros(len(positions))
                points = shapely.points(positions[:,0],-positions[:,2])
                if len(tone_range)==2 and tone_range[1]!=tone_range[0]:
                    t = np.clip((positions[:,0]/sx+anchor[0]-tone_range[0])/(tone_range[1]-tone_range[0]),0.,1.)
                    t = t*t*(3.-2.*t)
                    if cfg.get('water_color_transition_main_only',False):
                        selected = shapely.dwithin(main,points,fringe_width+.01)
                        if marine_tone is not None:
                            selected |= shapely.dwithin(marine_tone,points,fringe_width+.01)
                        t *= selected
                elif marine_tone is not None:
                    t = shapely.dwithin(marine_tone,points,fringe_width+.01).astype(float)
                colors[:,:3] *= 1.+t[:,None]*(np.array([.12,.20,.23])/np.array([.34,.46,.45])-1.)
                mesh.colors[surface] = colors.ravel().tolist()
        count, triangles = mesh.write(args.scratch/('river_'+name+'.bin'))
        levels.append({'id':name,'mpp':mpp,'path':f'res://{args.output.as_posix()}/river_{name}.res','vertices':count,'triangles':triangles,'water_triangles':len(mesh.indices[0])//3,'shore_triangles':len(mesh.indices[1])//3,'simplification_m':tolerance,'fringe_m':fringe_width,'main_component_count':1,'main_boundary_deviation_m':round(main.boundary.hausdorff_distance(max(polygons(source),key=lambda p:p.area).boundary),3)})
        print('water LOD',levels[-1],flush=True)
    index['foundation'] = [r for r in index['foundation'] if r['id'] not in ['water','water_inner','banks']]
    index['water_lods'] = {'basis':doc['role'],'source':str(args.water),'bounds':b,'levels':levels,'note':'Same modern reference polygon and holes at all scales. Main channel retained. Source-window cuts are not banks. Alpha fringe is display antialiasing, not historical shoreline. No runtime reconstruction.','source_continuity':{'sample_count':doc.get('centreline_sample_count',0),'uncovered_inside_background':doc.get('uncovered_inside_camera_background',[])}}
    index['water_lods']['color_transition_longitudes'] = tone_range
    index['water_lods']['sea_color_reference'] = sea_paths
    index['water_lods']['coastal_palette_natures'] = doc.get('coastal_water_natures',[]) if cfg.get('water_color_coastal_reference',False) else []
    index_path.write_text(json.dumps(index,separators=(',',':')),encoding='utf-8')


def build(args):
    if args.parks_only:
        build_parks(args)
        return
    if args.water_only:
        build_water_lods(args)
        return
    cfg = json.loads(args.structure.read_text(encoding='utf-8'))
    anchor = cfg['anchor']
    sx, sy = 111195*math.cos(math.radians(anchor[1])), 111195
    to_ll = Transformer.from_crs(3857, 4326, always_xy=True)
    to_merc = Transformer.from_crs(4326, 3857, always_xy=True)
    def local(x, y, z=None): return (np.asarray(x)-anchor[0])*sx, (np.asarray(y)-anchor[1])*sy
    def ll(p): return [round(p[0]/sx+anchor[0], 7), round(p[1]/sy+anchor[1], 7)]
    roads = unary_union([transform(local, LineString(r['points'])).buffer(r['width_m']/2, cap_style=2, join_style=2) for r in cfg['routes']])
    park_geometry, park_reference = open_spaces(cfg,args.structure)
    parks = transform(local,park_geometry)
    water_doc = json.loads(args.water.read_text(encoding='utf-8'))
    water = transform(local, shape(water_doc['geometry']))
    exclusion = unary_union([roads, parks, water.buffer(5)])
    args.scratch.mkdir(parents=True, exist_ok=True)
    args.output.mkdir(parents=True, exist_ok=True)
    # The same source roofs are generalised at two fixed scales, never random.
    levels = [('overview', 12., 8., 1200., False), ('district', 4., 3., 160., True)]
    bounds_ll = cfg['source_bounds']
    (x0, y0), (x1, y1) = local(bounds_ll[0], bounds_ll[1]), local(bounds_ll[2], bounds_ll[3])
    tile_size = 3000
    tiles = [(x, y) for y in range(math.floor(y0/tile_size), math.ceil(y1/tile_size)) for x in range(math.floor(x0/tile_size), math.ceil(x1/tile_size))]
    # A second sourced city can use the same producer without fabricating a
    # London-named GeoPackage table. GeoJSON input is geographic EPSG:4326.
    source_geoms = None
    source_tree = None
    if args.input.suffix.lower() in ['.json', '.geojson']:
        document = json.loads(args.input.read_text(encoding='utf-8'))
        source_geoms = shapely.from_geojson([json.dumps(f['geometry']) for f in document['features'] if f.get('geometry')])
        source_geoms = shapely.transform(source_geoms, local, interleaved=False)
        source_tree = shapely.STRtree(source_geoms)
    def tile(key):
        tx, ty = key
        bounds = (tx*tile_size, ty*tile_size, (tx+1)*tile_size, (ty+1)*tile_size)
        padded = box(*bounds).buffer(24, join_style=2)
        lo, hi = ll((bounds[0]-24, bounds[1]-24)), ll((bounds[2]+24, bounds[3]+24))
        a, b = to_merc.transform(*lo), to_merc.transform(*hi)
        if source_tree is not None:
            selected = source_tree.query(padded)
            count_source = len(selected)
            geoms = source_geoms[selected]
        else:
            c = sqlite3.connect('file:'+args.input.resolve().as_posix()+'?mode=ro', uri=True)
            table = 'london_buildings_1891-96_corr_v1'
            raw = c.execute(f'SELECT b.geom FROM "{table}" b JOIN "rtree_{table}_geom" r ON b.fid=r.id WHERE r.maxx>? AND r.minx<? AND r.maxy>? AND r.miny<?', (a[0], b[0], a[1], b[1])).fetchall()
            c.close()
            count_source = len(raw)
            geoms = shapely.from_wkb([bytes(r[0])[{0:8, 1:40, 2:56, 3:56, 4:72}[(r[0][3]>>1)&7]:] for r in raw])
            geoms = shapely.transform(geoms, to_ll.transform, interleaved=False)
            geoms = shapely.transform(geoms, local, interleaved=False)
        if not count_source: return None
        invalid = int(np.count_nonzero(~shapely.is_valid(geoms)))
        if invalid: geoms = shapely.make_valid(geoms)
        geoms = geoms[shapely.area(geoms) >= 9]
        if not len(geoms): return None
        result = {'id':f'{tx}_{ty}', 'bounds':[ll(bounds[:2]),ll(bounds[2:])], 'source_count':count_source, 'invalid_repaired':invalid, 'lods':{}}
        mask = exclusion.intersection(padded)
        for level, resolution, tolerance, area_min, walls in levels:
            n = int((tile_size+48)/resolution)
            grid = from_origin(bounds[0]-24, bounds[3]+24, resolution, resolution)
            pixels = rasterize(((g, 1) for g in geoms), out_shape=(n,n), transform=grid, fill=0, dtype='uint8')
            # Morphological closing is bounded to one pixel. Explicit primary
            # routes, parks and water are cut afterwards at both levels.
            image = Image.fromarray(pixels*255).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
            # Do not erase source buildings to force an approximate route or
            # park outline. Only remove closing-added pixels in those spaces.
            original = pixels.copy()
            pixels = np.asarray(image).copy()//255
            if not mask.is_empty:
                blocked = rasterize([(mask,1)], out_shape=(n,n), transform=grid, dtype='uint8')>0
                pixels[blocked] = original[blocked]
            wet = water.buffer(5).intersection(padded)
            if not wet.is_empty: pixels[rasterize([(wet,1)],out_shape=(n,n),transform=grid,dtype='uint8')>0]=0
            mesh = Mesh(); count = 0
            for geom, value in shapes(pixels, mask=pixels>0, transform=grid):
                if not value: continue
                p = shape(geom).simplify(tolerance, preserve_topology=True).intersection(box(*bounds))
                for part in polygons(p):
                    if part.area < area_min: continue
                    mesh.polygon(part, 8 if walls else 1.5, walls and part.area>700, bounds)
                    count += 1
            if count:
                name = f'{level}_{tx}_{ty}'
                vertices, triangles = mesh.write(args.scratch/(name+'.bin'))
                result['lods'][level] = {'path':f'res://{args.output.as_posix()}/{name}.res', 'blocks':count, 'vertices':vertices, 'triangles':triangles}
        return result if result['lods'] else None
    rows = []
    results = json.loads((args.output/'index.json').read_text(encoding='utf-8'))['tiles'] if args.foundation_only else ThreadPoolExecutor(max_workers=args.workers).map(tile, tiles)
    for row in results:
        if row:
            rows.append(row)
            print('tile', row['id'], 'source',row['source_count'], 'blocks',{k:v['blocks'] for k,v in row['lods'].items()},flush=True)
    # One coarse whole-city draw; detailed geometry remains spatially tiled.
    overview = Mesh()
    for row in rows:
        if 'overview' not in row['lods']: continue
        p = args.scratch/('overview_'+row['id']+'.bin')
        if not p.exists(): continue
        data = p.read_bytes(); count, indices = struct.unpack_from('<II',data,8)
        start = len(overview.positions[0])//3
        overview.positions[0].extend(np.frombuffer(data,dtype='<f4',count=count*3,offset=16).tolist())
        overview.indices[0].extend((np.frombuffer(data,dtype='<u4',count=indices,offset=16+count*12)+start).tolist())
    ov_vertices, ov_triangles = overview.write(args.scratch/'overview.bin')
    # Foundation uses the same cartesian anchor and offline topology.
    if args.buildings_only:
        previous = json.loads((args.output/'index.json').read_text(encoding='utf-8'))
        previous.update(tiles=rows,overview={'path':f'res://{args.output.as_posix()}/overview.res','vertices':ov_vertices,'triangles':ov_triangles})
        (args.output/'index.json').write_text(json.dumps(previous,separators=(',',':')),encoding='utf-8')
        print('Building layers updated; water and foundation unchanged',flush=True)
        return
    foundation = []
    bridges = unary_union([transform(local, LineString(r['points'])).buffer(r['width_m']/2,cap_style=2) for r in cfg['bridges']])
    for name, geometry, height in [('water', water, 2), ('water_inner', water.buffer(-12), 2.03), ('banks', water.boundary.buffer(3).difference(water), 1.9), ('parks', parks.difference(water), .5), ('routes', roads.difference(water), .9), ('bridges',bridges,3.5)]:
        mesh = Mesh(); mesh.geometry(geometry.simplify(1.5, preserve_topology=True), height)
        vertices, triangles = mesh.write(args.scratch/(name+'.bin'))
        if not vertices: continue
        foundation.append({'id':name,'path':f'res://{args.output.as_posix()}/{name}.res','vertices':vertices,'triangles':triangles})
    index = {'schema':'city_historical_presentation_v1','anchor':anchor,'tiles':rows,'overview':{'path':f'res://{args.output.as_posix()}/overview.res','vertices':ov_vertices,'triangles':ov_triangles},'foundation':foundation,'generalisation':{'source_minimum_m2':9,'overview_grid_m':12,'district_grid_m':4,'closing_radius_pixels':1,'height_m':8,'height_basis':'PRESENTATION_ASSUMPTION_NOT_SURVEY','note':'Building gaps are not all classified as roads. Primary route corridors are separately traced inputs.'},'water_sources':water_doc['sources']}
    index['geometry_basis'] = cfg.get('geometry_basis','HISTORICAL_FOOTPRINT_REFERENCE')
    index['open_spaces_reference'] = park_reference
    index['mesh_chart'] = 'RegionProjection spherical azimuthal equidistant; radius 6371008.8m; index anchor. Numeric intermediates use an equirectangular production grid and are converted by save_city_meshes.gd.'
    (args.output/'index.json').write_text(json.dumps(index,separators=(',',':')),encoding='utf-8')
    print('tiles',len(rows),'source appearances',sum(r['source_count'] for r in rows),'numeric bytes',sum(p.stat().st_size for p in args.scratch.glob('*.bin')),flush=True)
    if 'camera_background_bounds' in water_doc: build_water_lods(args)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True)
    p.add_argument('--structure',type=Path,required=True)
    p.add_argument('--water',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--scratch',type=Path,required=True)
    p.add_argument('--workers',type=int,default=1)
    p.add_argument('--water-only',action='store_true',help='Only preprocess water LODs; preserve every building and other foundation mesh.')
    p.add_argument('--parks-only',action='store_true',help='Only replace the green-space foundation; preserve buildings and river LODs.')
    p.add_argument('--foundation-only',action='store_true',help='Reuse existing footprint tiles when only foundation inputs change.')
    p.add_argument('--buildings-only',action='store_true',help='Update footprint tiles and merged overview, preserving water and foundation resources.')
    build(p.parse_args())
