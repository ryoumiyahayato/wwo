class_name GlobeController
extends Node
## Sole map orientation and selection owner; requests never change world facts.

signal view_changed
signal appearance_changed
signal selection_changed
const MIN_ZOOM: float = 0.74
const MAX_ZOOM: float = 9.0
const ZOOM_FACTOR: float = 1.22
const DRAG_THRESHOLD: float = 5.0
const MOTION_EPSILON: float = 0.0005
const DRAG_RADIANS_PER_PIXEL: Vector2 = Vector2(0.006, 0.0048)
const BEARING_RADIANS_PER_PIXEL: float = 0.008
var _orientation: Quaternion = (
	Quaternion(Vector3.RIGHT, -0.18) * Quaternion(Vector3.UP, -0.08)
).normalized()
var zoom: float = 0.86
var initial_framing_pending: bool = true
var selected_polity_id: String = ""
var selected_place_id: String = ""
var hovered_polity_id: String = ""
var hovered_place_id: String = ""
var map_mode: String = "political"
var labels_enabled: bool = false
var strategic_rails_enabled: bool = false
var player_polity_id: String = ""
var economic_mode: String = "fulfillment"
var region_camera := RegionCamera.new()
var _angular_velocity: float = 0.0
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_last: Vector2 = Vector2.ZERO
var _drag_moved: bool = false
var _bearing_dragging: bool = false
var _bearing_anchor := Vector3.ZERO
var _bearing_pixel := Vector2.ZERO

func begin_bearing(unit: Vector3, pixel: Vector2) -> void:
	if unit.is_zero_approx():
		return
	suspend_motion()
	_bearing_anchor = unit.normalized()
	_bearing_pixel = pixel
	_bearing_dragging = true

func _ready() -> void:
	set_process(false)

func observation_basis(viewport_size: Vector2) -> Basis:
	if not region_camera.active: return orientation()
	var camera := region_camera
	var unit := camera.valid_anchor(viewport_size).unit as Vector3
	# Transport the chart frame without longitude seams or a pole-specific reset.
	var transported := Basis(Quaternion(camera.tangent_frame.z,unit))*camera.tangent_frame
	var up_step := camera.project((unit+transported.y*0.0001).normalized())-camera.project(unit)
	var angle := atan2(up_step.x,-up_step.y)
	return Basis(Vector3.BACK,-angle)*transported.transposed()

func orientation() -> Basis:
	return Basis(_orientation)

func _rotate_view(angles: Vector2) -> void:
	# Left multiplication keeps both drag axes in the observer's coordinates,
	# including after a pole crossing. The quaternion is the only attitude state.
	var horizontal := Quaternion(Vector3.UP, angles.x)
	var vertical := Quaternion(Vector3.RIGHT, angles.y)
	_orientation = (vertical * horizontal * _orientation).normalized()

func handle_input(event: InputEvent, globe_rect: Rect2) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT and not button.pressed:
			_bearing_dragging = false
			return false
		if button.pressed and globe_rect.has_point(button.position):
			initial_framing_pending = false
			if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if region_camera.active:
					region_camera.zoom_at(button.position, 1.0 / ZOOM_FACTOR if button.button_index == MOUSE_BUTTON_WHEEL_UP else ZOOM_FACTOR, globe_rect.size)
				else:
					zoom = clampf(zoom * ZOOM_FACTOR if button.button_index == MOUSE_BUTTON_WHEEL_UP else zoom / ZOOM_FACTOR, MIN_ZOOM, MAX_ZOOM)
				view_changed.emit()
				return false
			if button.button_index == MOUSE_BUTTON_LEFT:
				_dragging = true
				_drag_start = button.position
				_drag_last = button.position
				_drag_moved = false
				_angular_velocity = 0.0
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed and _dragging:
			_dragging = false
			set_process(absf(_angular_velocity) > MOTION_EPSILON)
			return not _drag_moved
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _bearing_dragging:
			var angle := motion.relative.x * BEARING_RADIANS_PER_PIXEL
			if is_zero_approx(angle):
				return false
			if region_camera.active:
				region_camera.rotate_at(_bearing_anchor, _bearing_pixel, angle, globe_rect.size)
			else:
				# The viewed anchor is the rotation axis, so its screen point is fixed.
				_orientation = (Quaternion((_orientation * _bearing_anchor).normalized(), angle) * _orientation).normalized()
			view_changed.emit()
			return false
		if _dragging:
			var delta := motion.position - _drag_last
			_drag_last = motion.position
			_drag_moved = _drag_moved or motion.position.distance_to(_drag_start) > DRAG_THRESHOLD
			if region_camera.active:
				region_camera.pan(delta, globe_rect.size)
			else:
				_rotate_view(delta * DRAG_RADIANS_PER_PIXEL)
				_angular_velocity = delta.x * 0.018
			view_changed.emit()
	return false

func _process(delta: float) -> void:
	_rotate_view(Vector2(_angular_velocity * delta, 0.0))
	_angular_velocity = lerpf(_angular_velocity, 0.0, minf(1.0, delta * 6.5))
	view_changed.emit()
	if absf(_angular_velocity) <= MOTION_EPSILON:
		_angular_velocity = 0.0
		set_process(false)

func suspend_motion() -> void:
	_dragging = false
	_bearing_dragging = false
	_angular_velocity = 0.0
	set_process(false)

func select(polity_id: String, place_id: String = "") -> void:
	if selected_polity_id == polity_id and selected_place_id == place_id: return
	selected_polity_id = polity_id
	selected_place_id = place_id
	selection_changed.emit()

func begin_player_view(polity_id: String) -> void:
	player_polity_id = polity_id
	map_mode = "political"
	appearance_changed.emit()

func administrative_map_active() -> bool:
	return map_mode=="political"

func hover(polity_id: String, place_id: String) -> void:
	if hovered_polity_id != polity_id or hovered_place_id != place_id:
		hovered_polity_id = polity_id
		hovered_place_id = place_id
		appearance_changed.emit()

func focus(anchor: Vector3) -> void:
	if anchor.is_zero_approx():
		return
	suspend_motion()
	region_camera.leave_local()
	region_camera.active = false
	var viewed_anchor := _orientation * anchor.normalized()
	_orientation = (Quaternion(viewed_anchor, Vector3.BACK) * _orientation).normalized()
	zoom = maxf(zoom, 1.55)
	view_changed.emit()

func set_map_mode(mode: String) -> void:
	if mode in ["political", "fulfillment", "shortage"]:
		map_mode = mode
		if mode!="political": economic_mode = mode
		appearance_changed.emit()

func toggle_labels() -> void:
	labels_enabled = not labels_enabled
	appearance_changed.emit()

