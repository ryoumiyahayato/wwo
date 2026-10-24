extends Node
## Reconstructed base after cloud reset. Fictional Combat rules; no aggregate vehicle HP.
const FriendlySafety = preload("res://modules/ai_safety/friendly_safety.gd")
const CombatAudit = preload("res://modules/ai_armor/combat_audit.gd")
var combat_audit = CombatAudit.new()
const DamageFeedback = preload("res://modules/ai_armor/vehicle_damage_feedback.gd")
var damage_feedback = DamageFeedback.new()
const DeploymentTerrain = preload("res://modules/ai_armor/deployment_terrain.gd")
const VisualContact = preload("res://modules/ai_armor/visual_contact.gd")
const Gunnery = preload("res://modules/ai_armor/gunnery_solution.gd")
const ACQUIRE_SECONDS := 1.0
const STABLE_AIM_SECONDS := 0.45
const GroundSupport = preload("res://scripts/vehicle_ground_support.gd")
const Combat = preload("res://scripts/combat.gd")
const Visibility = preload("res://scripts/battle_ai_presets.gd")
var main: Node3D
var units: Dictionary = {}
var optimization_enabled := true
var elapsed := 0.0
var shots_fired := 0
var blocked_moves := 0

func setup(owner_main: Node3D) -> void:
	main=owner_main

func on_stage_reset() -> void:
	for u in units.values():
		if is_instance_valid(u.model): u.model.queue_free()
	units.clear()
	combat_audit.clear()
	elapsed=0.0
	shots_fired=0
	blocked_moves=0

func spawn(stage: Node3D) -> void:
	on_stage_reset()
	var origin: Vector3=main.hero.global_position
	DeploymentTerrain.spawn(main,origin,"blue","player")
	# Keep the same cover and spawn; face the open left flank rather than its wall.
	main.hero.set_meta("deployment_home",origin)
	main.hero.rotation.y=atan2(20.0,-8.0)
	main.align_vehicle_ground(main.hero,true)
	for i in range(9):
		var team := "blue" if i<4 else "red"
		var slot := i if i<4 else i-4
		var pos := origin+Vector3((float(slot)-1.5)*36.0,0,-100.0 if team=="blue" else 245.0)
		if team=="blue" and slot>=2: pos.z-=18.0
		var id := "armor_%s_%d"%[team,slot]
		spawn_unit(id,team,pos,stage,i%2,i)
		var forward := 1.0 if team=="blue" else -1.0
		var side := -18.0 if team=="blue" else 18.0
		units[id].deployment_route=[pos+Vector3(side,0,0),pos+Vector3(side,0,forward*40.0)]
		DeploymentTerrain.spawn(main,pos,team,id)

func spawn_unit(id: String, team: String, position: Vector3, stage: Node3D, model_index := 0, index := 0) -> Node3D:
	var model: Node3D=main.load_model(model_index,false)
	model.name=id
	model.visible=false # Fail closed from allocation, including the first render frame.
	model.set_meta("actor_id",id)
	model.set_meta("team_id",team)
	model.set_meta("actor_kind","vehicle")
	stage.add_child(model)
	model.global_position=position
	model.rotation.y=PI if team=="blue" else 0.0
	var state=Combat.new(20261017+index*131)
	state.configure_tank("heavy" if model_index==0 else "light")
	var turret: Node3D=model.find_child("Turret",true,false)
	if turret==null: turret=model
	var center := Vector3(0,.745,0) if model_index==0 else Vector3(0,.95,0)
	var size := Vector3(2.18,.91,5.31) if model_index==0 else Vector3(2.7,1.05,4.6)
	main.hitbox(model,center,size,"armor_group","hull")
	main.hitbox(turret,Vector3(0,.25,.07),Vector3(2.25,.7,3.28),"armor_group","turret")
	for side in [-1,1]: main.hitbox(model,Vector3(side*1.42,.411,0),Vector3(.56,.7975,5.223),"armor","track_left" if side<0 else "track_right")
	main.add_internal_crew(model,state)
	_add_team_panels(model,team,center,size)
	var excludes: Array[RID]=[]
	for body in model.find_children("*","CollisionObject3D",true,false):
		body.set_meta("actor_id",id)
		excludes.append(body.get_rid())
	var envelope := BoxShape3D.new()
	envelope.size=Vector3(3.4,1.4,5.4)
	var u := {"visual_weapons":{"primary":{"weapon_id":"game_tank_cannon"},"mg":{"weapon_id":"game_vehicle_mg"}},"id":id,"team":team,"model":model,"combat":state,"turret":turret,
		"barrel":model.find_child("Barrel",true,false),"muzzle":model.find_child("Muzzle",true,false),
		"mg_muzzle":model.find_child("MG_Muzzle",true,false),"mg_reload":0.0,
		"exclude":excludes,"shape":envelope,"home":position,"goal":position+Vector3(0,0,12 if team=="blue" else -12),
		"memory":{},"scan_cursor":index*3,"target":{},"think":index*.07,"reload":5.0+index*.8,"speed":0.0,"travel":0.0,
		"left_travel":0.0,"right_travel":0.0,"shots":0,"blocked":0,"avoid":0.0,"index":index}
	u["focus_id"]=""
	u["target_acquired_at"]=elapsed
	u["stable_aim"]=0.0
	u["deployment_route"]=[]
	units[id]=u
	main.vehicle_ammo.register_vehicle(id,preload("res://modules/vehicle_ammo/ammo_config.gd").loadout("cannon",true))
	damage_feedback.setup(u)
	main.align_vehicle_ground(model,true)
	return model

func _add_team_panels(model: Node3D, team: String, center: Vector3, size: Vector3) -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color=Color("397bcb") if team=="blue" else Color("ba493e")
	paint.roughness=.92
	for side in [-1,1]:
		var panel := MeshInstance3D.new()
		panel.name="TeamHullPanelLeft" if side<0 else "TeamHullPanelRight"
		var mesh := BoxMesh.new()
		mesh.size=Vector3(.012,.26,.85)
		panel.mesh=mesh
		panel.material_override=paint
		panel.position=center+Vector3(side*(size.x*.5+.004),size.y*.22,size.z*.27)
		model.add_child(panel)
	var roof := MeshInstance3D.new()
	roof.name="TeamRearDeckStripe"
	var mesh := BoxMesh.new()
	mesh.size=Vector3(size.x*.65,.012,.28)
	roof.mesh=mesh
	roof.material_override=paint
	roof.position=center+Vector3(0,size.y*.5+.004,size.z*.35)
	model.add_child(roof)

func candidates() -> Array:
	var result: Array=[]
	for u in units.values():
		if not is_instance_valid(u.model): continue
		result.append({"actor_id":u.id,"team_id":u.team,"actor_kind":"vehicle","position":u.model.global_position+Vector3.UP*1.1,"alive":_alive(u),"node":u.model,"exclude":u.exclude})
	return result

func _alive(u: Dictionary) -> bool:
	for person in u.combat.crew:
		if person.alive: return true
	return false

func _role_alive(u: Dictionary, role: String) -> bool:
	# Historical name retained for adapters; this is now the shared capability gate.
	var index: int=u.combat.crew_roles.find(role)
	return index>=0 and preload("res://modules/vehicle_crew/role_capability.gd").capable(u.combat.crew[index],role)

func _process(_delta:float) -> void:
	if not is_instance_valid(main) or main.garage:return
	for u in units.values():
		if is_instance_valid(u.model):u.model.visible=main.visibility_for_node(u.model)=="visible"

func _physics_process(delta: float) -> void:
	if not is_instance_valid(main) or main.garage or main.game_mode!="skirmish": return
	if main.has_method("is_battle_active") and not main.is_battle_active(): return
	elapsed+=delta
	for u in units.values():
		if not is_instance_valid(u.model): continue
		if not u.get("tactical_order",{}).is_empty():
			u.tactical_order.remaining=maxf(0.0,float(u.tactical_order.remaining)-delta)
			if float(u.tactical_order.remaining)<=0:u.tactical_order={}
		u.combat.advance_time(delta)
		u["reload_overshoot"]=maxf(0.0,delta-float(u.reload)) if u.reload>0.0 else 0.0
		u["mg_overshoot"]=maxf(0.0,delta-float(u.mg_reload)) if u.mg_reload>0.0 else 0.0
		u.reload=maxf(0,u.reload-delta)
		u.mg_reload=maxf(0,u.mg_reload-delta)
		u.think-=delta
		if u.think<=0 or not optimization_enabled:
			u.think=.65
			damage_feedback.sync(u)
			_think(u)
		_move(u,delta)
		_aim(u,delta)

func _think(u: Dictionary) -> void:
	var previous_id: String=u.target.get("actor_id","")
	u.target={}
	if not _alive(u): return
	for id in u.memory.keys():
		if float(u.memory[id].expires)<=elapsed: u.memory.erase(id)
	var list: Array=candidates()
	if is_instance_valid(main.hero): list.append({"actor_id":"player","team_id":"blue","actor_kind":"vehicle","position":main.hero.global_position+Vector3.UP*1.1,"alive":true})
	if is_instance_valid(main.ai_host):
		for entry in main.ai_host.infantry_candidates(u.id):
			if str(entry.get("actor_id",""))!="player" and not units.has(entry.get("actor_id","")): list.append(entry)
	var enemies: Array=[]
	for candidate in list:
		if candidate.team_id!=u.team and candidate.get("alive",false): enemies.append(candidate)
	# A requested enemy gets priority only after this vehicle observes it.
	var requested: Dictionary=u.get("tactical_order",{})
	if not requested.is_empty():
		for candidate in enemies:
			if str(candidate.actor_id)==str(requested.target_id):
				var contact:=_observe(u,candidate)
				if not contact.is_empty():
					_accept_target(u,contact)
					return
	# Keep a currently re-observed target rather than selecting a different scan slice.
	for candidate in enemies:
		if str(candidate.actor_id)==previous_id:
			var contact := _observe(u,candidate)
			if not contact.is_empty():
				_accept_target(u,contact)
				return
	var distance := INF
	# Bounded observer-local rays. Circular scan never infers that unseen candidates are known.
	for i in range(mini(8,enemies.size())):
		var candidate: Dictionary=enemies[(int(u.scan_cursor)+i)%enemies.size()]
		var observed := _observe(u,candidate)
		if observed.is_empty(): continue
		var d: float=u.model.global_position.distance_squared_to(observed.position)
		if d<distance:
			distance=d
			u.target=observed
	u.scan_cursor+=8
	if not u.target.is_empty():
		_accept_target(u,u.target)
		return
	u.focus_id=""
	u.stable_aim=0.0
	if not requested.is_empty() and float(requested.get("remaining",0))>0:
		u.goal=requested.position
		return
	# Only prior observations guide search; memory never permits firing.
	var remembered_distance := INF
	for record in u.memory.values():
		var d: float=u.model.global_position.distance_squared_to(record.position)
		if d<remembered_distance:
			remembered_distance=d
			u.goal=record.position
	if remembered_distance<INF: return
	if is_instance_valid(main.ai_host) and main.ai_host.has_method("shared_contacts"):
		for record in main.ai_host.shared_contacts(u.team):
			if float(record.get("remaining",0))<=0: continue
			var d: float=u.model.global_position.distance_squared_to(record.position)
			if d<remembered_distance:
				remembered_distance=d
				u.goal=record.position
	if remembered_distance<INF: return
	if u.model.global_position.distance_to(u.goal)<4:
		u.goal=u.home+Vector3(18*sin(elapsed*.12+u.index),0,(80 if u.team=="blue" else -80)+18*cos(elapsed*.12+u.index))

func _accept_target(u: Dictionary, candidate: Dictionary) -> void:
	# Candidate is already a bounded sensor packet; never refill it from live target transforms.
	var observed: Dictionary=candidate.duplicate(true)
	if str(u.focus_id)!=str(candidate.actor_id):
		u.target_acquired_at=elapsed
		u.stable_aim=0.0
	u.focus_id=str(candidate.actor_id)
	u.target=observed
	u.goal=observed.position
	u.memory[candidate.actor_id]={"position":observed.position,"expires":elapsed+Visibility.MEMORY_TTL}
	if is_instance_valid(main.ai_host) and main.ai_host.has_method("report_contact"):main.ai_host.report_contact(u.team,observed)

func _observe(u: Dictionary, candidate: Dictionary) -> Dictionary:
	var origin: Vector3=u.model.global_position+Vector3.UP*1.5
	var contact := VisualContact.observe(origin,-u.turret.global_basis.z,candidate.position,str(candidate.get("actor_kind","vehicle")),elapsed)
	if contact.is_empty() or not _visible(u,candidate): return {}
	contact.merge({"actor_id":candidate.actor_id,"team_id":candidate.team_id,"actor_kind":candidate.get("actor_kind","vehicle"),"alive":true,"visible":true})
	return contact

func _visible(u: Dictionary, candidate: Dictionary) -> bool:
	var origin: Vector3=u.model.global_position+Vector3.UP*1.5
	var destination: Vector3=candidate.position
	# Use exactly the infantry bridge's live rendered smoke volume, including growth/fade.
	var smoke := {"center":Vector3.ZERO,"radius":0.0,"active":false}
	if is_instance_valid(main.ai_host) and main.ai_host.has_method("_smoke_data"):
		smoke=main.ai_host._smoke_data()
	elif is_instance_valid(main.smoke_root) and main.combat.smoke_remaining>0:
		return false # Missing visibility bridge may not grant sight through active smoke.
	if Visibility.reason(origin,destination,["clear","rain","fog"][clampi(main.weather_index,0,2)],smoke.center,smoke.active,false,float(smoke.radius))!="visible": return false
	var query := PhysicsRayQueryParameters3D.create(origin,destination,1|8|128)
	query.exclude=u.exclude
	var hit: Dictionary=main.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or actor_id(hit.get("collider"))==candidate.actor_id

func _move(u: Dictionary, delta: float) -> void:
	var model: Node3D=u.model
	var unfit_pose: Transform3D=model.global_transform
	var baseline: Dictionary=main.align_vehicle_ground(model,true)
	if not bool(baseline.get("loaded",false)):
		model.global_transform=unfit_pose
		u.speed=0.0
		model.set_meta("track_left_speed",0.0)
		model.set_meta("track_right_speed",0.0)
		model.set_meta("vehicle_speed",0.0)
		return
	var before: Transform3D=model.global_transform
	var contact_before: Dictionary=main.vehicle_contacts.capture_pose(model)
	var old_yaw := model.rotation.y
	var desired_speed := 0.0
	if _role_alive(u,"驾驶员"):
		var route: Array=u.get("deployment_route",[])
		while not route.is_empty() and Vector2(model.global_position.x-route[0].x,model.global_position.z-route[0].z).length()<2.0:route.pop_front()
		var movement_goal: Vector3=route[0] if not route.is_empty() else u.goal
		var direction: Vector3=movement_goal-model.global_position
		var desired_yaw := atan2(-direction.x,-direction.z)
		if u.avoid>0:
			u.avoid-=delta
			# First back straight: turning into a nearby friendly used to roll back escape forever.
			desired_yaw=old_yaw if u.avoid>.5 else old_yaw+(.8 if int(u.index)%2==0 else -.8)
		var turn := clampf(wrapf(desired_yaw-old_yaw,-PI,PI),-.65*delta,.65*delta)
		var mobility: float=minf(float(u.combat.modules.track_left.integrity),float(u.combat.modules.track_right.integrity))/100.0
		model.rotation.y+=turn*mobility
		if direction.length()>(2.0 if not route.is_empty() else (20.0 if not u.target.is_empty() else 3.0)): desired_speed=3.8*mobility*maxf(.15,cos(wrapf(desired_yaw-old_yaw,-PI,PI)))
		if u.avoid>0: desired_speed=-1.0*mobility
	u.speed=move_toward(u.speed,desired_speed,3.0*delta)
	model.position+=Vector3(-sin(model.rotation.y),0,-cos(model.rotation.y))*u.speed*delta
	var attempted_yaw := model.rotation.y
	var ground: Dictionary=main.align_vehicle_ground(model,true)
	var horizontal := Vector2(model.position.x-before.origin.x,model.position.z-before.origin.z).length()
	var turn_distance := absf(wrapf(attempted_yaw-old_yaw,-PI,PI))
	var valid := GroundSupport.transition_allowed(baseline,ground,horizontal,turn_distance)
	if not valid:
		# A terrain-blocked drive may still make a physically safe pivot, never teleport.
		model.global_transform=before
		model.rotation.y=attempted_yaw
		ground=main.align_vehicle_ground(model,true)
		valid=GroundSupport.transition_allowed(baseline,ground,0.0,turn_distance)
		u.speed=0.0
	if valid:
		var contact: Dictionary=main.vehicle_contacts.resolve_pose(model,contact_before,u.speed,delta)
		if bool(contact.get("blocked",false)):
			u.speed=0.0
			u.avoid=1.0
			u.blocked+=1
			blocked_moves+=1
	else:
		model.global_transform=before
		u.speed=0.0
		u.avoid=1.0
		u.blocked+=1
		blocked_moves+=1
	var distance: float=model.global_position.distance_to(before.origin)
	var yaw_delta := wrapf(model.rotation.y-old_yaw,-PI,PI)
	var signed_distance: float=distance*signf(u.speed)
	u.travel+=distance
	u.left_travel+=signed_distance-yaw_delta*1.4
	u.right_travel+=signed_distance+yaw_delta*1.4
	model.set_meta("track_left_travel",u.left_travel)
	model.set_meta("track_right_travel",u.right_travel)
	model.set_meta("track_left_speed",u.speed-yaw_delta*1.4/maxf(delta,.001))
	model.set_meta("track_right_speed",u.speed+yaw_delta*1.4/maxf(delta,.001))
	model.set_meta("vehicle_speed",u.speed)
	model.set_meta("steering_input",yaw_delta/maxf(delta,.001))

func _aim(u: Dictionary, delta: float) -> void:
	if not _alive(u) or (units.has(str(u.target.get("actor_id",""))) and not _alive(units[str(u.target.actor_id)])):
		u.target={}
		u.stable_aim=0.0
		return
	if u.target.is_empty():
		_search_sector(u,delta)
		u.stable_aim=0.0
		return
	if not _role_alive(u,"炮手") or not is_instance_valid(u.muzzle) or not is_instance_valid(u.barrel):
		u.stable_aim=0.0
		return
	if not VisualContact.fresh(u.target,elapsed):
		u.target={}
		u.focus_id=""
		u.stable_aim=0.0
		return
	u["visible_checked_at"]=u.target.observed_at
	var contact_before: Dictionary=main.vehicle_contacts.capture_pose(u.model)
	var point: Vector3=u.target.position
	var local: Vector3=u.model.to_local(point)-u.turret.position
	var yaw := atan2(-local.x,-local.z)
	u.turret.rotation.y=rotate_toward(u.turret.rotation.y,yaw,.7*delta)
	var barrel_local: Vector3=u.turret.to_local(point)-u.barrel.position
	var pitch := clampf(atan2(barrel_local.y,Vector2(barrel_local.x,barrel_local.z).length()),-.15,.32)
	u.barrel.rotation.x=move_toward(u.barrel.rotation.x,pitch,.5*delta)
	main.vehicle_contacts.resolve_pose(u.model,contact_before,0.0,delta)
	var direction: Vector3=-u.muzzle.global_basis.z.normalized()
	var to_target: Vector3=(point-u.muzzle.global_position).normalized()
	var shot_range: float=Visibility.weapon_range("mg" if str(u.target.get("actor_kind","vehicle"))=="infantry" else "cannon")
	var aligned := direction.dot(to_target)>.9995
	u.stable_aim=float(u.stable_aim)+delta if aligned else 0.0
	if u.muzzle.global_position.distance_to(point)<=shot_range and aligned and elapsed-float(u.target_acquired_at)>=float(u.target.get("acquire_seconds",ACQUIRE_SECONDS)) and float(u.stable_aim)>=STABLE_AIM_SECONDS:
		if str(u.target.get("actor_kind","vehicle"))=="infantry" and is_instance_valid(u.mg_muzzle):
			if u.mg_reload<=0: _fire(u,-u.mg_muzzle.global_basis.z.normalized(),true)
		elif u.reload<=0: _fire(u,direction)

func _search_sector(u: Dictionary, delta: float) -> void:
	if not _role_alive(u,"炮手") or not is_instance_valid(u.turret): return
	var before: Dictionary=main.vehicle_contacts.capture_pose(u.model)
	u.turret.rotation.y=rotate_toward(u.turret.rotation.y,Gunnery.search_yaw(elapsed,int(u.get("index",0))),.35*delta)
	main.vehicle_contacts.resolve_pose(u.model,before,0.0,delta)

func _fire(u: Dictionary, direction: Vector3, machinegun := false) -> void:
	if not _alive(u) or not _role_alive(u,"炮手") or elapsed<float(u.get("safety_retry_until",0.0)) or not VisualContact.fresh(u.target,elapsed):return
	var muzzle:Node3D=u.mg_muzzle if machinegun else u.muzzle
	if not is_instance_valid(muzzle) or not muzzle.is_inside_tree():return
	if (float(u.mg_reload) if machinegun else float(u.reload))>0:return
	var intended_id:String=str(u.target.get("actor_id",""))
	if units.has(intended_id) and not _alive(units[intended_id]):
		u.target={}
		return
	var barrel_axis := direction.normalized()
	direction=Gunnery.shot_axis(barrel_axis,float(u.get("speed",0.0)),int(u.shots),int(u.get("index",0)),machinegun)
	u["shot_barrel_axis"]=barrel_axis
	u["shot_cone_radians"]=Gunnery.cone_radians(float(u.get("speed",0.0)),machinegun)
	var origin: Vector3=u.mg_muzzle.global_position if machinegun else u.muzzle.global_position
	var shot_range: float=Visibility.weapon_range("mg" if machinegun else "cannon")
	var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*shot_range,1|8|128)
	query.exclude=u.exclude
	var hit: Dictionary=main.get_world_3d().direct_space_state.intersect_ray(query)
	var endpoint: Vector3=hit.get("position",origin+direction*shot_range)
	if (not hit.is_empty() and FriendlySafety.collider_team(hit.collider)==u.team) or FriendlySafety.friendly_corridor(main.get_world_3d().direct_space_state,origin,endpoint,u.exclude,u.team):
		u["safety_retry_until"]=elapsed+.15
		return
	var period:float=.6 if machinegun else (6.0 if _role_alive(u,"装填手") else 8.0)
	var committed:Dictionary=main.vehicle_ammo.commit_fire(str(u.id),"mg" if machinegun else "primary",main.vehicle_ammo.request_id(),period,true,true)
	if not bool(committed.ok):
		u["ammo_reason"]=str(committed.reason)
		return
	u["ammo_reason"]=""
	u["ammo_commit"]=committed.commit
	var audit_id := _audit_shot(u,origin,direction,endpoint,hit,machinegun)
	main.spawn_ai_shot(origin,endpoint,"mg" if machinegun else "cannon",not hit.is_empty(),preload("res://scripts/weapon_vfx_profile.gd").describe(u,"mg" if machinegun else "cannon","mg" if machinegun else "primary"))
	if machinegun: u.mg_reload=.6-float(u.get("mg_overshoot",0.0))
	else: u.reload=(6.0 if _role_alive(u,"装填手") else 8.0)-float(u.get("reload_overshoot",0.0))
	if is_instance_valid(main.ai_host):
		if machinegun and main.ai_host.has_method("suppress_near_segment"): main.ai_host.suppress_near_segment(origin,endpoint,u.team,"mg")
	u.shots+=1
	shots_fired+=1
	if hit.is_empty(): return
	var event := hit.duplicate()
	event["hit"]=hit.duplicate()
	event["hit_actor_id"]=actor_id(hit.collider)
	event["actor_id"]=u.id
	event["team_id"]=u.team
	event["weapon"]="mg" if machinegun else "cannon"
	event["penetration"]=9 if machinegun else 110
	event["direction"]=direction
	event["origin"]=origin
	event["audit_id"]=audit_id
	event["ammo_commit"]=committed.commit
	if units.has(event.hit_actor_id): receive_hit(event)
	elif event.hit_actor_id=="player": main.apply_ai_hit(event)
	elif is_instance_valid(main.ai_host): main.ai_host.infantry_apply_hit(event)
	if not machinegun and main.has_method("explode_terrain"): main.explode_terrain(endpoint,.1)

func _audit_shot(u: Dictionary, origin: Vector3, direction: Vector3, endpoint: Vector3, hit: Dictionary, machinegun: bool) -> int:
	var target_point: Vector3=u.target.get("position",endpoint)
	return combat_audit.append({"ammo_commit":u.get("ammo_commit",-1),"time":elapsed,"source":u.id,"team":u.team,"weapon":"mg" if machinegun else "cannon", "origin":origin,"direction":direction,"barrel_axis":u.get("shot_barrel_axis",direction),"dispersion_cone_radians":u.get("shot_cone_radians",0.0),"vehicle_speed":u.get("speed",0.0),"target_id":u.target.get("actor_id",""),"target_position":target_point,"target_distance":origin.distance_to(target_point),"axis_dot":direction.dot((target_point-origin).normalized()),"visible_confirmed":VisualContact.fresh(u.target,elapsed),"observation_age":elapsed-float(u.get("visible_checked_at",-1.0)),"sensor":u.target.get("sensor",""),"range_uncertainty":u.target.get("range_uncertainty",0.0),"acquired_seconds":elapsed-float(u.target_acquired_at),"stable_seconds":u.stable_aim,"hit_actor_id":actor_id(hit.get("collider")),"hit_key":str(hit.collider.get_meta("key","")) if not hit.is_empty() else "","hit_position":endpoint,"hit_normal":hit.get("normal",Vector3.ZERO)})

func record_player_impact(event: Dictionary, impact: Dictionary) -> void:
	var source := str(event.get("actor_id",""))
	if combat_audit.attach_impact(int(event.get("audit_id",-1)),source,impact):return
	# Infantry/rocket hits use their already-resolved muzzle ray; no second query.
	var hit: Dictionary=event.get("hit",{})
	var point: Vector3=hit.get("position",event.get("position",Vector3.ZERO))
	var origin: Vector3=event.get("origin",point)
	combat_audit.append({"time":elapsed,"source":source,"team":event.get("team_id",""),"weapon":event.get("weapon",""),"origin":origin,"direction":event.get("direction",Vector3.ZERO),"target_id":"player","hit_actor_id":"player","target_distance":origin.distance_to(point),"hit_position":point,"player_impact":impact})

func recent_shots() -> Array:
	return combat_audit.snapshot()

func last_player_hit_summary() -> String:
	var last: Dictionary=combat_audit.last_player_impact()
	if last.is_empty():return ""
	var damage: Dictionary=last.player_impact
	var before: Array=damage.get("before_crew",[])
	var after: Array=damage.get("after_crew",[])
	var hp := ""
	if not before.is_empty() and not after.is_empty():hp=" · 车长 %.0f→%.0f"%[float(before[0].hp),float(after[0].hp)]
	return "%.1fs %s · %s %d/%d · %s%s"%[float(last.time),str(last.source),str(damage.get("entry","")),int(damage.get("penetration",0)),int(damage.get("thickness",0)),(str(damage.get("part","")) if not str(damage.get("part","")).is_empty() else "未直中乘员"),hp]

func actor_id(collider: Object) -> String:
	var node := collider as Node
	while is_instance_valid(node):
		if node.has_meta("actor_id"): return str(node.get_meta("actor_id"))
		node=node.get_parent()
	return ""

func receive_hit(event: Dictionary) -> Dictionary:
	event=event.duplicate()
	var nested: Dictionary=event.get("hit",{})
	for field in ["collider","normal","position"]:
		if nested.has(field): event[field]=nested[field]
	var id := str(event.get("hit_actor_id",actor_id(event.get("collider"))))
	if not units.has(id): return {"kind":"unknown_actor"}
	var u: Dictionary=units[id]
	if str(event.get("team_id",""))==u.team: return {"kind":"friendly_blocked"}
	var collider=event.get("collider")
	var key := str(collider.get_meta("key","hull")) if is_instance_valid(collider) else "hull"
	var entry := key
	if key in ["hull","turret"]: entry=Combat.face_from_hit(collider,event.get("normal",Vector3.FORWARD)) if is_instance_valid(collider) else Combat.face_from_normal(u.model.global_basis,event.get("normal",Vector3.FORWARD),key)
	var weapon := str(event.get("weapon","rifle"))
	var penetration := int(event.get("penetration",9))
	if weapon=="rifle": penetration=9
	if str(event.get("ammo",""))=="smoke": penetration=0
	if str(event.get("ammo",""))=="he" and weapon=="cannon": penetration=15
	if not u.combat.modules.has(entry): return {"kind":"invalid_module"}
	var impact:Dictionary={"normal":event.get("normal",Vector3.ZERO),"direction":event.direction} if event.has("direction") else {}
	var geometry:Dictionary=Combat.armor_geometry(float(u.combat.modules[entry].thickness),impact)
	if penetration<=0 or (weapon in ["rifle","pistol","smg","sniper","hmg","mg"] and (penetration<=geometry.effective_thickness or not geometry.valid)): return {"kind":"armor_stopped","damage":0,"module":entry}
	var crew_index := -1
	var part := ""
	if geometry.valid and penetration>geometry.effective_thickness and event.has("position"):
		var direction: Vector3=event.get("direction",-event.get("normal",Vector3.FORWARD))
		var query := PhysicsRayQueryParameters3D.create(event.position+direction*.03,event.position+direction*8,2)
		var internal: Dictionary=main.get_world_3d().direct_space_state.intersect_ray(query)
		if not internal.is_empty() and actor_id(internal.collider)==id:
			crew_index=int(internal.collider.get_meta("crew_index",-1))
			part=str(internal.collider.get_meta("key",""))
	var result: Dictionary=u.combat.hit_armor(entry,penetration,crew_index,part,null,impact)
	damage_feedback.sync(u)
	return result

func handle_player_projectile(hit: Dictionary, kind: String, ammo_name: String, penetration := 110) -> String:
	if hit.is_empty() or not units.has(actor_id(hit.get("collider"))): return ""
	var event := hit.duplicate()
	event["team_id"]="blue"
	event["weapon"]=kind
	event["ammo"]=ammo_name
	event["penetration"]=penetration
	var source_muzzle: Node3D=main.weapon_muzzle(kind=="mg")
	if not event.has("direction") and is_instance_valid(source_muzzle): event["direction"]=(hit.position-source_muzzle.global_position).normalized()
	var result := receive_hit(event)
	var unit:Dictionary=units[actor_id(hit.get("collider"))]
	if main.has_method("record_hit_feedback"):main.record_hit_feedback(int(hit.get("feedback_id",-1)),result,main.visibility_for_node(unit.model)=="visible" and str(unit.team)=="blue")
	if main.visibility_for_node(unit.model)!="visible":return "射击已结算，结果无法确认"
	if str(unit.team)!="blue":return "可见装甲弹着"+(" · 外置油布燃烧" if unit.combat.tarp_burning else "")
	return DamageFeedback.hit_message(result,unit)

func snapshot() -> Dictionary:
	var result := {"blue_ai":0,"red_ai":0,"shots":shots_fired,"blocked_moves":blocked_moves,"units":{}}
	for u in units.values():
		result["blue_ai" if u.team=="blue" else "red_ai"]+=1
		result.units[u.id]={"team":u.team,"position":u.model.global_position,"travel":u.travel,"shots":u.shots,"blocked":u.blocked,"alive":_alive(u),"damage_status":DamageFeedback.status(u),"driver":_role_alive(u,"驾驶员"),"gunner":_role_alive(u,"炮手"),"modules":u.combat.modules.duplicate(true),"crew":u.combat.crew.duplicate(true)}
	return result
