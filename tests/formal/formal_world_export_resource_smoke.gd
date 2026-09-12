extends SceneTree
## Verifies the same imported resource contract used by the Windows release.

const FLAGS_PATH := "res://data/world_map/historical/flags_1900.json"
const HISTORICAL_FLAG_ASSET_PREFIX := "res://assets/historical_flags/1900/"
const INTENDED_ENTITY_ID := "state:country_fra"
const INTENDED_FLAG_ID := "france_tricolour_1794"
const SUPPORTED_REFERENCE_KEYS: Array[String] = [
	"data",
	"object",
	"objects",
	"payload",
	"record",
	"records",
	"reference",
	"resource",
	"resources",
	"value",
]

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
	var records := _validated_historical_flag_records(document)
	if records.is_empty():
		_finish()
		return
	var discovered_asset_paths: Array[String] = []
	_collect_supported_resource_paths(records, discovered_asset_paths)
	_check(
		discovered_asset_paths.size() == 60,
		"历史旗帜目录的递归资源发现没有找到全部60个已渲染资源"
	)
	var source_asset_count := 0
	var france_asset_path := ""
	for record_key: Variant in records.keys():
		var record_value: Variant = records.get(record_key)
		var record := record_value as Dictionary
		var flag_id := str(record.get("id", ""))
		_check(
			_is_historical_flag_record(str(record_key), record),
			"历史旗帜目录包含未登记为历史旗帜的records对象：" + str(record_key)
		)
		if str(record.get("render_mode", "")) != "source_asset":
			continue
		source_asset_count += 1
		var asset_path := str(record.get("asset_path", ""))
		_check(
			asset_path.begins_with(HISTORICAL_FLAG_ASSET_PREFIX),
			"历史旗帜资源越出正式素材目录：" + flag_id
		)
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
		if flag_id == INTENDED_FLAG_ID:
			france_asset_path = asset_path
	_check(source_asset_count == 60, "source_asset旗帜数量不是60")
	_check(
		not france_asset_path.is_empty(),
		"历史旗帜目录缺少法兰西实际Texture2D记录"
	)

	var source := FileAccess.get_file_as_string(
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd"
	)
	_check(
		not source.contains("Image.load_from_file"),
		"正式旗帜仍绕过Godot导入器读取原始文件"
	)
	_check_windows_export_preset()

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
	if application._country_by_id.has(INTENDED_ENTITY_ID):
		var france_entity := application._country_by_id.get(INTENDED_ENTITY_ID) as Dictionary
		var france_palette := application._resolved_flag_palette(
			str(france_entity.get("iso_a3", ""))
		)
		var product_texture := application._flag_texture_for_entity(
			INTENDED_ENTITY_ID, france_palette
		)
		_check(
			product_texture != null,
			"正式世界资源路径没有返回法兰西产品旗帜Texture2D"
		)
		var imported_by_id := application._historical_imported_flag_texture_by_id as Dictionary
		var imported_france := imported_by_id.get(INTENDED_FLAG_ID) as Texture2D
		_check(
			imported_france != null and str(imported_france.resource_path) == france_asset_path,
			"法兰西产品旗帜没有经过实际导入Texture2D资源路径"
		)
	else:
		_check(false, "正式世界没有法兰西历史政治单元")
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


func _validated_historical_flag_records(document: Dictionary) -> Dictionary:
	_check(int(document.get("schema_version", -1)) == 1, "历史旗帜目录schema版本不受支持")
	_check(
		str(document.get("snapshot_date", "")) == "1900-03-12",
		"历史旗帜目录不是1900-03-12快照"
	)
	_check(
		bool((document.get("policy", {}) as Dictionary).get("source_asset_required_for_rendered_flag", false)),
		"历史旗帜目录没有声明渲染旗帜必须使用source_asset"
	)
	var records_value: Variant = document.get("records", null)
	_check(records_value is Dictionary, "历史旗帜目录records不是对象")
	if not records_value is Dictionary:
		return {}
	var records := records_value as Dictionary
	_check(int(document.get("record_count", -1)) == records.size(), "历史旗帜目录record_count不匹配")
	return records


func _is_historical_flag_record(record_key: String, record: Dictionary) -> bool:
	return (
		not record_key.is_empty()
		and str(record.get("id", "")) == record_key
		and record.has("render_mode")
		and record.has("flag_type")
		and record.has("valid_from")
		and record.has("valid_to")
		and record.has("ratio")
	)


func _collect_supported_resource_paths(value: Variant, output: Array[String]) -> void:
	if value is Dictionary:
		var dictionary := value as Dictionary
		var asset_path := str(dictionary.get("asset_path", ""))
		if asset_path.begins_with(HISTORICAL_FLAG_ASSET_PREFIX) and asset_path not in output:
			output.append(asset_path)
		var resource_path := str(dictionary.get("resource_path", ""))
		if resource_path.begins_with(HISTORICAL_FLAG_ASSET_PREFIX) and resource_path not in output:
			output.append(resource_path)
		for key: String in SUPPORTED_REFERENCE_KEYS:
			if dictionary.has(key):
				_collect_supported_resource_paths(dictionary.get(key), output)
		# A validated catalog map is itself a supported object structure. Walk its
		# values so a resource wrapped below a record/reference is not dropped.
		for child: Variant in dictionary.values():
			_collect_supported_resource_paths(child, output)
		return
	if value is Array:
		for child: Variant in value as Array:
			_collect_supported_resource_paths(child, output)


func _check_windows_export_preset() -> void:
	var config := ConfigFile.new()
	var load_error := config.load("res://export_presets.cfg")
	_check(load_error == OK, "export_presets.cfg无法作为Godot配置读取")
	if load_error != OK:
		return
	var windows_sections: Array[String] = []
	for section: String in config.get_sections():
		if str(config.get_value(section, "name", "")) == "Windows Desktop":
			windows_sections.append(section)
	_check(windows_sections.size() == 1, "Windows Desktop发布预设不唯一")
	if windows_sections.is_empty():
		return
	var windows_section := windows_sections[0]
	_check(
		str(config.get_value(windows_section, "export_filter", "")) == "all_resources",
		"Windows发布没有包含全部产品资源"
	)
	var exclude_filter := str(config.get_value(windows_section, "exclude_filter", ""))
	_check(
		not exclude_filter.contains("assets/"),
		"Windows发布显式排除了产品素材"
	)


func _finish() -> void:
	print("Formal export resource smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
