class_name AlphaMapCanvas
extends Control
## Batched Alpha map projection. It stores no world state of its own.

signal object_selected(kind: String, object_id: String)

const MODES: Array[String] = [
	"administration",
	"cities_locations",
	"transport",
	"wages_employment",
	"goods_prices",
	"enterprises_industries",
	"organization_influence",
	"political_control",
	"law_institutions",
	"risk_events",
]
const MODE_LABELS: Dictionary = {
	"administration": "行政区",
	"cities_locations": "城市与地点",
	"transport": "交通",
	"wages_employment": "工资与就业",
	"goods_prices": "商品价格",
	"enterprises_industries": "企业与产业",
	"organization_influence": "组织影响",
	"political_control": "政治控制",
	"law_institutions": "法律与制度",
	"risk_events": "风险与事件",
}

var simulation: AlphaSimulationService
var map_mode: String = "administration"
var selected_object_id: String = ""
var selected_good_id: String = "grain"
var _map_rect := Rect2()
var _cell_size := Vector2.ZERO


func setup(target: AlphaSimulationService) -> void:
	simulation = target
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func set_map_mode(mode: String) -> bool:
	if mode not in MODES:
		return false
	map_mode = mode
	queue_redraw()
	return true


func set_selected_object(object_id: String) -> void:
	selected_object_id = object_id
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and (event as InputEventMouseButton).pressed
	):
		_select_at((event as InputEventMouseButton).position)


func _draw() -> void:
	if simulation == null or size.x < 100.0 or size.y < 100.0:
		return
	_map_rect = Rect2(
		Vector2(24.0, 34.0),
		Vector2(maxf(100.0, size.x - 48.0), maxf(100.0, size.y - 70.0))
	)
	_cell_size = Vector2(_map_rect.size.x / 10.0, _map_rect.size.y / 8.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color("#111821"))
	_draw_cells()
	if map_mode == "transport":
		_draw_routes()
	if map_mode in [
		"cities_locations", "transport", "enterprises_industries",
		"organization_influence", "risk_events",
	]:
		_draw_cities_and_locations()
	_draw_title()


func _draw_cells() -> void:
	var cell_ids: Array[String] = []
	for raw_id: Variant in simulation.world.cells:
		cell_ids.append(str(raw_id))
	cell_ids.sort()
	for cell_id: String in cell_ids:
		var cell: Dictionary = simulation.world.cells[cell_id] as Dictionary
		var rect: Rect2 = _cell_rect(cell)
		draw_rect(rect, _cell_color(cell), true)
		var border_color := Color("#334252")
		var border_width: float = 1.0
		if str(cell.get("country_id", "")) == "country:vesta_union":
			border_color = Color("#4d596c")
		if cell_id == selected_object_id:
			border_color = Color("#f1c75b")
			border_width = 3.0
		draw_rect(rect, border_color, false, border_width)
		if map_mode == "administration":
			var label: String = str(cell.get("region_id", "")).get_slice(":", 1)
			if int(cell.get("grid_x", 0)) % 3 == 0 and int(cell.get("grid_y", 0)) % 2 == 0:
				draw_string(
					ThemeDB.fallback_font,
					rect.position + Vector2(4.0, 15.0),
					label.left(10),
					HORIZONTAL_ALIGNMENT_LEFT,
					rect.size.x - 6.0,
					10,
					Color("#d9dfdf")
				)


func _draw_routes() -> void:
	for raw_route: Variant in simulation.world.routes.values():
		var route: Dictionary = raw_route as Dictionary
		var from_id: String = str(route.get("from_location_id", ""))
		var to_id: String = str(route.get("to_location_id", ""))
		var from_location: Dictionary = simulation.world.locations.get(
			from_id, {}
		) as Dictionary
		var to_location: Dictionary = simulation.world.locations.get(
			to_id, {}
		) as Dictionary
		if from_location.is_empty() or to_location.is_empty():
			continue
		var from_position: Vector2 = _world_to_map(
			from_location.get("world_position", []) as Array
		)
		var to_position: Vector2 = _world_to_map(
			to_location.get("world_position", []) as Array
		)
		var cross_border: bool = bool(route.get("cross_border", false))
		draw_line(
			from_position,
			to_position,
			Color("#d8905d") if cross_border else Color("#8ca7b7"),
			2.4 if cross_border else 1.4,
			true
		)


func _draw_cities_and_locations() -> void:
	for raw_city: Variant in simulation.world.cities.values():
		var city: Dictionary = raw_city as Dictionary
		var point: Vector2 = _world_to_map(city.get("anchor", []) as Array)
		var radius: float = 6.0
		draw_circle(point, radius + 2.0, Color("#121820"))
		draw_circle(point, radius, Color("#f0ce76"))
		draw_string(
			ThemeDB.fallback_font,
			point + Vector2(9.0, 4.0),
			str(city.get("name", "")),
			HORIZONTAL_ALIGNMENT_LEFT,
			100.0,
			13,
			Color("#f4f0de")
		)
	if map_mode != "cities_locations":
		return
	for raw_location: Variant in simulation.world.locations.values():
		var location: Dictionary = raw_location as Dictionary
		var point: Vector2 = _world_to_map(
			location.get("world_position", []) as Array
		)
		draw_circle(point, 2.2, Color("#9fd0bd"))


func _draw_title() -> void:
	draw_string(
		ThemeDB.fallback_font,
		Vector2(24.0, 23.0),
		"地图模式：%s" % str(MODE_LABELS.get(map_mode, map_mode)),
		HORIZONTAL_ALIGNMENT_LEFT,
		340.0,
		15,
		Color("#d8e3df")
	)


func _select_at(position: Vector2) -> void:
	if not _map_rect.has_point(position) or _cell_size == Vector2.ZERO:
		return
	var grid_x: int = clampi(
		int((position.x - _map_rect.position.x) / _cell_size.x), 0, 9
	)
	var grid_y: int = clampi(
		int((position.y - _map_rect.position.y) / _cell_size.y), 0, 7
	)
	for raw_cell: Variant in simulation.world.cells.values():
		var cell: Dictionary = raw_cell as Dictionary
		if (
			int(cell.get("grid_x", -1)) == grid_x
			and int(cell.get("grid_y", -1)) == grid_y
		):
			selected_object_id = str(cell.get("cell_id", ""))
			object_selected.emit("cell", selected_object_id)
			queue_redraw()
			return


func _cell_color(cell: Dictionary) -> Color:
	var region_id: String = str(cell.get("region_id", ""))
	var region: Dictionary = simulation.world.regions.get(region_id, {}) as Dictionary
	match map_mode:
		"wages_employment":
			var wage: float = float(cell.get("wage_index", 100))
			return _gradient(wage, 70.0, 125.0, Color("#5c3d45"), Color("#3f806d"))
		"goods_prices":
			var price: float = float(
				simulation.economy.market_price(region_id, selected_good_id)
			)
			return _gradient(price, 70.0, 450.0, Color("#3a765b"), Color("#8a584e"))
		"enterprises_industries":
			var industry: String = str(cell.get("major_industry", ""))
			var hue: float = float(abs(hash(industry)) % 360) / 360.0
			return Color.from_hsv(hue, 0.42, 0.52)
		"organization_influence":
			return (
				Color("#467067")
				if "loran" in str(cell.get("major_organization_influence", ""))
				else Color("#635b83")
			)
		"political_control":
			return (
				Color("#3f776c")
				if str(cell.get("controller_country_id", "")).contains("loran")
				else Color("#655c86")
			)
		"law_institutions":
			var credit: float = float(region.get("credit_environment", 50))
			return _gradient(credit, 30.0, 90.0, Color("#6f4b4b"), Color("#496f7c"))
		"risk_events":
			var environment: Dictionary = cell.get(
				"security_or_political_environment", {}
			) as Dictionary
			var risk: float = float(environment.get("contested_level", 0.0))
			return Color("#834f4d").lerp(Color("#445d59"), 1.0 - risk)
		"transport":
			var infrastructure: Dictionary = cell.get("infrastructure", {}) as Dictionary
			return Color("#4e6170") if bool(infrastructure.get("rail", false)) else Color("#37454c")
		"cities_locations":
			return Color("#344d4d") if str(cell.get("land_use_or_terrain", "")) == "urban" else Color("#34433c")
		_:
			var region_index: int = _region_index(region_id)
			var palette: Array[Color] = [
				Color("#315c57"), Color("#3f655c"), Color("#4d6656"), Color("#5b624e"),
				Color("#4d526d"), Color("#555878"), Color("#5d5e72"), Color("#655e69"),
			]
			return palette[region_index % palette.size()]


func _cell_rect(cell: Dictionary) -> Rect2:
	return Rect2(
		_map_rect.position + Vector2(
			int(cell.get("grid_x", 0)) * _cell_size.x,
			int(cell.get("grid_y", 0)) * _cell_size.y
		),
		_cell_size
	)


func _world_to_map(world_position: Array) -> Vector2:
	if world_position.size() < 2:
		return _map_rect.position
	return _map_rect.position + Vector2(
		float(world_position[0]) * _cell_size.x,
		float(world_position[1]) * _cell_size.y
	)


func _region_index(region_id: String) -> int:
	var ids: Array[String] = []
	for raw_id: Variant in simulation.world.regions:
		ids.append(str(raw_id))
	ids.sort()
	return maxi(0, ids.find(region_id))


static func _gradient(
	value: float, minimum: float, maximum: float, low: Color, high: Color
) -> Color:
	return low.lerp(
		high, clampf((value - minimum) / maxf(1.0, maximum - minimum), 0.0, 1.0)
	)
