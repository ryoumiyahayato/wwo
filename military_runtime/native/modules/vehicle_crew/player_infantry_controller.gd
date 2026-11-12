extends Node
## Input ownership of the existing commander; never creates a replacement actor.
signal control_changed(on_foot: bool)
signal commander_died(person_id: String)
var main: Node3D
var person_id := ""
var _actor: Node3D
var _move := Vector2.ZERO
var _aim := Vector3.ZERO
var _firing := false
var _death_reported := ""

func setup(owner_main: Node3D) -> void:
 main = owner_main
 process_physics_priority = -100
 process_priority = -100
 refresh_control()

func _physics_process(_delta: float) -> void:
 refresh_control()

func actor() -> Node3D:
 return _actor if is_instance_valid(_actor) else null

func active() -> bool:
 return is_instance_valid(_actor) and not _actor.embarked and float(_actor.person_state.get("hp",0.0))>0.0 and bool(_actor.person_state.get("alive",false))

func refresh_control() -> void:
 if not is_instance_valid(main) or bool(main.get("garage")) or str(main.get("game_mode"))!="skirmish":
  release_control()
  _death_reported = ""
  return
 var crew = main.get("crew_host")
 var ai = main.get("ai_host")
 if not is_instance_valid(crew) or not is_instance_valid(ai):
  release_control()
  return
 var commander: String = crew.commander_person_id()
 if commander.is_empty():
  release_control()
  return
 var person: Dictionary = crew.registry.person_ref(commander)
 if not bool(person.get("alive",false)) or float(person.get("hp",0.0))<=0.0:
  release_control()
  if _death_reported!=commander:
   _death_reported = commander
   commander_died.emit(commander)
  return
 var candidate = ai.actors.get(commander)
 if person.get("location",{}).get("kind","")!="world" or not is_instance_valid(candidate) or candidate.embarked:
  release_control()
  return
 if candidate==_actor and person_id==commander: return
 release_control()
 _actor = candidate
 _death_reported = ""
 person_id = commander
 clear_input()
 _aim = _actor.global_position-_actor.global_basis.z*100.0+Vector3.UP*1.1
 _actor.set_meta("player_controlled",true)
 _actor.set_meta("player_controller",self)
 if crew.pending_returns.has(person_id): crew._finish_return(person_id,{"ok":false,"reason":"player_controlled"},false)
 if _actor.has_meta("crew_return_order"): _actor.remove_meta("crew_return_order")
 _actor.brain.order.clear()
 if _actor.has_meta("construction_order"): _actor.remove_meta("construction_order")
 _actor.velocity = Vector3.ZERO
 control_changed.emit(true)

func release_control() -> void:
 var had_actor := is_instance_valid(_actor)
 if had_actor:
  _actor.set_meta("player_controlled",false)
  if _actor.has_meta("player_controller"): _actor.remove_meta("player_controller")
  _actor.velocity = Vector3.ZERO
 _actor = null
 person_id = ""
 clear_input()
 if had_actor: control_changed.emit(false)

func clear_input() -> void:
 _move = Vector2.ZERO
 _firing = false
 if is_instance_valid(_actor) and _actor.has_method("request_sprint"): _actor.request_sprint(false)

## Main transforms keyboard/touch motion to world X/Z, and supplies camera aim.
func set_input(move: Vector2, aim_point: Vector3, firing: bool) -> void:
 if not active():
  clear_input()
  return
 _move = move.limit_length(1.0) if move.is_finite() else Vector2.ZERO
 if aim_point.is_finite(): _aim = aim_point
 _firing = firing

func request_board() -> Dictionary:
 if not active(): return {"ok":false,"reason":"actor_unavailable"}
 clear_input()
 _actor._sync_person_state()
 var result: Dictionary = main.crew_host.embark_person(person_id)
 main.crew_host.report_transfer(result,"车长已返回原车 · 武器与伤情保留")
 refresh_control()
 return result

func weapon_label() -> String:
 if not active() or _actor.weapon.is_empty(): return "徒手"
 return {"at":"火箭筒","rocket":"火箭筒","grenade":"榴弹","hmg":"重机枪","smg":"冲锋枪","sniper":"狙击枪","rifle":"步枪","pistol":"手枪"}.get(_actor.weapon,_actor.weapon)

func request_pickup() -> Dictionary:
 if not active(): return {"ok":false,"reason":"车长当前不能拾取"}
 _firing = false
 var result: Dictionary = main.ai_host.player_pickup_weapon(_actor)
 var text: String = "已拾取%s · 弹药 %d / %d"%[weapon_label(),int(result.get("ammo",0)),int(result.get("reserve",0))] if result.ok else str(result.reason)
 main.message = text
 var controls = main.get("battle_controls")
 if is_instance_valid(controls):
  controls.fire_held = false
  controls.fire_pointer = -99
  controls.show_notice(text)
 return result

func can_reload() -> bool:
 if not active(): return false
 var brain = _actor.brain
 return brain.state!="reload" and brain.ammo<brain.magazine_size and brain.reserve_ammo>0 and not _actor.weapon.is_empty()

func request_reload() -> bool:
 if not can_reload(): return false
 _actor.brain._set_state("reload")
 return true

func physics_tick(body: CharacterBody3D, delta: float) -> void:
 if body!=_actor or not bool(body.get_meta("player_controlled",false)): return
 var brain = body.brain
 var dt := clampf(delta,0.0,0.25)
 if not active() or (main.has_method("is_battle_active") and not main.is_battle_active()):
  clear_input()
  body.velocity = Vector3.ZERO
  return
 brain.cooldown = maxf(0.0,brain.cooldown-dt)
 brain.state_time += dt
 if brain.state=="reload" and brain.state_time>=2.1:
  var transferred := mini(maxi(0,brain.magazine_size-brain.ammo),brain.reserve_ammo)
  brain.ammo += transferred
  brain.reserve_ammo -= transferred
  brain._set_state("idle")
 var speed: float = body.locomotion_speed() if body.has_method("locomotion_speed") else body.move_speed
 var parts: Dictionary = body.person_state.get("parts",{})
 if parts.get("left_leg","healthy")=="disabled" and parts.get("right_leg","healthy")=="disabled": speed = 0.0
 else:
  for leg in ["left_leg","right_leg"]:
   if str(parts.get(leg,"healthy"))!="healthy": speed *= 0.6
 var movement := Vector3(_move.x,0.0,_move.y)
 if body.has_method("guard_stance_motion"): movement = body.guard_stance_motion(movement,speed,dt)
 body.velocity.x = movement.x*speed
 body.velocity.z = movement.z*speed
 body.velocity.y = -0.1 if body.is_on_floor() else body.velocity.y-body.gravity*dt
 body.move_and_slide()
 body.aim_visible_weapon(_aim)
 if _firing and not body.weapon.is_empty() and brain.state!="reload":
  if brain.ammo<=0: request_reload()
  elif brain.cooldown<=0.0:
   var previous: int = body.shot_sequence
   body._shoot("",_aim)
   if body.shot_sequence>previous:
    if is_instance_valid(main.battle_controls): main.battle_controls.record_shot("infantry",false)
    brain.ammo -= 1
    brain.cooldown = brain.shot_interval
    brain._set_state("fire")
 elif brain.state!="reload": brain._set_state("patrol" if _move.length_squared()>0.01 else "idle")
 body._sync_person_state()

func _exit_tree() -> void:
 release_control()


func stance_label() -> String:
 if not active() or not _actor.has_method("request_stance"): return "站立"
 return {"stand":"站立","crouch":"蹲姿","prone":"匍匐"}.get(_actor.stance,"站立")

func next_stance_label() -> String:
 if not active() or not _actor.has_method("request_stance"): return "蹲下"
 return {"stand":"蹲下","crouch":"趴下","prone":"起身"}.get(_actor.stance,"蹲下")

func cycle_stance() -> bool:
 if not active() or not _actor.has_method("request_stance"): return false
 return request_stance({"stand":"crouch","crouch":"prone","prone":"stand"}.get(_actor.stance,"stand"))

func request_stance(value: String) -> bool:
 if not active() or not _actor.has_method("request_stance"): return false
 var ok: bool = _actor.request_stance(value)
 _firing = false
 var controls = main.get("battle_controls")
 if is_instance_valid(controls):
  controls.fire_held = false
  controls.fire_pointer = -99
  controls.show_notice(stance_label() if ok else "周围或脚下空间不足，无法改变姿态")
 return ok

func toggle_sprint() -> bool:
 if not active() or not _actor.has_method("request_sprint"): return false
 var ok: bool = _actor.request_sprint(not _actor.sprinting)
 var controls = main.get("battle_controls")
 if is_instance_valid(controls): controls.show_notice(("跑步" if _actor.sprinting else "步行") if ok else "先起身再跑步")
 return ok
