extends SceneTree
const Host = preload("res://modules/infantry_ai/infantry_host.gd")
class FixtureMain:
 extends Node3D
 var camera:Camera3D
 var stage:Node3D
var failures=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1280,720)
 var main=FixtureMain.new();root.add_child(main);main.stage=Node3D.new();main.add_child(main.stage);main.camera=Camera3D.new();main.add_child(main.camera);main.camera.position=Vector3(0,.85,0)
 var host=Host.new();main.add_child(host);host.setup(main)
 check(is_instance_valid(host.character_detail_lod),"production host creates LOD manager")
 var actor=host.spawn_actor("detail_test","blue",Vector3(0,0,-4));actor.set_physics_process(false)
 var muzzle_before=actor.muzzle;var visual=actor.get_node("InfantryVisual");var count=visual.find_children("*","Node",true,false).size()
 host.character_detail_lod._clock=2;host.character_detail_lod.refresh()
 check(host.character_detail_lod.snapshot().near==1,"production spawn enters near LOD")
 check(actor.muzzle==muzzle_before and visual.find_children("*","Node",true,false).size()==count,"production binding and hierarchy retained")
 host.clear();check(host.character_detail_lod.snapshot().registered==0,"production clear releases LOD references")
 print("CHARACTER_DETAIL_LOD_FAILURES=",failures);quit(0 if failures==0 else 1)
