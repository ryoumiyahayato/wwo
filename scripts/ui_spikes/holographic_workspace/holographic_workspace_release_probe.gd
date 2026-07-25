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
	await _settle_frames(8)
	var coverage := workspace.call("flag_coverage_report") as Dictionary
	var explicit_count := int(coverage.get("explicit_count", 0))
	var generated_count := int(coverage.get("generated_count", 0))
	var unique_signatures := int(coverage.get("unique_signatures", 0))
	if not _require(explicit_count >= 40, "明确配置的1900政治实体数量不足"):
		return
	if not _require(generated_count == explicit_count, "仍有明确政治实体没有生成旗帜纹理"):
		return
	if not _require(unique_signatures == explicit_count, "政治实体旗面仍存在视觉签名重复"):
		return
	var navigation := workspace.call("navigation_coverage_report") as Dictionary
	var total_territories := int(navigation.get("total_territories", 0))
	var classified := int(navigation.get("curated_navigation", 0)) + int(navigation.get("modern_reference", 0)) + int(navigation.get("country_terminal", 0))
	if not _require(total_territories > 0 and classified == total_territories, "政治实体辖区没有全部得到数据等级分类"):
		return
	if not _require(int(navigation.get("curated_navigation", 0)) >= 1, "法兰西专门导航没有被识别"):
		return
	if not _require(int(navigation.get("modern_reference", 0)) > 0, "现代行政参考层没有被明确分类"):
		return
	if not _require(not bool(navigation.get("fully_historical", true)), "现代参考数据被错误标记为完整1900历史GIS"):
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
	if not _require(str(workspace.get("selected_historical_territory_iso")) == "DEU", "德国人物进入本国时没有自动选择德国辖区"):
		return
	var admin1_by_iso := workspace.get("_world_admin1_by_iso") as Dictionary
	var german_regions := admin1_by_iso.get("DEU", []) as Array
	if not _require(not german_regions.is_empty(), "德国一级行政区为空"):
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
