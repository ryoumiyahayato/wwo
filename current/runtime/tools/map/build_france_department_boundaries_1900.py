"""France 1900 references and coarse physical land, preserving the Paris lineage.

Offline Shapely/PROJ/pyshp only. TRF-GIS: Victor Gay, CC BY 4.0,
doi:10.7910/DVN/ULQYM5. Physical geometry: Natural Earth public domain.
"""
from pathlib import Path
import csv
import json
import math
import re
import zipfile
from math import gcd
import shapefile
from pyproj import Transformer, CRS
from shapely.geometry import Polygon, LineString, box, shape
from shapely.geometry.polygon import orient
from shapely.ops import transform, unary_union

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "local-artifacts/trf-gis-1900"
LAND = ROOT / "data/land/paris_land_pilot_r1.json"
INDEX = ROOT / "data/world_map/historical/france_department_boundaries_1900.json"
IDENTITY = ROOT / "data/world_map/historical/france_administrative_identity_1900.json"
GEOMETRY = ROOT / "data/world_map/historical/france_departments_1900"
SCOPE = {"kind":"metropolitan_france_annual_departments","id":"country_fra"}


def read(path): return json.loads(path.read_text(encoding="utf-8"))


def write(path, value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")


def parts(g):
    if g.geom_type=="Polygon": return [g] if not g.is_empty else []
    if g.geom_type in ("MultiPolygon","GeometryCollection"): return [p for child in g.geoms for p in parts(child)]
    return []


def clean(coords):
    values = list(coords)[:-1]
    result = []
    for i,b in enumerate(values):
        a,c = values[i-1],values[(i+1)%len(values)]
        if abs((b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0]))>1e-7: result.append(list(b))
    return result


def polygons_value(g):
    return [[clean(r.coords) for r in [p.exterior,*p.interiors]] for p in parts(g)]


def paris_junctions(scope, origin):
    nodes = []
    vertices = list(scope.exterior.coords)
    for a,b in zip(vertices,vertices[1:]):
        dx,dy = int(b[0]-a[0]),int(b[1]-a[1])
        divisor = gcd(abs(dx),abs(dy))
        vx,vy = dx/divisor*.25,dy/divisor*.25
        for axis in (0,1):
            for absolute in range(math.floor((min(a[axis],b[axis])+origin[axis])/5000)*5000,math.ceil((max(a[axis],b[axis])+origin[axis])/5000)*5000+1,5000):
                value = absolute-origin[axis]
                if b[axis]==a[axis]: continue
                t = (value-a[axis])/(b[axis]-a[axis])
                if not 0<=t<=1: continue
                point = (a[0]+t*dx,a[1]+t*dy)
                k = round(((point[0]-a[0])*vx+(point[1]-a[1])*vy)/(vx*vx+vy*vy))
                nodes.append((point,(a[0]+k*vx,a[1]+k*vy)))
    return nodes


def land_polygon(g, junctions):
    if g.interiors: return None
    coords = []
    for p in list(orient(g,sign=1).exterior.coords):
        q = (round(p[0]*4)/4,round(p[1]*4)/4)
        for original,snapped in junctions:
            if math.hypot(p[0]-original[0],p[1]-original[1])<1e-5: q = snapped; break
        if not coords or coords[-1]!=q: coords.append(q)
    if coords[-1]!=coords[0]: coords.append(coords[0])
    result = Polygon(clean(coords))
    return result if result.is_valid and len(clean(result.exterior.coords))<=64 else None


def build():
    seed,previous,identity = read(LAND),read(INDEX),read(IDENTITY)
    preserved = previous.get("paris_correspondence",previous["land_correspondence"])
    # No regenerated Paris cut: retain every one of the 74 leaves and 44 binary cuts.
    preserved = {**preserved,"leaf_assignments":[r for r in preserved["leaf_assignments"] if not r["id"].startswith("territory_unit:l93_")]}
    base = [r for r in seed["seed_units"] if not r["id"].startswith("territory_unit:l93_")]
    paris = unary_union([Polygon(r["local_polygon"]) for r in base])
    origin = seed["projection"]["origin_m"]
    project = Transformer.from_crs(4326,2154,always_xy=True)
    unproject = Transformer.from_crs(2154,4326,always_xy=True)
    with (RAW / "COG_DEPARTEMENTS_1900.txt").open(encoding="cp1252") as stream:
        roster = {int(r["dep"]):r for r in csv.DictReader(stream)}
    departments,attrs = {},{}
    with zipfile.ZipFile(RAW / "DEPARTEMENTS_1900.zip") as z:
        if CRS.from_wkt(z.read("DEPARTEMENTS_1900.prj").decode()).to_epsg()!=2154: raise ValueError("Unexpected source CRS")
        reader = shapefile.Reader(shp=z.open("DEPARTEMENTS_1900.shp"),dbf=z.open("DEPARTEMENTS_1900.dbf"),encoding="utf-8")
        for r in reader.iterShapeRecords():
            a = r.record.as_dict()
            if roster[int(a["dep_id"])]["dep_name"]!=a["dep_name"]: raise ValueError("1900 department identity mismatch")
            id = "administrative_region:france_"+re.sub(r"[^a-z0-9]+","_",a["dep_name"].lower()).strip("_")
            g = transform(lambda x,y:(x-origin[0],y-origin[1]),shape(r.shape.__geo_interface__))
            if not g.is_valid: raise ValueError("Invalid source department geometry")
            departments[id],attrs[id] = g,a
    political_doc = read(ROOT / "data/world_map/historical/cshapes_1900_snapshot.json")
    france = next(r for r in political_doc["features"] if r["id"]=="gw_220")
    if not france["valid_from"]<="1900-01-01"<france["valid_to"]: raise ValueError("France political record does not cover the opening date")
    geo_political = shape(france["geometry"])
    political = transform(lambda x,y: tuple(v-o for v,o in zip(project.transform(x,y),origin)),geo_political)
    xmin,ymin,xmax,ymax = geo_political.bounds
    physical_raw = read(ROOT / "local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson")
    physical_geo = unary_union([shape(r["geometry"]) for r in physical_raw["features"]]).intersection(box(xmin-1,ymin-1,xmax+1,ymax+1))
    physical = transform(lambda x,y: tuple(v-o for v,o in zip(project.transform(x,y),origin)),physical_geo).simplify(750,preserve_topology=True)
    junctions = paris_junctions(paris,origin)
    new,excluded,opening_facts = [],[],{}
    bx,by,ex,ey = political.bounds
    def tile(x,y,width):
        cell = box(x-origin[0],y-origin[1],x+width-origin[0],y+width-origin[1])
        candidates = [p for p in parts(cell.intersection(physical).difference(paris)) if p.intersection(political).area>0]
        if not candidates: return
        normalized = [land_polygon(p,junctions) for p in candidates]
        if any(p is None for p in normalized):
            next_width = 25000 if width==50000 else 5000 if width==25000 else 0
            if next_width:
                for sx in range(x,x+width,next_width):
                    for sy in range(y,y+width,next_width): tile(sx,sy,next_width)
            else: excluded.extend({"reason":"NON_SIMPLE_OR_VERTEX_LIMIT","area_km2":p.area/1e6,"local_bounds":list(p.bounds)} for p in candidates)
            return
        normalized.sort(key=lambda p:p.bounds)
        for i,p in enumerate(normalized,1):
            if p.area<1000000:
                excluded.append({"reason":"BELOW_FIRST_LAYER_GAME_AREA_1_KM2","area_km2":p.area/1e6,"local_bounds":list(p.bounds)}); continue
            id = "territory_unit:l93_s%d_x%d_y%d_p%02d" % (width//1000,x//width,y//width,i)
            # Dated political evidence assigns sovereignty. Province geometry never does.
            sovereign = "state:country_fra" if p.difference(political).area<=.5 else None
            opening_facts[id] = {"sovereign_polity_id":sovereign,
                                 "controller_polity_id":"state:country_fra" if sovereign else "",
                                 "sovereignty_basis":"FULL_CONTAINMENT_IN_DATED_COUNTRY_FRA_REFERENCE" if sovereign else "COARSE_COAST_OR_INTERNATIONAL_EDGE_UNRESOLVED",
                                 "controller_basis":"EXPLICIT_FRANCE_OPENING_CONTROL_ASSUMPTION" if sovereign else "UNKNOWN"}
            new.append({"id":id,"local_polygon":clean(p.exterior.coords),"partition_basis":"PHYSICAL_FIXED_L93_CELL",
                        "parent_id":"","base_query_width_km":width//1000})
    for x in range(math.floor((bx+origin[0])/50000)*50000,math.ceil((ex+origin[0])/50000)*50000,50000):
        for y in range(math.floor((by+origin[1])/50000)*50000,math.ceil((ey+origin[1])/50000)*50000,50000): tile(x,y,50000)
    roots = base+sorted(new,key=lambda r:r["id"])
    polygons = {r["id"]:Polygon(r["local_polygon"]) for r in roots}
    for r in roots:
        p = polygons[r["id"]]
        r["neighbor_ids"] = sorted(id for id,g in polygons.items() if id!=r["id"] and not (p.bounds[2]<g.bounds[0] or g.bounds[2]<p.bounds[0] or p.bounds[3]<g.bounds[1] or g.bounds[3]<p.bounds[1]) and p.boundary.intersection(g.boundary).length>.01)
    coverage = unary_union(list(polygons.values()))
    if abs(sum(p.area for p in polygons.values())-coverage.area)>.5: raise ValueError("Formal land overlap")
    seed.update(seed_units=roots,coverage_id="france_metropolitan_l93_50_r1",initial_land_facts=opening_facts)
    if "coverage_generation" in seed: seed["paris_generation_reference"] = seed.pop("coverage_generation")
    seed["seed_extensions"] = [r for r in seed["seed_extensions"] if r["id"]!="france_metropolitan_l93_50_r1"]+[{"id":"france_metropolitan_l93_50_r1","root_ids":sorted(r["id"] for r in new)}]
    seed["limits"].update(max_active_units=4096,max_retired_units=4096)
    seed["source_geometry"] = {"basis":"SOURCE_GEOMETRY","kind":"physical_first_layer_cells","local_polygons":polygons_value(coverage),"area_m2":coverage.area,
       "coverage_method":"Natural Earth physical connected parts clipped to fixed Lambert-93 50 km cells selected by the dated France record. Coordinates of the political or administrative borders are not copied into land. Retain Paris, refine only non-simple physical parts to 25/5 km, reject sub-1 km2 new fragments.",
       "outer_extent_basis":"DATED_FRANCE_SELECTED_PHYSICAL_CELLS","source_scale":"Natural Earth 1:10,000,000; generated coarse game partition",
       "water_policy":"GENERALIZED_PHYSICAL_MASK; inland waters not classified; existing Paris surfaces retained",
       "intentional_exclusions":excluded,"uncovered_area_m2":sum(r["area_km2"] for r in excluded)*1e6,
       "international_edge_policy":"Cells can straddle dated borders; unresolved sovereignty/control are explicit and no foreign-state simulation is created."}
    seed["source_review"].update(method=seed["source_geometry"]["coverage_method"],historical_fit="QUALIFIED_COARSE_PHYSICAL_REFERENCE",
       political_reference={"path":"res://data/world_map/historical/cshapes_1900_snapshot.json","feature_id":"gw_220","valid_from":france["valid_from"],"valid_to":france["valid_to"],"license":political_doc["source"]["license"],"role":"SELECTION_AND_SOVEREIGNTY_REFERENCE_ONLY"})
    write(LAND,seed)

    leaves = [dict(r) for r in preserved["leaf_assignments"]]
    for r in new:
        p = polygons[r["id"]]
        matching = [id for id,g in departments.items() if p.difference(g).area<=.5]
        leaves.append({"id":r["id"],"local_polygon":r["local_polygon"],"administrative_region_id":matching[0] if len(matching)==1 else None})
    members = {id:[] for id in departments}
    for r in leaves:
        if r["administrative_region_id"]: members[r["administrative_region_id"]].append(r["id"])
    source = dict(previous["source"])
    source["title"] = "Victor Gay: TRF-GIS metropolitan France 1900 annual administrative reference"
    source["access_metadata"] = dict(source["access_metadata"],method="Extract all 87 original metropolitan records. Province polygons are historical reference only; national land is physical fixed-cell geometry and single membership requires full containment. Paris lineage retained.",department_ids=sorted(a["dep_id"] for a in attrs.values()))
    descriptors = []
    units = {r["id"]:r for r in identity["units"]}
    for id,g in sorted(departments.items()):
        a = attrs[id]; row = roster[int(a["dep_id"])]; code = str(a["dep_id"])
        west,south,east,north = transform(lambda x,y:unproject.transform(x+origin[0],y+origin[1]),g).bounds
        descriptor = {"id":id,"source_dep_id":a["dep_id"],"source_dep_name":a["dep_name"],"source_area_km2":g.area/1e6,
           "local_bounds":[g.bounds[0],g.bounds[1],g.bounds[2]-g.bounds[0],g.bounds[3]-g.bounds[1]],
           "bounds":[west,east,south,north],
           "coarse_path":"res://data/world_map/historical/france_departments_1900/dep_"+code+"_coarse.json",
           "detail_path":"res://data/world_map/historical/france_departments_1900/dep_"+code+"_detail.json"}
        for lod,geometry in [("coarse",g.simplify(1500,preserve_topology=True)),("detail",g)]:
            write(ROOT / descriptor[lod+"_path"].removeprefix("res://"),{"schema_id":"trf_gis_1900_reference_geometry_v1","id":id,"source_dep_id":a["dep_id"],"source_id":source["source_id"],"observation_year":1900,"lod":lod,"local_polygons":polygons_value(geometry)})
        descriptors.append(descriptor)
        if id not in units:
            units[id] = {"id":id,"polity_id":"state:country_fra","historical_name":row["dep_name_prop"],"name_zh":row["dep_name_prop"],
              "unit_type":"territoire" if a["dep_name"].startswith("TERRITOIRE") else "departement","level":1,"parent_region_id":None,
              "capital_place_id":None,"capital_name":row["cl_name_prop"],"capital_reference_status":"PLACE_REFERENCE_MISSING",
              "identity_locator":"TRF-GIS 1900 dep_id="+code+"; COG_DEPARTEMENTS_1900 chef-lieu="+row["cl"],"source_ids":[source["source_id"]]}
        units[id].update(historical_source_dep_id=a["dep_id"],historical_source_dep_name=a["dep_name"],boundary_reference_status="HISTORICAL_GIS_RECONSTRUCTION",boundary_reference=source["access_metadata"]["doi"],boundary_note_zh=previous["temporal_note_zh"])
    unresolved = []
    for r in leaves:
        if r["administrative_region_id"]: continue
        p = Polygon(r["local_polygon"])
        overlap = sum(p.intersection(g).area for g in departments.values())
        reason = "REFERENCE_EDGE_OR_PARTIAL_SOURCE_COVERAGE" if p.area-overlap>.5 else "CROSSES_HISTORICAL_PROVINCES_PENDING_REFINEMENT"
        unresolved.append({"land_id":r["id"],"reason":reason,"area_km2":p.area/1e6})
    correspondence = dict(preserved,leaf_assignments=leaves,initial_member_ids=members,coverage_area_km2=coverage.area/1e6,
       active_unit_count=len(leaves),assigned_unit_count=sum(len(v) for v in members.values()),unknown_area_km2=sum(r["area_km2"] for r in unresolved),unresolved=unresolved)
    correspondence["fully_contained"] = preserved["fully_contained"]+[{"land_id":r["id"],"administrative_region_id":r["administrative_region_id"]} for r in leaves if r["id"].startswith("territory_unit:l93_") and r["administrative_region_id"]]
    for key in ["opening_sovereign_polity_id","opening_controller_polity_id"]: correspondence.pop(key,None)
    correspondence["opening_facts_reference"] = "land seed initial_land_facts per root; initial_politics applies only to retained Paris roots"
    reference_extent = unary_union(list(departments.values()))
    coverage_statistics = {"formal_area_km2":coverage.area/1e6,"within_trf_1900_reference_km2":coverage.intersection(reference_extent).area/1e6,
       "trf_reference_area_km2":reference_extent.area/1e6,"within_dated_political_reference_km2":coverage.intersection(political).area/1e6,
       "outside_dated_political_reference_km2":coverage.difference(political).area/1e6,
       "basis":"Offline source intersection, not legal ownership or measured dry-land area; source coastlines and scales differ."}
    index = {"schema_id":"france_department_reference_index_1900_v2","observation_year":1900,"date_precision":"YEAR","valid_from":"1900-01-01","valid_to":"1901-01-01",
       "geometry_basis":"HISTORICAL_GIS_RECONSTRUCTION","projection":seed["projection"],"source":source,"features":descriptors,
       "temporal_note_zh":previous["temporal_note_zh"],"accuracy_note_zh":previous["accuracy_note_zh"],"paris_correspondence":preserved,"land_correspondence":correspondence,"coverage_statistics":coverage_statistics}
    write(INDEX,index)
    identity.update(units=list(units.values()),coverage_status="METROPOLITAN_ANNUAL_REFERENCE",membership_status="PARTIAL_FORMAL_LAND_CORRESPONDENCE",level_name_zh="1900 法国本土历史行政参考",source_basis="年度历史 GIS 重建；当前成员独立保存在 Spatial。参考年份结束不删除当前成员。")
    identity["sources"] = [r for r in identity["sources"] if r["source_id"]!=source["source_id"]]+[source]
    write(IDENTITY,identity)
    source_registry_path = ROOT / "data/provenance/historical_source_registry.json"
    registry = read(source_registry_path)
    registry["sources"] = [r for r in registry["sources"] if r["source_id"]!=source["source_id"]]+[source]
    land_source = next(r for r in registry["sources"] if r["source_id"]=="paris_land_pilot_r1")
    land_source.update(title="France physical first-layer land with retained Paris identities",access_metadata={"source_review":seed["source_review"],"historical_admin_boundary":"SEPARATE_REFERENCE"})
    write(source_registry_path,registry)
    facts_path = ROOT / "data/provenance/historical_fact_evidence.json"
    catalog = read(facts_path)
    next(r for r in catalog["facts"] if r["fact_id"]=="administrative_identity:france_administrative_identity_1900").update(value=identity,spatial_scope={"kind":"metropolitan_historical_admin_reference","id":"country_fra"})
    next(r for r in catalog["facts"] if r["fact_id"]=="spatial_boundary:france_trf_gis_departments_1900").update(value=index,spatial_scope=SCOPE,methodology=source["access_metadata"]["method"])
    next(r for r in catalog["facts"] if r["fact_id"]=="spatial_boundary:paris_land_pilot_r1").update(value=seed,methodology=seed["source_geometry"]["coverage_method"],spatial_scope={"kind":"metropolitan_physical_cells","id":"country_fra"})
    write(facts_path,catalog)
    territory_path = ROOT / "data/world_map/territory_source_registry.json"
    territory = read(territory_path)
    record = next(r for r in territory["sources"] if r["source_snapshot_id"]==seed["source_snapshot_id"])
    record.update(dataset_name="WWO coarse France physical land with retained Paris lineage",feature_count=len(roots),geometry_scope="dated-France-selected physical cells; international edge facts may be unresolved",geometry_granularity="fixed_l93_50km_with_bounded_physical_25_5km_refinement",derivation_method=seed["source_geometry"]["coverage_method"])
    write(territory_path,territory)
    print(json.dumps({"administrative_records":len(departments),"new_roots":len(new),"active_units":len(leaves),"area_km2":coverage.area/1e6,"assigned_administration":sum(len(v) for v in members.values()),"unresolved_administration":len(correspondence["unresolved"]),"unknown_sovereignty":sum(1 for r in opening_facts.values() if r["sovereign_polity_id"] is None),"excluded_fragments":len(excluded),"excluded_area_km2":sum(r["area_km2"] for r in excluded),"width_counts":{w:sum(1 for r in new if r["base_query_width_km"]==w) for w in [50,25,5]},"source_coverage":coverage_statistics},ensure_ascii=False))


if __name__=="__main__": build()
