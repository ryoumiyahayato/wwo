extends SceneTree
## Bounded native terrain/scenery contract test, not a gameplay or GPU stress test.
const Field = preload("res://ridgevale/heightfield.gd")
const Terrain = preload("res://ridgevale/terrain.gd")
const Scenery = preload("res://ridgevale/world.gd")
const Support = preload("res://scripts/vehicle_ground_support.gd")
class SupportHost extends Node3D:
	var terrain_damage: Node3D
	func terrain_height(x: float, z: float) -> float:
		return terrain_damage.sample_height(x,z)
var failures: Array[String] = []
var checks := 0
var route_profiles: Array = []
var ray_samples := 0
var obstacle_probes := 0
var detail_lod_evidence: Array = []
var courtyard_native_samples := 0
var tree_material_evidence: Dictionary = {}
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
func _run() -> void:
	var field = Field.new()
	check(field.valid,"valid 1251x1251 float32 baked field")
	check(FileAccess.get_file_as_bytes(Field.HEIGHT_FILE).size()==1251*1251*4,"exact baked float32 byte count")
	if not field.valid:
		_finish(null,null)
		return
	check(field.heights.size()==1251*1251,"field sample count")
	check(Field.STEP==4.0 and Field.ORIGIN == -2500.0,"4m grid centered on original origin")
	check(Field.SOURCE_ID=="ridgevale_5km_c1_20261020","field identity")
	check(is_nan(field.sample(NAN,0)) and is_nan(field.sample(0,INF)),"reject nonfinite queries")
	for p in [Vector2(-2500,-2500),Vector2(2500,2500),Vector2(-2500,2500),Vector2(2500,-2500),Vector2.ZERO]:
		check(is_finite(field.sample(p.x,p.y)),"finite field at " + str(p))
	check(field.sample(-222,80)>field.sample(0,80)+20.0,"west ridge above saddle")
	check(field.sample(225,90)>field.sample(0,90)+25.0,"east ridge above saddle")
	var terrain = Terrain.new()
	root.add_child(terrain)
	terrain.set_process(false)
	var configured: Dictionary = terrain.configure(Vector3.ZERO,null)
	check(configured.get("ok",false),"native terrain configure succeeds")
	check(terrain.source_id==Field.SOURCE_ID,"terrain source identity")
	check(terrain.bounds.position.x == -2500 and terrain.bounds.end.x == 2500 and terrain.bounds.position.z == -2500 and terrain.bounds.end.z == 2500,"exact 5km world bounds")
	check(terrain.chunks.size()==9,"initial physical 3x3 spawn chunks")
	check(is_nan(terrain.sample_height(2500.1,0)) and is_nan(terrain.sample_height(0,-2500.1)),"terrain refuses out-of-bounds support")
	check(not terrain.configure(Vector3.ZERO,null).get("ok",true),"duplicate configure rejected")
	var scenery = Scenery.new()
	root.add_child(scenery)
	scenery.build(terrain)
	check(scenery.manifest.get("schema","")=="ridgevale-map-c1","manifest schema")
	check(scenery.manifest.get("source_id","")==terrain.source_id,"manifest agrees with terrain identity")
	var counts := {"house":0,"barn":0,"tree":0,"rock":0,"wall":0}
	var ids := {}
	for row in scenery.manifest.placements:
		check(not ids.has(row.id),"unique placement " + str(row.id))
		ids[row.id]=true
		for kind in counts:
			if str(row.kind).begins_with(kind): counts[kind] += 1
		var x := float(row.position[0]); var z := float(row.position[2])
		check(not (x > -120 and x < 120 and z > -180 and z < 340),"deployment center clear " + str(row.id))
		check(absf(x)<=400 and absf(z)<=400,"placement in authored focal square " + str(row.id))
	# Protect lateral village-yard access from an artificially steep protection-zone skirt.
	for row in scenery.manifest.placements:
		if not str(row.kind).begins_with("house"): continue
		var end_x:=float(row.position[0])-signf(float(row.position[0]))*14.0
		var z:=float(row.position[2])
		var count:=ceili(absf(end_x)/2.0)
		var previous:float=terrain.sample_height(0,z)
		var maximum_yard_grade:=0.0
		for i in range(1,count+1):
			var height:float=terrain.sample_height(end_x*float(i)/count,z)
			maximum_yard_grade=maxf(maximum_yard_grade,absf(height-previous)/(absf(end_x)/count))
			previous=height
		check(maximum_yard_grade<Support.MAX_GRADE,"village lateral yard approach below production traction limit " + str(row.id))
	check(counts.house==12 and counts.barn==1,"twelve houses and one barn")
	var detailed: bool = scenery.manifest.get("detail_overlay",{}).get("id","") == "ridgevale_existing_village_detail_v2"
	check(counts.tree==(77 if detailed else 60) and counts.rock==32 and counts.wall==(64 if detailed else 12),"bounded trees, rocks and stone walls")
	check(scenery.placement_count==scenery.manifest.placements.size(),"all placements built")
	check(scenery.collider_count==scenery.placement_count,"all scenery has defined collision")
	check(scenery.batch_count>0 and scenery.batch_count<scenery.placement_count,"cell+asset MultiMesh batching")
	check(scenery.snapshot().actors_created==0,"no new battle actors")
	check(scenery.find_children("*Bridge*","",true,false).is_empty() and scenery.find_children("*Water*","",true,false).is_empty(),"dry map has no bridge or water")
	# Imported mesh identity is preserved, including Godot's real index LODs.
	for kind in scenery.geometry_cache:
		check(scenery.geometry_cache[kind] is ArrayMesh,"reuse imported ArrayMesh " + str(kind))
	await physics_frame
	await physics_frame
	var probe_shape := BoxShape3D.new()
	probe_shape.size=Vector3(4.0,1.8,7.0)
	var deploy_points: Array[Vector2]=[Vector2.ZERO,Vector2(0,4),Vector2(-6,-7)]
	var hero:=Vector2(-6,-7)
	for i in range(9):
		var blue:=i<4
		var slot:=i if blue else i-4
		deploy_points.append(hero+Vector2((float(slot)-1.5)*36.0,(-100.0-18.0 if slot>=2 else -100.0) if blue else 245.0))
	for team in range(2):
		for squad in range(3):
			for member in range(5):
				deploy_points.append(hero+Vector2((float(squad)-1.0)*36.0+(float(member)-2.0)*3.0,15.0-float(squad)*40.0 if team==0 else 135.0+float(squad)*40.0))
	for p in deploy_points:
		var h: float=terrain.sample_height(p.x,p.y)
		check(is_finite(h),"deployment ground finite " + str(p))
		_obstacle_probe(terrain,p,probe_shape,"original actor slot")
	check(scenery.manifest.roads.size()==3,"one center and two flank routes")
	for road in scenery.manifest.roads:
		var maximum_grade:=0.0
		var maximum_cross_grade:=0.0
		var samples:=0
		for segment in range(road.points.size()-1):
			var p:=Vector2(float(road.points[segment][0]),float(road.points[segment][1]))
			var q:=Vector2(float(road.points[segment+1][0]),float(road.points[segment+1][1]))
			var distance:=p.distance_to(q)
			var count:=maxi(1,ceili(distance/2.0))
			var side:=Vector2(-(q-p).normalized().y,(q-p).normalized().x)
			var previous:float=terrain.sample_height(p.x,p.y)
			for i in range(count+1):
				var at:=p.lerp(q,float(i)/count)
				var height:float=terrain.sample_height(at.x,at.y)
				check(is_finite(height),"route finite " + str(road.id))
				if i>0: maximum_grade=maxf(maximum_grade,absf(height-previous)/(distance/count))
				previous=height
				var left:=at-side*float(road.width_m)*.5
				var right:=at+side*float(road.width_m)*.5
				maximum_cross_grade=maxf(maximum_cross_grade,absf(terrain.sample_height(left.x,left.y)-terrain.sample_height(right.x,right.y))/float(road.width_m))
				if i%4==0: _obstacle_probe(terrain,at,probe_shape,str(road.id))
				samples+=1
		check(maximum_grade<.16,"longitudinal route grade under 16% " + str(road.id))
		check(maximum_cross_grade<.16,"cross route grade under 16% " + str(road.id))
		route_profiles.append({"id":road.id,"max_longitudinal_grade":maximum_grade,"max_cross_grade":maximum_cross_grade,"samples":samples})
		# Actual physical rays and production rigid-track support at all route vertices.
		for pair in road.points:
			var at:=Vector2(float(pair[0]),float(pair[1]))
			await _physical_support(terrain,at)
	await _physical_support(terrain,Vector2.ZERO)
	if detailed:
		check(scenery.placement_count==186 and scenery.batch_count==113,"detail exact prop and batching budget")
		var tree_batches:=0
		var other_batches:=0
		var tree_receiving_disabled:=true
		var tree_cast_preserved:=true
		var non_tree_original_material:=true
		var tree_lod_bias_preserved:=true
		for node in scenery.get_children():
			if not node is MultiMeshInstance3D:continue
			if str(node.name).begins_with("RidgevaleBatch_tree_"):
				tree_batches+=1
				tree_receiving_disabled=tree_receiving_disabled and node.material_override==scenery.tree_material and node.material_override.disable_receive_shadows
				tree_cast_preserved=tree_cast_preserved and node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				tree_lod_bias_preserved=tree_lod_bias_preserved and is_equal_approx(node.lod_bias,1.0)
			else:
				other_batches+=1
				non_tree_original_material=non_tree_original_material and node.material_override==scenery.material and not node.material_override.disable_receive_shadows
		var changed_properties:Array=[]
		for property in scenery.material.get_property_list():
			if (int(property.usage)&PROPERTY_USAGE_STORAGE)==0:continue
			if scenery.material.get(property.name)!=scenery.tree_material.get(property.name):changed_properties.append(str(property.name))
		check(tree_batches==60 and other_batches==53,"tree-only material applied to exact tree batches")
		check(tree_receiving_disabled,"tree-only material disables receiving shadow banding")
		check(tree_cast_preserved,"all tree batches retain shadow casting")
		check(tree_lod_bias_preserved,"all tree batches retain default LOD bias")
		check(non_tree_original_material,"non-tree batches retain original shadow-receiving material")
		check(changed_properties==["disable_receive_shadows"],"tree material copy changes exactly one stored property")
		tree_material_evidence={"tree_batches":tree_batches,"non_tree_batches":other_batches,"tree_receive_shadows_disabled":tree_receiving_disabled,"tree_cast_shadows_preserved":tree_cast_preserved,"non_tree_original_material":non_tree_original_material,"tree_lod_bias_preserved":tree_lod_bias_preserved,"changed_properties":changed_properties,"tradeoff":"Trees no longer receive building, other-tree or self shadows; diffuse lighting and outward shadows remain"}
		for kind in ["wall_4m","tree_0","tree_1","tree_2"]:
			var mesh: ArrayMesh = scenery.geometry_cache[kind]
			var data: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(),0)
			var lods: Array = data.get("lods",[])
			check(lods.size()>0,"reused detail asset has native index LODs " + kind)
			var base_index_bytes: int = data.get("index_data",PackedByteArray()).size()
			var minimum_index_bytes: int = base_index_bytes
			for lod in lods: minimum_index_bytes=mini(minimum_index_bytes,lod.index_data.size())
			check(minimum_index_bytes<base_index_bytes,"detail native LOD reduces indices " + kind)
			detail_lod_evidence.append({"kind":kind,"base_indices":data.get("index_count",0),"lod_levels":lods.size(),"base_index_bytes":base_index_bytes,"minimum_lod_index_bytes":minimum_index_bytes})
		for court in scenery.manifest.detail_overlay.courtyards:
			var side:=float(court.side)
			var z:=float(court.center_z)
			for x in [123.0,131.0,139.0,143.0]:
				var at:=Vector2(side*x,z)
				# Long axis follows the actual lateral approach, not world Z.
				await _physical_support(terrain,at,PI*.5)
				for offset in [-3.0,0.0,3.0]:
					_obstacle_probe(terrain,Vector2(at.x,z+offset),probe_shape,"detail courtyard "+str(court.id),PI*.5,.9)
				courtyard_native_samples+=1
		# Representative west node: north exit and cardinal circulation stations
		# around the original house; cardinal samples are not a full driving proof.
		for at in [Vector2(-142.5,118),Vector2(-142.5,110),Vector2(-142.5,95),Vector2(-142.5,81.5),Vector2(-161.5,81.5),Vector2(-161.5,95),Vector2(-161.5,108.5)]:
			await _physical_support(terrain,at,0.0)
			_obstacle_probe(terrain,at,probe_shape,"west complete court north-south passage",0.0,.9)
		for at in [Vector2(-153,81.5),Vector2(-153,108.5)]:
			await _physical_support(terrain,at,PI*.5)
			_obstacle_probe(terrain,at,probe_shape,"west complete court lateral passage",PI*.5,.9)
		for at in [Vector2(-142.5,95),Vector2(-142.5,110)]:
			_obstacle_probe(terrain,at,probe_shape,"west east-lane diagonal turning clearance",PI*.25,.9)
	# Preserve sparse edits and single-step streaming under the same inherited owner.
	terrain.set_focus(Vector3.ZERO)
	_drain_until_loaded(terrain,Vector3.ZERO)
	var original:float=terrain.sample_height(0,0)
	var revision:int=terrain.ground_support_revision()
	check(terrain.apply_explosion(Vector3(0,original,0),.05).get("ok",false),"inherited edit accepts crater")
	terrain.flush_updates()
	var edited:float=terrain.sample_height(0,0)
	check(edited<original and terrain.ground_support_revision()>revision,"inherited edits invalidate support cache")
	terrain.set_simulation_anchors([])
	terrain.set_focus(Vector3(1200,0,1200))
	check(not terrain.is_position_loaded(Vector3.ZERO),"origin really evicted for persistence test")
	_drain_until_loaded(terrain,Vector3(1200,0,1200))
	terrain.set_focus(Vector3.ZERO)
	_drain_until_loaded(terrain,Vector3.ZERO)
	check(is_equal_approx(terrain.sample_height(0,0),edited),"baked base plus edit persists after eviction")
	_finish(terrain,scenery)
func _obstacle_probe(terrain: Node3D, at: Vector2, shape: BoxShape3D, label: String, yaw: float = 0.0, y_offset: float = 2.1) -> void:
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.collision_mask=8
	query.transform=Transform3D(Basis(Vector3.UP,yaw),Vector3(at.x,terrain.sample_height(at.x,at.y)+y_offset,at.y))
	var hits:=root.get_world_3d().direct_space_state.intersect_shape(query,16)
	var blocked:=false
	for hit in hits:
		if not hit.collider.is_in_group("drivable_ground"): blocked=true
	obstacle_probes+=1
	check(not blocked,"static obstacle clearance " + label + " " + str(at))
func _drain_until_loaded(terrain: Node3D, point: Vector3) -> void:
	for i in range(26):
		if terrain.is_position_loaded(point): return
		var before:int=terrain.chunks.size()
		terrain._process(.016)
		check(terrain.chunks.size()<=before+1,"one chunk per inherited stream tick")
	check(false,"bounded stream reaches requested point")
func _physical_support(terrain: Node3D, at: Vector2, yaw: float = 0.0) -> void:
	var point:=Vector3(at.x,0,at.y)
	terrain.set_focus(point)
	# Include a full tank footprint at route junctions and chunk boundaries.
	terrain.set_simulation_anchors([point])
	for i in range(25):
		if terrain.stream_queue.is_empty(): break
		terrain._process(.016)
	check(terrain.is_position_loaded(point),"physical sample streamed " + str(at))
	await physics_frame
	await physics_frame
	var height:float=terrain.sample_height(at.x,at.y)
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(at.x,height+10,at.y),Vector3(at.x,height-10,at.y),8)
	var hit:=root.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty(),"actual native terrain ray " + str(at))
	if not hit.is_empty():
		check(hit.collider.is_in_group("drivable_ground"),"ray reaches terrain, not prop roof " + str(at))
		check(absf(float(hit.position.y)-height)<.035,"ray agrees with support height " + str(at))
	var host:=SupportHost.new()
	host.terrain_damage=terrain
	root.add_child(host)
	var tank:=Node3D.new()
	host.add_child(tank)
	tank.position=Vector3(at.x,height,at.y)
	tank.rotation.y=yaw
	var support:Dictionary=Support.fit(host,tank,true)
	check(support.loaded and support.driveable,"production rigid-track support is driveable " + str(at))
	host.free()
	ray_samples+=1
func _finish(terrain,scenery) -> void:
	var report:={"test":"ridgevale_native_contract","ok":failures.is_empty(),"checks":checks,"failures":failures,"route_profiles":route_profiles,"native_ray_and_track_samples":ray_samples,"static_obstacle_probes":obstacle_probes,"source_id":Field.SOURCE_ID,"scope":"Terrain and scenery only; no GUI, combat, Android, or GPU/FPS claim"}
	report["detail_native_lods"]=detail_lod_evidence
	report["tree_material_policy"]=tree_material_evidence
	report["courtyard_native_support_samples"]=courtyard_native_samples
	if terrain!=null: report["streaming"]=terrain.simulation_stream_snapshot()
	if scenery!=null: report["scenery"]=scenery.snapshot()
	var output:=FileAccess.open("res://ridgevale/review/native_contract.json",FileAccess.WRITE)
	if output!=null: output.store_string(JSON.stringify(report,"  ")+"\n")
	print("RIDGEVALE_NATIVE=",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
