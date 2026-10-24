class_name VNextSpatialWorld
extends RefCounted
## Authoritative Spatial / Infrastructure fact layer.
## Static topology is supplied by VNextSpatialCatalog. This class owns all
## dynamic facts and accepts explicit hours instead of owning a global clock.

const SNAPSHOT_SCHEMA_ID: String = "vnext_spatial_world_v2"
const DEFAULT_NOMINAL_CAPACITY_BY_TYPE: Dictionary = {
	VNextSpatialCatalog.LINK_TYPE_ROAD: 100.0,
	VNextSpatialCatalog.LINK_TYPE_RAIL: 1000.0,
	VNextSpatialCatalog.LINK_TYPE_SHIPPING: 2000.0,
}

var _catalog: VNextSpatialCatalog = null
var _current_hour: int = 0
var _infrastructure: Dictionary = {}
var _territories: Dictionary = {}
var _capacity: VNextSpatialCapacityWindow = null
var _land: LandTopology
var _land_facts: Dictionary = {}
var _land_politics: RuntimePoliticalEntityRegistry
var _land_administrations: Dictionary = {}
var _land_boundaries: Dictionary = {}
var _land_admin_document: Dictionary = {}
var _land_boundary_lods: Dictionary = {}
var _administrative_coverage: Dictionary = {}
signal administrative_display_changed
signal land_politics_changed(land_id: String)
var _administrative_display_revision: int = 0
var _opening_admin_members: Dictionary = {}
var _admin_member_view: Dictionary = {}
var _admin_member_view_revision: int = -1
var _administrative_children: Dictionary = {}
var _loaded_child_rosters: Dictionary = {}

func configure_land_administrations(document: Dictionary, boundaries: Dictionary = {}) -> bool:
	if not document.get("units") is Array: return false
	var reference_only: bool = boundaries.get("schema_id")=="historical_administrative_reference_index_v1"
	var candidate: Dictionary = {}
	for raw: Variant in document.units as Array:
		if not raw is Dictionary: return false
		var row := raw as Dictionary
		var id := str(row.get("id",""))
		if not id.begins_with("administrative_region:") or candidate.has(id) or _land_administrations.has(id) or _land_politics == null or not _land_politics.has_entity(str(row.get("polity_id",""))): return false
		candidate[id] = row.duplicate(true)
	if (not reference_only and (boundaries.get("schema_id") != "france_department_reference_index_1900_v2" or not boundaries.get("land_correspondence") is Dictionary)) or not boundaries.get("features") is Array: return false
	var seen: Dictionary = {}
	for feature: Dictionary in boundaries.features as Array:
		var id := str(feature.get("id",""))
		if not candidate.has(id) or seen.has(id) or not feature.get("local_bounds") is Array or (feature.local_bounds as Array).size()!=4 or not feature.get("bounds") is Array or (feature.bounds as Array).size()!=4 or not feature.get("coarse_path") is String or not feature.get("detail_path") is String: return false
		seen[id] = true
		candidate[id]["boundary_area_km2"] = feature.source_area_km2
		candidate[id]["reference_descriptor"] = feature.duplicate(true)
	_land_administrations.merge(candidate)
	for id: String in candidate:
		var parent := str(candidate[id].get("parent_region_id",""))
		if parent.is_empty() or parent=="<null>": continue
		if not _administrative_children.has(parent): _administrative_children[parent] = []
		_administrative_children[parent].append(id)
	if reference_only: return true
	_land_admin_document = boundaries.duplicate(true)
	for leaf: Dictionary in boundaries.land_correspondence.get("leaf_assignments",[]):
		var region := str(leaf.get("administrative_region_id",""))
		if not _opening_admin_members.has(region): _opening_admin_members[region] = []
		_opening_admin_members[region].append(str(leaf.id))
	for ids: Array in _opening_admin_members.values(): ids.sort()
	return true

func administrative_boundary_ids(date: String) -> Array[String]:
	var ids: Array[String] = []
	for id: String in _land_administrations:
		if _administrative_reference_visible(id,date): ids.append(id)
	ids.sort()
	return ids

func _administrative_reference_visible(id: String, date: String) -> bool:
	var row := _land_administrations.get(id,{}) as Dictionary
	if not row.has("reference_descriptor"): return false
	var descriptor := row.reference_descriptor as Dictionary
	if descriptor.has("reference_display_from"):
		return date>=str(descriptor.reference_display_from)
	return date>=str(_land_admin_document.get("valid_from","")) and date<str(_land_admin_document.get("valid_to",""))

func loaded_administrative_boundary_ids(date: String) -> Array[String]:
	var ids: Array[String] = []
	for id: String in _land_boundaries:
		if _administrative_reference_visible(id,date): ids.append(id)
	ids.sort()
	return ids

func administrative_reference_bounds(id: String) -> Rect2:
	var descriptor := (_land_administrations.get(id,{}) as Dictionary).get("reference_descriptor",{}) as Dictionary
	var values := descriptor.get("local_bounds",[]) as Array
	return Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3])) if values.size()==4 else Rect2()

func administrative_display_revision() -> int:
	return _administrative_display_revision

func _invalidate_administrative_display() -> void:
	_administrative_display_revision += 1
	administrative_display_changed.emit()

func _current_administrative_members() -> Dictionary:
	if _admin_member_view_revision == _administrative_display_revision: return _admin_member_view
	_admin_member_view = {}
	for id: String in _land_facts:
		var region: Variant = _land_facts[id].administrative_region_id
		if region == null: continue
		if not _admin_member_view.has(region): _admin_member_view[region] = {"ids":[],"bounds":_land.land_bounds(id)}
		_admin_member_view[region].ids.append(id)
		_admin_member_view[region].bounds = (_admin_member_view[region].bounds as Rect2).merge(_land.land_bounds(id))
	for row: Dictionary in _admin_member_view.values(): row.ids.sort()
	_admin_member_view_revision = _administrative_display_revision
	return _admin_member_view

func administrative_display_uses_members(id: String, date: String) -> bool:
	var current := _current_administrative_members().get(id,{"ids":[]}) as Dictionary
	var reference_active := _administrative_reference_visible(id,date)
	return not reference_active or current.ids != _opening_admin_members.get(id,[])

func administrative_display_bounds(id: String, date: String) -> Rect2:
	if administrative_display_uses_members(id,date):
		return (_current_administrative_members().get(id,{}) as Dictionary).get("bounds",Rect2())
	return administrative_reference_bounds(id)

func request_administrative_boundaries(view: Rect2, date: String, mpp: float, enabled: bool, selected_id: String = "", home_polity_id: String = "") -> Array[Dictionary]:
	# Display demand only. Current membership never rewrites the dated reference.
	var result: Array[Dictionary] = []
	if not enabled or _land == null or mpp>6500.0 or not view.has_area() or home_polity_id.is_empty(): return result
	var members := _current_administrative_members()
	for id: String in _land_administrations:
		var identity := _land_administrations[id] as Dictionary
		if str(identity.get("polity_id","")) != home_polity_id and id!=selected_id: continue
		# Lower units only enter the existing view demand at close range.
		var level := int(identity.get("level",1))
		var max_mpp := float(identity.get("display_max_mpp",6500.0 if level<=1 else 1400.0 if level==2 else 300.0 if level==3 else 80.0))
		if mpp>max_mpp and id!=selected_id: continue
		if mpp<float(identity.get("display_min_mpp",0.0)) and id!=selected_id: continue
		var current := administrative_display_uses_members(id,date)
		var bounds := administrative_display_bounds(id,date)
		if not view.intersects(bounds,true): continue
		if id!=selected_id and minf(bounds.size.x,bounds.size.y)/mpp<12.0: continue
		if current:
			var polygons: Dictionary = {}
			var neighbors: Dictionary = {}
			var ids := (members.get(id,{"ids":[]}) as Dictionary).ids as Array
			for land_id: String in ids:
				if not _land.land_bounds(land_id).intersects(view.grow(mpp*60.0),true): continue
				polygons[land_id] = _land.polygon(land_id)
				neighbors[land_id] = []
				for neighbor: String in _land.neighbors(land_id):
					if _land_facts[neighbor].administrative_region_id == id: neighbors[land_id].append(_land.polygon(neighbor))
			if not polygons.is_empty(): result.append({"id":id,"level":level,"lod":"members:"+str(_administrative_display_revision),"basis":"current_members","polygons":polygons,"neighbors":neighbors,"bounds":bounds})
		elif identity.has("reference_descriptor"):
			result.append({"id":id,"level":level,"descriptor":identity.reference_descriptor,"basis":"historical_reference",
				"lod":"detail" if mpp<450.0 or (_land_boundary_lods.get(id,"")=="detail" and mpp<650.0) else "coarse","bounds":bounds})
	return result

func install_administrative_boundary(id: String, components: Array, lod: String) -> void:
	_land_boundaries[id] = components
	_land_boundary_lods[id] = lod

func retain_administrative_boundaries(ids: Array[String]) -> void:
	for id: String in _land_boundaries.keys():
		if not ids.has(id):
			_land_boundaries.erase(id)
			_land_boundary_lods.erase(id)

func administrative_coverage_ready(id: String) -> bool:
	return _land != null and int((_administrative_coverage.get(id,{}) as Dictionary).get("revision",-1)) == _land.display_revision()

func install_administrative_coverage(id: String, overlaps: Dictionary, revision: int) -> void:
	if _land!=null and revision==_land.display_revision():
		_administrative_coverage[id] = {"revision":revision,"overlaps":overlaps}

func pick_administration(lon_lat: Vector2, date: String, visible_ids: Array[String]) -> String:
	if _land == null: return ""
	var land_id := _land.pick_geographic(lon_lat)
	var member: Variant = (_land_facts.get(land_id,{}) as Dictionary).get("administrative_region_id")
	# An explicit game change takes precedence over the opening reference. The
	# unchanged opening department must not intercept its displayed lower units.
	if member != null and administrative_display_uses_members(str(member),date): return str(member)
	var point := _land.from_geographic(lon_lat)
	# Only installed units in this display demand participate. Preserve deepest
	# level first and the original stable identity order within a level.
	var candidates: Array[String] = []
	for id: String in visible_ids:
		if _land_boundaries.has(id) and _administrative_reference_visible(id,date): candidates.append(id)
	candidates.sort_custom(func(a: String,b: String) -> bool:
		var a_level := int(_land_administrations[a].get("level",1))
		var b_level := int(_land_administrations[b].get("level",1))
		return a_level>b_level if a_level!=b_level else a<b)
	for id: String in candidates:
		var bounds := administrative_reference_bounds(id)
		if bounds.has_area() and not bounds.grow(0.5).has_point(point): continue
		if administrative_display_uses_members(id,date): continue
		for rings: Array in _land_boundaries[id] as Array:
			if not Geometry2D.is_point_in_polygon(point,rings[0]): continue
			var in_hole := false
			for i: int in range(1,rings.size()):
				if Geometry2D.is_point_in_polygon(point,rings[i]): in_hole = true; break
			if not in_hole: return id
	return str(member) if member != null else ""

func apply_historical_land_administration(control: TerritoryState, date: String) -> bool:
	if _land == null or control == null or not control.is_bound_to_land(_land): return false
	if not control.controller_changed.is_connected(_on_land_control_changed): control.controller_changed.connect(_on_land_control_changed)
	if administrative_boundary_ids(date).is_empty(): return true
	# Source cuts are initialization only. Explicit game mutations revoke eligibility.
	var correspondence := _land_admin_document.land_correspondence as Dictionary
	for plan: Dictionary in correspondence.get("splits",[]) as Array:
		var parent := str(plan.parent_id)
		if not _historical_land_eligible(parent,control): continue
		if not _land._same_coverage(_land.polygon(parent),_land._polygon_from_value(plan.parent_local_polygon)): continue
		var children := plan.children as Array
		if children.size()!=2: return false
		# Existing limits and split rejection leave the affected parent unresolved.
		split_land(parent,str(children[0].id),_land._polygon_from_value(children[0].local_polygon),str(children[1].id),_land._polygon_from_value(children[1].local_polygon),control,true)
	# Offline assignments use full polygons. Only the actual authored leaf may inherit one.
	for leaf: Dictionary in correspondence.get("leaf_assignments",[]) as Array:
		var id := str(leaf.id)
		var region: Variant = leaf.administrative_region_id
		if not _historical_land_eligible(id,control) or region == null or not _land_administrations.has(region): continue
		if not _land._same_coverage(_land.polygon(id),_land._polygon_from_value(leaf.local_polygon)): continue
		_land_facts[id]["administrative_status"] = "ASSIGNED"
		_land_facts[id]["administrative_region_id"] = region
	_invalidate_administrative_display()
	return true

func _historical_land_eligible(id: String, control: TerritoryState) -> bool:
	if not _land.has_land(id) or not _land_facts.has(id) or not control.has_territory(id): return false
	var facts := _land_facts[id] as Dictionary
	var opening := (_land._seed.get("initial_land_facts",{}) as Dictionary).get(id,_land._seed.initial_politics) as Dictionary
	return bool(facts.get("historical_initialization_eligible",false)) and facts.administrative_status=="UNRESOLVED" and facts.sovereign_polity_id==opening.sovereign_polity_id and control.get_controller(id)==opening.controller_polity_id

func _on_land_control_changed(id: String) -> void:
	if _land_facts.has(id): _land_facts[id]["historical_initialization_eligible"] = false

func administrative_land_members(region_id: String) -> Array[String]:
	var result: Array[String] = []
	if not _land_administrations.has(region_id): return result
	for id: String in _land_facts:
		if _land_facts[id].administrative_region_id == region_id: result.append(id)
	result.sort()
	return result

func administrative_identity(region_id: String) -> Dictionary:
	return (_land_administrations.get(region_id,{}) as Dictionary).duplicate(true)

func administrative_children(region_id: String) -> Array[Dictionary]:
	var parent := _land_administrations.get(region_id,{}) as Dictionary
	var path := str(parent.get("children_path",""))
	if not path.is_empty() and not _loaded_child_rosters.has(region_id):
		var errors: Array[String] = []
		var document := ContentDocument.read(path,errors)
		if errors.is_empty() and document.get("schema_id")=="historical_administrative_children_v1" and document.get("parent_region_id")==region_id:
			var source := document.get("source",{}) as Dictionary
			for child: Dictionary in document.get("units",[]) as Array:
				if str(child.get("parent_region_id",""))!=region_id or _land_administrations.has(str(child.get("id",""))): continue
				var row := child.duplicate(true)
				row["source_citation"] = source.get("attribution","")
				row["source_license"] = source.get("license","")
				row["source_name_zh"] = source.get("publisher","")
				row["boundary_reference"] = (source.get("supporting_locators",[]) as Array).back() if not (source.get("supporting_locators",[]) as Array).is_empty() else source.get("locator","")
				_land_administrations[str(row.id)] = row
				if not _administrative_children.has(region_id): _administrative_children[region_id] = []
				_administrative_children[region_id].append(str(row.id))
			_loaded_child_rosters[region_id] = true
	var result: Array[Dictionary] = []
	for id: String in _administrative_children.get(region_id,[]) as Array:
		var row := _land_administrations[id] as Dictionary
		result.append({"id":id,"name_zh":row.get("name_zh",""),"unit_type_name_zh":row.get("unit_type_name_zh",""),"has_boundary":row.has("reference_descriptor")})
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return str(a.name_zh)<str(b.name_zh))
	return result

func set_land_administration(land_ids: Array[String], region_id: String) -> bool:
	# Explicit membership mutation. Occupation and sovereignty never call this.
	if _land == null or land_ids.is_empty() or (not region_id.is_empty() and not _land_administrations.has(region_id)): return false
	for id: String in land_ids:
		if not _land.has_land(id) or not _land_facts.has(id): return false
	for id: String in land_ids:
		_land_facts[id]["administrative_status"] = "UNRESOLVED" if region_id.is_empty() else "ASSIGNED"
		_land_facts[id]["administrative_region_id"] = null if region_id.is_empty() else region_id
		_land_facts[id]["historical_initialization_eligible"] = false
	_invalidate_administrative_display()
	return true

func administrative_land_summary(region_id: String, date: String = "1900-01-01") -> Dictionary:
	if not _land_administrations.has(region_id): return {}
	var row := administrative_identity(region_id)
	var ids := administrative_land_members(region_id)
	var total := 0.0
	for id: String in ids: total += LandTopology.area(_land.polygon(id))
	row["land_member_ids"] = ids
	row["child_units"] = administrative_children(region_id)
	var parent := str(row.get("parent_region_id",""))
	row["parent_name_zh"] = (_land_administrations.get(parent,{}) as Dictionary).get("name_zh","")
	var related: Array[Dictionary] = []
	for related_id: String in row.get("related_region_ids",[]) as Array:
		var unit := _land_administrations.get(related_id,{}) as Dictionary
		if not unit.is_empty(): related.append({"id":related_id,"name_zh":unit.get("name_zh","")})
	row["related_units"] = related
	row["known_area_km2"] = total/1000000.0
	row["membership_coverage"] = "PARTIAL_FORMAL_LAND_ONLY"
	row["membership_basis_zh"] = "当前边界只覆盖已确定的正式土地成员；历史参考另列。" if administrative_display_uses_members(region_id,date) else str(row.get("membership_basis_zh","省界为 1900 年历史重建参考；当前成员只覆盖已确定的正式土地。"))
	row["boundary_status"] = "HISTORICAL_GIS_RECONSTRUCTION" if row.has("reference_descriptor") else "NO_ADMITTED_HISTORICAL_GEOMETRY"
	row["historical_reference_active"] = _administrative_reference_visible(region_id,date)
	row["place_id"] = region_id
	row["spatial_kind"] = "historical_administration"
	row["observation_year"] = row.get("observation_year",_land_admin_document.get("observation_year",0))
	row["temporal_note_zh"] = row.get("temporal_note_zh",_land_admin_document.get("temporal_note_zh",""))
	row["accuracy_note_zh"] = row.get("accuracy_note_zh",_land_admin_document.get("accuracy_note_zh",""))
	var source := _land_admin_document.get("source",{}) as Dictionary
	row["source_citation"] = row.get("source_citation",(source.get("access_metadata",{}) as Dictionary).get("attribution",""))
	row["source_license"] = row.get("source_license",source.get("license",""))
	var covered := 0.0
	var unresolved: Array[String] = []
	var ready := administrative_coverage_ready(region_id)
	if ready:
		for land_id: String in _administrative_coverage[region_id].overlaps:
			var overlap := float(_administrative_coverage[region_id].overlaps[land_id])
			covered += overlap
			if overlap>float(_land._seed.limits.area_tolerance_m2) and _land_facts[land_id].administrative_region_id==null: unresolved.append(land_id)
	row["formal_coverage_pending"] = not ready
	row["formal_coverage_area_km2"] = covered/1000000.0
	row["intersecting_unresolved_land_ids"] = unresolved
	return row

func land_details(id: String, control: TerritoryState) -> Dictionary:
	if _land == null or not _land.has_land(id): return {}
	var row := land_facts(id)
	var center := _land.center_geographic(id)
	row.merge({"place_id":id,"name":"正式土地单元","spatial_kind":"formal_land",
		"neighbor_ids":_land.neighbors(id),
		"source_id":_land.identity(id).get("source_snapshot_ref",""),"lon_lat":[center.x,center.y],
		"area_km2":LandTopology.area(_land.polygon(id))/1000000.0,
		"geometry_basis":"GENERATED_PARTITION","controller_polity_id":control.get_controller(id) if control != null and control.has_territory(id) else ""})
	if row.administrative_region_id == null and bool(row.historical_initialization_eligible) and id.begins_with("territory_unit:l93_"): row["administrative_resolution"] = "PENDING_REFINEMENT"
	var opening := (_land._seed.get("initial_land_facts",{}) as Dictionary).get(id,{}) as Dictionary
	row["initial_sovereignty_basis"] = opening.get("sovereignty_basis","")
	row["initial_controller_basis"] = opening.get("controller_basis","")
	if row.administrative_region_id != null:
		row["administrative_name_zh"] = _land_administrations[row.administrative_region_id].get("name_zh",row.administrative_region_id)
	return row

func query_land(lon_lat: Vector2, width_km: int, control: TerritoryState) -> Dictionary:
	if _land == null: return {}
	var result := _land.query_geographic(lon_lat,width_km)
	if result.is_empty(): return {}
	var sovereign: Dictionary = {}
	var controllers: Dictionary = {}
	var administrations: Dictionary = {}
	for member: Dictionary in result.get("members",[]) as Array:
		var id := str(member.land_id)
		var facts := _land_facts[id] as Dictionary
		var owner := str(facts.sovereign_polity_id) if facts.sovereign_polity_id!=null else "UNKNOWN"
		var controller_id := control.get_controller(id) if control != null and control.has_territory(id) else "UNKNOWN"
		if controller_id.is_empty(): controller_id = "UNKNOWN"
		var region := str(facts.administrative_region_id) if facts.administrative_region_id != null else "UNRESOLVED"
		for pair: Array in [[sovereign,owner],[controllers,controller_id],[administrations,region]]:
			var areas := pair[0] as Dictionary
			areas[pair[1]] = float(areas.get(pair[1],0.0))+float(member.area_km2)
	result.merge({"sovereign_areas_km2":sovereign,"controller_areas_km2":controllers,"administrative_areas_km2":administrations})
	return result

func land_place_relations(id: String) -> Dictionary:
	var places: Array[Dictionary] = []
	var links: Array[Dictionary] = []
	if _land == null or not _land.has_land(id): return {"places":places,"links":links}
	var seen: Dictionary = {}
	for map_id: String in _catalog.place_map_ids():
		var place := _catalog.get_place(map_id)
		var coordinates := place.get("lon_lat",[]) as Array
		if coordinates.size() != 2 or _land.pick_geographic(Vector2(float(coordinates[0]),float(coordinates[1]))) != id: continue
		places.append(place)
		for link: Dictionary in _catalog.links_from(map_id):
			var link_id := str(link.get("link_id",""))
			if not seen.has(link_id):
				seen[link_id] = true
				links.append(link)
	return {"places":places,"links":links,"basis":"EXISTING_FORMAL_PLACE_LINKS"}

func install_land(topology: LandTopology, opening: Dictionary, politics: RuntimePoliticalEntityRegistry) -> bool:
	if _land != null or topology == null or not topology.is_initialized() or politics == null:
		return false
	var facts: Dictionary = {}
	for id: String in topology.land_ids():
		var initial := (opening.get("land_overrides",{}) as Dictionary).get(id,opening) as Dictionary
		facts[id] = {"id":id,"sovereign_polity_id":initial.get("sovereign_polity_id"),"administrative_status":"UNRESOLVED","administrative_region_id":null,"historical_initialization_eligible":true}
	if not _valid_land_facts(topology,facts,politics):
		return false
	_land = topology
	_land_facts = facts
	_land_politics = politics
	return true

func land_topology() -> LandTopology:
	return _land

func land_facts(id: String) -> Dictionary:
	return (_land_facts.get(id,{}) as Dictionary).duplicate(true)

func set_land_sovereign(id: String, polity_id: String) -> bool:
	if not _land_facts.has(id) or not _land_politics.has_entity(polity_id):
		return false
	var changed: bool = _land_facts[id].sovereign_polity_id != polity_id
	if changed: _land_facts[id]["historical_initialization_eligible"] = false
	_land_facts[id]["sovereign_polity_id"] = polity_id
	if changed: land_politics_changed.emit(id)
	return true

func split_land(id: String, first_id: String, first: PackedVector2Array, second_id: String, second: PackedVector2Array, control: TerritoryState, historical_initialization: bool = false) -> bool:
	if _land == null or control == null or not control.is_bound_to_land(_land) or not _land_facts.has(id):
		return false
	var plan := _land.prepare_split(id,first_id,first,second_id,second)
	if plan.is_empty() or not control.can_split_land(id,first_id,second_id):
		return false
	var inherited := land_facts(id)
	# Both owners are preflighted. No signals, await or fallible operation during commit.
	_land.commit_split(plan)
	control.commit_land_split(id,first_id,second_id)
	_land_facts.erase(id)
	for child: String in [first_id,second_id]:
		_land_facts[child] = inherited.duplicate(true)
		_land_facts[child]["id"] = child
		if not historical_initialization: _land_facts[child]["historical_initialization_eligible"] = false
	_invalidate_administrative_display()
	land_politics_changed.emit("")
	return true

func _valid_land_facts(topology: LandTopology, facts: Dictionary, politics: RuntimePoliticalEntityRegistry) -> bool:
	if facts.size() != topology.land_ids().size():
		return false
	for id: String in topology.land_ids():
		var raw: Variant = facts.get(id)
		if not raw is Dictionary:
			return false
		var row := raw as Dictionary
		if row.size() != 5 or not row.get("historical_initialization_eligible") is bool or row.get("id") != id or not row.has("sovereign_polity_id") or not row.has("administrative_region_id"):
			return false
		if row.sovereign_polity_id!=null and (not row.sovereign_polity_id is String or not politics.has_entity(str(row.sovereign_polity_id))): return false
		if row.get("administrative_status") == "UNRESOLVED":
			if row.administrative_region_id != null: return false
		elif row.get("administrative_status") == "ASSIGNED":
			if not row.administrative_region_id is String or not _land_administrations.has(row.administrative_region_id): return false
		else: return false
	return true


func _init(catalog_value: VNextSpatialCatalog = null) -> void:
	_catalog = catalog_value


static func create(catalog_value: VNextSpatialCatalog) -> VNextSpatialWorld:
	var world := VNextSpatialWorld.new()
	if not world.initialize(catalog_value):
		return null
	return world


static func create_from_legacy_world_map() -> VNextSpatialWorld:
	var catalog := VNextSpatialCatalog.new()
	if not catalog.load_legacy_world_map():
		return null
	return create(catalog)


func initialize(catalog_value: VNextSpatialCatalog) -> bool:
	if catalog_value == null or not catalog_value.is_loaded():
		return false
	var candidate_infrastructure: Dictionary = {}
	for link: Dictionary in catalog_value.links():
		var link_id: String = str(link.get("link_id", ""))
		var link_type: String = str(link.get("link_type", ""))
		var default_capacity: float = float(
			DEFAULT_NOMINAL_CAPACITY_BY_TYPE.get(link_type, -1.0)
		)
		var state := VNextInfrastructureLinkState.new()
		if not state.configure(link_id, link_type, default_capacity):
			return false
		candidate_infrastructure[link_id] = state

	var candidate_territories: Dictionary = {}
	for place_map_id: String in catalog_value.place_map_ids():
		var place: Dictionary = catalog_value.get_place(place_map_id)
		if place.is_empty():
			return false
		var owner_id: String = str(place.get("parent_country_id", ""))
		var place_kind: String = _place_kind(place)
		var parent_id: String = ""
		if place_kind != "region":
			parent_id = str(place.get("parent_region_id", ""))
		candidate_territories[place_map_id] = {
			"entity_id": place_map_id,
			"entity_kind": place_kind,
			"sovereign_owner_id": owner_id,
			"administrative_parent_id": parent_id,

		}

	var candidate_capacity := VNextSpatialCapacityWindow.new()
	if not candidate_capacity.initialize(catalog_value, candidate_infrastructure, 0):
		return false
	_catalog = catalog_value
	_current_hour = 0
	_infrastructure = candidate_infrastructure
	_territories = candidate_territories
	_capacity = candidate_capacity
	return _is_internal_state_valid()


func is_valid() -> bool:
	return _is_internal_state_valid()


func catalog() -> VNextSpatialCatalog:
	return _catalog


func current_hour() -> int:
	return _current_hour


func advance_to_hour(absolute_hour: int) -> bool:
	if not _is_internal_state_valid():
		return false
	if not _capacity.advance_to_hour(absolute_hour):
		return false
	_current_hour = _capacity.current_hour()
	return true


func advance_hours(elapsed_hours: int) -> bool:
	if not _is_internal_state_valid():
		return false
	if not _capacity.advance_hours(elapsed_hours):
		return false
	_current_hour = _capacity.current_hour()
	return true


func get_place(place_query: String) -> Dictionary:
	if _catalog == null:
		return {}
	return _catalog.get_place(place_query)


func get_region(region_query: String) -> Dictionary:
	if _catalog == null:
		return {}
	return _catalog.get_region(region_query)


func get_city(city_query: String) -> Dictionary:
	if _catalog == null:
		return {}
	return _catalog.get_city(city_query)


func get_port(port_query: String) -> Dictionary:
	if _catalog == null:
		return {}
	return _catalog.get_port(port_query)


func links_of_type(link_type: String) -> Array[Dictionary]:
	if _catalog == null:
		return []
	return _catalog.links_of_type(link_type)


func links_between(
	origin_query: String, destination_query: String, link_type: String = ""
) -> Array[Dictionary]:
	if _catalog == null:
		return []
	return _catalog.links_between(origin_query, destination_query, link_type)


func links_from(place_query: String, link_type: String = "") -> Array[Dictionary]:
	if _catalog == null:
		return []
	return _catalog.links_from(place_query, link_type)


func neighboring_place_ids(place_query: String, link_type: String = "") -> Array[String]:
	if _catalog == null:
		return []
	return _catalog.neighboring_place_ids(place_query, link_type)


func effective_capacity(link_id: String) -> float:
	# Allocation-independent physical query for routing/access consumers. This
	# reads the authoritative InfrastructureLinkState directly and never creates
	# a second capacity ledger.
	var state: VNextInfrastructureLinkState = _state_for_link(link_id)
	return 0.0 if state == null else state.effective_capacity()


func infrastructure_state(link_id: String) -> Dictionary:
	if _catalog == null or not _infrastructure.has(link_id):
		return {}
	var state: VNextInfrastructureLinkState = _state_for_link(link_id)
	if state == null:
		return {}
	var output: Dictionary = _catalog.get_link(link_id)
	output.merge(state.snapshot(), true)
	var capacity: Dictionary = _capacity.capacity_summary(link_id)
	output["effective_capacity"] = state.effective_capacity()
	output["used_capacity"] = float(capacity.get("used_capacity", 0.0))
	output["remaining_capacity"] = float(capacity.get("remaining_capacity", 0.0))
	return output


func set_infrastructure_status(link_id: String, status_value: String) -> bool:
	return _mutate_infrastructure(link_id, Callable(_state_for_link(link_id), "set_status").bind(status_value))


func set_infrastructure_condition(link_id: String, condition_value: Variant) -> bool:
	return _mutate_infrastructure(link_id, Callable(_state_for_link(link_id), "set_condition").bind(condition_value))


func set_nominal_capacity(link_id: String, capacity_value: Variant) -> bool:
	return _mutate_infrastructure(link_id, Callable(_state_for_link(link_id), "set_nominal_capacity").bind(capacity_value))


func restore_infrastructure(link_id: String) -> bool:
	if not set_infrastructure_condition(link_id, 1.0):
		return false
	return set_infrastructure_status(link_id, VNextInfrastructureLinkState.STATUS_RESTORED)


func set_territorial_facts(
	entity_query: String,
	sovereign_owner_id: String,
	administrative_parent_query: String
) -> bool:
	if not _is_internal_state_valid():
		return false
	var entity_id: String = _entity_query_to_map_id(entity_query)
	if entity_id.is_empty():
		return false
	var parent_id: String = _administrative_query_to_map_id(administrative_parent_query)
	if not administrative_parent_query.is_empty() and parent_id.is_empty():
		return false
	var candidate_territories: Dictionary = _duplicate_territories()
	var current: Dictionary = candidate_territories[entity_id]
	candidate_territories[entity_id] = {
		"entity_id": entity_id,
		"entity_kind": str(current.get("entity_kind", "")),
		"sovereign_owner_id": sovereign_owner_id,
		"administrative_parent_id": parent_id,

	}
	if not _validate_territory_collection(candidate_territories):
		return false
	_territories = candidate_territories
	return true


func set_sovereign_owner(entity_query: String, owner_id: String) -> bool:
	var current: Dictionary = get_territorial_facts(entity_query)
	if current.is_empty():
		return false
	return set_territorial_facts(
		entity_query, owner_id, str(current.get("administrative_parent_id", ""))
	)


func set_administrative_parent(entity_query: String, parent_query: String) -> bool:
	var current: Dictionary = get_territorial_facts(entity_query)
	if current.is_empty():
		return false
	return set_territorial_facts(
		entity_query, str(current.get("sovereign_owner_id", "")), parent_query
	)


func get_territorial_facts(entity_query: String) -> Dictionary:
	var entity_id: String = _entity_query_to_map_id(entity_query)
	var value: Variant = _territories.get(entity_id, {})
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return (value as Dictionary).duplicate(true)


func request_capacity(
	request_id: String, link_id: String, window_hour: int, demand: Variant
) -> Dictionary:
	if _capacity == null:
		return {"success": false, "accepted": false, "reason": "invalid_world"}
	return _capacity.request_capacity(request_id, link_id, window_hour, demand)


func request_capacity_batch(request_values: Array[Dictionary]) -> Dictionary:
	if _capacity == null:
		return {"success": false, "accepted": false, "reason": "invalid_world", "results": {}}
	return _capacity.request_capacity_batch(request_values)


func reserve_capacity(
	request_id: String, link_id: String, window_hour: int, demand: Variant
) -> Dictionary:
	return request_capacity(request_id, link_id, window_hour, demand)


func cancel_capacity_request(request_id: String, link_id: String, window_hour: int) -> bool:
	return _capacity != null and _capacity.cancel_capacity_request(request_id, link_id, window_hour)


func reservation_result(request_id: String, link_id: String, window_hour: int) -> Dictionary:
	if _capacity == null:
		return {"success": false, "accepted": false, "reason": "invalid_world"}
	return _capacity.reservation_result(request_id, link_id, window_hour)


func reservation_results_batch(request_values: Array[Dictionary]) -> Dictionary:
	if _capacity == null:
		return {"success": false, "accepted": false, "reason": "invalid_world", "results": {}}
	return _capacity.reservation_results_batch(request_values)


func consume_capacity_batch(entries: Array[Dictionary]) -> Dictionary:
	if _capacity == null: return {"success": false, "reason": "invalid_world"}
	return _capacity.consume_capacity_batch(entries)

func capacity_adoption(id: String) -> Dictionary:
	return _capacity.capacity_adoption(id) if _capacity != null else {}

func capacity_summary(link_id: String) -> Dictionary:
	if _capacity == null:
		return {}
	return _capacity.capacity_summary(link_id)


func used_capacity(link_id: String) -> float:
	return float(capacity_summary(link_id).get("used_capacity", 0.0))


func remaining_capacity(link_id: String) -> float:
	return float(capacity_summary(link_id).get("remaining_capacity", 0.0))


func snapshot() -> Dictionary:
	if not _is_internal_state_valid():
		return {}
	var infrastructure: Array[Dictionary] = []
	for link_id: String in _catalog.link_ids():
		infrastructure.append(_state_for_link(link_id).snapshot())
	var territories: Array[Dictionary] = []
	for entity_id: String in _catalog.place_map_ids():
		territories.append((_territories[entity_id] as Dictionary).duplicate(true))
	var output := {
		"schema_id": SNAPSHOT_SCHEMA_ID if _land == null else "vnext_spatial_world_v3",
		"current_hour": _current_hour,
		"infrastructure": infrastructure,
		"territories": territories,
		"capacity_window": _capacity.snapshot(),
	}
	if _land != null:
		output["land"] = {"topology":_land.snapshot(),"politics":_land_facts.duplicate(true)}
	return output


func restore(snapshot_value: Dictionary) -> bool:
	if not _is_internal_state_valid():
		return false
	var expected_schema := SNAPSHOT_SCHEMA_ID if _land == null else "vnext_spatial_world_v3"
	if snapshot_value.size() != (5 if _land == null else 6) or snapshot_value.get("schema_id") != expected_schema:
		return false
	if not _has_fields(snapshot_value, [
		"schema_id", "current_hour", "infrastructure", "territories", "capacity_window",
	]):
		return false
	var candidate_hour: int = _parse_hour(snapshot_value.get("current_hour"))
	if candidate_hour < 0:
		return false
	if typeof(snapshot_value.get("infrastructure")) != TYPE_ARRAY:
		return false
	if typeof(snapshot_value.get("territories")) != TYPE_ARRAY:
		return false
	if typeof(snapshot_value.get("capacity_window")) != TYPE_DICTIONARY:
		return false

	var candidate_infrastructure: Dictionary = {}
	for raw_value: Variant in (snapshot_value.get("infrastructure") as Array):
		if typeof(raw_value) != TYPE_DICTIONARY:
			return false
		var state := VNextInfrastructureLinkState.new()
		if not state.restore(raw_value as Dictionary):
			return false
		var link_id: String = state.link_id()
		if candidate_infrastructure.has(link_id) or not _catalog.has_link(link_id):
			return false
		if str(_catalog.get_link(link_id).get("link_type", "")) != state.link_type():
			return false
		candidate_infrastructure[link_id] = state
	if candidate_infrastructure.size() != _catalog.link_ids().size():
		return false
	for link_id: String in _catalog.link_ids():
		if not candidate_infrastructure.has(link_id):
			return false

	var candidate_territories: Dictionary = {}
	for raw_value: Variant in (snapshot_value.get("territories") as Array):
		if typeof(raw_value) != TYPE_DICTIONARY:
			return false
		var territory: Dictionary = raw_value
		if territory.size() != 4 or not _has_fields(territory, [
			"entity_id", "entity_kind", "sovereign_owner_id",
			"administrative_parent_id",
		]) or not _all_string_fields(territory, [
			"entity_id", "entity_kind", "sovereign_owner_id",
			"administrative_parent_id",
		]):
			return false
		var entity_id: String = str(territory.get("entity_id"))
		if candidate_territories.has(entity_id):
			return false
		candidate_territories[entity_id] = territory.duplicate(true)
	if candidate_territories.size() != _catalog.place_map_ids().size():
		return false
	for entity_id: String in _catalog.place_map_ids():
		if not candidate_territories.has(entity_id):
			return false

	var candidate := VNextSpatialWorld.new()
	candidate._land_administrations = _land_administrations
	candidate._administrative_children = _administrative_children
	candidate._loaded_child_rosters = _loaded_child_rosters
	candidate._land_boundaries = _land_boundaries
	candidate._land_admin_document = _land_admin_document
	if _land != null:
		if not snapshot_value.get("land") is Dictionary:
			return false
		var land_value := snapshot_value.land as Dictionary
		if land_value.size() != 2 or not land_value.get("topology") is Dictionary or not land_value.get("politics") is Dictionary:
			return false
		candidate._land = _land.restored_copy(land_value.topology)
		if candidate._land == null:
			return false
		candidate._land_facts = (land_value.politics as Dictionary).duplicate(true)
		# Older saves have no mutation history. Do not infer that an unknown member
		# or a sourced-looking child has never been changed by the player.
		for id: String in candidate._land_facts:
			var raw: Variant = candidate._land_facts[id]
			if raw is Dictionary and (raw as Dictionary).size()==4 and not (raw as Dictionary).has("historical_initialization_eligible"):
				var old_facts := raw as Dictionary
				old_facts["historical_initialization_eligible"] = false
		for id: String in candidate._land.restored_seed_ids():
			if candidate._land_facts.has(id): return false
			candidate._land_facts[id] = land_facts(id)
		if not candidate._valid_land_facts(candidate._land,candidate._land_facts,_land_politics): return false
		candidate._land_politics = _land_politics
	candidate._catalog = _catalog
	candidate._current_hour = candidate_hour
	candidate._infrastructure = candidate_infrastructure
	candidate._territories = candidate_territories
	candidate._capacity = VNextSpatialCapacityWindow.new()
	if not candidate._validate_infrastructure_collection():
		return false
	if not candidate._validate_territory_collection(candidate_territories):
		return false
	if not candidate._capacity.initialize(
		_catalog, candidate_infrastructure, candidate_hour
	):
		return false
	if not candidate._capacity.restore(snapshot_value.get("capacity_window") as Dictionary):
		return false
	if not candidate._is_internal_state_valid():
		return false

	_current_hour = candidate._current_hour
	_infrastructure = candidate._infrastructure
	_territories = candidate._territories
	_capacity = candidate._capacity
	_land = candidate._land
	_land_facts = candidate._land_facts
	_invalidate_administrative_display()
	land_politics_changed.emit("")
	return true


func _is_internal_state_valid() -> bool:
	if _catalog == null or not _catalog.is_loaded() or _capacity == null:
		return false
	# Land is validated at admission/mutation/restore; hourly settlement never scans it.
	if _land != null and not _land.is_initialized():
		return false
	if not _validate_infrastructure_collection():
		return false
	if not _validate_territory_collection(_territories):
		return false
	return _capacity.is_valid() and _capacity.current_hour() == _current_hour


func _validate_infrastructure_collection() -> bool:
	if _infrastructure.size() != _catalog.link_ids().size():
		return false
	for link_id: String in _catalog.link_ids():
		if not _infrastructure.has(link_id):
			return false
		var state: VNextInfrastructureLinkState = _state_for_link(link_id)
		if state == null or not state.is_valid():
			return false
		if str(_catalog.get_link(link_id).get("link_type", "")) != state.link_type():
			return false
	return true


func _validate_territory_collection(territories: Dictionary) -> bool:
	if territories.size() != _catalog.place_map_ids().size():
		return false
	for entity_id: String in _catalog.place_map_ids():
		if not territories.has(entity_id):
			return false
		var value: Variant = territories.get(entity_id)
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var territory: Dictionary = value
		if territory.size() != 4 or not _has_fields(territory, [
			"entity_id", "entity_kind", "sovereign_owner_id",
			"administrative_parent_id",
		]) or not _all_string_fields(territory, [
			"entity_id", "entity_kind", "sovereign_owner_id",
			"administrative_parent_id",
		]):
			return false
		if str(territory.get("entity_id")) != entity_id:
			return false
		var place: Dictionary = _catalog.get_place(entity_id)
		if place.is_empty() or _place_kind(place) != str(territory.get("entity_kind")):
			return false
		if not _catalog.has_country(str(territory.get("sovereign_owner_id"))):
			return false
		var parent_id: String = str(territory.get("administrative_parent_id"))
		if not parent_id.is_empty() and not (
			_catalog.has_country(parent_id) or _catalog.has_region(parent_id)
		):
			return false
		if parent_id == entity_id:
			return false
	for entity_id: String in _catalog.place_map_ids():
		var seen: Dictionary = {entity_id: true}
		var cursor: String = str(territories[entity_id].get("administrative_parent_id", ""))
		while not cursor.is_empty() and _catalog.has_region(cursor):
			if seen.has(cursor):
				return false
			seen[cursor] = true
			cursor = str(territories.get(cursor, {}).get("administrative_parent_id", ""))
	return true


func _mutate_infrastructure(link_id: String, mutation: Callable) -> bool:
	var state: VNextInfrastructureLinkState = _state_for_link(link_id)
	if state == null or not mutation.is_valid():
		return false
	var before: Dictionary = state.snapshot()
	var mutation_result: Variant = mutation.call()
	if typeof(mutation_result) != TYPE_BOOL or not bool(mutation_result):
		return false
	_capacity._recompute_allocations()
	if _is_internal_state_valid():
		return true
	state.restore(before)
	_capacity._recompute_allocations()
	return false


func _state_for_link(link_id: String) -> VNextInfrastructureLinkState:
	var value: Variant = _infrastructure.get(link_id)
	if not value is VNextInfrastructureLinkState:
		return null
	return value as VNextInfrastructureLinkState


func _entity_query_to_map_id(entity_query: String) -> String:
	if _catalog == null:
		return ""
	var map_id: String = VNextSpatialCatalog.place_query_to_map_id(entity_query)
	return map_id if _catalog.has_place(map_id) else ""


func _administrative_query_to_map_id(parent_query: String) -> String:
	if parent_query.is_empty():
		return ""
	if _catalog.has_country(parent_query):
		return parent_query
	var map_id: String = VNextSpatialCatalog.place_query_to_map_id(parent_query)
	return map_id if _catalog.has_region(map_id) else ""


func _duplicate_territories() -> Dictionary:
	var output: Dictionary = {}
	for entity_id: String in _catalog.place_map_ids():
		output[entity_id] = (_territories[entity_id] as Dictionary).duplicate(true)
	return output


static func _place_kind(place: Dictionary) -> String:
	return str(place.get("object_level", place.get("spatial_kind", "")))


static func _parse_hour(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		var integer_hour: int = int(value)
		return integer_hour if integer_hour >= 0 and integer_hour <= 9_007_199_254_740_991 else -1
	if typeof(value) == TYPE_FLOAT:
		var float_hour: float = float(value)
		if not is_finite(float_hour) or float_hour != floor(float_hour):
			return -1
		var normalized_hour: int = int(float_hour)
		return normalized_hour if normalized_hour >= 0 and normalized_hour <= 9_007_199_254_740_991 else -1
	return -1


static func _has_fields(value: Dictionary, fields: Array[String]) -> bool:
	for field_name: String in fields:
		if not value.has(field_name):
			return false
	return true


static func _all_string_fields(value: Dictionary, fields: Array[String]) -> bool:
	for field_name: String in fields:
		if typeof(value.get(field_name)) != TYPE_STRING:
			return false
	return true
