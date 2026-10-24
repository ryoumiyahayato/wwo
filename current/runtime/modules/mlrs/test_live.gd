extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1;print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var main=load("res://main.tscn").instantiate();root.add_child(main);await process_frame
 main.selected_catalog_id="mlrs_prototype";main.unit=0;main.choose_game_mode("skirmish")
 for i in range(10):await physics_frame
 main.set_process(false);main.set_physics_process(false);main.ai_host.set_physics_process(false);main.armor_host.set_physics_process(false);main.battle_controls.set_physics_process(false)
 main.garage=false;main.battle_finished=false
 check(main.artillery_mode(),"prototype registered in shared artillery control")
 check(main.hero.rails.size()==8 and main.weapon_muzzle()!=null,"actual rail set and separate central aiming reference")
 check(main.vehicle_ammo.total(main.PLAYER_VEHICLE_ID,"primary")==8,"host finite eight-round burst ammo")
 var hull:Transform3D=main.hero.global_transform
 var destination:Vector3=main.hero.global_position-main.hero.global_basis.z*100
 check(main.select_artillery_target(destination),"existing minimap targeting accepts point")
 for i in range(120):main.aim_weapon(destination);main.advance_weapon_aim(1.0/60)
 main.artillery_aim.tick(main,.5)
 check(main.hero.global_transform==hull,"target assistance does not drive vehicle")
 var before:int=main.requested_terrain_events
 main.fire_cannon();var adapter=main.mlrs_adapter;var ctl=adapter.controller;ctl.set_physics_process(false)
 check(main.vehicle_ammo.total(main.PLAYER_VEHICLE_ID,"primary")==8,"queue request does not consume whole salvo upfront")
 for i in range(200):
  ctl._physics_process(.05)
  for rocket in ctl.active.values().duplicate():
   if is_instance_valid(rocket):rocket.set_physics_process(false);rocket._physics_process(.05)
 check(main.vehicle_ammo.total(main.PLAYER_VEHICLE_ID,"primary")==0,"actual host ammo commits eight independent rounds")
 var rows:Array=[]
 for row in main.shot_audit:
  if row.get("weapon","")=="mlrs":rows.append(row)
 check(rows.size()==8,"host audit records all eight rails")
 var touched:=0
 for row in rows:
  if row.get("flight_state","")=="impacted":touched+=1
 check(touched==8,"host records eight real delayed collisions")
 check(main.requested_terrain_events==before+8,"one actual terrain event per rocket")
 check(main.hero.global_transform==hull,"salvo never moves player vehicle")
 main.fire_cannon();check(ctl.queue.is_empty(),"empty rack fire has no phantom queue")
 main.garage=true;main.clear_stage();await process_frame
 check(get_nodes_in_group("mlrs_projectile").is_empty(),"scene exit clears all rocket instances")
 print("MLRS_LIVE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));main.queue_free();await process_frame;quit(1 if failures else 0)
