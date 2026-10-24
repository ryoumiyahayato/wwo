extends Node3D
## Fictional game terrain: 1 Godot unit = 1 metre. No physical blast model.
## One bounded edit transaction (at most four loaded chunks) and one stream
## chunk per frame. Sparse world-grid edits survive chunk eviction.
signal terrain_changed(event: Dictionary)
const WORLD_HALF := 2500.0
const CHUNK_SIZE := 50
const CELL_SIZE := 1.0
const CELLS := 50
const ACTIVE_RADIUS := 2
const MAX_DEPTH := 4.0
const MAX_EDIT_RADIUS := 12.0
const MAX_PENDING := 32
const MAX_EDIT_VERTICES := 120000
var bounds := AABB(Vector3(-2500,-100,-2500), Vector3(5000,200,5000))
var body: StaticBody3D # Compatibility only; actual bodies have drivable_ground group.
var ready_surface := false
var chunks: Dictionary = {}
var edits: Dictionary = {}
var local_base: Dictionary = {}
var pending: Array = []
var next_edit_serial := 1
var stream_queue: Array[Vector2i] = []
var jobs: Array = []
const SIMULATION_MARGIN := 9.0
const SIMULATION_CHUNK_BUDGET := 160
var simulation_chunks: Dictionary = {}
var simulation_budget_exceeded := false
var peak_loaded_chunks := 0
var _anchor_signature := ""
var focus_chunk := Vector2i(9999,9999)
var material: StandardMaterial3D
var rebuild_count := 0
var last_update_usec := 0
var maximum_update_usec := 0
var last_transaction_chunks := 0
var last_transaction_usec := 0
var maximum_transaction_usec := 0
var source_id := "battle_land_5km_v1"
var horizon: MeshInstance3D
# Exact double-precision cell corners, bounded independently of streamed mesh memory.
# Edits invalidate before rebuilding collision; stream changes invalidate support poses.
const HEIGHT_CELL_CACHE_LIMIT := 8192
var _height_cells: Dictionary = {}
# Only the two production resolutions are retained; lifetime follows this terrain.
var _mesh_index_cache: Dictionary = {}
var support_revision := 0
var height_cache_hits := 0
var height_cache_misses := 0
func ground_support_revision() -> int: return support_revision
func _invalidate_height_cache() -> void:
	_height_cells.clear()
	support_revision += 1


func configure(focus: Vector3 = Vector3.ZERO, original_mesh: MeshInstance3D = null) -> Dictionary:
	if ready_surface: return {"ok": false, "error": "already_configured"}
	material = StandardMaterial3D.new()
	material.albedo_color = Color("777b50")
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = true
	if original_mesh != null: _capture_original(original_mesh)
	_build_horizon()
	ready_surface = true
	set_focus(focus)
	# Spawn safety: the central 3x3 is ready before a vehicle can be placed.
	for key in stream_queue.duplicate():
		if absi(key.x-focus_chunk.x)<=1 and absi(key.y-focus_chunk.y)<=1:
			_build_chunk(key); stream_queue.erase(key)
	return {"ok": true, "bounds": bounds, "world_size_metres": Vector2(5000,5000), "loaded_chunks": chunks.size()}

func setup(host: Node3D, original: Node = null) -> Dictionary:
	var source := _find_surface(original)
	return configure(host.get("hero").global_position if host.get("hero") is Node3D else Vector3.ZERO, source)

func _find_surface(node: Node) -> MeshInstance3D:
	if node == null: return null
	if node is MeshInstance3D and ("Terrain" in str(node.name) or node.get_meta("deformable_terrain",false)): return node
	for child in node.get_children():
		var result := _find_surface(child)
		if result != null: return result
	return null

func in_bounds(x: float, z: float) -> bool:
	return is_finite(x) and is_finite(z) and absf(x)<=WORLD_HALF and absf(z)<=WORLD_HALF

func _chunk_key(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(floori(x/CHUNK_SIZE),-50,49), clampi(floori(z/CHUNK_SIZE),-50,49))

func set_simulation_anchors(positions: Array) -> void:
	var required := {}
	for point in positions:
		if not point is Vector3 or not point.is_finite() or not in_bounds(point.x,point.z): continue
		for dx in [-SIMULATION_MARGIN,SIMULATION_MARGIN]:
			for dz in [-SIMULATION_MARGIN,SIMULATION_MARGIN]:
				required[_chunk_key(point.x+dx,point.z+dz)]=true
		required[_chunk_key(point.x,point.z)]=true
	var keys: Array=required.keys()
	keys.sort_custom(func(a,b):return a.x<b.x or (a.x==b.x and a.y<b.y))
	var signature:=str(keys)
	if signature==_anchor_signature:return
	_anchor_signature=signature
	simulation_chunks=required
	# Collision safety outranks optional render-ring budget. Fixed unit count bounds union.
	simulation_budget_exceeded=required.size()>SIMULATION_CHUNK_BUDGET
	_refresh_stream_targets()
func set_focus(position: Vector3) -> void:
	if not position.is_finite():return
	var next:=_chunk_key(position.x,position.z)
	if next==focus_chunk:return
	focus_chunk=next
	_refresh_stream_targets()
func _refresh_stream_targets() -> void:
	var required: Dictionary=simulation_chunks.duplicate()
	var radius:=0 if simulation_budget_exceeded else ACTIVE_RADIUS
	for z in range(focus_chunk.y-radius,focus_chunk.y+radius+1):
		for x in range(focus_chunk.x-radius,focus_chunk.x+radius+1):
			if x>=-50 and x<50 and z>=-50 and z<50:required[Vector2i(x,z)]=true
	stream_queue.clear()
	for key in required:
		if not chunks.has(key):stream_queue.append(key)
	stream_queue.sort_custom(func(a:Vector2i,b:Vector2i):
		if simulation_chunks.has(a)!=simulation_chunks.has(b):return simulation_chunks.has(a)
		return (a-focus_chunk).length_squared()<(b-focus_chunk).length_squared())
	for key in chunks.keys():
		if not required.has(key):
			var old:Node3D=chunks[key]
			remove_child(old)
			old.queue_free()
			chunks.erase(key)
			support_revision += 1
func simulation_stream_snapshot() -> Dictionary:
	return {"simulation_chunks":simulation_chunks.size(),"loaded_chunks":chunks.size(),"peak_loaded_chunks":peak_loaded_chunks,"queued_chunks":stream_queue.size(),"simulation_chunk_budget":SIMULATION_CHUNK_BUDGET,"budget_exceeded":simulation_budget_exceeded,"chunks_built_per_frame_limit":1}

func update_focus(position: Vector3) -> void: set_focus(position)
func is_position_loaded(position: Vector3) -> bool:
	return in_bounds(position.x,position.z) and chunks.has(_chunk_key(position.x,position.z))

func _process(delta: float) -> void:
	if not ready_surface: return
	var start := Time.get_ticks_usec()
	_tick_jobs(delta)
	flush_updates()
	if not stream_queue.is_empty(): _build_chunk(stream_queue.pop_front())
	peak_loaded_chunks=maxi(peak_loaded_chunks,chunks.size())
	last_update_usec = Time.get_ticks_usec()-start
	maximum_update_usec = maxi(maximum_update_usec,last_update_usec)

func _procedural_base(x: float, z: float) -> float:
	# Smooth driveable land, with broad hills rather than impassable noise.
	return 3.0*sin(x/115.0)*cos(z/137.0)+1.3*sin((x+z)/49.0)+0.65*cos(z/24.0)*sin(x/32.0)

func base_height(x: int, z: int) -> float:
	return local_base.get(Vector2i(x,z),_procedural_base(x,z))

func _vertex_height(x: int, z: int) -> float:
	return base_height(x,z)+float(edits.get(Vector2i(x,z),0.0))

func sample_height(x: float, z: float) -> float:
	if not in_bounds(x,z): return NAN
	var ix := mini(floori(x),2499)
	var iz := mini(floori(z),2499)
	var fx := x-ix; var fz := z-iz
	var key := Vector2i(ix,iz)
	var corners: Array
	if _height_cells.has(key):
		corners = _height_cells[key]
		height_cache_hits += 1
	else:
		corners = [_vertex_height(ix,iz),_vertex_height(ix+1,iz),_vertex_height(ix,iz+1),_vertex_height(ix+1,iz+1)]
		if _height_cells.size() >= HEIGHT_CELL_CACHE_LIMIT: _height_cells.clear()
		_height_cells[key] = corners
		height_cache_misses += 1
	var a: float = corners[0]
	var b: float = corners[1]
	var c: float = corners[2]
	var d: float = corners[3]
	# Same diagonal and barycentric interpolation as visual/collision triangles.
	if fx+fz<=1.0: return a+(b-a)*fx+(c-a)*fz
	return d+(c-d)*(1.0-fx)+(b-d)*(1.0-fz)

func terrain_height(position: Vector3) -> float: return sample_height(position.x,position.z)
func sample_normal(x: float, z: float) -> Vector3:
	var left := sample_height(maxf(-2500,x-0.5),z)
	var right := sample_height(minf(2500,x+0.5),z)
	var back := sample_height(x,maxf(-2500,z-0.5))
	var front := sample_height(x,minf(2500,z+0.5))
	return Vector3(left-right,1.0,back-front).normalized()

func _build_chunk(key: Vector2i) -> void:
	var mesh := _make_mesh(key.x*CHUNK_SIZE,key.y*CHUNK_SIZE,CELLS,1.0,true)
	var tile: Node3D
	if chunks.has(key): tile = chunks[key]
	else:
		tile = Node3D.new(); tile.name = "Land_%d_%d" % [key.x,key.y]; add_child(tile)
		var visual := MeshInstance3D.new(); visual.name="Surface"; tile.add_child(visual)
		var ground := StaticBody3D.new(); ground.name="Ground"; ground.collision_layer=8; ground.collision_mask=0
		ground.add_to_group("drivable_ground"); tile.add_child(ground)
		var shape := CollisionShape3D.new(); shape.name="Shape"; ground.add_child(shape)
		chunks[key]=tile
	tile.get_node("Surface").mesh=mesh
	tile.get_node("Ground/Shape").shape=mesh.create_trimesh_shape()
	rebuild_count+=1
	# Explicit rebuild also supports editor/test base-grid changes.
	_invalidate_height_cache()

func _mesh_indices(cells: int) -> PackedInt32Array:
	if _mesh_index_cache.has(cells): return _mesh_index_cache[cells]
	var indices := PackedInt32Array()
	indices.resize(cells*cells*6)
	var cursor := 0
	for z in range(cells):
		for x in range(cells):
			var a := z*(cells+1)+x; var b := a+1; var c := a+cells+1; var d := c+1
			indices[cursor]=a; indices[cursor+1]=b; indices[cursor+2]=c
			indices[cursor+3]=b; indices[cursor+4]=d; indices[cursor+5]=c
			cursor+=6
	if cells==CELLS or cells==100: _mesh_index_cache[cells]=indices
	return indices

func _make_mesh(ox: float, oz: float, cells: int, step: float, detailed: bool) -> ArrayMesh:
	var vertices := PackedVector3Array(); var normals := PackedVector3Array()
	var colors := PackedColorArray(); var indices := _mesh_indices(cells)
	var vertex_count := (cells+1)*(cells+1)
	vertices.resize(vertex_count); normals.resize(vertex_count); colors.resize(vertex_count)
	# Cache the padded grid once: normals share samples with neighboring chunks.
	var height_grid := PackedFloat32Array()
	if detailed:
		height_grid.resize((cells+3)*(cells+3))
		for gz in range(-1,cells+2):
			for gx in range(-1,cells+2): height_grid[(gz+1)*(cells+3)+gx+1]=_vertex_height(roundi(ox+gx),roundi(oz+gz))
	for z in range(cells+1):
		for x in range(cells+1):
			var wx := ox+x*step; var wz := oz+z*step
			var gi := (z+1)*(cells+3)+x+1
			var h := height_grid[gi] if detailed else _procedural_base(wx,wz)-6.0
			var vi := z*(cells+1)+x
			vertices[vi]=Vector3(wx,h,wz)
			normals[vi]=Vector3(height_grid[gi-1]-height_grid[gi+1],2.0,height_grid[gi-cells-3]-height_grid[gi+cells+3]).normalized() if detailed else Vector3.UP
			var tint := 0.90+0.06*sin(wx*0.13)*cos(wz*0.11)
			var surface_color := Color(tint,tint,tint)
			if detailed:
				# Color-only exposed soil; filling back to the local base restores grass.
				var drop: float = -float(edits.get(Vector2i(roundi(wx),roundi(wz)),0.0))
				var soil_blend := smoothstep(0.0,0.18,drop)
				surface_color=surface_color.lerp(Color(0.61*tint,0.39*tint,0.24*tint),soil_blend)
			colors[vi]=surface_color
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,material)
	return mesh

func _build_horizon() -> void:
	# 20,000 triangles across the actual 5 km extent; no distant collision.
	# Depressed proxy stays below detailed terrain, including maximum-depth pits.
	horizon=MeshInstance3D.new(); horizon.name="DistantLandProxy"
	horizon.mesh=_make_mesh(-2500,-2500,100,50.0,false); add_child(horizon)

func apply_explosion(position: Vector3, explosive_mass_kg: float) -> Dictionary:
	if not is_finite(explosive_mass_kg) or explosive_mass_kg<0.0: return {"ok":false,"error":"invalid_mass"}
	if explosive_mass_kg==0.0: return {"ok":true,"changed":false,"reason":"no_explosive_charge"}
	# Explicit fictional coefficients, only charge mass matters. No penetration input.
	var power := pow(explosive_mass_kg,0.333333)
	return _queue_edit(position,clampf(1.0+2.0*power,1.0,12.0),clampf(0.10+0.32*power,0.10,1.4),"crater")

func apply_command(position: Vector3, kind: String="dig", layer: String="terrain") -> Dictionary:
	if layer!="terrain": return {"ok":false,"error":"invalid_layer"}
	if kind=="crater": return apply_explosion(position,1.0)
	if kind=="dig": return _queue_edit(position,1.8,0.22,"dig")
	if kind=="fill": return _queue_edit(position,2.4,0.30,"fill")
	return {"ok":false,"error":"unknown_command"}

func _queue_edit(position: Vector3, radius: float, depth: float, kind: String) -> Dictionary:
	if not ready_surface or not position.is_finite() or not in_bounds(position.x,position.z): return {"ok":false,"error":"out_of_bounds"}
	if pending.size()>=MAX_PENDING: return {"ok":false,"error":"edit_queue_full"}
	if kind!="fill" and edits.size()+int((2*radius+3)*(2*radius+3))>MAX_EDIT_VERTICES: return {"ok":false,"error":"persistent_edit_budget_reached"}
	var serial := next_edit_serial
	next_edit_serial+=1
	pending.append({"center":position,"radius":radius,"depth":depth,"kind":kind,"serial":serial})
	return {"ok":true,"kind":kind,"radius":radius,"depth":depth,"collision_pending":true,"serial":serial}

func flush_updates() -> void:
	if pending.is_empty(): return
	var transaction_start := Time.get_ticks_usec()
	# One atomic bounded transaction, never drain an unbounded queue here.
	var command: Dictionary=pending.pop_front()
	var p: Vector3=command.center; var radius: float=command.radius
	var touched: Dictionary={}
	for z in range(maxi(-2500,floori(p.z-radius)),mini(2500,ceili(p.z+radius))+1):
		for x in range(maxi(-2500,floori(p.x-radius)),mini(2500,ceili(p.x+radius))+1):
			var distance := Vector2(x-p.x,z-p.z).length()
			if distance>=radius: continue
			var key := Vector2i(x,z)
			var t := 1.0-distance*distance/(radius*radius)
			var change: float=command.depth*t*t
			var old: float=edits.get(key,0.0)
			var value := clampf(old+(change if command.kind=="fill" else -change),-MAX_DEPTH,0.0)
			if is_equal_approx(value,old): continue
			if absf(value)<0.00001: edits.erase(key)
			else: edits[key]=value
			# Include one-vertex normal halo as well as shared boundary vertices.
			for tz in range(floori((z-1.001)/50.0),floori((z+1)/50.0)+1):
				for tx in range(floori((x-1.001)/50.0),floori((x+1)/50.0)+1): touched[Vector2i(tx,tz)]=true
	_invalidate_height_cache()
	last_transaction_chunks=0
	for key in touched:
		if chunks.has(key): _build_chunk(key); last_transaction_chunks+=1
	last_transaction_usec=Time.get_ticks_usec()-transaction_start
	maximum_transaction_usec=maxi(maximum_transaction_usec,last_transaction_usec)
	command["ok"]=true; command["collision_pending"]=false
	terrain_changed.emit(command)

func request_engineer_work(actor: Node3D, target: Vector3, kind: String, seconds: float=4.0) -> Dictionary:
	if actor==null or not is_instance_valid(actor) or not kind in ["dig","fill"] or not target.is_finite() or not in_bounds(target.x,target.z): return {"ok":false,"error":"invalid_job"}
	if jobs.size()>=8: return {"ok":false,"error":"worker_budget_reached"}
	var job := {"actor":weakref(actor),"target":target,"kind":kind,"remaining":clampf(seconds,0.5,30.0),"tick":0.0,"state":"walking"}
	jobs.append(job)
	return {"ok":true,"state":"walking","target":target,"requires_actor_movement":true}

func _worker_can_work(actor: Node3D) -> bool:
	if actor.get_meta("engineering_disabled",false): return false
	if actor.has_method("can_engineer_work"): return bool(actor.call("can_engineer_work"))
	for property in actor.get_property_list():
		if property.name=="brain":
			var brain = actor.get("brain")
			if brain != null and (float(brain.hp)<=0.0 or str(brain.state)=="disabled"): return false
		if property.name=="person_state":
			var person = actor.get("person_state")
			if person is Dictionary and not bool(person.get("alive",true)): return false
	return true

func _tick_jobs(delta: float) -> void:
	for job in jobs.duplicate():
		var actor: Node3D=job.actor.get_ref()
		if actor==null or not _worker_can_work(actor): jobs.erase(job); continue
		var target: Vector3=job.target
		if Vector2(actor.global_position.x-target.x,actor.global_position.z-target.z).length()>2.5 or absf(actor.global_position.y-sample_height(target.x,target.z))>3.0:
			job.state="walking"; continue
		job.state="working"; job.tick+=minf(delta,0.1)
		if job.tick<0.5: continue
		var result := apply_command(target,job.kind)
		if not result.ok: continue
		job.tick=0.0; job.remaining-=0.5
		if job.remaining<=0.0: jobs.erase(job)

func save_state() -> Dictionary:
	var rows: Array=[]
	for key in edits: rows.append([key.x,key.y,edits[key]])
	return {"version":1,"source_id":source_id,"edits":rows}

func replay_state(state: Dictionary) -> Dictionary:
	if state.get("version")!=1 or state.get("source_id")!=source_id or not state.get("edits") is Array or state.edits.size()>MAX_EDIT_VERTICES: return {"ok":false,"error":"invalid_state"}
	var restored: Dictionary={}
	for row in state.edits:
		if not row is Array or row.size()!=3: return {"ok":false,"error":"invalid_row"}
		for value in row:
			if not (value is int or value is float) or not is_finite(value): return {"ok":false,"error":"invalid_number"}
		if not in_bounds(row[0],row[1]) or row[0]!=roundf(row[0]) or row[1]!=roundf(row[1]) or row[2]>0 or row[2]<-MAX_DEPTH: return {"ok":false,"error":"invalid_edit"}
		restored[Vector2i(row[0],row[1])]=float(row[2])
	edits=restored; pending.clear(); jobs.clear()
	_invalidate_height_cache()
	# Replay is a loading operation; normal runtime edits remain bounded.
	for key in chunks.keys(): _build_chunk(key)
	return {"ok":true}

func reset() -> void:
	edits.clear(); pending.clear(); jobs.clear()
	_invalidate_height_cache()
	for key in chunks.keys(): _build_chunk(key)

func _capture_original(source: MeshInstance3D) -> void:
	_invalidate_height_cache()
	if source.mesh==null: return
	var world_bounds := source.global_transform*source.mesh.get_aabb()
	if world_bounds.size.x>200.0 or world_bounds.size.z>200.0: return
	source_id += ":"+str(source.name)+":"+str(source.mesh.get_aabb())+":"+str(source.global_transform)
	for surface in range(source.mesh.get_surface_count()):
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in vertices.size(): indices.append(i)
		for i in range(0,indices.size()-2,3):
			var a: Vector3=source.global_transform*vertices[indices[i]]
			var b: Vector3=source.global_transform*vertices[indices[i+1]]
			var c: Vector3=source.global_transform*vertices[indices[i+2]]
			var av:=Vector2(a.x,a.z); var bv:=Vector2(b.x,b.z); var cv:=Vector2(c.x,c.z)
			var den := (bv-av).cross(cv-av)
			if absf(den)<0.00001: continue
			for z in range(floori(minf(a.z,minf(b.z,c.z))),ceili(maxf(a.z,maxf(b.z,c.z)))+1):
				for x in range(floori(minf(a.x,minf(b.x,c.x))),ceili(maxf(a.x,maxf(b.x,c.x)))+1):
					var pv:=Vector2(x,z)
					var v := (pv-av).cross(cv-av)/den; var w := (bv-av).cross(pv-av)/den
					if v< -0.00001 or w< -0.00001 or v+w>1.00001: continue
					var edge := minf(minf(x-world_bounds.position.x,world_bounds.end.x-x),minf(z-world_bounds.position.z,world_bounds.end.z-z))
					var blend := smoothstep(0.0,8.0,edge)
					local_base[Vector2i(x,z)]=lerpf(_procedural_base(x,z),a.y+(b.y-a.y)*v+(c.y-a.y)*w,blend)
	source.visible=false
	_disable_collision(source)

func _disable_collision(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D: child.collision_layer=0; child.collision_mask=0
		if child is CollisionShape3D: child.disabled=true
		_disable_collision(child)
