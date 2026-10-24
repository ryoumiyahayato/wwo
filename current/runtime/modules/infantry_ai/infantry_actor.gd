extends CharacterBody3D
## Host-owned actor, real CharacterBody3D movement; never writes global combat state.
const Stance = preload("res://modules/infantry_ai/infantry_stance.gd")
var stance := "stand"
var sprinting := false
var _stance_pose: Dictionary = Stance.profile("stand")
var _stance_from: Dictionary = Stance.profile("stand")
var _stance_elapsed := Stance.TRANSITION_SECONDS
var _stance_enabled := false
var _stance_weapon_rest := Vector3.ZERO
var _stance_weapon_bound := false
var _pose_nodes: Dictionary = {}
var _pose_rest: Dictionary = {}
var _stance_support_clock := 0.0
var _stance_support_ok := true
var _visual_elapsed := 0.0

const FriendlySafety = preload("res://modules/ai_safety/friendly_safety.gd")
var _vehicle_yield_clock:=0.0
var _vehicle_yield_active:=false
var _vehicle_yield_direction:=Vector3.ZERO
const LocalNavigation = preload("res://modules/infantry_ai/infantry_navigation.gd")
var _route_planner = LocalNavigation.new()
var _route: Array[Vector3] = []
var _route_goal := Vector3.ZERO
var _route_retry := 0.0
const BattlePresets = preload("res://scripts/battle_ai_presets.gd")
const Brain = preload("res://modules/infantry_ai/infantry_brain.gd")
signal combat_event(event: Dictionary)
var brain = Brain.new()
var host: Node
var move_speed := 1.7
var gravity := 18.0
var aim_height := 1.1
var collision_mask_for_shots := 1 | 8 | 16 | 32 | 128
var shot_sequence := 0
var weapon := "rifle"
var damage := 2.0
var penetration := 9
var weapon_id := ""
var pickup_cooldown := 0.0
var suppression_cooldown := 0.0
var loot_target := ""
var loot_stall_time := 0.0
var loot_last_distance := INF
var loot_ignored: Dictionary = {}
var _configured := false
var person_state: Dictionary = {}
var embarked := false
var weapon_pivot: Node3D
var muzzle: Node3D
var engagement_delay := 0.0
var aim_offsets: Array = []
var _detour_direction := Vector3.ZERO
var _detour_remaining := 0.0
var _walk_phase := 0.0
var _walk_blend := 0.0
var _limbs: Dictionary = {}
var _limb_rest: Dictionary = {}
var _recoil := 0.0
# Fictional readability tuning: acquisition is not an instantaneous aim snap.
var ai_body_turn_rate := 2.4
var ai_weapon_turn_rate := 1.8
const AI_AIM_DOT := 0.999
var perception_slot := 0
var _cached_observations: Array = []
var _candidate_cursor := 0
var _ground_probe_clock := 0.0
var _ground_safe := true
var _last_progress := Vector3.ZERO
var _stalled := 0.0
var mg_suppression := 0.0
var blast_suppression := 0.0
var suppression_level := 0.0

func _scheduled_observations() -> Array:
 if brain.hp<=0.0:
  _cached_observations.clear()
  return []
 if not is_instance_valid(host) or not host.has_method("perception_due") or host.perception_due(perception_slot):
  _cached_observations = _observations()
  if is_instance_valid(host) and host.has_method("performance_snapshot"): host._perception_updates += 1
 return _cached_observations


func _process(delta: float) -> void:
 if _configured and not embarked:
  _visual_elapsed += delta
  var interval := float(get_meta("animation_interval",0.0))
  if _visual_elapsed>=interval:
   update_visual_pose(_visual_elapsed)
   _visual_elapsed = 0.0


func configure(id: String, team: String, owner_host: Node) -> void:
 brain.setup(id,team)
 host = owner_host
 set_meta("actor_id",id)
 set_meta("actor_kind","infantry")
 set_meta("kind","ai_person")
 set_meta("key","torso")
 set_meta("team_id",team)
 _configured = true

func _ready() -> void:
 collision_layer = 128
 collision_mask = 1 | 8 | 16 | 32 | 128
 floor_snap_length = 0.35
 if get_node_or_null("BodyCollision") == null:
  var capsule := CapsuleShape3D.new()
  capsule.radius = 0.27
  capsule.height = 1.65
  var shape := CollisionShape3D.new()
  shape.name = "BodyCollision"
  shape.shape = capsule
  shape.position.y = 0.825
  add_child(shape)

func _physics_process(delta: float) -> void:
 if not _configured or embarked: return
 var owner_main = host.get("main") if is_instance_valid(host) else null
 if is_instance_valid(owner_main):
  if owner_main.has_method("is_battle_active") and not owner_main.is_battle_active(): return
  var terrain = owner_main.get("terrain_damage")
  if is_instance_valid(terrain) and terrain.has_method("is_position_loaded") and not terrain.is_position_loaded(global_position):
   velocity = Vector3.ZERO
   return
 _advance_stance(delta)
 _advance_suppression(delta)
 if not person_state.is_empty():
  brain.hp = float(person_state.get("hp",brain.hp))
  brain.ammo = int(person_state.get("ammo",brain.ammo))
  brain.reserve_ammo = int(person_state.get("reserve_ammo",brain.reserve_ammo))
  if not bool(person_state.get("alive",true)): brain.hp = 0.0
 brain.memory_ttl = BattlePresets.MEMORY_TTL
 brain.nearby_vehicle_radius = 360.0
 brain.engagement_range = BattlePresets.weapon_range(weapon)
 brain.prefer_vehicles = weapon in ["at","rocket","grenade","grenade_launcher","heavy_grenade"]
 engagement_delay = maxf(0.0,engagement_delay-delta)
 pickup_cooldown = maxf(0.0,pickup_cooldown-delta)
 suppression_cooldown = maxf(0.0,suppression_cooldown-delta)
 if is_instance_valid(host) and host.has_method("infantry_weapon_tick"):
  host.infantry_weapon_tick(self,delta)
 if bool(get_meta("player_controlled",false)):
  var controller = get_meta("player_controller",null)
  if is_instance_valid(controller): controller.physics_tick(self,delta)
  return
 if suppression_level>=0.6: brain.cooldown += delta*0.65
 # Crew host owns this temporary movement request; never replace construction orders.
 var returning: Dictionary = get_meta("crew_return_order", {})
 var command: Dictionary
 if not returning.is_empty() and brain.hp > 0.0 and not bool(get_meta("construction_order",false)) and brain.order.is_empty():
  var destination: Vector3 = returning.get("destination",global_position)
  brain._set_state("return_to_vehicle")
  command = {"move":global_position.distance_to(destination)>float(returning.get("stop_distance",5.6)), "destination":destination, "fire":false, "target_id":"", "build":false}
 else:
  var observations := _scheduled_observations() if engagement_delay<=0.0 and weapon!="" and not bool(get_meta("construction_order",false)) else []
  var loot_command: Dictionary = {}
  if brain.hp>0.0 and not bool(get_meta("construction_order",false)) and brain.order.is_empty() and brain.tactical_order.is_empty() and is_instance_valid(host) and host.has_method("infantry_loot_command"):
   loot_command = host.infantry_loot_command(self,delta)
  command = brain.tick(delta,global_position,observations,false) if loot_command.is_empty() else loot_command
 var direction: Vector3 = command.destination - global_position
 direction.y = 0.0
 direction = direction.normalized() if bool(command.move) and direction.length() > 0.1 else Vector3.ZERO
 _route_retry = maxf(0.0,_route_retry-delta)
 _ground_probe_clock -= delta
 if direction.length_squared()>0.01 and _ground_probe_clock<=0.0:
  _ground_probe_clock = 0.12
  var ahead := global_position+direction*0.8
  var query := PhysicsRayQueryParameters3D.create(ahead+Vector3.UP*0.8,ahead-Vector3.UP*0.8,8,[get_rid()])
  var ground_hit := get_world_3d().direct_space_state.intersect_ray(query)
  _ground_safe = not ground_hit.is_empty() and ground_hit.normal.dot(Vector3.UP)>=cos(floor_max_angle)
 if direction.length_squared()>0.01:
  _stalled = _stalled+delta if global_position.distance_to(_last_progress)<0.015 else 0.0
 else: _stalled = 0.0
 _last_progress = global_position
 if _stalled>0.8:
  _route.clear()
  _stalled = 0.0
  _route_retry = 0.0
 var requested: Vector3 = command.destination
 if not bool(command.move):
  _route.clear()
 elif Vector2(requested.x-_route_goal.x,requested.z-_route_goal.z).length()>1.0:
  _route.clear()
  _route_retry = 0.0
  _route_goal = requested
 while not _route.is_empty() and Vector2(_route[0].x-global_position.x,_route[0].z-global_position.z).length()<0.26:
  _route.pop_front()
 _update_vehicle_yield(direction,delta)
 if _vehicle_yield_active:
  direction=_vehicle_yield_direction
  _stalled=0.0
 if direction.length_squared()>0.01 and not _vehicle_yield_active:
  # This local result lives only until planning/movement, never across actors or ticks.
  # The empty-route branch used to perform the same two capsule sweeps twice.
  var path_blocked_now: bool = _path_blocked(direction) if _route.is_empty() else false
  if _route.is_empty() and (path_blocked_now or not _ground_safe) and _route_retry<=0.0 and (not is_instance_valid(host) or not host.has_method("request_path_plan") or host.request_path_plan()):
   _route = _route_planner.plan(self,requested)
   # Re-probe after planner callbacks, which may change scene state.
   if _route.is_empty(): path_blocked_now = _path_blocked(direction)
   _route_goal = requested
   _route_retry = 1.0
  if not _route.is_empty():
   var next: Vector3 = _route[0]-global_position
   next.y = 0.0
   direction = next.normalized()
   # Dynamic people/obstacles may invalidate a previously clear route.
   if _path_blocked(direction,minf(0.65,next.length())):
    if _route_retry<=0.0:
     _route.clear()
     _route_retry = 0.25
    direction = Vector3.ZERO
  elif path_blocked_now or not _ground_safe: direction = Vector3.ZERO
 var effective_speed := locomotion_speed()*(0.6 if suppression_level>=0.6 else 1.0)
 if not person_state.is_empty():
  var parts: Dictionary = person_state.get("parts",{})
  for leg in ["left_leg","right_leg"]:
   if str(parts.get(leg,"healthy")) != "healthy": effective_speed *= 0.6
 direction = guard_stance_motion(direction,effective_speed,delta)
 velocity.x = direction.x * effective_speed
 velocity.z = direction.z * effective_speed
 if not is_on_floor(): velocity.y -= gravity * delta
 else: velocity.y = -0.1
 move_and_slide()
 if direction.length_squared() > 0.01: _set_body_heading(lerp_angle(rotation.y,atan2(-direction.x,-direction.z),minf(1.0,delta*9.0)))
 if brain.state in ["see_target","fire"] and not brain.target_id.is_empty():
  _aim_autonomous_weapon(_shot_aim_point(brain.last_known),delta)
 if command.fire:
  if not _shoot(str(command.target_id),command.destination,true):
   # Rejected intents do not consume ammunition. Bound retries while obstructed.
   brain.cooldown = maxf(brain.cooldown,0.15)
 _sync_person_state()
 if command.build:
  _emit({"kind":"build_requested","actor_id":brain.actor_id,"preset":command.preset,"position":global_position})

func _observations() -> Array:
 var result: Array = []
 if bool(get_meta("construction_order",false)): return result
 if not is_instance_valid(host) or not host.has_method("infantry_candidates"): return result
 var candidates: Array = host.infantry_candidates(brain.actor_id)
 for offset in candidates.size():
  var candidate: Dictionary = candidates[(_candidate_cursor+offset)%candidates.size()]
  if str(candidate.get("actor_id","")) == brain.actor_id: continue
  if str(candidate.get("team_id",brain.team_id)) == brain.team_id: continue
  if not bool(candidate.get("alive",false)): continue
  if str(candidate.get("actor_kind","infantry")) in ["vehicle","fortification"] and weapon not in ["at","rocket","grenade","grenade_launcher","heavy_grenade"]: continue
  var point: Vector3 = candidate.position
  var visible := false
  # Missing visibility integration fails closed; never grants omniscience.
  if host.has_method("infantry_visibility"):
   visible = float(host.infantry_visibility(brain.actor_id,str(candidate.actor_id))) > 0.0
  if visible:
   if host.has_method("consume_perception_ray") and not host.consume_perception_ray():
    _candidate_cursor = (_candidate_cursor+offset)%maxi(1,candidates.size())
    break
   var hit := _ray(point)
   visible = not hit.is_empty() and _collision_actor_id(hit.collider) == str(candidate.actor_id)
  if visible:
   var observation: Dictionary = candidate.duplicate()
   observation.visible = true
   result.append(observation)
   if host.has_method("report_contact"): host.report_contact(brain.team_id,observation)
 if host.has_method("shared_contacts"): result.append_array(host.shared_contacts(brain.team_id))
 return result

func _ray(point: Vector3) -> Dictionary:
 var start := global_position + Vector3.UP * aim_height
 var query := PhysicsRayQueryParameters3D.create(start,point,collision_mask_for_shots,[get_rid()])
 return get_world_3d().direct_space_state.intersect_ray(query)

func _collision_actor_id(collider: Object) -> String:
 var node := collider as Node
 while is_instance_valid(node):
  if node.has_meta("actor_id"): return str(node.get_meta("actor_id"))
  node = node.get_parent()
 return ""

func bind_weapon_geometry(visible_weapon: Node3D, actual_muzzle: Node3D) -> void:
 muzzle = actual_muzzle
 if not is_instance_valid(visible_weapon) or not is_instance_valid(muzzle): return
 weapon_pivot = Node3D.new()
 weapon_pivot.name = "WeaponAimPivot"
 add_child(weapon_pivot)
 # Pivot is half a model unit behind the actual authored muzzle, on its axis.
 weapon_pivot.global_transform = Transform3D(muzzle.global_basis.orthonormalized(),muzzle.global_position+muzzle.global_basis.z.normalized()*0.5)
 visible_weapon.reparent(weapon_pivot,true)
 _stance_weapon_rest = weapon_pivot.position
 _stance_weapon_bound = true

func aim_visible_weapon(point: Vector3) -> bool:
 if not is_instance_valid(weapon_pivot) or not is_instance_valid(muzzle): return false
 var planar := point-global_position
 planar.y = 0.0
 if planar.length_squared()>0.001: _set_body_heading(atan2(-planar.x,-planar.z))
 if weapon_pivot.global_position.distance_to(point)<0.01: return false
 weapon_pivot.look_at(point,Vector3.UP)
 return true

func _shot_aim_point(point: Vector3) -> Vector3:
 if aim_offsets.is_empty(): return point
 var offset: Vector2 = aim_offsets[shot_sequence%aim_offsets.size()]
 var toward := (point-global_position).normalized()
 return point+toward.cross(Vector3.UP).normalized()*offset.x+Vector3.UP*offset.y

func _aim_autonomous_weapon(point: Vector3, delta: float) -> void:
 if not is_instance_valid(weapon_pivot) or not is_instance_valid(muzzle): return
 var before := weapon_pivot.global_basis.orthonormalized().get_rotation_quaternion()
 var planar := point-global_position
 planar.y=0.0
 if planar.length_squared()>0.001:
  _set_body_heading(rotate_toward(rotation.y,atan2(-planar.x,-planar.z),ai_body_turn_rate*maxf(delta,0.0)))
 var toward := point-weapon_pivot.global_position
 if toward.length_squared()<0.0001: return
 var up := Vector3.FORWARD if absf(toward.normalized().dot(Vector3.UP))>0.999 else Vector3.UP
 var wanted := Basis.looking_at(toward,up).get_rotation_quaternion()
 var angle := before.angle_to(wanted)
 var weight := 1.0 if angle<0.0001 else minf(1.0,ai_weapon_turn_rate*maxf(delta,0.0)/angle)
 weapon_pivot.global_basis=Basis(before.slerp(wanted,weight))

func muzzle_trace() -> Dictionary:
 if not is_instance_valid(muzzle): return {}
 var origin := muzzle.global_position
 var direction := -muzzle.global_basis.z.normalized()
 var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*BattlePresets.weapon_range(weapon),collision_mask_for_shots,[get_rid()])
 query.hit_from_inside = true
 return get_world_3d().direct_space_state.intersect_ray(query)

## Optional bounded diagnostic facts only. Never changes targeting, aim or fire gates.
var fire_audit_enabled:=false
var fire_attempts:Array=[]
func _record_fire_attempt(row:Dictionary) -> void:
 row["physics_frame"]=Engine.get_physics_frames()
 row["actor"]=brain.actor_id
 row["state"]=brain.state
 fire_attempts.append(row)
 if fire_attempts.size()>256:fire_attempts.pop_front()
func _fire_rejected(reason:String,intended_id:String,point:Vector3) -> bool:
 if fire_audit_enabled:_record_fire_attempt({"reason":reason,"intended":intended_id,"observed_point":point,"ammo":brain.ammo,"seq":shot_sequence})
 return false

func _shoot(intended_id: String, point: Vector3, commit_round := false) -> bool:
 var ray_begun:=Time.get_ticks_usec()
 if embarked or brain.hp<=0.0 or weapon.is_empty(): return _fire_rejected("actor_unavailable",intended_id,point)
 if _stance_elapsed < Stance.TRANSITION_SECONDS: return _fire_rejected("stance_transition",intended_id,point)
 if not bool(get_meta("player_controlled",false)):
  if not is_instance_valid(host) or not host.has_method("infantry_visibility") or host.infantry_visibility(brain.actor_id,intended_id)<=0.0: return _fire_rejected("target_not_currently_visible",intended_id,point)
  var confirmed := _ray(point)
  if confirmed.is_empty() or _collision_actor_id(confirmed.collider)!=intended_id: return _fire_rejected("observation_ray_blocked_or_stale",intended_id,point)
  if global_position.distance_to(point)>BattlePresets.weapon_range(weapon): return _fire_rejected("out_of_weapon_range",intended_id,point)
 if brain.hp <= 0.0 or weapon.is_empty(): return _fire_rejected("actor_unavailable",intended_id,point)
 point = _shot_aim_point(point)
 if commit_round:
  # AI has been rotating visibly on preceding ticks; firing may never snap it.
  if not is_instance_valid(muzzle): return _fire_rejected("muzzle_unavailable",intended_id,point)
  var toward := (point-muzzle.global_position).normalized()
  if (-muzzle.global_basis.z.normalized()).dot(toward)<AI_AIM_DOT: return _fire_rejected("aim_slewing",intended_id,point)
 elif not aim_visible_weapon(point): return _fire_rejected("weapon_aim_unavailable",intended_id,point)
 # A barrel intersecting scenery cannot shoot through it even if its muzzle protrudes.
 var clearance := PhysicsRayQueryParameters3D.create(weapon_pivot.global_position,muzzle.global_position,collision_mask_for_shots,[get_rid()])
 clearance.hit_from_inside = true
 if not get_world_3d().direct_space_state.intersect_ray(clearance).is_empty(): return _fire_rejected("barrel_obstructed",intended_id,point)
 var ammo_before:int=brain.ammo
 var hit := muzzle_trace()
 # An opt-in equipment owner commits only after the real muzzle/clearance ray.
 # Existing training hosts have no callback and retain their original behavior.
 if is_instance_valid(host) and host.has_method("before_infantry_shot"):
  if host.has_method("record_native_ray_cost"):host.record_native_ray_cost(Time.get_ticks_usec()-ray_begun)
  if commit_round:return _fire_rejected("external_round_owner_requires_player_input",intended_id,point)
  if not host.before_infantry_shot(self,hit):return _fire_rejected("equipment_commit_refused",intended_id,point)
 if commit_round:
  var player_team:String=str(host.player_team) if is_instance_valid(host) else "blue"
  if not hit.is_empty() and FriendlySafety.collider_team(hit.collider,player_team)==brain.team_id:return _fire_rejected("friendly_first_collision",intended_id,point)
  var actual_end:Vector3=hit.get("position",muzzle.global_position-muzzle.global_basis.z.normalized()*BattlePresets.weapon_range(weapon))
  if FriendlySafety.friendly_corridor(get_world_3d().direct_space_state,muzzle.global_position,actual_end,[get_rid()],brain.team_id,player_team):return _fire_rejected("friendly_corridor",intended_id,point)
  brain.commit_shot()
 _recoil = 1.0
 shot_sequence += 1
 var origin := muzzle.global_position
 var direction := -muzzle.global_basis.z.normalized()
 var actual_id := "" if hit.is_empty() else _collision_actor_id(hit.collider)
 var event := {"kind":"shot","actor_id":brain.actor_id,"team_id":brain.team_id,"intended_actor_id":intended_id,"hit_actor_id":actual_id,"weapon":weapon,"preset":weapon+"_fixed","damage":damage,"penetration":penetration,"hit":hit,"direction":direction,"seq":shot_sequence,"origin":origin,"position":origin+direction*BattlePresets.weapon_range(weapon) if hit.is_empty() else hit.position}
 event["weapon_id"] = weapon_id
 event["weapon_instance_kind"] = host.weapon_instance_kind(weapon_id,weapon) if is_instance_valid(host) and host.has_method("weapon_instance_kind") else weapon
 event["render_weapon_nodes"] = weapon_render_nodes()
 event["round"] = "anti_armor_rocket" if weapon in ["at","rocket"] else weapon
 if fire_audit_enabled:
  _record_fire_attempt({"reason":"emitted","intended":intended_id,"hit":actual_id,"origin":origin,"endpoint":event.position,"ammo_before":ammo_before,"ammo_after":brain.ammo,"seq":shot_sequence,"collision_model":"muzzle_hitscan"})
 _emit(event)
 if not actual_id.is_empty() and is_instance_valid(host) and host.has_method("infantry_apply_hit"):
  host.infantry_apply_hit(event)

 return true

func body_part_at(world_point: Vector3) -> String:
 if _stance_enabled:
  var visual := get_node_or_null("InfantryVisual")
  if is_instance_valid(visual):
   var closest := INF
   var selected := "torso"
   for part in ["Head","Torso_Upper","Pelvis","UpperArm_L","UpperArm_R","Forearm_L","Forearm_R","Thigh_L","Thigh_R","Shin_L","Shin_R"]:
    var mesh := visual.find_child("*"+part,true,false) as MeshInstance3D
    if not is_instance_valid(mesh): continue
    var bounds := mesh.get_aabb()
    var point := mesh.to_local(world_point)
    var nearest := point.clamp(bounds.position,bounds.end)
    var distance := world_point.distance_squared_to(mesh.to_global(nearest))
    if distance<closest:
     closest = distance
     if part=="Head": selected = "head"
     elif "Arm" in part or "Forearm" in part: selected = "left_arm" if part.ends_with("_L") else "right_arm"
     elif "Thigh" in part or "Shin" in part: selected = "left_leg" if part.ends_with("_L") else "right_leg"
     else: selected = "torso"
   return selected
 var point := to_local(world_point)
 if point.y >= 1.38: return "head"
 if point.y < 0.65: return "left_leg" if point.x < 0.0 else "right_leg"
 if absf(point.x)>0.18 and point.y>=0.7: return "left_arm" if point.x < 0.0 else "right_arm"
 return "torso"

func _emit(event: Dictionary) -> void:
 combat_event.emit(event)
 if is_instance_valid(host) and host.has_method("infantry_event"):
  host.infantry_event(event)

func receive_damage(amount: float) -> void:
 if embarked: return
 if not person_state.is_empty(): brain.hp = float(person_state.get("hp",brain.hp))
 brain.receive_damage(amount)
 _sync_person_state()
 if brain.hp <= 0.0:
  velocity.x = 0.0
  velocity.z = 0.0

func order_build(site: Vector3, preset: String, approved: bool) -> bool:
 return brain.order_build(site,preset,approved)

func snapshot() -> Dictionary:
 return {"brain":brain.snapshot(),"position":[global_position.x,global_position.y,global_position.z],"shot_sequence":shot_sequence}

func bind_person_state(person: Dictionary) -> void:
 person_state = person
 brain.hp = float(person.get("hp",brain.hp))
 brain.ammo = int(person.get("ammo",brain.ammo))
 brain.reserve_ammo = int(person.get("reserve_ammo",brain.reserve_ammo))
 if brain.hp <= 0.0: brain._set_state("disabled")
 _sync_person_state()

func _sync_person_state() -> void:
 if person_state.is_empty(): return
 person_state["hp"] = brain.hp
 person_state["ammo"] = brain.ammo
 person_state["reserve_ammo"] = brain.reserve_ammo
 person_state["weapon_id"] = weapon_id
 person_state["weapon_kind"] = weapon
 person_state["alive"] = brain.hp > 0.0
 person_state["ai_state"] = brain.state

func set_embarked(value: bool) -> void:
 # Vehicle combat may have changed shared injury state while this actor slept.
 if not person_state.is_empty():
  brain.hp = float(person_state.get("hp",brain.hp))
  brain.ammo = int(person_state.get("ammo",brain.ammo))
  brain.reserve_ammo = int(person_state.get("reserve_ammo",brain.reserve_ammo))
  if not bool(person_state.get("alive",true)) or brain.hp <= 0.0:
   brain.hp = 0.0
   brain._set_state("disabled")
 embarked = value
 visible = not value
 set_physics_process(not value)
 collision_layer = 0 if value else 128
 collision_mask = 0 if value else 1|8|16|32|128
 velocity = Vector3.ZERO
 # The registry owns valid world exit placement; no HP/ammo/state reset here.
 _sync_person_state()

func update_visual_pose(delta: float) -> void:
 # Already-prone casualties retain their supported last articulated pose.
 # Applying the standing fall tilt on top of prone would twist limbs into ground.
 if brain.hp<=0.0 and _stance_enabled and float(_stance_pose.prone)>0.5:
  if is_instance_valid(weapon_pivot): weapon_pivot.visible = false
  return
 var body_shape := get_node_or_null("BodyCollision") as CollisionShape3D
 if is_instance_valid(body_shape) and body_shape.shape is CapsuleShape3D and not _stance_enabled:
  body_shape.shape.height = 0.56 if brain.hp<=0.0 else 1.65
  body_shape.position.y = 0.28 if brain.hp<=0.0 else 0.825
 var visual := get_node_or_null("InfantryVisual") as Node3D
 if not is_instance_valid(visual): return
 if _limbs.is_empty():
  for part in ["Thigh_L","Thigh_R","Shin_L","Shin_R","Foot_L","Foot_R","UpperArm_L","UpperArm_R","Forearm_L","Forearm_R"]:
   var limb := visual.find_child("*"+part,true,false) as Node3D
   if is_instance_valid(limb):
    _limbs[part] = limb
    _limb_rest[part] = limb.rotation
 var dead: bool = brain.hp<=0.0
 # Animate real displacement, never requested velocity against a wall.
 var speed := Vector2(get_real_velocity().x,get_real_velocity().z).length()
 _walk_blend = move_toward(_walk_blend,clampf(speed/maxf(move_speed,0.01),0.0,1.0) if not dead else 0.0,delta*5.0)
 _walk_phase += speed*delta*5.5
 _recoil = move_toward(_recoil,0.0,delta*8.0)
 for part in _limbs:
  var rest: Vector3 = _limb_rest[part]
  var swing := sin(_walk_phase+(PI if str(part).ends_with("_R") else 0.0))
  var gait_scale := 1.0-0.8*float(_stance_pose.prone)-0.65*float(_stance_pose.crouch)
  if str(part).begins_with("Thigh"):
   rest.x += swing*0.5*_walk_blend*gait_scale
  elif str(part).begins_with("Shin"):
   rest.x += maxf(0.0,-swing)*0.65*_walk_blend*gait_scale
  elif str(part).begins_with("Foot"):
   rest.x -= maxf(0.0,-swing)*0.35*_walk_blend*gait_scale
  elif str(part).begins_with("UpperArm"):
   # Keep authored two-hand ready pose with a weapon; no extra -0.75 rad snap.
   rest.x += -swing*0.10*_walk_blend if not weapon.is_empty() else -swing*0.28*_walk_blend
   rest.x += _recoil*0.12
  _limbs[part].rotation = rest

 _apply_articulated_stance(visual,delta,dead)
 if not dead:
  _solve_leg_plants()
  if not weapon.is_empty(): _solve_weapon_grips()
 var injured: bool = brain.hp<10.0
 var lean := 1.25 if dead else (0.14 if injured else 0.0)
 visual.rotation.z = move_toward(visual.rotation.z,lean,delta*2.5)
 visual.position.y = move_toward(visual.position.y,0.24 if dead else 0.0,delta*1.5)
 visual.scale.y = move_toward(visual.scale.y,0.58 if dead else 1.0,delta*1.2)
 if is_instance_valid(weapon_pivot): weapon_pivot.visible = not dead and not weapon.is_empty()

func _path_blocked(direction: Vector3, probe_distance := 0.65) -> bool:
 # A grounded capsule's horizontal probe commonly touches its walkable floor.
 # Only non-walkable contacts are obstacles; move_and_slide remains authoritative.
 var walkable_dot:=cos(floor_max_angle)
 var raised:=global_transform
 raised.origin+=up_direction*0.08
 # The second diagnostic sweep avoids a zero-distance floor contact masking a wall.
 # Neither sweep changes the actor transform; real movement still uses move_and_slide.
 for probe in [global_transform,raised]:
  var contact:=KinematicCollision3D.new()
  if not test_move(probe,direction*probe_distance,contact,0.001,false,8): continue
  for index in range(contact.get_collision_count()):
   if contact.get_normal(index).dot(up_direction)<walkable_dot: return true
 return false

# Fictional suppression uses two separate meters, never HP changes.
func receive_suppression(strength := 0.05, kind := "mg") -> void:
 if embarked or brain.hp<=0.0: return
 if kind=="blast": blast_suppression=minf(1.5,blast_suppression+maxf(0.0,strength))
 else: mg_suppression=minf(1.5,mg_suppression+maxf(0.0,strength))
 suppression_level=clampf(mg_suppression+blast_suppression,0.0,1.5)
 if suppression_level<1.0 or suppression_cooldown>0.0 or weapon.is_empty(): return
 suppression_cooldown=8.0
 if is_instance_valid(host) and host.has_method("infantry_drop_weapon"):
  host.infantry_drop_weapon(self,"suppression")
  pickup_cooldown=3.0
  if not bool(get_meta("player_controlled",false)): brain._set_state("suppressed")

func _advance_suppression(delta: float) -> void:
 mg_suppression=maxf(0.0,mg_suppression-maxf(0.0,delta)*0.18)
 blast_suppression=maxf(0.0,blast_suppression-maxf(0.0,delta)*0.07)
 suppression_level=clampf(mg_suppression+blast_suppression,0.0,1.5)

func suppression_snapshot() -> Dictionary:
 return {"mg":mg_suppression,"blast":blast_suppression,"combined":suppression_level,"hp":brain.hp}

func weapon_render_nodes() -> Array:
 var result: Array = []
 if is_instance_valid(weapon_pivot): _collect_weapon_meshes(weapon_pivot,result)
 return result
func _collect_weapon_meshes(node: Node, result: Array) -> void:
 if node is MeshInstance3D: result.append({"name":str(node.name),"path":str(node.get_path()),"visible":node.is_visible_in_tree(),"instance_id":node.get_instance_id()})
 for child in node.get_children(): _collect_weapon_meshes(child,result)

func receive_vehicle_contact(direction: Vector3, speed: float, crush: bool) -> bool:
 if embarked: return false
 if brain.hp<=0.0:
  collision_layer=0
  collision_mask=0
  if is_instance_valid(host) and host.has_method("infantry_weapon_tick"): host.infantry_weapon_tick(self,0.0)
  set_physics_process(false)
  return true
 if crush:
  receive_damage(100.0)
  if is_instance_valid(host) and host.has_method("infantry_weapon_tick"): host.infantry_weapon_tick(self,0.0)
  collision_layer=0
  collision_mask=0
  velocity=Vector3.ZERO
  set_physics_process(false)
  update_visual_pose(1.0)
  _emit({"kind":"vehicle_contact","actor_id":brain.actor_id,"result":"crushed","speed":speed})
  return true
 var planar := Vector3(direction.x,0,direction.z)
 if planar.length_squared()<0.0001: return false
 var collision := move_and_collide(planar.normalized()*clampf(maxf(0.15,absf(speed)/60.0),0.15,0.6))
 return collision==null

func _update_vehicle_yield(intended:Vector3,delta:float)->void:
 _vehicle_yield_clock-=delta
 if _vehicle_yield_clock>0.0:return
 _vehicle_yield_clock=.15
 _vehicle_yield_active=false
 _vehicle_yield_direction=Vector3.ZERO
 var neighbors:Array[Node3D]=FriendlySafety.nearby_friendly_vehicles(self,host,brain.team_id)
 for vehicle in neighbors:
  # A stopped vehicle remains a real navigation/collision obstacle, not an endless moving-track wait.
  # Approximate zero is the engine epsilon, not a gameplay low-speed threshold.
  if is_zero_approx(float(vehicle.get_meta("vehicle_speed",0.0))):continue
  var inside:bool=FriendlySafety.corridor_contains(vehicle,global_position)
  var entering:bool=FriendlySafety.corridor_contains(vehicle,global_position+intended*1.2)
  if not inside and not entering:continue
  _vehicle_yield_active=true
  if not inside:return # Wait outside; do not step into a moving track corridor.
  var local:Vector3=vehicle.to_local(global_position)
  var side:=1.0 if local.x>=0.0 else -1.0
  var outward:Vector3=vehicle.global_basis.x*side
  outward.y=0;outward=outward.normalized()
  var away:Vector3=global_position-vehicle.global_position;away.y=0;away=away.normalized()
  for candidate in [outward,(outward+away*.6).normalized()]:
   var end:Vector3=global_position+candidate*.85
   var unsafe:=false
   for other in neighbors:
    if other!=vehicle and FriendlySafety.corridor_contains(other,end):unsafe=true;break
   if unsafe or _path_blocked(candidate,.85):continue
   var query:=PhysicsRayQueryParameters3D.create(end+Vector3.UP*.8,end-Vector3.UP*.8,8,[get_rid()])
   var ground:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
   if ground.is_empty() or ground.normal.dot(Vector3.UP)<cos(floor_max_angle):continue
   _vehicle_yield_direction=candidate
   return
  return # No safe side exit: stop rather than push into another track/wall.


## Explicit request only; AI and spawn counts are deliberately unchanged.
func request_stance(requested: String) -> bool:
 if requested not in Stance.NAMES or embarked or brain.hp<=0.0: return false
 if requested==stance: return true
 var target: Dictionary = Stance.profile(requested)
 # Test the complete swept envelope, not only the final low/high shape.
 # Excludes self but includes ceilings, people, props and terrain.
 var swept := Vector3(0.54,maxf(float(_stance_pose.height),float(target.height)),maxf(float(_stance_pose.length),float(target.length)))
 if not _stance_envelope_clear(swept): return false
 # Prone/crawl needs support at both ends; do not bridge a crater or steep edge.
 if requested=="prone" and not _stance_support_safe(float(target.length)): return false
 _stance_from = _stance_pose.duplicate()
 stance = requested
 if stance!="stand": sprinting = false
 _stance_elapsed = 0.0
 _stance_enabled = true
 return true

func locomotion_speed() -> float:
 return move_speed*float(_stance_pose.speed)*(1.65 if sprinting and stance=="stand" else 1.0)

func _stance_envelope_clear(size: Vector3, heading := INF) -> bool:
 if not is_inside_tree(): return false
 var box := BoxShape3D.new()
 # Small sole gap avoids treating the supporting floor as an overhead obstacle.
 box.size = Vector3(size.x,size.y-0.04,size.z)
 var query := PhysicsShapeQueryParameters3D.new()
 query.shape = box
 query.transform = global_transform
 if is_finite(heading): query.transform.basis = Basis(Vector3.UP,heading)
 query.transform.origin += Vector3.UP*(size.y*0.5+0.025)
 query.collision_mask = collision_mask_for_shots
 query.exclude = [get_rid()]
 query.margin = 0.001
 return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _stance_support_safe(length: float, displacement := Vector3.ZERO, heading := INF) -> bool:
 var forward := -global_basis.z.normalized()
 if is_finite(heading): forward = Vector3(-sin(heading),0.0,-cos(heading))
 for along in [-0.4,0.0,0.4]:
  var point := global_position+displacement+forward*length*float(along)
  var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.18,point-Vector3.UP*0.22,8,[get_rid()])
  var hit := get_world_3d().direct_space_state.intersect_ray(query)
  if hit.is_empty() or hit.normal.dot(Vector3.UP)<0.94: return false
 return true

func _advance_stance(delta: float) -> void:
 if not _stance_enabled: return
 var body_shape := get_node_or_null("BodyCollision") as CollisionShape3D
 if not is_instance_valid(body_shape): return
 if brain.hp<=0.0:
  if body_shape.has_meta("stance_dead"): return
  body_shape.set_meta("stance_dead",true)
  var dead_shape := BoxShape3D.new()
  dead_shape.size = Vector3(0.54,0.52,1.85)
  body_shape.shape = dead_shape
  body_shape.position = Vector3(0.0,0.28,0.0)
  return
 if _stance_elapsed>=Stance.TRANSITION_SECONDS: return
 var next_time := minf(Stance.TRANSITION_SECONDS,_stance_elapsed+maxf(0.0,delta))
 var next_pose := Stance.blend(_stance_from,Stance.profile(stance),next_time/Stance.TRANSITION_SECONDS)
 # Recheck growth every physics tick: another actor/prop can enter mid-transition.
 if (float(next_pose.height)>float(_stance_pose.height)+0.001 or float(next_pose.length)>float(_stance_pose.length)+0.001) and not _stance_envelope_clear(Stance.envelope(next_pose)): return
 _stance_elapsed = next_time
 _stance_pose = next_pose
 aim_height = float(_stance_pose.eye)
 if not body_shape.shape is BoxShape3D: body_shape.shape = BoxShape3D.new()
 body_shape.shape.size = Stance.envelope(_stance_pose)
 body_shape.position = Vector3(0.0,float(_stance_pose.height)*0.5,0.0)
 if is_instance_valid(weapon_pivot) and _stance_weapon_bound:
  weapon_pivot.position = _stance_weapon_rest+Vector3(0.0,float(_stance_pose.weapon_y),float(_stance_pose.weapon_z))

func _apply_articulated_stance(visual: Node3D, _delta: float, dead: bool) -> void:
 if not _stance_enabled or dead: return
 if _pose_nodes.is_empty():
  for part in ["Pelvis","Torso_Upper","Neck"]:
   var node := visual.find_child("*"+part,true,false) as Node3D
   if is_instance_valid(node):
    _pose_nodes[part] = node
    _pose_rest[part] = node.transform
 if _pose_nodes.has("Pelvis"):
  var rest: Transform3D = _pose_rest.Pelvis
  rest.origin.y = float(_stance_pose.hip)
  rest.basis = Basis(Vector3.RIGHT,float(_stance_pose.pitch))*rest.basis
  _pose_nodes.Pelvis.transform = rest
 var crouch := float(_stance_pose.crouch)
 var prone := float(_stance_pose.prone)
 for side in ["L","R"]:
  var swing := sin(_walk_phase+(PI if side=="R" else 0.0))
  if _limbs.has("Thigh_"+side):
   _limbs["Thigh_"+side].rotation.x += -1.4*crouch+prone*swing*0.10*_walk_blend
  if _limbs.has("Shin_"+side):
   _limbs["Shin_"+side].rotation.x += 2.4*crouch+prone*0.18
  if _limbs.has("Foot_"+side): _limbs["Foot_"+side].rotation.x -= crouch
 # Head counter-rotation keeps gaze ahead while torso/hips lie along the ground.
 if _pose_nodes.has("Neck"):
  var rest: Transform3D = _pose_rest.Neck
  rest.basis = rest.basis*Basis(Vector3.RIGHT,-prone*1.47)
  _pose_nodes.Neck.transform = rest


func _solve_weapon_grips() -> void:
 if not is_instance_valid(weapon_pivot): return
 for side in ["L","R"]:
  if not _limbs.has("UpperArm_"+side) or not _limbs.has("Forearm_"+side): continue
  var upper: Node3D = _limbs["UpperArm_"+side]
  var lower: Node3D = _limbs["Forearm_"+side]
  var shoulder := upper.global_position
  var grip := weapon_pivot.to_global(Vector3(0.0,-0.02,-0.18 if side=="L" else -0.02))
  var offset := grip-shoulder
  var distance := clampf(offset.length(),0.031,0.485)
  if offset.length_squared()<0.0001: continue
  var toward := offset.normalized()
  var bend := (global_basis.x*(-1.0 if side=="L" else 1.0)+Vector3.DOWN*0.8)
  bend = bend-toward*bend.dot(toward)
  if bend.length_squared()<0.0001: bend = global_basis.z.cross(toward)
  bend = bend.normalized()
  var along := (0.26*0.26-0.23*0.23+distance*distance)/(2.0*distance)
  var radius := sqrt(maxf(0.0,0.26*0.26-along*along))
  var center := shoulder+toward*along
  # Prone elbows choose the supported point on the two-bone solution circle.
  # The gun is pulled back to make support reachable without stretching arms.
  var prone := float(_stance_pose.prone)
  if prone>0.001:
   var down := Vector3.DOWN-toward*Vector3.DOWN.dot(toward)
   if down.length_squared()>0.0001:
    down = down.normalized()
    var lateral := toward.cross(down).normalized()
    var shoulder_side := (shoulder-global_position).dot(global_basis.x)
    if lateral.dot(global_basis.x)*shoulder_side<0.0: lateral = -lateral
    var desired_y := global_position.y+0.065
    var support_weight := clampf((center.y-desired_y)/maxf(0.0001,-down.y*radius),0.0,1.0)
    var supported := down*support_weight+lateral*sqrt(maxf(0.0,1.0-support_weight*support_weight))
    bend = bend.lerp(supported,prone).normalized()
  var elbow := center+bend*radius
  _point_limb(upper,elbow-shoulder)
  _point_limb(lower,grip-lower.global_position)

func _point_limb(limb: Node3D, direction: Vector3) -> void:
 if direction.length_squared()<0.0001: return
 var before := limb.global_basis.orthonormalized()
 var turn := Quaternion(-before.y,direction.normalized())
 limb.global_basis = Basis(turn)*before


func _solve_leg_plants() -> void:
 # Keep soles above the local supporting plane during walk/crouch transitions.
 # These articulated targets use displacement phase, not extra per-frame raycasts.
 var prone := float(_stance_pose.prone)
 var crouch := float(_stance_pose.crouch)
 var normal := get_floor_normal() if is_on_floor() else Vector3.UP
 var run_blend := clampf((Vector2(get_real_velocity().x,get_real_velocity().z).length()/maxf(move_speed,0.01)-1.0)/0.65,0.0,1.0)
 for side in ["L","R"]:
  if not _limbs.has("Thigh_"+side) or not _limbs.has("Shin_"+side) or not _limbs.has("Foot_"+side): continue
  var upper: Node3D = _limbs["Thigh_"+side]
  var lower: Node3D = _limbs["Shin_"+side]
  var foot: Node3D = _limbs["Foot_"+side]
  var phase := _walk_phase+(PI if side=="R" else 0.0)
  var local_target := Vector3(-0.105 if side=="L" else 0.105,0.08+maxf(0.0,cos(phase))*lerpf(0.10,0.16,run_blend)*_walk_blend,sin(phase)*lerpf(lerpf(0.25,0.35,run_blend),0.12,crouch)*_walk_blend-0.025*crouch)
  var crawl_target := Vector3(-0.17 if side=="L" else 0.17,0.08+maxf(0.0,cos(phase))*0.025*_walk_blend,0.74+sin(phase)*0.075*_walk_blend)
  local_target = local_target.lerp(crawl_target,prone)
  var target := to_global(local_target)
  var horizontal := target-global_position
  target.y -= (normal.x*horizontal.x+normal.z*horizontal.z)/maxf(normal.y,0.2)
  var offset := target-upper.global_position
  if offset.length_squared()<0.0001: continue
  var distance := clampf(offset.length(),0.02,0.789)
  var toward := offset.normalized()
  var bend := (-global_basis.z).lerp(global_basis.x*(-1.0 if side=="L" else 1.0),prone)
  bend = bend-toward*bend.dot(toward)
  if bend.length_squared()<0.0001: bend = global_basis.x.cross(toward)
  bend = bend.normalized()
  var along := (0.4*0.4-0.39*0.39+distance*distance)/(2.0*distance)
  var knee := upper.global_position+toward*along+bend*sqrt(maxf(0.0,0.4*0.4-along*along))
  _point_limb(upper,knee-upper.global_position)
  _point_limb(lower,target-lower.global_position)
  foot.global_basis = global_basis.orthonormalized()*Basis(Vector3.UP,lerpf(PI,0.0,prone))


func _set_body_heading(heading: float) -> void:
 if not _stance_enabled or float(_stance_pose.length)<=0.6:
  rotation.y = heading
  return
 # A long prone body must not rotate its tail through a wall/person.
 var delta_angle := wrapf(heading-rotation.y,-PI,PI)
 var steps := maxi(1,ceili(absf(delta_angle)/0.12))
 for i in range(1,steps+1):
  var candidate := rotation.y+delta_angle*float(i)/float(steps)
  if not _stance_envelope_clear(Stance.envelope(_stance_pose),candidate): return
  if stance=="prone" and not _stance_support_safe(float(_stance_pose.length),Vector3.ZERO,candidate): return
 rotation.y = heading


func request_sprint(enabled: bool) -> bool:
 if embarked or brain.hp<=0.0 or (enabled and stance!="stand"): return false
 sprinting = enabled
 return true


func guard_stance_motion(movement: Vector3, speed: float, delta: float) -> Vector3:
 if stance!="prone" or movement.length_squared()<0.0001: return movement
 _stance_support_clock -= maxf(0.0,delta)
 if _stance_support_clock<=0.0:
  _stance_support_clock = 0.12
  _stance_support_ok = _stance_support_safe(float(_stance_pose.length),movement*speed*0.2)
 return movement if _stance_support_ok else Vector3.ZERO

func view_height() -> float:
 return float(_stance_pose.eye)+lerpf(0.45,0.20,float(_stance_pose.prone))
