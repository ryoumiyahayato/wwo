extends Node

const MENU_SCENE := "res://scenes/v2_3/v2_3_life_loop_menu.tscn"
const MAIN_SCENE := "res://scenes/v2_3/v2_3_life_loop_main.tscn"


func _ready() -> void:
	_run_probe.call_deferred()


func _run_probe() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var menu_packed := load(MENU_SCENE) as PackedScene
	if not _require(menu_packed != null, "标题场景无法加载"):
		return
	var menu := menu_packed.instantiate() as Control
	add_child(menu)
	await _settle_frames(4)
	if not _require(str(menu.get_node("Center/Content/TitleLabel").get("text")) == "1900", "标题不是1900"):
		return
	if not _require(str(menu.get_node("Center/Content/VersionLabel").get("text")) == "V0.001", "版本不是V0.001"):
		return
	var legacy_card := menu.get_node_or_null("Center/Card") as Control
	if not _require(legacy_card != null and not legacy_card.visible, "旧按钮兼容节点没有隐藏"):
		return
	var enter_event := InputEventKey.new()
	enter_event.keycode = KEY_SPACE
	enter_event.pressed = true
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	if not _require(bool(menu.call("accepts_entry_event", enter_event)), "普通按键没有被接受为进入输入"):
		return
	if not _require(not bool(menu.call("accepts_entry_event", escape_event)), "Escape错误地被接受为进入输入"):
		return
	menu.queue_free()
	await _settle_frames(3)
	get_tree().set_meta(&"v2_3_launch_mode", "new")
	var main_packed := load(MAIN_SCENE) as PackedScene
	if not _require(main_packed != null, "正式主场景无法加载"):
		return
	var main := main_packed.instantiate() as Control
	add_child(main)
	await _settle_frames(20)
	var interface := main.get_node_or_null("PrototypeInterface") as Control
	if not _require(interface != null, "正式玩家界面缺失"):
		return
	var overlay := interface.get_node_or_null("MinimalHudOverlay") as Control
	if not _require(overlay != null, "极简HUD覆盖层缺失"):
		return
	if not _require(str(overlay.call("_home_country_key")).contains("fra"), "法国人物没有得到法国国家徽记"):
		return
	if not _require(str(overlay.call("_role_category")) in ["worker", "official", "farmer", "merchant", "intellectual", "royal"], "人物身份图标分类无效"):
		return
	if not _require(not (overlay.call("_left_page_lines") as Array).is_empty(), "事务书左页没有内容"):
		return
	if not _require(not (overlay.call("_right_page_lines") as Array).is_empty(), "事务书右页没有愿景内容"):
		return
	overlay.call("set_field_book_open", true)
	await _settle_frames(25)
	if not _require(bool(overlay.get("field_book_open")) and float(overlay.get("field_book_progress")) > 0.90, "事务书没有展开到中央"):
		return
	overlay.call("set_field_book_open", false)
	await _settle_frames(25)
	if not _require(not bool(overlay.get("field_book_open")) and float(overlay.get("field_book_progress")) < 0.10, "事务书没有收回屏幕边缘"):
		return
	main.queue_free()
	get_tree().quit(0)


func _settle_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("V2.3 entry HUD probe: " + message)
	get_tree().quit(1)
	return false
