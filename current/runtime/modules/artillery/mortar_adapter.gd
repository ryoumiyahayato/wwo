extends RefCounted
## Mounted-mortar adapter using the shared abstract game arc and live shell.
## All values are fictional game balance, never historical weapon performance.
## Entity inventory is serialized with construction state; vehicle ammunition is never used.
const Arc = preload("res://modules/artillery/arc_solution.gd")
const Shell = preload("res://modules/artillery/artillery_shell.gd")
const AmmoProfiles = preload("res://scripts/ammo_profiles.gd")
const MAX_ACTIVE := 8
const RELOAD_SECONDS := 5.0
const SLEW_RADIANS_PER_SECOND := PI * 50.0 / 180.0
const MIN_PITCH := PI / 6.0
const MAX_PITCH := PI * 80.0 / 180.0
var initial_rounds := 12
var settled: Dictionary = {}

func _view(muzzle: Node3D) -> Node3D:
 var node: Node = muzzle.get_parent() if is_instance_valid(muzzle) else null
 while is_instance_valid(node):
  if node is Node3D and node.has_method("aim_at"): return node
  node = node.get_parent()
 return null

func _state(main, muzzle: Node3D) -> Dictionary:
 if not is_instance_valid(main.construction_host) or not is_instance_valid(muzzle): return {}
 if not muzzle.is_inside_tree() or main.weapon_override != muzzle: return {}
 var host = main.construction_host
 var id: String = host.model.occupied
 if not host.model.structures.has(id) or not host.views.has(id): return {}
 var state: Dictionary = host.model.structures[id]
 if state.get("preset", "") != "mortar" or state.get("state", "") != "occupied": return {}
 var view: Node3D = host.views[id]
 if not is_instance_valid(view) or view.muzzle != muzzle: return {}
 return state

func _ensure_inventory(state: Dictionary) -> void:
 if not state.has("mortar_rounds"):
  state["mortar_rounds"] = maxi(0, int(state.get("mortar_initial_rounds", initial_rounds)))
 if not state.has("mortar_reload_remaining"): state["mortar_reload_remaining"] = 0.0

func status(main) -> Dictionary:
 var state := _state(main, main.weapon_override)
 if state.is_empty(): return {"available": false, "rounds": 0, "remaining": 0.0}
 _ensure_inventory(state)
 return {"available": true, "rounds": int(state.mortar_rounds), "remaining": float(state.mortar_reload_remaining), "construction_id": str(state.id)}

func tick(main, delta: float) -> void:
 if delta <= 0.0 or not is_finite(delta) or main.garage or main.battle_finished: return
 if not is_instance_valid(main.construction_host): return
 for state in main.construction_host.model.structures.values():
  if state.get("preset", "") != "mortar" or not state.has("mortar_reload_remaining"): continue
  state.mortar_reload_remaining = maxf(0.0, float(state.mortar_reload_remaining) - delta)
 var current := _state(main, main.weapon_override)
 if not current.is_empty():
  _ensure_inventory(current)
  main.reload_remaining = float(current.mortar_reload_remaining)

func exclusions(main, muzzle: Node3D) -> Array[RID]:
 var items: Array[RID] = []
 var roots: Array[Node] = []
 if is_instance_valid(main.hero): roots.append(main.hero)
 var view := _view(muzzle)
 if is_instance_valid(view): roots.append(view)
 for owner in roots:
  if owner is CollisionObject3D: items.append(owner.get_rid())
  for body in owner.find_children("*", "CollisionObject3D", true, false):
   var rid: RID = body.get_rid()
   if not items.has(rid): items.append(rid)
 return items

func _tube(group: Node3D) -> Node3D:
 # The existing procedural view has no tube name. Identify its unique tall box,
 # then keep the visible tube and its attached collision body together.
 for child in group.get_children():
  if not child is Node3D: continue
  for mesh in child.get_children():
   if mesh is MeshInstance3D and mesh.mesh is BoxMesh:
    var size: Vector3 = mesh.mesh.size
    if size.y > size.x * 2.0 and size.y > size.z * 2.0: return child
 return null

func aim(main, point: Vector3, pitch: float = Arc.PREFERRED_PITCH, delta: float = 1.0 / 60.0) -> Dictionary:
 var muzzle: Node3D = main.weapon_override
 if _state(main, muzzle).is_empty() or not point.is_finite(): return {"valid": false}
 if not is_finite(pitch) or not is_finite(delta) or delta < 0.0: return {"valid": false}
 var view := _view(muzzle)
 var group: Node3D = view.weapon_group if is_instance_valid(view) else null
 if not is_instance_valid(group): return {"valid": false}
 var applied_pitch := clampf(pitch, MIN_PITCH, MAX_PITCH)
 var solution: Dictionary = Arc.solve(muzzle.global_position, point, applied_pitch)
 if not bool(solution.valid):
  main.aim_limited = true; main.aim_limit_reason = "迫击炮目标超出游戏曲射范围"
  return solution
 # Solve in world space, then transform its actual launch direction into the
 # tilted mount frame. A flat target projection would drift sideways on slopes.
 var local_direction: Vector3 = group.get_parent().global_basis.inverse() * solution.direction
 var desired_yaw := atan2(-local_direction.x, -local_direction.z)
 # Bound pathological frame deltas; targeting never owns camera or body movement.
 var step := SLEW_RADIANS_PER_SECOND * minf(delta, 0.1)
 group.rotation.y = rotate_toward(group.rotation.y, desired_yaw, step)
 var barrel_direction: Vector3 = group.global_basis.inverse() * solution.direction
 var raw_local_pitch := atan2(barrel_direction.y, Vector2(barrel_direction.x, barrel_direction.z).length())
 var desired_local_pitch := clampf(raw_local_pitch, MIN_PITCH, MAX_PITCH)
 muzzle.rotation.x = move_toward(muzzle.rotation.x, desired_local_pitch, step)
 var tube := _tube(group)
 if is_instance_valid(tube):
  tube.rotation.x = muzzle.rotation.x - PI / 2.0
  var length := 1.1
  for mesh in tube.get_children():
   if mesh is MeshInstance3D and mesh.mesh is BoxMesh: length = mesh.mesh.size.y; break
  muzzle.position = tube.position + tube.basis.y.normalized() * (length * 0.5 + 0.04)
 # Re-solve at the physical muzzle after its small slew displacement, using the
 # same shared solver rather than copying or approximating its range equation.
 solution = Arc.solve(muzzle.global_position, point, applied_pitch)
 main.artillery_launch_speed = float(solution.speed)
 muzzle.set_meta("mortar_launch_speed", float(solution.speed))
 var aligned: bool = (-muzzle.global_basis.z.normalized()).dot(solution.direction) > 0.9995
 solution["aligned"] = aligned
 var limited := not is_equal_approx(applied_pitch, pitch) or not is_equal_approx(raw_local_pitch, desired_local_pitch)
 main.aim_limited = not bool(solution.valid) or limited
 main.aim_limit_reason = "迫击炮已到游戏仰角限位" if limited else "迫击炮目标超出游戏曲射范围" if not bool(solution.valid) else ""
 solution["limited"] = limited
 return solution

func _deny(main, reason: String, text: String) -> Dictionary:
 main.message = text
 main.refresh_hud()
 return {"ok": false, "reason": reason}

func fire(main, muzzle: Node3D) -> Dictionary:
 if main.garage or main.battle_finished or not main.player_can_fire(): return {"ok": false, "reason": "actor_unavailable"}
 var state := _state(main, muzzle)
 if state.is_empty(): return _deny(main, "muzzle_unavailable", "迫击炮炮口或占用状态不可用")
 _ensure_inventory(state)
 if float(state.mortar_reload_remaining) > 0.0: return _deny(main, "reloading", "迫击炮装填中")
 if int(state.mortar_rounds) <= 0: return _deny(main, "empty", "这具迫击炮弹药已耗尽")
 if main.get_tree().get_nodes_in_group("artillery_projectile").size() >= MAX_ACTIVE: return _deny(main, "projectile_limit", "空中炮弹达到游戏上限，请稍候")
 if not is_instance_valid(main.stage): return {"ok": false, "reason": "stage_unavailable"}
 var speed: float = float(muzzle.get_meta("mortar_launch_speed", Arc.MIN_SPEED))
 var shell = Shell.new()
 shell.visual_kind = "mortar"
 main.stage.add_child(shell)
 if not shell.setup(muzzle.global_transform, speed, exclusions(main, muzzle), Callable(main, "effect_point_visible"), Callable(main, "indirect_surface_height")):
  shell.queue_free()
  return _deny(main, "invalid_launch", "迫击炮发射配置无效，未消耗炮弹")
 # Synchronous commit, after launch validation: exactly one entity round and one
 # reload cycle. No vehicle_ammo commit, no host-button second consumption.
 state.mortar_rounds = int(state.mortar_rounds) - 1
 state.mortar_reload_remaining = RELOAD_SECONDS
 main.reload_remaining = RELOAD_SECONDS
 main.shot_sequence += 1
 var shot: int = main.shot_sequence
 var generation: int = main.stage_generation
 var visual_weapon: Dictionary = state.get("visual_weapon", {"weapon_id":"game_mortar","mount_id":str(state.id)}).duplicate(true)
 shell.impacted.connect(_impact.bind(main, generation, shot, visual_weapon))
 shell.expired.connect(_expired.bind(main, generation, shot))
 main.last_muzzle = muzzle.global_position
 main.shot_audit.append({"id": shot, "accepted": true, "weapon": "mortar", "ammo": 1, "ammo_commit": -1, "construction_id": str(state.id), "ammo_remaining": int(state.mortar_rounds), "origin": muzzle.global_position, "direction": -muzzle.global_basis.z.normalized(), "flight_state": "flying"})
 if main.shot_audit.size() > 128: main.shot_audit.pop_front()
 main.spawn_combat_vfx("muzzle_pulse", muzzle.global_position, -muzzle.global_basis.z, visual_weapon)
 if is_instance_valid(main.battle_controls): main.battle_controls.record_shot("mortar", false)
 main.message = "迫击炮弹飞行中 · 剩余 %d 发 · 落点由实际碰撞决定" % int(state.mortar_rounds)
 main.refresh_hud()
 return {"ok": true, "shot": shot, "shell": shell, "rounds": int(state.mortar_rounds)}

func _finish_audit(main, shot: int, phase: String, event: Dictionary) -> void:
 for row in main.shot_audit:
  if int(row.get("id", -1)) != shot: continue
  row["flight_state"] = phase
  row["flight_seconds"] = float(event.get("flight_seconds", 0.0))
  row["impact"] = event.position
  break

func _expired(event: Dictionary, main, generation: int, shot: int) -> void:
 if not is_instance_valid(main) or generation != main.stage_generation: return
 _finish_audit(main, shot, "expired", event)

func _impact(event: Dictionary, main, generation: int, shot: int, visual_weapon: Dictionary = {}) -> void:
 if not is_instance_valid(main) or main.garage or main.battle_finished or generation != main.stage_generation: return
 var key := str(generation) + ":" + str(shot)
 if settled.has(key): return
 settled[key] = true
 if settled.size() > 128: settled.erase(settled.keys()[0])
 _finish_audit(main, shot, "impacted", event)
 main.last_muzzle = event.origin
 main.last_impact = event.position
 # Existing mortar damage calls, unchanged in meaning, now only at real contact.
 main.explode_terrain(main.last_impact, AmmoProfiles.explosive_mass("mortar"))
 if main.effect_point_visible(main.last_impact + Vector3.UP * 0.8):
  main.spawn_combat_vfx("impact_explosion", main.last_impact, Vector3.FORWARD, visual_weapon)
  main.spawn_combat_vfx("smoke_aftershot", main.last_impact + Vector3.UP * 0.8)
 if main.game_mode == "skirmish" and is_instance_valid(main.ai_host): main.ai_host.apply_player_blast(main.last_impact)
 if is_instance_valid(main.target): main.combat.high_explosive("infantry" if main.target_infantry else "armor", main.last_impact.distance_to(main.target.position + Vector3.UP), main.blast_occluded(main.last_impact))
 main.message = "迫击炮弹已在实际落点爆炸" if main.effect_point_visible(main.last_impact) else "迫击炮弹已落地，远处结果无法确认"
 main.update_person_visuals()
 main.refresh_hud()

func aim_manual(main,point:Vector3,delta:float)->void:
 var muzzle:Node3D=main.weapon_override
 if _state(main,muzzle).is_empty() or not point.is_finite() or not is_finite(delta) or delta<0:return
 var direction:Vector3=(point-muzzle.global_position).normalized()
 if direction.length_squared()<.5:return
 var view:=_view(muzzle)
 var group:Node3D=view.weapon_group
 var local_direction:Vector3=group.get_parent().global_basis.inverse()*direction
 var yaw:=atan2(-local_direction.x,-local_direction.z)
 var step:=SLEW_RADIANS_PER_SECOND*minf(delta,.1)
 group.rotation.y=rotate_toward(group.rotation.y,yaw,step)
 var local_barrel:Vector3=group.global_basis.inverse()*direction
 var requested:=atan2(local_barrel.y,Vector2(local_barrel.x,local_barrel.z).length())
 var pitch:=clampf(requested,MIN_PITCH,MAX_PITCH)
 muzzle.rotation.x=move_toward(muzzle.rotation.x,pitch,step)
 var tube:=_tube(group)
 if is_instance_valid(tube):
  tube.rotation.x=muzzle.rotation.x-PI/2.0
  var length:=1.1
  for mesh in tube.get_children():
   if mesh is MeshInstance3D and mesh.mesh is BoxMesh:length=mesh.mesh.size.y;break
  muzzle.position=tube.position+tube.basis.y.normalized()*(length*.5+.04)
 main.aim_limited=not is_equal_approx(requested,pitch)
 main.aim_limit_reason="迫击炮已到游戏仰角限位" if main.aim_limited else ""
 # Preserve the current game launch setting; hand aiming does not solve speed.
 muzzle.set_meta("mortar_launch_speed",main.artillery_launch_speed)
