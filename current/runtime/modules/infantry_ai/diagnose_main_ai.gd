extends SceneTree
var shots: Array = []
func _initialize(): call_deferred("run")
func run():
 var main = load("res://main.tscn").instantiate()
 root.add_child(main)
 await process_frame
 main.switch_mode()
 for i in 20: await physics_frame
 # Controlled integration fixture, separate from the protected production spawn.
 # Remove scenario cover and pin initial actors so each real weapon gets a turn.
 # Damage, actual muzzle rays, physics, target state and death proxies stay real.
 for fort in main.ai_host.fortifications.values():
  if is_instance_valid(fort.node): fort.node.queue_free()
 main.ai_host.fortifications.clear()
 var fixture_points := {"friendly_rifle":Vector3(-4,0,-1),"enemy_rifle":Vector3(4,0,6),"enemy_at":Vector3(-8,0,9)}
 for id in fixture_points:
  var actor = main.ai_host.actors[id]
  var point: Vector3 = fixture_points[id]
  point.y = main.terrain_height(point.x,point.z)+0.12
  actor.global_position = point
  actor.brain.patrol_points.clear()
  actor.brain.cover_points.clear()
  actor.suppression_cooldown = 100.0
 main.ai_host.actors["friendly_rifle"].aim_offsets = [Vector2.ZERO]
 main.ai_host.actors["friendly_rifle"].engagement_delay = 12.0
 main.ai_host.actors["enemy_rifle"].engagement_delay = 16.0
 main.ai_host.actors["enemy_at"].engagement_delay = 2.0
 var target_before: Dictionary=main.combat.modules.duplicate(true)
 main.ai_host.event_emitted.connect(func(event):
  if event.kind=="shot": shots.append({"actor":event.actor_id,"hit":event.hit_actor_id,"origin":event.origin,"end":event.position})
 )
 for step in 40*Engine.physics_ticks_per_second:
  await physics_frame
  if step%300==0:
   print("SIM_SECONDS=",float(step)/Engine.physics_ticks_per_second)
   for id in ["enemy_rifle","enemy_at","friendly_rifle"]:
    var a = main.ai_host.actors[id]
    print(id," p=",a.global_position," hp=",a.brain.hp," state=",a.brain.state," observations=",a._observations()," shots=",a.shot_sequence)
    for candidate in main.ai_host.infantry_candidates(id):
     if candidate.team_id==a.brain.team_id: continue
     var hit: Dictionary=a._ray(candidate.position)
     print(" -> ",candidate.actor_id," visibility=",main.ai_host.infantry_visibility(id,candidate.actor_id)," ray=",hit)
 print("SHOTS=",shots)
 print("PLAYER_MODULES=",main.player_combat.modules)
 var incoming := 0
 var friendly_fire := 0
 for shot in shots:
  if shot.actor=="enemy_at" and shot.hit=="player": incoming+=1
  if shot.actor=="friendly_rifle" and str(shot.hit).begins_with("enemy_"): friendly_fire+=1
 var posed_disabled := 0
 for id in ["enemy_rifle","enemy_at","friendly_rifle"]:
  var actor = main.ai_host.actors[id]
  if actor.brain.hp<=0.0:
   var visual = actor.get_node("InfantryVisual")
   var shape = actor.get_node("BodyCollision")
   if visual.rotation.z>1.0 and shape.shape.height<0.6 and shape.position.y<0.3: posed_disabled+=1
 var independent: bool=main.combat.modules==target_before
 var valid_events:=true
 for shot in shots:
  if not main.ai_host.actors.has(str(shot.actor)) or not shot.origin is Vector3 or not shot.end is Vector3 or not shot.origin.is_finite() or not shot.end.is_finite():valid_events=false
 var disabled_count:=0
 for id in ["enemy_rifle","enemy_at","friendly_rifle"]:
  if main.ai_host.actors[id].brain.hp<=0.0:disabled_count+=1
 var success: bool = not shots.is_empty() and valid_events and independent and posed_disabled==disabled_count
 print("TARGET_STATE_INDEPENDENT=",independent," DISABLED_POSE_AND_PROXY=",posed_disabled)
 print("ACTUAL_MAIN_40S_COMBAT=", "PASS" if success else "FAIL", " incoming=",incoming," friendly_hits=",friendly_fire," all_event_sources_valid=",valid_events," disabled_count=",disabled_count)
 main.queue_free()
 await process_frame
 quit(0 if success else 1)
