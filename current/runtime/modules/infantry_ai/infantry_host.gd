extends Node
## Reusable demo/WWO boundary. No singleton or WWO code dependencies.
const AmmoProfiles = preload("res://scripts/ammo_profiles.gd")
const Drops = preload("res://modules/infantry_ai/weapon_drops.gd")
var arsenal = Drops.new()
var weapon_visuals: Dictionary = {}
var fortifications: Dictionary = {}
var _loot_clock := 0.0
const Actor = preload("res://modules/infantry_ai/infantry_actor.gd")
const Combat = preload("res://scripts/combat.gd")
const Visibility = preload("res://scripts/battle_ai_presets.gd")
signal event_emitted(event: Dictionary)
signal player_hit(event: Dictionary)
var main: Node3D
var actors: Dictionary = {}
var persons: Dictionary = {}
var player_actor: Node3D
var player_id := "player"
var player_team := "friendly"
var rules = Combat.new()
var events: Array = []
var optimization_enabled := true
var _budget_frame := -1
var _frame_rays := 0
var _frame_plans := 0
var _perception_updates := 0
var _perception_rays := 0
var _path_plans := 0
var _peak_frame_rays := 0
var _peak_frame_plans := 0
var _spawn_sequence := 0
var team_contacts: Dictionary = {}
var _loot_reach_cache: Dictionary = {}
var _loot_choice_cache: Dictionary = {}
var character_detail_lod: Node

func _refresh_budget() -> void:
 var frame := Engine.get_physics_frames()
 if frame!=_budget_frame:
  _budget_frame=frame
  _frame_rays=0
  _frame_plans=0
var _perception_next:Dictionary={}
func perception_due(slot: int) -> bool:
 if not optimization_enabled:return true
 var due:float=_perception_next.get(slot,(slot%12)*(.2/12.0))
 if _loot_clock+0.000001<due:return false
 _perception_next[slot]=due+.2*(floori(maxf(0.0,_loot_clock-due)/.2)+1)
 return true
func consume_perception_ray() -> bool:
 _refresh_budget()
 if optimization_enabled and _frame_rays>=ceili(64.0*60.0/Engine.physics_ticks_per_second): return false
 _frame_rays+=1
 _perception_rays+=1
 _peak_frame_rays=maxi(_peak_frame_rays,_frame_rays)
 return true
func request_path_plan() -> bool:
 _refresh_budget()
 if optimization_enabled and _frame_plans>=maxi(1,ceili(60.0/Engine.physics_ticks_per_second)): return false
 _frame_plans+=1
 _path_plans+=1
 _peak_frame_plans=maxi(_peak_frame_plans,_frame_plans)
 return true
func performance_snapshot() -> Dictionary:
 return {"optimization_enabled":optimization_enabled,"perception_updates":_perception_updates,"perception_rays":_perception_rays,"path_plans":_path_plans,"peak_perception_rays_per_frame":_peak_frame_rays,"peak_path_plans_per_frame":_peak_frame_plans}
func reset_performance_counters() -> void:
 _perception_updates=0
 _perception_rays=0
 _path_plans=0
 _peak_frame_rays=0
 _peak_frame_plans=0
 _budget_frame=-1
func armor_candidates() -> Array:
 var armor = main.get("armor_host") if is_instance_valid(main) else null
 return armor.candidates() if is_instance_valid(armor) and armor.has_method("candidates") else []
func report_contact(team: String, observation: Dictionary) -> void:
 if not bool(observation.get("visible",false)) or not bool(observation.get("alive",false)) or str(observation.get("team_id",team))==team: return
 if not team_contacts.has(team): team_contacts[team]={}
 var report: Dictionary=observation.duplicate()
 report.erase("node")
 report.erase("exclude")
 report.visible=false
 report.reported=true
 report.expires=_loot_clock+Visibility.MEMORY_TTL
 team_contacts[team][str(report.actor_id)]=report
func shared_contacts(team: String) -> Array:
 var result: Array=[]
 var records: Dictionary=team_contacts.get(team,{})
 for id in records.keys():
  if float(records[id].expires)<=_loot_clock:
   records.erase(id)
   continue
  var report: Dictionary=records[id].duplicate()
  report.remaining=float(report.expires)-_loot_clock
  result.append(report)
 return result


func setup(owner_main: Node3D) -> void:
 main = owner_main
 var near_path := "res://assets/user_derived/models/user_rifleman_near.glb"
 var view_camera = main.get("camera")
 if view_camera is Camera3D and ResourceLoader.exists(near_path):
  character_detail_lod = load("res://modules/infantry_ai/character_detail_lod.gd").new()
  add_child(character_detail_lod)
  character_detail_lod.setup(self,view_camera,load(near_path))

func register_player(actor: Node3D, id := "player", team := "friendly") -> void:
 player_actor = actor
 player_id = id
 player_team = team
 if is_instance_valid(actor): actor.set_meta("actor_id",id)

func clear() -> void:
 if is_instance_valid(character_detail_lod): character_detail_lod.restore_all()
 for visual in weapon_visuals.values():
  if is_instance_valid(visual) and visual.get_parent()==main.stage: visual.queue_free()
 weapon_visuals.clear()
 fortifications.clear()
 arsenal = Drops.new()
 _loot_clock = 0.0
 _perception_next.clear()
 _spawn_sequence=0
 team_contacts.clear()
 _loot_reach_cache.clear()
 _loot_choice_cache.clear()
 reset_performance_counters()
 for actor in actors.values():
  if is_instance_valid(actor): actor.queue_free()
 actors.clear()
 persons.clear()

func spawn_actor(id: String, team: String, position: Vector3, patrol: Array = [], cover: Array = [], model_path := "res://assets/user_derived/models/user_rifleman_armed.glb") -> CharacterBody3D:
 if actors.has(id): return actors[id]
 var actor := CharacterBody3D.new()
 actor.set_script(Actor)
 actor.name = id
 if has_method("is_identified"):actor.visible=false # No first-frame observation leak.
 actor.configure(id,team,self)
 actor.perception_slot=_spawn_sequence
 _spawn_sequence+=1
 actor.brain.patrol_points = patrol
 actor.brain.cover_points = cover
 main.stage.add_child(actor)
 actor.global_position = position
 if ResourceLoader.exists(model_path):
  var visual = load(model_path).instantiate()
  actor.add_child(visual)
  visual.name = "InfantryVisual"
  var rifle = visual.find_child("Rifle",true,false)
  var muzzle_node = visual.find_child("Muzzle",true,false)
  if rifle is Node3D and muzzle_node is Node3D: actor.bind_weapon_geometry(rifle,muzzle_node)
 actors[id] = actor
 persons[id] = rules.person()
 persons[id]["person_id"] = id
 persons[id]["ammo"] = actor.brain.ammo
 actor.bind_person_state(persons[id])
 return actor

func infantry_candidates(_observer_id: String) -> Array:
 var result: Array = []
 for id in actors:
  var actor = actors[id]
  if is_instance_valid(actor) and not actor.embarked:
   result.append({"actor_id":id,"team_id":actor.brain.team_id,"actor_kind":"infantry","position":actor.global_position+Vector3.UP*actor.aim_height,"alive":actor.brain.hp>0.0})
 for id in fortifications:
  var fort: Dictionary = fortifications[id]
  if is_instance_valid(fort.node) and float(fort.hp)>0.0:
   result.append({"actor_id":id,"team_id":fort.team_id,"actor_kind":"fortification","position":fort.node.global_position,"alive":true})
 if is_instance_valid(player_actor):
  result.append({"actor_id":player_id,"team_id":player_team,"actor_kind":"vehicle" if int(main.get("unit"))!=2 else "infantry","position":player_actor.global_position+Vector3.UP*1.1,"alive":true})
 result.append_array(armor_candidates())
 return result

func _smoke_data() -> Dictionary:
 var node = main.get("smoke_root") if is_instance_valid(main) else null
 if not is_instance_valid(node): return {"center":Vector3.ZERO,"radius":0.0,"active":false}
 return {"center":node.obscuration_center() if node.has_method("obscuration_center") else node.global_position+Vector3.UP*2.6,"radius":node.obscuration_radius() if node.has_method("obscuration_radius") else 6.5,"active":main.combat.smoke_remaining>0.0}

func infantry_visibility(observer_id: String, target_id: String) -> float:
 if not actors.has(observer_id) or not is_instance_valid(actors[observer_id]): return 0.0
 var observer=actors[observer_id]
 var subject: Node3D=player_actor if target_id==player_id else actors.get(target_id)
 if fortifications.has(target_id): subject=fortifications[target_id].node
 var end := Vector3.ZERO
 var found := false
 if is_instance_valid(subject):
  if actors.has(target_id) and (subject.embarked or subject.brain.hp<=0.0): return 0.0
  end=subject.global_position+(Vector3.ZERO if fortifications.has(target_id) else Vector3.UP*1.1)
  found=true
 else:
  for candidate in armor_candidates():
   if str(candidate.actor_id)==target_id and bool(candidate.get("alive",false)):
    end=candidate.position
    found=true
    break
 if not found: return 0.0
 var smoke:=_smoke_data()
 return 1.0 if Visibility.reason(observer.global_position+Vector3.UP*observer.aim_height,end,["clear","rain","fog"][clampi(int(main.weather_index),0,2)],smoke.center,smoke.active,false,float(smoke.radius))=="visible" else 0.0

func minimap_visible_enemy_ids() -> Array[String]:
 var result: Array[String]=[]
 if not is_instance_valid(main) or not main.is_inside_tree(): return result
 var observers: Array=[]
 var occupied := false
 var targets: Array=[]
 for actor in actors.values():
  if not is_instance_valid(actor) or actor.brain.hp<=0.0: continue
  if actor.brain.team_id==player_team:
   if actor.embarked:
    if actor.has_meta("crew_role"): occupied=true
   else: observers.append({"position":actor.global_position+Vector3.UP*actor.aim_height,"exclude":[actor.get_rid()]})
  elif not actor.embarked: targets.append({"actor_id":actor.brain.actor_id,"position":actor.global_position+Vector3.UP*actor.aim_height})
 if occupied and is_instance_valid(player_actor):
  var excluded: Array[RID]=[]
  _minimap_collect_rids(player_actor,excluded)
  var crew=main.get("crew_host")
  var multiplier: float=float(crew.observation_multiplier()) if is_instance_valid(crew) and crew.has_method("observation_multiplier") else 1.0
  observers.append({"position":player_actor.global_position+Vector3.UP*1.6,"exclude":excluded,"sight_multiplier":multiplier})
 for vehicle in armor_candidates():
  if not bool(vehicle.get("alive",false)): continue
  if str(vehicle.team_id)==player_team:
   var excluded: Array[RID]=[]
   if is_instance_valid(vehicle.get("node")): _minimap_collect_rids(vehicle.node,excluded)
   else: excluded.assign(vehicle.get("exclude",[]))
   observers.append({"position":vehicle.position,"exclude":excluded})
  else: targets.append(vehicle)
 var smoke:=_smoke_data()
 var weather: String=["clear","rain","fog"][clampi(int(main.weather_index),0,2)]
 for target in targets:
  for observer in observers:
   if observer.position.distance_to(target.position)>float(Visibility.VISION.get(weather,85.0))*float(observer.get("sight_multiplier",1.0)): continue
   if Visibility.reason(observer.position,target.position,weather,smoke.center,smoke.active,false,float(smoke.radius))!="visible": continue
   var excluded: Array[RID]=[]
   excluded.assign(observer.exclude)
   var query:=PhysicsRayQueryParameters3D.create(observer.position,target.position,1|8|16|32|128,excluded)
   var hit:=main.get_world_3d().direct_space_state.intersect_ray(query)
   if not hit.is_empty() and _contact_actor_id(hit.collider)==str(target.actor_id):
    result.append(str(target.actor_id))
    break
 result.sort()
 return result
func _contact_actor_id(collider: Object) -> String:
 var node:=collider as Node
 while is_instance_valid(node):
  if node.has_meta("actor_id"): return str(node.get_meta("actor_id"))
  node=node.get_parent()
 return ""

func _minimap_collect_rids(node: Node, output: Array[RID]) -> void:
 if node is CollisionObject3D: output.append(node.get_rid())
 for child in node.get_children(): _minimap_collect_rids(child,output)

func infantry_apply_hit(event: Dictionary) -> void:
 var id := str(event.get("hit_actor_id",""))
 if fortifications.has(id):
  damage_fortification(id,str(event.get("weapon","")),str(event.get("team_id","")))
  return
 if id == player_id:
  if str(event.get("team_id","")) != player_team:
   player_hit.emit(event.duplicate(true))
   if main.has_method("apply_ai_hit"): main.apply_ai_hit(event)
  return
 if not actors.has(id):
  var armor=main.get("armor_host") if is_instance_valid(main) else null
  if is_instance_valid(armor) and armor.has_method("receive_hit"): armor.receive_hit(event)
  return
 if not is_instance_valid(actors[id]): return
 var actor = actors[id]
 if actor.embarked:
  infantry_event({"kind":"embarked_hit_rejected","actor_id":id})
  return
 if actor.brain.team_id == str(event.get("team_id","")): return
 var part: String = actor.body_part_at(event.position)
 var result: Dictionary = rules.hit_person(persons[id],part)
 sync_actor_person(id)
 infantry_event({"kind":"infantry_hit","actor_id":id,"source_actor_id":str(event.get("actor_id","player")),"result":result})

func apply_actor_damage(id: String, amount: float, source_id := "player") -> Dictionary:
 if not actors.has(id) or not is_instance_valid(actors[id]): return {"kind":"unknown_actor"}
 var actor = actors[id]
 if actor.embarked: return {"kind":"embarked_protected","damage":0.0}
 if actor.brain.hp <= 0.0: return {"kind":"inactive"}
 actor.receive_damage(amount)
 persons[id].hp = actor.brain.hp
 persons[id].alive = actor.brain.hp > 0.0
 persons[id].parts.torso = "injured" if actor.brain.hp>0.0 else "disabled"
 var event := {"kind":"infantry_damage","actor_id":id,"source_actor_id":source_id,"damage":amount,"hp":actor.brain.hp,"alive":actor.brain.hp>0.0}
 infantry_event(event)
 return event

func infantry_event(event: Dictionary) -> void:
 events.append(event.duplicate(true))
 if events.size() > 128: events.pop_front()
 event_emitted.emit(event)
 if event.kind == "shot":
  var munition: String = "anti_armor_rocket" if str(event.get("weapon","")) in ["at","rocket"] else ("grenade" if str(event.get("weapon","")) in ["grenade","grenade_launcher","heavy_grenade"] else "rifle")
  var mass: float = AmmoProfiles.explosive_mass(munition)
  if mass>0.0 and not event.get("hit",{}).is_empty() and main.has_method("explode_terrain"):
   main.explode_terrain(event.position,mass)
  suppress_near_segment(event.origin,event.position,str(event.get("team_id","")),str(event.get("weapon","rifle")))
 if event.kind == "shot" and main.has_method("spawn_ai_shot"):
  main.spawn_ai_shot(event.origin,event.position,event.weapon,not event.get("hit",{}).is_empty())
 # A build event only requests the previously approved preset at the arrived site.
 # Host validates resources/site and advances construction; no automatic terrain mutation here.
 if event.kind == "build_requested" and main.has_method("apply_ai_build_request"):
  main.apply_ai_build_request(event)

func drain_events() -> Array:
 var result := events.duplicate(true)
 events.clear()
 return result

func snapshot() -> Dictionary:
 var data := {}
 for id in actors:
  if is_instance_valid(actors[id]): data[id] = actors[id].snapshot()
 return {"version":1,"actors":data}

func sync_actor_person(id: String) -> void:
 if not actors.has(id) or not is_instance_valid(actors[id]): return
 var actor = actors[id]
 actor.brain.hp = float(persons[id].hp)
 actor.brain._set_state("disabled" if not bool(persons[id].alive) else "wounded")
 actor._sync_person_state()

func register_bound_crew(person_id: String, person_dict: Dictionary, position: Vector3, role: String = "") -> CharacterBody3D:
 var actor = spawn_actor(person_id,"blue",position,[],[])
 person_dict["person_id"] = person_id
 persons[person_id] = person_dict
 actor.bind_person_state(person_dict)
 actor.set_meta("crew_role",role)
 actor.set_embarked(true)
 return actor

func set_crew_embarked(person_id: String, value: bool, world_position: Vector3 = Vector3.ZERO) -> bool:
 if not actors.has(person_id) or not is_instance_valid(actors[person_id]): return false
 var actor = actors[person_id]
 if not value:
  # Authorized seat transition only. Registry validates clearance before calling.
  actor.global_position = world_position
  if actor.has_meta("crew_return_order"): actor.remove_meta("crew_return_order")
  _loot_choice_cache.erase(person_id)
  actor.brain.patrol_points = [world_position,world_position+Vector3(3,0,0)]
 actor.set_embarked(value)
 return true

func infantry_weapon_tick(actor, _delta: float) -> void:
 if actor.weapon_id.is_empty() and not actor.weapon.is_empty():
  actor.weapon_id = arsenal.create(actor.weapon,actor.brain.actor_id,actor.brain.ammo,actor.brain.reserve_ammo)
  if not actor.weapon_id.is_empty() and is_instance_valid(actor.weapon_pivot):
   weapon_visuals[actor.weapon_id] = actor.weapon_pivot
   actor.weapon_pivot.set_meta("held_transform",actor.weapon_pivot.transform)
 if not actor.weapon_id.is_empty():
  arsenal.sync_ammo(actor.weapon_id,actor.brain.ammo,actor.brain.reserve_ammo)
 if actor.brain.hp<=0.0 and not actor.weapon_id.is_empty(): infantry_drop_weapon(actor,"death")
 elif actor.brain.ammo+actor.brain.reserve_ammo<=0 and not actor.weapon_id.is_empty(): infantry_drop_weapon(actor,"empty")

func infantry_drop_weapon(actor, reason: String) -> void:
 var id: String = actor.weapon_id
 if id.is_empty(): return
 arsenal.sync_ammo(id,actor.brain.ammo,actor.brain.reserve_ammo)
 var point: Vector3 = actor.global_position
 if not arsenal.drop(id,actor.brain.actor_id,point,_loot_clock+3.0 if reason=="suppression" else _loot_clock): return
 var visual = weapon_visuals.get(id)
 if is_instance_valid(visual):
  visual.set_meta("held_transform",visual.transform)
  if is_instance_valid(actor.muzzle) and visual.is_ancestor_of(actor.muzzle):
   visual.set_meta("held_muzzle_path",visual.get_path_to(actor.muzzle))
  visual.reparent(main.stage,true)
  visual.global_position = point+Vector3.UP*0.16
  visual.rotation = Vector3(0,actor.rotation.y,PI/2.0)
  visual.visible = true
 actor.weapon_id = ""
 actor.weapon = ""
 actor.weapon_pivot = null
 actor.muzzle = null
 actor.brain.ammo = 0
 actor.brain.reserve_ammo = 0
 actor.loot_target = ""
 actor._sync_person_state()
 infantry_event({"kind":"weapon_dropped","actor_id":actor.brain.actor_id,"weapon_id":id,"reason":reason})

func loot_eligible(actor) -> bool:
 return is_instance_valid(actor) and not actor.embarked and actor.brain.hp>0.0 and not bool(actor.get_meta("player_controlled",false)) and not bool(actor.get_meta("construction_order",false)) and actor.brain.order.is_empty() and actor.get_meta("crew_return_order",{}).is_empty()

func _loot_reachable(actor, record: Dictionary) -> bool:
 var point: Vector3=record.position
 if absf(point.y-actor.global_position.y)>2.0 or float(actor.loot_ignored.get(record.id,0.0))>_loot_clock: return false
 var key: String=str(actor.brain.actor_id)+":"+str(record.id)
 var cached: Dictionary=_loot_reach_cache.get(key,{})
 if float(cached.get("until",0.0))>_loot_clock: return bool(cached.ok)
 var query:=PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*.65,point+Vector3.UP*.65,1|8|16|32,[actor.get_rid()])
 var reachable: bool=actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
 if not reachable:
  if not request_path_plan(): return false
  var route: Array=actor._route_planner.plan(actor,point)
  reachable=not route.is_empty() and route.back().distance_to(point)<2.5
 _loot_reach_cache[key]={"until":_loot_clock+.8,"ok":reachable}
 return reachable

func infantry_loot_command(actor, delta: float) -> Dictionary:
 if not loot_eligible(actor) or actor.pickup_cooldown>0.0: return {}
 var kind: String = actor.weapon if actor.brain.ammo+actor.brain.reserve_ammo>0 else ""
 var choice: Dictionary=_loot_choice_cache.get(actor.brain.actor_id,{})
 var id: String=str(choice.get("id",""))
 if float(choice.get("until",0.0))<=_loot_clock or (not id.is_empty() and (not arsenal.records.has(id) or not str(arsenal.records[id].owner).is_empty())):
  id=arsenal.choose(actor.global_position,kind,_loot_clock,func(record):return _loot_reachable(actor,record))
  _loot_choice_cache[actor.brain.actor_id]={"id":id,"until":_loot_clock+.35}
 if id.is_empty():
  actor.loot_target = ""
  return {}
 var record: Dictionary = arsenal.records[id]
 var distance: float = actor.global_position.distance_to(record.position)
 if actor.loot_target!=id:
  actor.loot_target = id
  actor.loot_stall_time = 0.0
  actor.loot_last_distance = distance
 elif distance<actor.loot_last_distance-0.1:
  actor.loot_last_distance = distance
  actor.loot_stall_time = 0.0
 else: actor.loot_stall_time += delta
 if actor.loot_stall_time>3.0:
  actor.loot_ignored[id] = _loot_clock+8.0
  actor.loot_target = ""
  return {}
 if distance<=1.25 and equip_ground_weapon(actor,id):
  return {}
 # A newly blocked handoff still needs the existing movement/path-planning branch.
 actor.brain._set_state("seek_weapon")
 return {"move":true,"destination":record.position,"fire":false,"target_id":"","build":false}

func _physics_process(delta: float) -> void:
 _loot_clock += delta

func suppress_near_segment(origin: Vector3, endpoint: Vector3, source_team: String, weapon_kind := "rifle") -> void:
 var strength := 0.24 if weapon_kind in ["mg","hmg","smg"] else 0.05
 for actor in actors.values():
  if not is_instance_valid(actor) or actor.embarked or actor.brain.hp<=0.0 or actor.brain.team_id==source_team: continue
  var point: Vector3=actor.global_position+Vector3.UP*.9
  var closest:=Geometry3D.get_closest_point_to_segment(point,origin,endpoint)
  if closest.distance_to(point)>1.8: continue
  var query:=PhysicsRayQueryParameters3D.create(closest,point,1|8|16|32)
  if actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): actor.receive_suppression(strength,"mg")

func apply_blast_suppression(origin: Vector3, source_team := "", radius := 14.0, strength := 0.85) -> void:
 for actor in actors.values():
  if not is_instance_valid(actor) or actor.embarked or actor.brain.hp<=0.0: continue
  var point: Vector3=actor.global_position+Vector3.UP*.9
  var distance: float=point.distance_to(origin)
  if distance>radius: continue
  var query:=PhysicsRayQueryParameters3D.create(origin+Vector3.UP*.2,point,1|8|16|32)
  if actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): actor.receive_suppression(strength*lerpf(1.0,.3,distance/maxf(radius,.01)),"blast")

func register_fortification(id: String, node: Node3D, team: String, health := 60.0, destroy_callback := Callable()) -> void:
 if id.is_empty() or not is_instance_valid(node) or team.is_empty(): return
 if fortifications.has(id): return
 node.set_meta("actor_id",id)
 node.set_meta("actor_kind","fortification")
 node.set_meta("kind","ai_fortification")
 node.set_meta("team_id",team)
 fortifications[id] = {"node":node,"team_id":team,"hp":health,"destroy":destroy_callback}

func damage_fortification(id: String, weapon_kind: String, source_team: String, ammo_kind := "") -> Dictionary:
 if not fortifications.has(id): return {"kind":"unknown_fortification"}
 var fort: Dictionary = fortifications[id]
 if float(fort.hp)<=0.0: return {"kind":"inactive"}
 # Friendly-fire behavior stays host-owned; AI acquisition never picks its own team.
 if weapon_kind not in ["at","rocket","grenade","grenade_launcher","heavy_grenade","cannon"] or ammo_kind=="smoke": return {"kind":"cover_stopped","damage":0.0}
 var amount := 35.0 if weapon_kind in ["at","rocket","cannon"] else 20.0
 fort.hp = maxf(0.0,float(fort.hp)-amount)
 var node = fort.node
 if is_instance_valid(node):
  node.set_meta("remaining_structure_hp",float(fort.hp))
  if float(fort.hp)<=0.0:
   if fort.destroy.is_valid(): fort.destroy.call(id)
   else: node.queue_free()
 infantry_event({"kind":"fortification_hit","actor_id":id,"source_team":source_team,"damage":amount,"destroyed":float(fort.hp)<=0.0})
 return {"kind":"fortification_hit","damage":amount,"destroyed":float(fort.hp)<=0.0}

func weapon_instance_kind(id: String, fallback: String) -> String:
 return str(arsenal.records.get(id,{}).get("category",fallback))


## One owner transition and the exact same visible model for AI and commander.
func equip_ground_weapon(actor, id: String) -> bool:
 # Planning caches are advisory: validate the physical handoff before either owner changes.
 if not is_instance_valid(actor) or actor.embarked or actor.brain.hp<=0.0 or not arsenal.records.has(id): return false
 var visual = weapon_visuals.get(id)
 if not is_instance_valid(visual) or not visual is Node3D or not visual.is_inside_tree(): return false
 var transferred_muzzle = visual.get_node_or_null(visual.get_meta("held_muzzle_path",NodePath("")))
 if not is_instance_valid(transferred_muzzle) or transferred_muzzle==visual:
  transferred_muzzle = visual.find_child("*Muzzle",true,false)
 if not is_instance_valid(transferred_muzzle) or not transferred_muzzle is Node3D or not visual.is_ancestor_of(transferred_muzzle): return false
 var point: Vector3 = arsenal.records[id].position
 var query := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*.65,point+Vector3.UP*.65,1|8|16|32,[actor.get_rid()])
 query.hit_from_inside = true
 if not actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return false
 var claimed: Dictionary = arsenal.claim(id,actor.brain.actor_id,actor.global_position,_loot_clock)
 if claimed.is_empty(): return false
 if not actor.weapon_id.is_empty(): infantry_drop_weapon(actor,"upgrade")
 actor.weapon_id = id
 actor.weapon = "at" if str(claimed.category)=="rocket" else str(claimed.category)
 var stats: Dictionary = Drops.STATS[claimed.category]
 actor.penetration = int(stats.penetration)
 actor.brain.magazine_size = int(stats.magazine)
 actor.brain.shot_interval = float(stats.interval)
 actor.brain.ammo = int(claimed.ammo)
 actor.brain.reserve_ammo = int(claimed.reserve)
 actor.brain.cooldown = 0.5
 actor.brain._set_state("idle")
 visual.reparent(actor,false)
 visual.transform = visual.get_meta("held_transform",Transform3D.IDENTITY)
 visual.visible = true
 actor.weapon_pivot = visual
 actor.muzzle = transferred_muzzle
 actor.pickup_cooldown = 1.0
 actor.loot_target = ""
 actor._sync_person_state()
 infantry_event({"kind":"weapon_picked_up","actor_id":actor.brain.actor_id,"weapon_id":id,"weapon":actor.weapon})
 return true

## Explicit player interaction never delegates movement to the AI loot planner.
func player_pickup_weapon(actor) -> Dictionary:
 if not is_instance_valid(actor) or actor.embarked or actor.brain.hp<=0.0 or not bool(actor.get_meta("player_controlled",false)):
  return {"ok":false,"reason":"车长当前不能拾取"}
 if actor.pickup_cooldown>0.0: return {"ok":false,"reason":"稍候再拾取"}
 var selected := ""
 var best_rank := 0
 var best_distance := INF
 var feedback := "附近没有可拾取武器（需靠近到1.4米内）"
 var current_rank: int = arsenal.rank(actor.weapon) if actor.brain.ammo+actor.brain.reserve_ammo>0 else 0
 for id in arsenal.records:
  var record: Dictionary = arsenal.records[id]
  var distance: float = actor.global_position.distance_to(record.position)
  if not str(record.owner).is_empty() or distance>1.4: continue
  if int(record.ammo)+int(record.reserve)<=0:
   feedback = "地面武器已无弹药，无法使用"
   continue
  if _loot_clock<float(record.blocked_until):
   feedback = "武器刚掉落，稍候再拾取"
   continue
  if not is_instance_valid(weapon_visuals.get(id)):
   feedback = "该武器实体不可用"
   continue
  var query := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*.65,record.position+Vector3.UP*.65,1|8|16|32,[actor.get_rid()])
  if not actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
   feedback = "武器被障碍挡住，请绕到旁边"
   continue
  var grade: int = arsenal.rank(str(record.category))
  if grade<=current_rank:
   feedback = "当前武器优先级不低于地面武器"
   continue
  if grade>best_rank or (grade==best_rank and distance<best_distance):
   selected = id
   best_rank = grade
   best_distance = distance
 if selected.is_empty(): return {"ok":false,"reason":feedback}
 if not equip_ground_weapon(actor,selected): return {"ok":false,"reason":"武器已被拾取或已不可用"}
 return {"ok":true,"weapon_id":selected,"category":arsenal.category(actor.weapon),"ammo":actor.brain.ammo,"reserve":actor.brain.reserve_ammo}
