extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures += 1
func run():
 var main = load("res://main.tscn").instantiate()
 root.add_child(main)
 await process_frame
 main.switch_mode()
 for i in 20: await physics_frame
 var friend = main.ai_host.actors["friendly_rifle"]
 var rifle = main.ai_host.actors["enemy_rifle"]
 var rocket = main.ai_host.actors["enemy_at"]
 check(friend.global_position.distance_to(rifle.global_position)>15.0,"opponents start beyond 15 metres")
 check(main.ai_host.fortifications.size()==2,"two real team-owned cover colliders exist")
 var crew_before: Array = main.player_combat.crew.duplicate(true)
 var armor_before: Dictionary = main.player_combat.modules.duplicate(true)
 for i in 3600: await physics_frame
 check(friend.brain.hp>0.0,"protected friendly survives idle first minute")
 check(main.player_combat.crew==crew_before,"stationary novice crew remains healthy through first minute")
 check(main.player_combat.modules==armor_before,"ordinary rifle fire does not chip vehicle armor")
 check(rifle.shot_sequence>0,"visible opposing rifle still fires in opening encounter")
 print("OPENING_ROCKET_SHOTS=",rocket.shot_sequence," FRIEND_HP=",friend.brain.hp," RIFLE_SHOTS=",rifle.shot_sequence)
 print("OPENING_COVER_FAILURES=",failures)
 main.queue_free()
 quit(1 if failures else 0)
