extends SceneTree
const CrewHost = preload("res://modules/vehicle_crew/vehicle_crew_host.gd")
const InfantryHost = preload("res://modules/infantry_ai/infantry_host.gd")
const Combat = preload("res://scripts/combat.gd")
class TestMain extends Node3D:
	var armor_host: Node = null # Legal scene with no armored AI units.
	var hero := Node3D.new()
	var hud := CanvasLayer.new()
	var stage := Node3D.new()
	var player_combat = Combat.new()
	var ai_host: Node
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
		assert(value, label)
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
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40,0.2,40)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.1
	main.add_child(ground)
	var host = CrewHost.new()
	main.add_child(host)
	host.setup(main)
	host.bind_player()
	await physics_frame
	await physics_frame
	check(host.person_ids.size() == 5, "five actors bound")
	var pid: String = host.person_ids[1]
	var actor = main.ai_host.actors[pid]
	var instance_id: int = actor.get_instance_id()
	check(actor.embarked and not actor.visible and actor.collision_layer == 0, "aboard suspended hidden noncolliding")
	main.player_combat.crew[1].hp = 4
	main.player_combat.crew[1].parts.left_arm = "injured"
	check(host.disembark_person(pid).ok, "safe host disembark")
	check(not actor.embarked and actor.visible and actor.brain.hp == 4, "injured actor emerges no reset")
	check(not host.can_fire(), "host gunner absent blocks weapon")
	check(host.embark_person(pid).ok, "host reembark")
	check(main.ai_host.actors[pid].get_instance_id() == instance_id and main.ai_host.actors.size() == 5, "same actor no duplicate")
	check(main.player_combat.crew[1].hp == 4 and main.player_combat.crew[1].parts.left_arm == "injured", "same injured person retained")
	check(host.disembark_person(pid).ok, "second exit")
	actor.global_position = Vector3(12,0,0)
	check(not host.embark_person(pid).ok, "distant boarding rejected")
	actor.global_position = Vector3(3,0,0)
	check(host.embark_person(pid).ok, "nearby boarding accepted")
	# A solid box surrounding all six proposed exits must reject without changing seat.
	var obstacle := StaticBody3D.new()
	var obstacle_shape := CollisionShape3D.new()
	var obstacle_box := BoxShape3D.new()
	obstacle_box.size = Vector3(14,4,14)
	obstacle_shape.shape = obstacle_box
	obstacle.add_child(obstacle_shape)
	obstacle.position.y = 2
	main.add_child(obstacle)
	await physics_frame
	await physics_frame
	check(not host.disembark_person(pid).ok and actor.embarked and host.can_fire(), "blocked exits preserve actor and seat atomically")
	obstacle.queue_free()
	main.ai_host.clear()
	host.on_stage_reset()
	await physics_frame
	main.player_combat.configure_tank("light")
	host.bind_player()
	await physics_frame
	check(host.person_ids.size() == 3 and main.ai_host.actors.size() == 3, "light tank three distinct crew after scene reset")
	check(host.reload_multiplier() == 1.0 and host.onboard_indices().size() == 3, "light tank has no missing loader penalty")
	var light_id: String = host.person_ids[2]
	check(host.disembark_person(light_id).ok and host.onboard_indices().size() == 2, "dismounted excluded from onboard hit list")
	var save: Dictionary = host.snapshot()
	check(save.people[light_id].location.kind == "world", "host snapshot keeps live actor location")
	print("PASS crew host: %d checks with actual infantry host, same actor and 3D physics" % checks)
	main.queue_free()
	quit(0)
