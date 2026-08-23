class_name ProductRuntimeProvenance
extends RefCounted
## Compact diagnostic assembled from the objects constructed by the product root.

const NOT_AVAILABLE: String = "NOT AVAILABLE"


static func capture(owner_specs: Array[Dictionary]) -> Dictionary:
	var runtime_scene := ""
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var current_scene := (loop as SceneTree).current_scene
		if current_scene != null:
			runtime_scene = current_scene.scene_file_path
	var records: Array[Dictionary] = []
	for spec_value: Variant in owner_specs:
		var spec := spec_value as Dictionary
		var owner: Variant = spec.get("owner")
		records.append({
			"label": str(spec.get("label", "OWNER")),
			"status": "ACTIVE" if owner != null else "NOT INTEGRATED",
			"owner": _owner_name(owner),
			"mode": str(spec.get("mode", "")) if owner != null else "",
			"detail": str(spec.get("detail", "")),
		})
	return {
		"build_head": resolve_build_head(),
		"product_entry": str(
			ProjectSettings.get_setting("application/run/main_scene", "")
		),
		"runtime_scene": runtime_scene,
		"owners": records,
		"e1_product_integration": false,
	}


static func resolve_build_head() -> String:
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var git_root := project_root.path_join(".git")
	var head_path := git_root.path_join("HEAD")
	if not FileAccess.file_exists(head_path):
		return NOT_AVAILABLE
	var head := _read_text(head_path).strip_edges()
	if head.begins_with("ref: "):
		var reference := head.trim_prefix("ref: ").strip_edges()
		head = _read_text(git_root.path_join(reference)).strip_edges()
	return head if _is_commit_id(head) else NOT_AVAILABLE


static func _owner_name(owner: Variant) -> String:
	if owner == null or not owner is Object:
		return "NONE"
	var object := owner as Object
	var script: Variant = object.get_script()
	if script is Script:
		var global_name := (script as Script).get_global_name()
		if not global_name.is_empty():
			return global_name
		var resource_path := (script as Script).resource_path
		if not resource_path.is_empty():
			return resource_path.get_file().get_basename().to_pascal_case()
	return object.get_class()


static func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


static func _is_commit_id(value: String) -> bool:
	if value.length() != 40:
		return false
	for character: String in value:
		if character.to_lower() not in "0123456789abcdef":
			return false
	return true
