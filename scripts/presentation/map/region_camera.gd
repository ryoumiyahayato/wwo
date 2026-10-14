class_name RegionCamera
extends RefCounted
## Finite presentation camera; anchor changes only when entering a new region.

const ENTER_KM_PER_PIXEL: float = 5.5
const EXIT_KM_PER_PIXEL: float = 7.0
const PREWARM_KM_PER_PIXEL: float = 8.5
const MIN_KM_PER_PIXEL: float = 0.002
const LOCAL_ENTER_KM_PER_PIXEL: float = 0.20
const LOCAL_EXIT_KM_PER_PIXEL: float = 0.28
const LOCAL_MIN_KM_PER_PIXEL: float = 0.025
const LOCAL_RADIUS_KM: float = 300.0
const PAN_MARGIN_KM: float = 1500.0
const MAX_EXTENT_KM: float = 9000.0
const PLACE_LABEL_KM_PER_PIXEL: float = 1.5
var active: bool = false
var local_active: bool = false
var local_center_km := Vector2.ZERO
var local_place_id: String = ""
var local_min_km_per_pixel: float = LOCAL_MIN_KM_PER_PIXEL
var tangent_frame := Basis()
var origin := Vector2.ZERO
var km_per_pixel: float = ENTER_KM_PER_PIXEL
var bearing: float = 0.0
var extent_km: float = 6000.0

func enter(unit: Vector3, pixel: Vector2, scale: float, angle: float, viewport_size: Vector2) -> void:
	leave_local()
	tangent_frame = RegionProjection.frame(RegionProjection.lon_lat(unit))
	origin = pixel
	km_per_pixel = scale
	bearing = angle
	var farthest := 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)]:
		farthest = maxf(farthest, corner.distance_to(pixel) * EXIT_KM_PER_PIXEL)
	extent_km = minf(MAX_EXTENT_KM, farthest + PAN_MARGIN_KM)
	active = true

func project(unit: Vector3) -> Vector2:
	return origin + RegionProjection.screen_axes(bearing) * (RegionProjection.forward(unit, tangent_frame) / km_per_pixel)

func unit_at(pixel: Vector2) -> Vector3:
	var km := RegionProjection.screen_axes(bearing).basis_xform_inv(pixel - origin) * km_per_pixel
	if km.length() > extent_km or (local_active and km.distance_to(local_center_km) > LOCAL_RADIUS_KM):
		return Vector3.ZERO
	return RegionProjection.inverse(km, tangent_frame)

func valid_anchor(viewport_size: Vector2) -> Dictionary:
	var pixel := viewport_size*0.5
	var km := RegionProjection.screen_axes(bearing).basis_xform_inv(pixel-origin)*km_per_pixel
	if local_active: km = local_center_km+(km-local_center_km).limit_length(LOCAL_RADIUS_KM*0.98)
	km = km.limit_length(extent_km*0.98)
	var unit := RegionProjection.inverse(km,tangent_frame)
	return {"unit":unit,"pixel":project(unit)}

func enter_local(unit: Vector3, pixel: Vector2, viewport_size: Vector2, place_id: String, minimum_mpp: float = 25.0) -> bool:
	if not active or local_active or place_id.is_empty() or unit.is_zero_approx():
		return false
	var km := RegionProjection.forward(unit, tangent_frame)
	if scale_at(unit) > LOCAL_ENTER_KM_PER_PIXEL:
		return false
	# The whole view must fit before switching. No recentering or boundary clamp
	# is allowed at the handoff, including for unusually large viewports.
	for corner: Vector2 in [Vector2.ZERO, Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)]:
		if corner.distance_to(pixel) * km_per_pixel > LOCAL_RADIUS_KM:
			return false
	local_center_km = km
	local_place_id = place_id
	local_min_km_per_pixel = minf(km_per_pixel,clampf(minimum_mpp*0.001,MIN_KM_PER_PIXEL,LOCAL_MIN_KM_PER_PIXEL))
	local_active = true
	return true

func leave_local() -> void:
	local_active = false
	local_place_id = ""
	local_min_km_per_pixel = LOCAL_MIN_KM_PER_PIXEL

func local_metric(unit: Vector3) -> Vector2:
	# Same fixed geographic chart as REGION. This is a presentation coordinate,
	# never a persistent territory, population, market or cell identity.
	return RegionProjection.forward(unit, tangent_frame) - local_center_km

func scale_at(unit: Vector3) -> float:
	var angle := acos(clampf(unit.dot(tangent_frame.z), -1.0, 1.0))
	return km_per_pixel * sqrt(sin(angle) / angle) if angle > 0.00001 else km_per_pixel

func pan(delta: Vector2, viewport_size: Vector2) -> void:
	origin += delta
	constrain(viewport_size)

func rotate_at(unit: Vector3, pixel: Vector2, angle: float, viewport_size: Vector2) -> bool:
	var next_bearing := bearing + angle
	var next_origin := pixel - RegionProjection.screen_axes(next_bearing) * (RegionProjection.forward(unit, tangent_frame) / km_per_pixel)
	# Reject only the finite-domain edge; never clamp and move the picked anchor.
	var center := next_origin + RegionProjection.screen_axes(next_bearing) * (local_center_km / km_per_pixel)
	for corner: Vector2 in [Vector2.ZERO, Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)]:
		if (corner - next_origin).length() * km_per_pixel > extent_km or (local_active and corner.distance_to(center) * km_per_pixel > LOCAL_RADIUS_KM):
			return false
	bearing = next_bearing
	origin = next_origin
	return true

func zoom_at(pixel: Vector2, factor: float, viewport_size: Vector2) -> void:
	var old_scale := km_per_pixel
	var next_scale := maxf(local_min_km_per_pixel if local_active else MIN_KM_PER_PIXEL, km_per_pixel * factor)
	if unit_at(pixel).is_zero_approx(): pixel = valid_anchor(viewport_size).pixel
	var next_origin := pixel + (origin - pixel) * old_scale / next_scale
	km_per_pixel = next_scale
	origin = next_origin
	# Translation constraints must not veto a legal scale change.
	if factor<1.0: constrain(viewport_size)

func constrain(viewport_size: Vector2) -> void:
	# Every viewport corner remains in the finite projected disc. Zooming out
	# exits before this constraint, preserving the reverse transition anchor.
	var center := viewport_size * 0.5
	if local_active:
		var local_screen := origin + RegionProjection.screen_axes(bearing) * (local_center_km / km_per_pixel)
		var local_available := maxf(0.0, LOCAL_RADIUS_KM / km_per_pixel - viewport_size.length() * 0.5)
		origin += center + (local_screen - center).limit_length(local_available) - local_screen
		return
	var available := maxf(0.0, extent_km / km_per_pixel - viewport_size.length() * 0.5)
	origin = center + (origin - center).limit_length(available)
