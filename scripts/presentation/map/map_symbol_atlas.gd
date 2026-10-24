class_name MapSymbolAtlas
extends RefCounted
## Shared UI artwork and finite screen-space layout; no world facts or RID owner.
const CATALOG := "res://assets/ui/map_symbols/symbols.json"
const BINDINGS := "res://assets/ui/map_symbols/place_bindings.json"
var texture: Texture2D
var icons: Dictionary = {}
var _bindings: Dictionary = {}
var _attempted: bool = false
var _roles: Dictionary = {}
var _polities: Dictionary = {}
var _date: String = ""
var _capitals: Dictionary = {}
var _capital_dirty: bool = true
var _retained_ids: Dictionary = {}

func configure(roles: Dictionary, polities: Dictionary, date: String) -> void:
	_roles = roles
	_polities = polities
	_date = date
	_capital_dirty = true

func _load() -> void:
	if _attempted: return
	_attempted = true
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG)) if FileAccess.file_exists(CATALOG) else null
	if not document is Dictionary or document.get("schema_id")!="wwo_map_symbols_r47": return
	icons = document.get("icons",{}) as Dictionary
	var atlas_path := str(document.get("atlas",""))
	if ResourceLoader.exists(atlas_path,"Texture2D"): texture = load(atlas_path) as Texture2D
	if FileAccess.file_exists(BINDINGS):
		var bindings: Variant = JSON.parse_string(FileAccess.get_file_as_string(BINDINGS))
		if bindings is Dictionary and bindings.get("schema_id")=="wwo_map_symbol_bindings_r47": _bindings = bindings

func capital_places() -> Dictionary:
	_load()
	if not _capital_dirty: return _capitals
	_capital_dirty = false
	_capitals.clear()
	for link: Dictionary in _bindings.get("capital_links",[]) as Array:
		if _date<str(link.valid_from) or _date>=str(link.valid_to): continue
		for polity: Dictionary in _polities.values():
			if str(polity.get("source_historical_id",""))!=str(link.source_historical_id): continue
			var capital := polity.get("capital",{}) as Dictionary
			# An updated official capital invalidates the old presentation link.
			if str(capital.get("name",""))!=str(link.capital_name): continue
			var id := str(link.place_id)
			var icon := "capital" if str(polity.get("relationship","")) in ["independent_state","belligerent_state"] else "admin_primary"
			_capitals[id] = {"id":id,"kind":"settlement","display_name":link.name,"lon_lat":link.lon_lat,"map_symbol":icon,"parent_country_id":link.source_historical_id,"source_name_zh":"既有历史首都／行政驻地声明与地点对应","source_reference":link.source,"coordinate_source_reference":link.place_source,"valid_from":link.valid_from,"valid_to":link.valid_to}
	return _capitals

func symbol_id(record: Dictionary, id: String) -> String:
	if capital_places().has(id): return str((capital_places()[id] as Dictionary).map_symbol)
	if _roles.has(id): return str((_roles[id] as Dictionary).get("icon","settlement"))
	var explicit := str(record.get("map_symbol",""))
	if icons.has(explicit): return explicit
	var overrides := _bindings.get("place_icons",{}) as Dictionary
	var dated := _date>=str(_bindings.get("valid_from","1900-01-01")) and _date<str(_bindings.get("valid_to","1901-01-01"))
	if dated and overrides.has(id): return str((overrides[id] as Dictionary).icon)
	if str(record.get("display_kind",""))=="transport_node":
		return "bridge" if str(record.get("transport_symbol",""))=="bridge" else "station"
	if str(record.get("kind",""))=="landmark":
		var kind := str(record.get("symbol_kind",""))
		if kind in ["tower","clock_tower","obelisk"]: return "monument"
		if kind in ["castle","fortress"]: return "castle"
		return "historic_site" # Legacy 'monument' is not a precise building type.
	var type := str(record.get("historical_settlement_type",record.get("settlement_type","")))
	if type in ["city","town","village"]: return type
	# These existing atlas entries explicitly cite the chief-city evidence.
	if dated and (_bindings.get("city_links",{}) as Dictionary).has(id): return "city"
	return "settlement"

func limit_for(record: Dictionary, id: String) -> float:
	var kind := symbol_id(record,id)
	return float((icons.get(kind,{}) as Dictionary).get("region_max_mpp",3000.0))*(1.12 if _retained_ids.has(id) else 1.0)

static func _cells(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(floori(rect.position.y/32.0),floori(rect.end.y/32.0)+1):
		for x: int in range(floori(rect.position.x/32.0),floori(rect.end.x/32.0)+1): result.append(Vector2i(x,y))
	return result

static func free_rect(rect: Rect2, grid: Dictionary) -> bool:
	for cell: Vector2i in _cells(rect):
		for other: Rect2 in grid.get(cell,[]) as Array:
			if rect.intersects(other): return false
	return true

static func occupy(rect: Rect2, grid: Dictionary) -> void:
	for cell: Vector2i in _cells(rect):
		if not grid.has(cell): grid[cell] = []
		(grid[cell] as Array).append(rect)

func layout(candidates: Array[Dictionary], regional: bool, mpp: float, selected: String, previous: Dictionary, reserved: Array[Rect2], viewport_size: Vector2, occupied: Dictionary) -> Array[Dictionary]:
	_load()
	var rows: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if not (candidate.point as Vector2).is_finite(): continue
		var id := str(candidate.id)
		var kind := symbol_id(candidate.record as Dictionary,id)
		var spec := icons.get(kind,{}) as Dictionary
		var chosen := id==selected
		if not regional and not bool(spec.get("world",false)) and not chosen: continue
		var limit := float(spec.get("region_max_mpp",3000.0) if regional else spec.get("world_max_mpp",18000.0))
		if mpp>limit*(1.12 if previous.has(id) else 1.0) and not chosen: continue
		var pixels := float(spec.get("screen_px",18.0))
		if not regional: pixels *= 0.78
		var model := bool(candidate.get("model",false))
		if model: pixels = 8.0
		var rect := Rect2((candidate.point as Vector2)-Vector2.ONE*pixels*0.5,Vector2.ONE*pixels)
		if not Rect2(Vector2.ZERO,viewport_size).encloses(rect): continue
		var row := candidate.duplicate()
		row.merge({"kind":kind,"spec":spec,"rect":rect,"priority":(1000 if chosen else 0)+int(spec.get("priority",50)),"retained":previous.has(id),"model":model},true)
		rows.append(row)
	# Preserve priority, retained status and ID order without a script callback
	# for every comparison. These buckets live only for this layout.
	var buckets: Dictionary = {}
	for row: Dictionary in rows:
		var rank := -2*int(row.priority)-int(row.retained)
		if not buckets.has(rank): buckets[rank] = {}
		(buckets[rank] as Dictionary)[row.id] = row

	rows.clear()
	buckets.sort()
	for rank: int in buckets:
		var bucket := buckets[rank] as Dictionary
		bucket.sort()
		for id: String in bucket: rows.append(bucket[id])
	var grid := occupied
	for rect: Rect2 in reserved:
		if not rect.position.is_finite() or not rect.size.is_finite(): continue
		var clipped := rect.intersection(Rect2(Vector2.ZERO,viewport_size))
		if clipped.has_area(): occupy(clipped,grid)
	var admitted: Array[Dictionary] = []
	for row: Dictionary in rows:
		# Selected rows sort first. Once full, rejected candidates need no grid
		# traversal, allocation or label preparation.
		if admitted.size()>=(160 if regional else 24): break
		var rect := (row.rect as Rect2).grow(2.0)
		# Hidden model locators do not reserve a full icon; model picking stays
		# with RegionView. Selection uses only its small existing ground anchor.
		if bool(row.model) and str(row.id)!=selected and not bool(row.get("topic_locator",false)): continue
		if not free_rect(rect,grid) and str(row.id)!=selected:
			if not bool(row.get("topic_locator",false)):continue
			# Keep the existing symbol at a shared city anchor. A free adjacent
			# status point remains linked to that same ground position.
			var located:=false
			for offset:Vector2 in [Vector2.ZERO,Vector2(18,0),Vector2(-18,0),Vector2(0,18),Vector2(0,-18),Vector2(28,0),Vector2(-28,0),Vector2(0,28),Vector2(0,-28)]:
				var anchor:=Rect2((row.point as Vector2)+offset-Vector2.ONE*4.0,Vector2.ONE*8.0)
				if not Rect2(Vector2.ZERO,viewport_size).encloses(anchor) or not free_rect(anchor.grow(2.0),grid):continue
				row["rect"]=anchor;row["topic_locator_only"]=true;rect=anchor.grow(2.0);located=true;break
			if not located:continue
		occupy(rect,grid)
		admitted.append(row)
	_retained_ids.clear()
	for row: Dictionary in admitted: _retained_ids[str(row.id)] = true
	return admitted

func draw(canvas: CanvasItem, rows: Array[Dictionary], selected: String, hovered: String) -> void:
	for row: Dictionary in rows:
		var rect := row.rect as Rect2
		var chosen := str(row.id)==selected
		if not bool(row.model) and not bool(row.get("topic_locator_only",false)):
			var color := Color(1.15,1.12,1.04) if str(row.id)==hovered else Color.WHITE
			if not bool((row.record as Dictionary).get("symbol_selectable",true)): color = Color(0.72,0.72,0.72,0.6)
			var coords := (row.spec as Dictionary).get("rect",[]) as Array
			if texture!=null and coords.size()==4:
				canvas.draw_texture_rect_region(texture,rect,Rect2(float(coords[0]),float(coords[1]),float(coords[2]),float(coords[3])),color)
			else: canvas.draw_circle(rect.get_center(),3.0,Color(0.84,0.78,0.64))
		if chosen:
			var point := Vector2(rect.get_center().x,rect.end.y+2.0)
			canvas.draw_line(point-Vector2(4,0),point+Vector2(4,0),Color(0.84,0.72,0.43),1.5,true)

func dispose() -> void:
	texture = null
	icons.clear()
	_capitals.clear()
	_roles = {}
	_polities = {}
	_bindings.clear()
	_retained_ids.clear()
