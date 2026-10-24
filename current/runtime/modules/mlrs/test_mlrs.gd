extends SceneTree
const Visual=preload("res://modules/mlrs/launcher_visual.gd")
const Salvo=preload("res://modules/mlrs/salvo_controller.gd")
var checks:=0
var failures:=0
var world:Node3D
var can_fire:=true
var ammo:=8
var commits:Array=[]
var launched:Array=[]
var impacts:Array=[]
func check(value:bool,label:String):
 checks+=1
 if not value:failures+=1;printerr("FAIL "+label)
 else:print("PASS "+label)
func _initialize():call_deferred("run")
func consume(index:int)->bool:
 if ammo<=0:return false
 ammo-=1;commits.append(index);return true
func allowed()->bool:return can_fire
func floor_body(size:Vector3,at:Vector3)->StaticBody3D:
 var body:=StaticBody3D.new();body.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);world.add_child(body);body.position=at;return body
func make_launcher()->Array:
 var vehicle:=Visual.new();world.add_child(vehicle)
 var controller:=Salvo.new();world.add_child(controller);controller.set_physics_process(false)
 check(controller.configure(vehicle,world,vehicle.rails,consume,allowed),"configure eight actual rails")
 controller.launched.connect(func(event):launched.append(event))
 controller.impact.connect(func(event):impacts.append(event))
 return [vehicle,controller]
func advance(controller,steps:int):
 for _i in range(steps):
  controller._physics_process(.05)
  for rocket in controller.active.values().duplicate():
   if is_instance_valid(rocket):rocket.set_physics_process(false);rocket._physics_process(.05)
func run():
 world=Node3D.new();root.add_child(world)
 floor_body(Vector3(500,.2,500),Vector3(0,-.1,-100))
 await physics_frame;await physics_frame
 var pair:=make_launcher();var vehicle=pair[0];var controller=pair[1]
 var unique:Dictionary={}
 for rail in vehicle.rails:unique[str(rail.global_position)]=true
 check(unique.size()==8,"eight distinct authored launch positions")
 check(vehicle.lods.size()==3,"three actual vehicle geometry LOD variants")
 vehicle.set_lod(2);check(vehicle.lods[2].visible and not vehicle.lods[0].visible,"LOD switches real geometry")
 vehicle.set_angles(9,9);check(is_equal_approx(vehicle.mount.rotation.y,deg_to_rad(8)) and is_equal_approx(vehicle.mount.get_node("Barrel").rotation.x,deg_to_rad(65)),"mount constrained to game mechanical limits")
 vehicle.set_angles(0,deg_to_rad(35))
 check(controller.begin_salvo(55,0),"start finite salvo")
 check(not controller.begin_salvo(55,0),"repeated key cannot duplicate queue")
 controller._physics_process(.05)
 check(ammo==7 and launched.size()==1 and impacts.is_empty(),"one launch one commit no immediate hit")
 check(not vehicle.loaded[0].visible and vehicle.loaded[1].visible,"spent rail becomes empty only")
 var first=controller.active.values()[0];first.set_physics_process(false)
 check(first.visual_lods.size()==2,"real rocket geometry has two LOD levels")
 var origin:Vector3=first.origin
 vehicle.position.x=1
 check(first.origin==origin,"moving vehicle cannot move launched rocket origin")
 advance(controller,180)
 check(launched.size()==8 and ammo==0 and commits.size()==8,"eight sequential rounds each deducted once")
 check(impacts.size()==8,"all rockets actually collide with ground")
 var xvalues:Array=[]
 for hit in impacts:xvalues.append(hit.position.x)
 print("BASELINE_LANDINGS ",JSON.stringify(impacts.map(func(e):return {"x":e.position.x,"y":e.position.y,"z":e.position.z,"seconds":e.flight_seconds})))
 check(xvalues.max()-xvalues.min()>1,"zero jitter still has geometry-derived spread")
 for row in launched:check(row.jitter_radians==Vector2.ZERO,"zero dispersion baseline remains zero")
 check(launched[1].origin.x!=vehicle.rails[0].global_position.x,"launch uses own rail not vehicle center")
 check(controller.active.is_empty(),"active pool drained after impacts")
 check(not controller.begin_salvo(55),"empty rack cannot fire again")
 vehicle.queue_free();controller.queue_free();await process_frame
 ammo=8;commits.clear();launched.clear();impacts.clear()
 pair=make_launcher();vehicle=pair[0];controller=pair[1]
 controller.begin_salvo(55,1)
 controller._physics_process(.05)
 check(launched[0].jitter_radians.length()>0,"optional precision dispersion logged separately")
 can_fire=false;controller._physics_process(.05)
 check(controller.queue.is_empty() and ammo==7,"destroy or deselect cancels unlaunched rounds without consuming")
 can_fire=true
 controller.reset_generation()
 check(controller.active.is_empty(),"stage reset clears active projectiles without damage")
 controller._settle({"position":Vector3.ZERO},1,0,true)
 check(impacts.is_empty(),"stale impact callback cannot damage new stage")
 vehicle.queue_free();controller.queue_free();await process_frame
 ammo=8;commits.clear();launched.clear();impacts.clear()
 pair=make_launcher();vehicle=pair[0];controller=pair[1]
 var wall:=floor_body(Vector3(20,20,.02),Vector3(0,8,-3))
 await physics_frame;await physics_frame
 controller.begin_salvo(55);advance(controller,80)
 check(impacts.size()==8,"all eight swept projectiles hit thin barrier")
 for hit in impacts:check(hit.collider==wall and hit.position.z>-3.1,"first obstacle blocks rocket, no through-wall target hit")
 controller.reset_generation();vehicle.queue_free();controller.queue_free();await process_frame
 ammo=8;can_fire=true
 pair=make_launcher();vehicle=pair[0];controller=pair[1]
 check(not controller.begin_salvo(NAN),"nonfinite launch speed rejected before ammo commit")
 controller.begin_salvo(55)
 for i in range(24):
  var blocker:=Node.new();world.add_child(blocker);blocker.add_to_group("mlrs_projectile")
 controller._physics_process(5)
 check(ammo==8 and controller.queue.size()==8,"global active cap backpressure preserves ammo and queue")
 for node in get_nodes_in_group("mlrs_projectile"):node.queue_free()
 await process_frame
 controller._physics_process(5)
 check(ammo==7,"long frame sends one round not full burst")
 controller.cancel("weapon_switched")
 check(controller.queue.is_empty() and ammo==7,"weapon switch preserves unlaunched rounds")
 controller.reset_generation();vehicle.queue_free();controller.queue_free();await process_frame
 check(failures==0,"aggregate no failures")
 print("MLRS_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(1 if failures else 0)
