extends SceneTree
const CrewHost = preload("res://modules/vehicle_crew/vehicle_crew_host.gd")
const InfantryHost = preload("res://modules/infantry_ai/infantry_host.gd")
const Controller = preload("res://modules/vehicle_crew/player_infantry_controller.gd")
const Combat = preload("res://scripts/combat.gd")
class TestMain extends Node3D:
 var hero := Node3D.new()
 var hud := CanvasLayer.new()
 var stage := Node3D.new()
 var player_combat = Combat.new()
 var ai_host: Node
 var crew_host: Node
 var unit := 0
 var game_mode := "skirmish"
 var garage := false
 var message := ""
 func terrain_height(_x:float, _z:float) -> float: return 0.0
var checks := 0
func check(value: bool, label: String) -> void:
 checks += 1
 if not value:
  push_error(label)
  quit(1)
  assert(value,label)
func _initialize(): call_deferred("run")
func run():
 var main := TestMain.new()
 main.player_combat.configure_tank("heavy")
 root.add_child(main)
 main.add_child(main.hero)
 main.add_child(main.hud)
 main.add_child(main.stage)
 main.ai_host = InfantryHost.new()
 main.add_child(main.ai_host)
 main.ai_host.setup(main)
 var floor_body := StaticBody3D.new()
 var shape := CollisionShape3D.new()
 var box := BoxShape3D.new()
 box.size = Vector3(100,0.2,100)
 shape.shape = box
 floor_body.add_child(shape)
 floor_body.position.y = -0.1
 main.add_child(floor_body)
 main.crew_host = CrewHost.new()
 main.add_child(main.crew_host)
 main.crew_host.setup(main)
 main.crew_host.bind_player()
 var control := Controller.new()
 main.add_child(control)
 control.setup(main)
 await physics_frame
 await physics_frame
 var pid: String = main.crew_host.person_ids[0]
 var actor = main.ai_host.actors[pid]
 var original_instance: int = actor.get_instance_id()
 var person: Dictionary = main.crew_host.registry.person_ref(pid)
 person.hp = 6.0
 person.parts.left_arm = "injured"
 var gunner: Dictionary = main.crew_host.registry.person_ref(main.crew_host.person_ids[1])
 gunner.hp = 0.0
 gunner.alive = false
 check(not main.crew_host.can_fire(),"dead original gunner blocks vehicle fire")
 check(main.crew_host.request_commander_takeover().ok,"living commander can begin taking gunner duty")
 main.crew_host._tick_takeover(1.0)
 check(not main.crew_host.can_fire(),"gunner duty unavailable during short transition")
 person.hp = 5.0
 main.crew_host._tick_takeover(0.1)
 check(not main.crew_host.takeover_status().pending,"taking damage cancels takeover")
 check(main.crew_host.request_commander_takeover().ok,"interrupted takeover can be explicitly restarted")
 main.crew_host._tick_takeover(2.5)
 check(main.crew_host.can_fire() and main.crew_host.takeover_status().active,"same commander fills the missing gunner job")
 check(not gunner.alive and gunner.hp==0.0 and person.hp==5.0,"takeover does not revive gunner or heal commander")
 check(is_equal_approx(main.crew_host.reload_multiplier(),1.35) and is_equal_approx(main.crew_host.observation_multiplier(),0.65),"dual duty exposes explicit reload and observation penalties")
 check(not control.active(),"seated commander leaves vehicle as controlled body")
 check(main.crew_host.disembark_person(pid).ok,"canonical commander safely exits")
 control.refresh_control()
 check(control.active() and control.actor()==actor,"existing commander receives actual input ownership")
 check(bool(actor.get_meta("player_controlled",false)),"AI suppression flag lives only on existing actor")
 var second_id: String = main.crew_host.person_ids[2]
 check(main.crew_host.disembark_person(second_id).ok,"second crew exits")
 check(not bool(main.ai_host.actors[second_id].get_meta("player_controlled",false)),"other crew retain autonomous ownership")
 var initial: Vector3 = actor.global_position
 for frame in range(40):
  control.set_input(Vector2(1,0),actor.global_position+Vector3(0,1.1,-100),false)
  await physics_frame
 check(actor.global_position.x>initial.x+0.4,"real CharacterBody physics walks under player input")
 control.clear_input()
 await physics_frame
 var stopped: Vector3 = actor.global_position
 for frame in range(12): await physics_frame
 check(Vector2(actor.global_position.x-stopped.x,actor.global_position.z-stopped.z).length()<0.05,"release stops movement and AI cannot resume patrol")
 var before_ammo: int = actor.brain.ammo
 var before_shots: int = actor.shot_sequence
 var weapon_identity: String = actor.weapon_id
 for frame in range(3):
  control.set_input(Vector2.ZERO,actor.global_position+Vector3(0,1.1,-100),true)
  await physics_frame
 control.clear_input()
 check(actor.shot_sequence==before_shots+1,"player rifle emits one actual muzzle-ray shot with cooldown")
 check(actor.brain.ammo==before_ammo-1 and int(person.ammo)==before_ammo-1,"actual shot spends one canonical cartridge")
 person.parts.left_leg = "disabled"
 person.parts.right_leg = "disabled"
 var immobile: Vector3 = actor.global_position
 for frame in range(10):
  control.set_input(Vector2(1,0),actor.global_position+Vector3(0,1,-100),false)
  await physics_frame
 check(Vector2(actor.global_position.x-immobile.x,actor.global_position.z-immobile.z).length()<0.05,"two disabled legs prevent walking")
 person.parts.left_leg = "healthy"
 person.parts.right_leg = "healthy"
 control.clear_input()
 var preboard: Dictionary = person.duplicate(true)
 check(control.request_board().ok,"nearby existing commander boards a vacant seat")
 check(not control.active() and not bool(actor.get_meta("player_controlled",false)),"boarding releases all player actor input")
 check(actor.get_instance_id()==original_instance and actor.weapon_id==weapon_identity,"boarding preserves actor and weapon identity")
 check(person.hp==preboard.hp and person.ammo==preboard.ammo and person.parts==preboard.parts,"boarding never heals injuries or replenishes ammo")
 check(main.crew_host.takeover_status().active and person.state.assigned_role=="gunner","takeover duty survives disembark and reboard without replacing commander")
 check(main.crew_host.disembark_person(pid).ok,"same commander exits again")
 control.refresh_control()
 actor.global_position = Vector3(12,0.12,0)
 check(not control.request_board().ok and control.active(),"distant boarding rejected without abandoning control")
 check(not main.crew_host.request_embark(pid).ok and not main.crew_host.pending_returns.has(pid),"batch return cannot take movement authority from player")
 var death_events: Array = []
 control.commander_died.connect(func(value): death_events.append(value))
 person.hp = 0.0
 person.alive = false
 control.refresh_control()
 control.refresh_control()
 check(death_events==[pid] and not control.active(),"canonical commander death signaled once, no replacement body")
 main.queue_free()
 await process_frame
 print("PLAYER_INFANTRY_CONTROL_PASS checks=",checks)
 quit(0)
