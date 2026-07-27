extends Node

const TARGET_SCENE := "res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn"

var workspace: Control


func _ready() -> void:
	_run_probe.call_deferred()


func _run_probe() -> void:
	var packed := load(TARGET_SCENE) as PackedScene
	if not _require(packed != null, "样机场景无法加载"):
		return
	workspace = packed.instantiate() as Control
	if not _require(workspace != null, "样机场景无法实例化"):
		return
	add_child(workspace)
	await _settle_frames(12)

	var evidence := workspace.call("historical_evidence_report") as Dictionary
	if not _require(str(evidence.get("snapshot_date", "")) == "1900-03-12", "历史GIS快照日期错误"):
		return
	if not _require(str(evidence.get("geometry_provider", "")) == "cshapes_2_0", "全球边界没有使用CShapes 2.0"):
		return
	if not _require(str(evidence.get("geometry_license", "")) == "CC BY-NC-SA 4.0", "CShapes许可信息缺失"):
		return
	if not _require(not bool(evidence.get("commercial_use_allowed", true)), "非商业数据层没有明确商业限制"):
		return
	if not _require(int(evidence.get("unit_count", 0)) == 151 and int(evidence.get("geometry_feature_count", 0)) == 151, "1900政治单元或边界未完整加载"):
		return
	if not _require(int(evidence.get("provisional_count", -1)) == 0 and not bool(evidence.get("modern_geometry_fallback", true)), "仍在使用现代或待校订边界回退"):
		return
	if not _require(int(evidence.get("unresolved_flag_count", -1)) == 0, "仍有旗帜史料记录未解决"):
		return

	var coverage := workspace.call("flag_coverage_report") as Dictionary
	var explicit_count := int(coverage.get("explicit_count", 0))
	var generated_count := int(coverage.get("generated_count", 0))
	var classified_flags := (
		int(coverage.get("local_historical_flags", 0))
		+ int(coverage.get("controller_identification_flags", 0))
		+ int(coverage.get("documented_absence", 0))
	)
	if not _require(explicit_count == 151 and generated_count == 151, "151个政治单元没有全部得到可显示旗面或中性缺席标记"):
		return
	if not _require(classified_flags == 151, "旗帜语义分类没有覆盖所有政治单元"):
		return
	if not _require(int(coverage.get("documented_absence", 0)) > 0, "无统一标准旗的政治单元被错误强制分配旗帜"):
		return

	var navigation := workspace.call("navigation_coverage_report") as Dictionary
	if not _require(int(navigation.get("total_territories", 0)) == 151, "历史政治边界导航没有覆盖151个单元"):
		return
	if not _require(int(navigation.get("dated_historical_boundaries", 0)) == 151 and bool(navigation.get("political_boundaries_historical", false)), "历史政治边界被错误降级为现代近似"):
		return
	if not _require(not bool(navigation.get("global_admin1_historical", true)) and not bool(navigation.get("fully_historical", true)), "尚未考证的全球下级行政区被错误标记为历史完成"):
		return

	var profiles := workspace.get("_character_profiles") as Dictionary
	profiles["german_test"] = {"nationality_id":"country_deu", "culture_id":"deu", "occupation":"行政主官", "role":"行政主官", "position":"地方行政主官"}
	workspace.set("_character_profiles", profiles)
	workspace.set("active_character_key", "german_test")
	if not _require(str((workspace.call("home_country_detail_report") as Dictionary).get("home_entity_id", "")) == "german_empire", "德国人物没有映射到德意志帝国"):
		return
	workspace.set("selected_country_id", "country_fra")
	workspace.call("_focus_selected_country")
	if not _require(str(workspace.get("world_mode")) == "historical_entity_focus", "德国人物查看法国时错误进入法国专用九大区"):
		return
	workspace.call("_return_to_global_world")
	workspace.set("selected_country_id", "german_empire")
	workspace.call("_focus_selected_country")
	workspace.call("_enter_region")
	if not _require(str(workspace.get("selected_historical_territory_iso")) == "DEU", "德国人物进入本国时没有自动选择德意志帝国历史辖区"):
		return
	var admin1_by_iso := workspace.get("_world_admin1_by_iso") as Dictionary
	var german_regions := admin1_by_iso.get("DEU", []) as Array
	if not _require(not german_regions.is_empty(), "德国现代一级行政参考层为空"):
		return
	workspace.set("selected_world_admin1_id", str((german_regions[0] as Dictionary).get("id", "")))
	workspace.call("_enter_selected_world_admin1")
	if not _require(str(workspace.get("space_level")) == "city", "德国人物无法从本国一级区进入本地参考层"):
		return

	workspace.call("_return_to_global_world")
	workspace.set("active_character_key", "worker")
	if not _require(str((workspace.call("home_country_detail_report") as Dictionary).get("home_entity_id", "")) == "country_fra", "法国人物没有映射到法兰西第三共和国"):
		return
	workspace.set("selected_country_id", "german_empire")
	workspace.call("_focus_selected_country")
	workspace.call("_enter_region")
	workspace.set("selected_world_admin1_id", str((german_regions[0] as Dictionary).get("id", "")))
	workspace.call("_activate_button", "history_enter_admin1")
	if not _require(str(workspace.get("space_level")) == "region", "法国人物查看德国时越过了外国省级终点"):
		return
	workspace.call("_return_to_global_world")
	workspace.set("selected_country_id", "country_fra")
	workspace.call("_focus_selected_country")
	if not _require(str(workspace.get("world_mode")) == "country_focus", "法国人物没有保留法国专用九大区"):
		return

	workspace.queue_free()
	get_tree().quit(0)


func _settle_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("Holographic workspace release probe: " + message)
	get_tree().quit(1)
	return false
