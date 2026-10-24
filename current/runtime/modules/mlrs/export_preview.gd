extends SceneTree
func _initialize():call_deferred("run")
func run():
 var model=preload("res://modules/mlrs/launcher_visual.gd").new();root.add_child(model)
 for l in range(1,3):model.lods[l].queue_free()
 await process_frame
 var document:=GLTFDocument.new();var state:=GLTFState.new()
 var error:=document.append_from_scene(model,state)
 print("EXPORT ",error," ",document.write_to_filesystem(state,"/workspace/shared/rocket_launcher/assembled_lod0.glb"))
 quit()
