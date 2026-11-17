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
var pose_valid: Callable
var local_regions: Array[Dictionary] = []
var boundary_limited: bool = false
var local_suppressed: bool = false
var viewport_extent := Vector2.ZERO

func enter(unit: Vector3, pixel: Vector2, scale: float, angle: float, viewport_size: Vector2) -> void:
	leave_local()
	local_suppressed=false
	local_regions.clear()
	viewport_extent=viewport_size
	tangent_frame = RegionProjection.frame(RegionProjection.lon_lat(unit))
	origin = pixel
	km_per_pixel = scale
	bearing = angle
	var farthest := 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)]:
		farthest = maxf(farthest, corner.distance_to(pixel) * EXIT_KM_PER_PIXEL)
	extent_km = minf(MAX_EXTENT_KM, farthest + PAN_MARGIN_KM)
	active = true
	fit_requested_scale(viewport_size,pixel)

func project(unit: Vector3) -> Vector2:
	return origin + RegionProjection.screen_axes(bearing) * (RegionProjection.forward(unit, tangent_frame) / km_per_pixel)

func unit_at(pixel: Vector2) -> Vector3:
	var km := RegionProjection.screen_axes(bearing).basis_xform_inv(pixel - origin) * km_per_pixel
	if km.length() > extent_km:
		return Vector3.ZERO
	return RegionProjection.inverse(km, tangent_frame)

func valid_anchor(viewport_size: Vector2) -> Dictionary:
	var pixel := viewport_size*0.5
	var km := RegionProjection.screen_axes(bearing).basis_xform_inv(pixel-origin)*km_per_pixel
	km = km.limit_length(extent_km*0.98)
	var unit := RegionProjection.inverse(km,tangent_frame)
	return {"unit":unit,"pixel":project(unit)}

func enter_local(unit: Vector3, pixel: Vector2, viewport_size: Vector2, place_id: String, minimum_mpp: float = 25.0) -> bool:
	if not active or local_active or place_id.is_empty() or unit.is_zero_approx():
		return false
	var km := RegionProjection.forward(unit, tangent_frame)
	if scale_at(unit) > LOCAL_ENTER_KM_PER_PIXEL:
		return false
	if local_suppressed or local_regions.is_empty(): return false
	local_center_km = km
	local_place_id = place_id
	local_min_km_per_pixel = maxf(MIN_KM_PER_PIXEL,minimum_mpp*.001)
	local_active = true
	if not accepts(origin,km_per_pixel,bearing,viewport_size):
		leave_local()
		return false
	return true

func leave_local() -> void:
	local_active = false
	local_place_id = ""
	local_min_km_per_pixel = LOCAL_MIN_KM_PER_PIXEL
	boundary_limited = false

func local_metric(unit: Vector3) -> Vector2:
	# Same fixed geographic chart as REGION. This is a presentation coordinate,
	# never a persistent territory, population, market or cell identity.
	return RegionProjection.forward(unit, tangent_frame) - local_center_km

func scale_at(unit: Vector3) -> float:
	var angle := acos(clampf(unit.dot(tangent_frame.z), -1.0, 1.0))
	return km_per_pixel * sqrt(sin(angle) / angle) if angle > 0.00001 else km_per_pixel

func pan(delta: Vector2, viewport_size: Vector2) -> void:
	var fraction := allowed_fraction(origin+delta,km_per_pixel,bearing,viewport_size)
	boundary_limited = fraction<0.9999
	# Exponential approach stops before the data edge, without a snap back.
	if boundary_limited and delta.length()>0.0:
		var distance := delta.length()*fraction
		fraction *= 1.0-exp(-distance/32.0)
	origin += delta*fraction
	constrain(viewport_size)

func rotate_at(unit: Vector3, pixel: Vector2, angle: float, viewport_size: Vector2) -> bool:
	var next_bearing := bearing + angle
	var next_origin := pixel - RegionProjection.screen_axes(next_bearing) * (RegionProjection.forward(unit, tangent_frame) / km_per_pixel)
	var fraction := 1.0
	if not accepts(next_origin,km_per_pixel,next_bearing,viewport_size):
		var low := 0.0;var high := 1.0
		for iteration: int in range(12):
			var middle := (low+high)*.5
			var angle_at := bearing+angle*middle
			var origin_at := pixel-RegionProjection.screen_axes(angle_at)*(RegionProjection.forward(unit,tangent_frame)/km_per_pixel)
			if accepts(origin_at,km_per_pixel,angle_at,viewport_size): low=middle
			else: high=middle
		fraction=low
	boundary_limited=fraction<0.9999
	if fraction<=0.0001: return false
	next_bearing=bearing+angle*fraction
	next_origin=pixel-RegionProjection.screen_axes(next_bearing)*(RegionProjection.forward(unit,tangent_frame)/km_per_pixel)
	bearing = next_bearing
	origin = next_origin
	return true

func zoom_at(pixel: Vector2, factor: float, viewport_size: Vector2, picked_unit: Vector3 = Vector3.ZERO, minimum_mpp: float = 2.0, ease_limit: bool = true) -> void:
	var old_scale := km_per_pixel
	var floor_scale := maxf(local_min_km_per_pixel if local_active else MIN_KM_PER_PIXEL,minimum_mpp*.001)
	# Panning into coarse coverage never forcibly zooms the camera backwards.
	floor_scale = minf(old_scale,floor_scale)
	if ease_limit and factor<1.0: factor=lerpf(1.0,factor,maxf(.2,smoothstep(floor_scale,floor_scale*2.0,old_scale)))
	var next_scale := maxf(floor_scale,km_per_pixel*factor)
	if unit_at(pixel).is_zero_approx(): pixel = valid_anchor(viewport_size).pixel
	var next_origin := pixel + (origin - pixel) * old_scale / next_scale
	if not picked_unit.is_zero_approx():
		next_origin = pixel-RegionProjection.screen_axes(bearing)*(RegionProjection.forward(picked_unit,tangent_frame)/next_scale)
	var fraction := allowed_fraction(next_origin,next_scale,bearing,viewport_size)
	boundary_limited=fraction<0.9999
	if boundary_limited:
		# Recompute the anchored pose at each candidate scale; an independent
		# origin interpolation would move the point under the wheel.
		var low := 0.0;var high := 1.0
		for iteration: int in range(12):
			var middle := (low+high)*.5
			var scale_at := lerpf(old_scale,next_scale,middle)
			var origin_at := pixel+(origin-pixel)*old_scale/scale_at
			if not picked_unit.is_zero_approx(): origin_at=pixel-RegionProjection.screen_axes(bearing)*(RegionProjection.forward(picked_unit,tangent_frame)/scale_at)
			if accepts(origin_at,scale_at,bearing,viewport_size): low=middle
			else: high=middle
		next_scale=lerpf(old_scale,next_scale,low)
		next_origin=pixel+(origin-pixel)*old_scale/next_scale
		if not picked_unit.is_zero_approx(): next_origin=pixel-RegionProjection.screen_axes(bearing)*(RegionProjection.forward(picked_unit,tangent_frame)/next_scale)
	km_per_pixel = next_scale
	origin = next_origin
	# Both directions must keep the centre inside this chart's finite domain.
	# The controller performs the WORLD handoff using that same centre.
	constrain(viewport_size)

func constrain(viewport_size: Vector2) -> void:
	# Every viewport corner remains in the finite projected disc. Zooming out
	# exits before this constraint, preserving the reverse transition anchor.
	var center := viewport_size * 0.5
	var available := maxf(0.0, extent_km / km_per_pixel - viewport_size.length() * 0.5)
	origin = center + (origin - center).limit_length(available)

func accepts(at_origin: Vector2, scale: float, angle: float, viewport_size: Vector2) -> bool:
	for corner: Vector2 in [Vector2.ZERO,Vector2(viewport_size.x,0),viewport_size,Vector2(0,viewport_size.y)]:
		if (corner-at_origin).length()*scale>extent_km: return false
	return not pose_valid.is_valid() or bool(pose_valid.call(at_origin,scale,angle,viewport_size))

func allowed_fraction(at_origin: Vector2, scale: float, angle: float, viewport_size: Vector2) -> float:
	# Check the swept path too: a large input cannot tunnel over a data gap.
	var low := 0.0
	for segment: int in range(1,9):
		var high := float(segment)/8.0
		if accepts(origin.lerp(at_origin,high),lerpf(km_per_pixel,scale,high),lerpf(bearing,angle,high),viewport_size):
			low=high
			continue
		for iteration: int in range(12):
			var middle := (low+high)*.5
			if accepts(origin.lerp(at_origin,middle),lerpf(km_per_pixel,scale,middle),lerpf(bearing,angle,middle),viewport_size): low=middle
			else: high=middle
		return low
	return 1.0

func fit_requested_scale(viewport_size: Vector2, pixel: Vector2) -> void:
	# Explicit location/resize only. Interactive motion uses swept constraints.
	viewport_extent=viewport_size
	if accepts(origin,km_per_pixel,bearing,viewport_size): return
	if local_active:
		leave_local()
		local_suppressed=true
	var anchor := RegionProjection.screen_axes(bearing).basis_xform_inv(pixel-origin)*km_per_pixel
	for iteration: int in range(48):
		km_per_pixel*=1.12
		origin=pixel-RegionProjection.screen_axes(bearing)*(anchor/km_per_pixel)
		if accepts(origin,km_per_pixel,bearing,viewport_size): return
