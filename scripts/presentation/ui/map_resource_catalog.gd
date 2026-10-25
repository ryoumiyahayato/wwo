extends RefCounted
## Presentation inputs only. No installer, world creation or domain mutation.
const CANDIDATES := "res://data/local/candidates"
const SCHEMA := "wwo_map_resource_candidate_v1"

static func discover() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for source: Dictionary in LocalSpatialLoader.SOURCES:
		if not LocalSpatialLoader._source_enabled(source): continue
		var row := _map_row(source)
		rows.append(row)
		for visual: Dictionary in row.get("visuals", []):
			var model := row.duplicate(true)
			model["id"] = "model:" + str(visual.get("id", visual.get("model_path", "")))
			model["kind"] = "model"
			model["name"] = str(visual.get("display_name", visual.get("anchor_name_zh", "模型")))
			model["model_path"] = str(visual.get("model_path", ""))
			model["visual_id"] = str(visual.get("id", ""))
			var coordinates: Array = visual.get("geometry", {}).get("coordinates", [])
			if coordinates.size() == 2: model["anchor"] = Vector2(float(coordinates[0]), float(coordinates[1]))
			model["missing"] = _missing(model["paths"])
			rows.append(model)
	var folder := DirAccess.open(CANDIDATES)
	if folder != null:
		for id: String in folder.get_directories():
			var candidate_folder := DirAccess.open(CANDIDATES.path_join(id))
			if candidate_folder == null: continue
			for name: String in candidate_folder.get_files():
				if name.ends_with(".candidate.json"):
					var manifest_path := CANDIDATES.path_join(id).path_join(name)
					var manifest := _read(manifest_path)
					var base := _base(str(manifest.get("base_map_id", "")))
					var candidate_source := base.duplicate()
					candidate_source["path"] = str(manifest.get("local_content_path", ""))
					var row := _map_row(candidate_source) if not base.is_empty() else {"name": id, "paths": [], "anchor": Vector2.ZERO, "map_id": ""}
					row.merge({"id": str(manifest.get("id", id)), "name": str(manifest.get("name", id)), "kind": "candidate", "version": str(manifest.get("version", "未记录")), "path": str(manifest.get("local_content_path", "")), "manifest_path": manifest_path, "manifest": manifest}, true)
					row["paths"] = _paths_for(str(row["path"]))
					row["missing"] = _missing(row["paths"])
					rows.append(row)
	return rows

static func _map_row(source: Dictionary) -> Dictionary:
	var path := str(source.get("path", ""))
	var doc := _read(path)
	var metadata: Dictionary = doc.get("metadata", {})
	var versions: Array[String] = []
	var sources: Array = doc.get("source_registry", {}).get("sources", [])
	for item: Dictionary in sources:
		var version := str(item.get("version", "未记录"))
		if version not in versions: versions.append(version)
	var visuals: Array[Dictionary] = []
	for item: Dictionary in metadata.get("landmark_visuals", []):
		if not str(item.get("model_path", "")).is_empty(): visuals.append(item)
	var paths := _paths_for(path)
	var id := str(source.get("anchor_id", ""))
	var names := {"place:paris": "巴黎 · 地形与城市", "place:london": "伦敦 · 威斯敏斯特", "place:berlin": "柏林 · 交通", "landmark:giza_pyramids_1900": "吉萨 · 地形与金字塔", "geographic_region:zermatt_west_reference": "采尔马特西侧 · 山地高程"}
	return {"id": "installed:" + id, "map_id": id, "kind": "map", "name": str(names.get(id, source.get("display_name", id))), "path": path, "anchor": source.get("anchor", Vector2.ZERO), "version": " / ".join(versions), "sources": sources, "paths": paths, "missing": _missing(paths), "visuals": visuals, "surface_path": str(metadata.get("surface_reference_path", "")), "terrain_note": str(metadata.get("terrain_note_zh", ""))}

static func _paths_for(path: String) -> Array[String]:
	var paths: Array[String] = []
	if not path.is_empty(): paths.append(path)
	var metadata: Dictionary = _read(path).get("metadata", {})
	_collect_paths(metadata.get("surface_presentation", {}), paths)
	var surface := str(metadata.get("surface_reference_path", ""))
	if not surface.is_empty():
		paths.append(surface)
		_collect_paths(_read(surface), paths)
	for visual: Dictionary in metadata.get("landmark_visuals", []):
		var model := str(visual.get("model_path", ""))
		if not model.is_empty() and model not in paths: paths.append(model)
	return paths

static func _collect_paths(value: Variant, paths: Array[String]) -> void:
	if value is Dictionary:
		for child: Variant in value.values(): _collect_paths(child, paths)
	elif value is Array:
		for child: Variant in value: _collect_paths(child, paths)
	elif value is String and value.begins_with("res://") and value not in paths:
		paths.append(value)

static func _missing(paths: Array) -> Array[String]:
	var missing: Array[String] = []
	for path: String in paths:
		if not FileAccess.file_exists(path): missing.append(path)
	return missing

static func detail_scale_needed(row: Dictionary) -> bool:
	if row.get("kind") == "model": return true
	var metadata: Dictionary = _read(str(row.get("path", ""))).get("metadata", {})
	var surface := _read(str(metadata.get("surface_reference_path", "")))
	return not surface.is_empty() and RegionView._terrain_limit_mpp(surface) < 10.0

static func inspect(row: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var files: Array[Dictionary] = []
	for path: String in row.get("paths", []):
		if not FileAccess.file_exists(path):
			errors.append("资源缺失：" + path)
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			errors.append("资源不可读：" + path)
			continue
		var bytes := file.get_length()
		file.close()
		var checksum := FileAccess.get_sha256(path)
		if checksum.length() != 64: errors.append("SHA256 读取失败：" + path)
		files.append({"path": path, "bytes": bytes, "sha256": checksum})
	var doc := _read(str(row.get("path", "")))
	if str(doc.get("metadata", {}).get("schema_id", "")) != "local_spatial_content_r1": errors.append("不是当前 LOCAL 显示合同")
	if str(doc.get("metadata", {}).get("anchor_place_id", "")) != str(row.get("map_id", "")): errors.append("地图身份与原模块不一致")
	if row.get("kind") == "candidate":
		var verified := verify_manifest(str(row.get("manifest_path", "")))
		errors.append_array(verified["errors"])
		var listed: Array = verified.get("paths", [])
		for path: String in row.get("paths", []):
			if path not in listed: errors.append("候选依赖不在清单中：" + path)
	return {"files": files, "errors": errors, "sources": doc.get("source_registry", {}).get("sources", []), "version": row.get("version", "未记录"), "checked_at": Time.get_datetime_string_from_system()}

static func verify_manifest(path: String) -> Dictionary:
	var errors: Array[String] = []
	var paths: Array[String] = []
	var files: Array[Dictionary] = []
	var doc := _read(path)
	var id := str(doc.get("id", ""))
	if doc.get("schema_id") != SCHEMA: errors.append("清单格式应为 " + SCHEMA)
	if id.is_empty() or id.validate_filename() != id or id in [".", ".."]: errors.append("候选 ID 无效")
	if _base(str(doc.get("base_map_id", ""))).is_empty(): errors.append("没有当前工程中的基础地图")
	if str(doc.get("version", "")).is_empty(): errors.append("候选版本缺失")
	var entries: Variant = doc.get("files", [])
	if not entries is Array or entries.is_empty() or entries.size() > 512:
		errors.append("文件清单为空或超过 512 项")
		return {"errors": errors, "paths": paths, "files": files}
	if not errors.is_empty(): return {"errors": errors, "paths": paths, "files": files}
	for entry: Variant in entries:
		if not entry is Dictionary:
			errors.append("文件清单项不是对象")
			continue
		var resource_path := str(entry.get("path", ""))
		if not _candidate_path(resource_path, id):
			errors.append("候选路径必须位于独立目录：" + resource_path)
			continue
		if resource_path in paths:
			errors.append("清单路径重复：" + resource_path)
			continue
		paths.append(resource_path)
		var expected := str(entry.get("sha256", "")).to_lower()
		if expected.length() != 64 or not expected.is_valid_hex_number(false):
			errors.append("SHA256 无效：" + resource_path)
			continue
		var file := FileAccess.open(resource_path, FileAccess.READ)
		if file == null:
			errors.append("候选文件缺失：" + resource_path)
			continue
		var bytes := file.get_length()
		file.close()
		if not entry.has("bytes") or float(entry["bytes"]) != float(bytes): errors.append("文件长度不符：" + resource_path)
		var actual := FileAccess.get_sha256(resource_path)
		if actual != expected: errors.append("SHA256 不符：" + resource_path)
		files.append({"path": resource_path, "bytes": bytes, "sha256": actual, "expected_sha256": expected})
	var content_path := str(doc.get("local_content_path", ""))
	if not _candidate_path(content_path, id) or content_path not in paths: errors.append("LOCAL 内容必须位于候选目录并列入清单")
	return {"id": id, "errors": errors, "paths": paths, "files": files, "manifest_path": path, "read_only": true}

static func _candidate_path(path: String, id: String) -> bool:
	if path != path.simplify_path() or "\\" in path: return false
	return path.begins_with(CANDIDATES.path_join(id) + "/") or path.begins_with("res://assets/landmarks/candidates/".path_join(id) + "/")

static func _base(id: String) -> Dictionary:
	for source: Dictionary in LocalSpatialLoader.SOURCES:
		if str(source["anchor_id"]) == id and LocalSpatialLoader._source_enabled(source): return source
	return {}

static func _read(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func project_version() -> Dictionary:
	var revision := "未记录"
	var head_path := "res://.git/HEAD"
	if FileAccess.file_exists(head_path):
		var head := FileAccess.get_file_as_string(head_path).strip_edges()
		if head.begins_with("ref: "):
			var reference := head.trim_prefix("ref: ")
			var ref_path := "res://.git/" + reference
			if FileAccess.file_exists(ref_path): revision = FileAccess.get_file_as_string(ref_path).strip_edges()
			elif FileAccess.file_exists("res://.git/packed-refs"):
				for line: String in FileAccess.get_file_as_string("res://.git/packed-refs").split("\n"):
					if line.ends_with(" " + reference): revision = line.get_slice(" ", 0)
		else: revision = head
	return {"name": ProjectSettings.get_setting("application/config/name", ""), "version": ProjectSettings.get_setting("application/config/version", ""), "build_label": ProjectSettings.get_setting("application/config/build_label", ""), "git_revision": revision, "source_state": "WORKTREE; git revision alone does not certify uncommitted source", "component_version": "map-resource-acceptance-v1", "project_sha256": FileAccess.get_sha256("res://project.godot"), "acceptance_code_sha256": FileAccess.get_sha256("res://scripts/presentation/ui/map_resource_acceptance.gd"), "engine": Engine.get_version_info()}
