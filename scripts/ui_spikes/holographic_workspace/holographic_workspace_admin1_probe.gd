extends Node

const TARGET_SCENE: String = "res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn"

var workspace: Control


func _ready() -> void:
	_run_probe.call_deferred()


func _run_probe() -> void:
	var packed_scene: PackedScene = load(TARGET_SCENE) as PackedScene
	if not _require(packed_scene != null, "样机场景无法加载"):
		return
	workspace = packed_scene.instantiate() as Control
	if not _require(workspace != null, "样机场景无法实例化"):
		return
	add_child(workspace)
	await _settle_frames(5)

	var admin1_by_iso: Dictionary = workspace.get("_world_admin1_by_iso") as Dictionary
	var admin1_by_id: Dictionary = workspace.get("_world_admin1_by_id") as Dictionary
	if not _require(admin1_by_iso.size() >= 180, "全球一级行政区国家覆盖不足"):
		return
	if not _require(admin1_by_id.size() >= 4000, "全球一级行政区记录不足"):
		return

	var german_records: Array = admin1_by_iso.get("DEU", []) as Array
	if not _require(german_records.size() >= 10, "德国一级行政区没有加载"):
		return
	workspace.set("selected_country_id", "german_empire")
	workspace.call("_focus_selected_country")
	var german_corner_title: String = str(workspace.call("_current_country_corner_title"))
	var german_entity: Dictionary = workspace.call("_current_country_entity") as Dictionary
	if not _require(german_corner_title == "德国", "国家HUD没有显示德意志帝国短名称"):
		return
	if not _require(str(german_entity.get("name_zh", "")) == "德意志帝国", "国家面板没有保留德意志帝国全称"):
		return
	if not _require("帝国" in str(workspace.call("_current_country_corner_subtitle")), "国家HUD没有显示德意志帝国地位"):
		return
	workspace.call("_enter_region")
	if not _require(str(workspace.get("world_mode")) == "historical_entity_focus", "德国没有保持历史政治实体模式"):
		return
	if not _require(str(workspace.get("selected_historical_territory_iso")) == "DEU", "德国单一辖区没有自动选中"):
		return
	if not _require(str(workspace.get("space_level")) == "region", "德国没有进入一级行政区层"):
		return
	var first_german: Dictionary = german_records[0] as Dictionary
	workspace.set("selected_world_admin1_id", str(first_german.get("id", "")))
	workspace.call("_enter_selected_world_admin1")
	if not _require(str(workspace.get("space_level")) == "city", "德国一级行政区没有进入本地层"):
		return
	if not _require((workspace.get("_world_admin1_by_id") as Dictionary).has(str(first_german.get("id", ""))), "德国一级行政区选择记录丢失"):
		return

	workspace.call("_return_to_global_world")
	workspace.set("selected_country_id", "kingdom_of_nepal")
	workspace.call("_focus_selected_country")
	workspace.call("_enter_region")
	if not _require(str(workspace.get("selected_historical_territory_iso")) == "NPL", "尼泊尔单一辖区没有自动选中"):
		return
	var nepal_corner_title: String = str(workspace.call("_current_country_corner_title"))
	var nepal_entity: Dictionary = workspace.call("_current_country_entity") as Dictionary
	if not _require(nepal_corner_title == "尼泊尔", "国家HUD没有显示尼泊尔王国短名称"):
		return
	if not _require(str(nepal_entity.get("name_zh", "")) == "尼泊尔王国", "国家面板没有保留尼泊尔王国全称"):
		return
	var nepal_records: Array = admin1_by_iso.get("NPL", []) as Array
	if not _require(not nepal_records.is_empty(), "尼泊尔没有一级行政区回退数据"):
		return
	if not _require(str(workspace.get("space_level")) == ("city" if nepal_records.size() == 1 else "region"), "尼泊尔层级跳转没有按一级区数量处理"):
		return

	workspace.call("_return_to_global_world")
	workspace.set("selected_country_id", "russian_empire")
	workspace.call("_focus_selected_country")
	if not _require(str(workspace.call("_current_country_corner_title")) == "俄罗斯帝国", "国家HUD没有切换到俄罗斯帝国"):
		return
	var russian_territories: Array = (workspace.get("_history_territories_by_entity") as Dictionary).get("russian_empire", []) as Array
	if not _require(russian_territories.size() >= 12, "俄罗斯帝国没有聚合足够的辖区"):
		return

	workspace.queue_free()
	get_tree().quit(0)


func _settle_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("Holographic workspace admin1 probe: " + message)
	get_tree().quit(1)
	return false
