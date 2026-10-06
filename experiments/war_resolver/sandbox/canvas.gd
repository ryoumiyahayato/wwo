extends Control
## Glyphs and projection only; rows are stable layout lanes, not simulated Y positions.
var view: Dictionary = {}
var scenario: String = ""
var selected_unit: String = "attack_00"
const BLUE: Color = Color(0.3, 0.7, 1.0)
const RED: Color = Color(1.0, 0.45, 0.4)


func present(observation: Dictionary, scenario_name: String, unit_id: String) -> void:
	view = observation
	scenario = scenario_name
	selected_unit = unit_id
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.10, 0.13))
	if view.is_empty():
		return
	var state: Dictionary = view.state
	var area: Dictionary = state.areas.field
	var left: float = 82.0
	var right: float = size.x - 12.0
	var top: float = 24.0
	var height: float = size.y - top - 8.0
	var font: Font = ThemeDB.fallback_font
	var ids: Array[String] = []
	for id: String in state.units:
		ids.append(id)
	ids.sort()
	# Terrain symbols describe the scenario. Resolver terrain is uniform per area.
	if scenario == "road_bottleneck":
		draw_rect(Rect2(left, top, right - left, height), Color(0.24, 0.22, 0.17))
		draw_line(Vector2(left, top + height * 0.5), Vector2(right, top + height * 0.5), Color(0.5, 0.46, 0.32), 6.0)
	elif scenario == "village_edge":
		for block: int in range(4):
			draw_rect(Rect2(left + float(block) * (right - left) / 4.0 + 5.0, top, 32.0, height), Color(0.22, 0.23, 0.25))
	elif scenario == "covered_defense":
		for tree: int in range(10):
			draw_circle(Vector2(left + float(tree) * (right - left) / 10.0 + 8.0, top + height * 0.5), 12.0, Color(0.12, 0.25, 0.16))
	for cell: int in range(11):
		var x: float = lerpf(left, right, float(cell) / 10.0)
		draw_line(Vector2(x, top), Vector2(x, size.y - 8.0), Color(0.22, 0.28, 0.32))
		if cell % 2 == 0:
			draw_string(font, Vector2(x - 6.0, 13.0), str(float(cell) / 2.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	for index: int in range(ids.size()):
		var id: String = ids[index]
		var unit: Dictionary = state.units[id]
		var mission: Dictionary = state.missions[unit.mission_id]
		var track: Dictionary = view.observation.tracks[id]
		var y: float = top + (float(index) + 0.5) * height / float(ids.size())
		var color: Color = BLUE if unit.side == "blue" else RED
		draw_string(font, Vector2(3.0, y + 4.0), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
		draw_line(Vector2(left, y), Vector2(right, y), Color(0.17, 0.21, 0.24))
		for position: float in track.trail:
			draw_circle(Vector2(lerpf(left, right, position / float(area.size_km)), y), 1.5, Color(color, 0.25))
		var goal: float = lerpf(left, right, float(mission.objective) / float(area.size_km))
		draw_rect(Rect2(goal - 2.0, y - 5.0, 4.0, 10.0), Color(0.95, 0.84, 0.3), false)
		var x: float = lerpf(left, right, float(unit.position) / float(area.size_km))
		draw_circle(Vector2(x, y), 4.0, color)
		if id == selected_unit:
			draw_arc(Vector2(x, y), 7.0, 0.0, TAU, 20, Color.WHITE, 1.0)
		if float(unit.effective) <= 0.001:
			draw_line(Vector2(x - 4.0, y - 4.0), Vector2(x + 4.0, y + 4.0), Color.WHITE)
		draw_line(Vector2(x - 5.0, y + 5.0), Vector2(x - 5.0 + float(unit.suppression) * 10.0, y + 5.0), Color(1.0, 0.7, 0.2), 2.0)
		if float(track.last_direction) != 0.0:
			draw_line(Vector2(x, y), Vector2(x + float(track.last_direction) * 10.0, y), color)
