class_name WorldPage
extends RefCounted

var _polity: Dictionary = {}
var _place: Dictionary = {}
var _flag: Dictionary = {}
var _profile: Dictionary = {}
var _administration: Dictionary = {}
var _texture: Texture2D = null
var admin_page: int = 0
const ADMIN_PAGE_SIZE: int = 12

func refresh(polity: Dictionary, place: Dictionary, content: WorldPageContent) -> void:
	_polity = polity.duplicate(true)
	_place = place.duplicate(true)
	_profile = content.profile()
	_administration = content.administration()
	_flag = content.flag()
	_texture = content.texture()
	admin_page = 0

func draw_card(shell: MainShell, rect: Rect2) -> void:
	if _polity.is_empty() and _place.is_empty():
		return
	shell.panel(rect, Color(0.016, 0.035, 0.039, 0.98), Color(0.72, 0.62, 0.38, 0.40))
	shell.label(rect.position + Vector2(18.0, 28.0), "PLACE CARD" if not _place.is_empty() else "POLITICAL ENTITY", 10, Color(0.75, 0.71, 0.49))
	var name := str(_place.get("name", _polity.get("name_zh", "")))
	shell.label(rect.position + Vector2(18.0, 60.0), name, 19, Color(0.94, 0.87, 0.65), rect.size.x - 36.0)
	if not _place.is_empty():
		var polity_name := str(_polity.get("name_zh", "未解析 · 原地域引用 " + str(_place.get("parent_country_id", "UNKNOWN"))))
		shell.lines(rect.position + Vector2(18.0, 90.0), [str(_place.get("place_id", "")), "类型：" + str(_place.get("spatial_kind", "")), "政治实体：" + polity_name], rect.size.x - 36.0)
	else:
		shell.lines(rect.position + Vector2(18.0, 90.0), [str(_polity.get("id", "")), "地位：" + str(_polity.get("status", "")), "历史有效期：" + str(_polity.get("valid_from", "")) + "—" + str(_polity.get("valid_to", ""))], rect.size.x - 36.0)
	if _texture != null:
		shell.draw_texture_rect(_texture, Rect2(rect.position.x + 18.0, rect.position.y + 176.0, 90.0, 58.0), false)
		shell.label(rect.position + Vector2(120.0, 198.0), str(_flag.get("flag_type", "")), 10, Color(0.79, 0.83, 0.75), rect.size.x - 140.0)
		shell.label(rect.position + Vector2(120.0, 219.0), "置信度：" + str(_flag.get("confidence", "")), 10)
	shell.button(Rect2(rect.position.x + 18.0, rect.end.y - 39.0, 100.0, 26.0), "放大定位", "map:focus")
	shell.button(Rect2(rect.position.x + 128.0, rect.end.y - 39.0, 112.0, 26.0), "历史行政区", "page:administration", not _administration.is_empty())

func draw_politics(shell: MainShell, rect: Rect2) -> void:
	shell.heading(rect, str(_polity.get("name_zh", "政治观察")), str(_profile.get("brief_zh", "在世界地图中选择政治实体")))
	var lines: Array[String] = []
	for raw_relation: Variant in _polity.get("authority_relations", []) as Array:
		var relation := raw_relation as Dictionary
		lines.append("%s：%s → %s" % [str(relation.get("relation_type", "")), str(relation.get("source_runtime_id", "")), str(relation.get("target_runtime_id", ""))])
	shell.lines(rect.position + Vector2(30.0, 128.0), lines, rect.size.x - 60.0)

func draw_administration(shell: MainShell, rect: Rect2) -> void:
	var caption := str(_administration.get("source_basis", ""))
	if str(_administration.get("schema_id", "")) == "france_administrative_identity_r1":
		# The evidence retains its original review status; it cannot describe
		# the current land model after the separate Paris land pilot admission.
		caption = "1900 年 SGF 名录与官方档案：仅核实 Seine、Seine-et-Oise 身份及首府；不是完整法国名录，历史行政边界与土地归属仍待核实。"
	shell.heading(rect, str(_polity.get("name_zh", "")) + " · " + str(_administration.get("level_name_zh", "历史行政区")), caption)
	var units := _administration.get("runtime_units", []) as Array
	var y := rect.position.y + 128.0
	for index: int in range(admin_page * ADMIN_PAGE_SIZE, mini(units.size(), (admin_page + 1) * ADMIN_PAGE_SIZE)):
		var unit := units[index] as Dictionary
		var text := str(unit.get("name_zh", ""))
		if unit.has("capital_name"):
			text += " · 首府 " + str(unit.capital_name)
		shell.label(Vector2(rect.position.x + 30.0, y), text, 13)
		y += 25.0
	shell.button(Rect2(rect.position.x + 28.0, rect.end.y - 40.0, 82.0, 26.0), "上一页", "admin:previous", admin_page > 0)
	shell.button(Rect2(rect.position.x + 126.0, rect.end.y - 40.0, 82.0, 26.0), "下一页", "admin:next", (admin_page + 1) * ADMIN_PAGE_SIZE < units.size())
	shell.label(Vector2(rect.position.x + 236.0, rect.end.y - 21.0), "历史名称与层级；未提供数字化边界的行政区不绘制现代替代边界。", 10)
