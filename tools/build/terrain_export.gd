@tool
extends EditorPlugin
# Editor-only substitution, shared by --export-release and --export-pack.
# All scripts/scenes and unrelated resources remain the normal current export.
class TerrainExport extends EditorExportPlugin:
	var recipe: Dictionary = {}
	var included: Dictionary = {}
	func _get_name() -> String:
		return "WWOTerrainStorage"
	func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
		recipe = {};included = {}
		var path := OS.get_environment("WWO_TERRAIN_EXPORT_RECIPE")
		if path.is_empty(): return
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			push_error("Invalid terrain export recipe")
			return
		recipe = parsed
		for virtual: String in recipe.get("forced",[]): _include(virtual)
	func _include(virtual: String) -> void:
		var source := str((recipe.replacements as Dictionary)[virtual])
		var file := FileAccess.open(source,FileAccess.READ)
		if file==null:
			push_error("Missing terrain export input: "+source)
			return
		var data := file.get_buffer(file.get_length())
		add_file("res://"+virtual,data,false)
		included[virtual] = data.size()
	func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
		var virtual := path.trim_prefix("res://")
		if (recipe.get("replacements",{}) as Dictionary).has(virtual):
			if not included.has(virtual): _include(virtual)
			skip() # Never ship the original payload alongside its replacement.
	func _export_end() -> void:
		if recipe.is_empty(): return
		var complete := included.size()==(recipe.replacements as Dictionary).size()
		FileAccess.open(str(recipe.report),FileAccess.WRITE).store_string(JSON.stringify({"complete":complete,"included":included},"\t"))
		print("WWO_TERRAIN_EXPORT complete=",complete," paths=",included.size())
		if not complete: push_error("Terrain export did not include every required replacement")

var terrain_export := TerrainExport.new()
func _enter_tree() -> void:
	add_export_plugin(terrain_export)
func _exit_tree() -> void:
	remove_export_plugin(terrain_export)
