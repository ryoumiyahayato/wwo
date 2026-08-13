extends SceneTree
## Verifies the same imported resource contract used by the Windows release.

const FLAGS_PATH := "res://data/world_map/historical/flags_1900.json"

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var document_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(FLAGS_PATH)
	)
	_check(document_value is Dictionary, "历史旗帜目录不是有效JSON对象")
	if not document_value is Dictionary:
		_finish()
		return
	var document := document_value as Dictionary
	var records := document.get("records", {}) as Dictionary
	var source_asset_count := 0
	for record_value: Variant in records.values():
		var record := record_value as Dictionary
		if str(record.get("render_mode", "")) != "source_asset":
			continue
		source_asset_count += 1
		var flag_id := str(record.get("id", ""))
		var asset_path := str(record.get("asset_path", ""))
		_check(asset_path.begins_with("res://"), "旗帜不是发布资源路径：" + flag_id)
		_check(
			ResourceLoader.exists(asset_path, "Texture2D"),
			"发布资源不存在或未导入为Texture2D：" + flag_id
		)
		var resource := ResourceLoader.load(
			asset_path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE
		)
		_check(resource is Texture2D, "发布资源不能作为Texture2D加载：" + flag_id)
		if resource is Texture2D:
			var image := (resource as Texture2D).get_image()
			_check(image != null and not image.is_empty(), "发布纹理没有可绘制图像：" + flag_id)
	_check(source_asset_count == 60, "source_asset旗帜数量不是60")

	var source := FileAccess.get_file_as_string(
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd"
	)
	_check(
		not source.contains("Image.load_from_file"),
		"正式旗帜仍绕过Godot导入器读取原始文件"
	)
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	_check(presets.contains('name="Windows Desktop"'), "缺少Windows Desktop发布预设")
	_check(presets.contains('export_filter="all_resources"'), "Windows发布没有包含全部产品资源")
	_check(not presets.contains("assets/*,assets/**"), "Windows发布显式排除了产品素材")

	var scene := load("res://scenes/formal/formal_world_main.tscn") as PackedScene
	_check(scene != null, "正式世界场景无法加载")
	if scene == null:
		_finish()
		return
	var application := scene.instantiate() as FormalWorldApplication
	get_root().add_child(application)
	for _index: int in range(6):
		await process_frame
	application._ensure_projection_cache()
	for entity_value: Variant in application._country_by_id.values():
		var entity := entity_value as Dictionary
		var entity_id := str(entity.get("id", ""))
		var palette := application._resolved_flag_palette(str(entity.get("iso_a3", "")))
		var texture := application._flag_texture_for_entity(entity_id, palette)
		_check(texture != null, "地图实体没有发布旗帜纹理：" + entity_id)
	_check(application._missing_flag_record_ids.is_empty(), "正式世界运行时发现缺失旗帜资源")
	_check(application._data_errors.is_empty(), "正式世界运行时发现玩家可见数据错误")
	application.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("Formal export resource smoke: " + message)


func _finish() -> void:
	print("Formal export resource smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
