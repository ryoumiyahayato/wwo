class_name RegionProjection
extends RefCounted
## Spherical azimuthal equidistant coordinates in kilometres; no world facts.

const EARTH_RADIUS_KM: float = 6371.0088

static func frame(lon_lat: Vector2) -> Basis:
	var lon := deg_to_rad(lon_lat.x)
	var lat := deg_to_rad(lon_lat.y)
	var east := Vector3(cos(lon), 0.0, -sin(lon))
	var north := Vector3(-sin(lon) * sin(lat), cos(lat), -cos(lon) * sin(lat))
	return Basis(east, north, GlobeProjection.lon_lat_to_unit(lon_lat))

static func lon_lat(unit: Vector3) -> Vector2:
	var point := unit.normalized()
	return Vector2(rad_to_deg(atan2(point.x, point.z)), rad_to_deg(asin(clampf(point.y, -1.0, 1.0))))

static func forward(unit: Vector3, tangent_frame: Basis) -> Vector2:
	var local := tangent_frame.transposed() * unit.normalized()
	var sine := Vector2(local.x, local.y).length()
	var angle := atan2(sine, local.z)
	if sine < 0.0000001:
		return Vector2.ZERO if local.z > 0.0 else Vector2(INF, INF)
	return Vector2(local.x, local.y) * (EARTH_RADIUS_KM * angle / sine)

static func inverse(km: Vector2, tangent_frame: Basis) -> Vector3:
	var distance := km.length()
	if distance < 0.0000001:
		return tangent_frame.z
	var angle := distance / EARTH_RADIUS_KM
	return tangent_frame * Vector3(km.x / distance * sin(angle), km.y / distance * sin(angle), cos(angle))

static func screen_axes(bearing: float) -> Transform2D:
	return Transform2D(Vector2(cos(bearing), sin(bearing)), Vector2(sin(bearing), -cos(bearing)), Vector2.ZERO)

static func world_unit(point: Vector2, center: Vector2, radius: float, orientation: Basis) -> Vector3:
	var xy := (point - center) / radius
	if xy.length_squared() >= 1.0:
		return Vector3.ZERO
	return orientation.transposed() * Vector3(xy.x, -xy.y, sqrt(1.0 - xy.length_squared()))

static func world_scale(unit: Vector3, orientation: Basis, radius: float) -> float:
	# Area-equivalent local metric: orthographic radial and transverse scales
	# differ off-centre. The geometric mean is explicit, not a zoom percentage.
	var depth := (orientation * unit).z
	return EARTH_RADIUS_KM / (radius * sqrt(maxf(depth, 0.000001)))

static func world_bearing(unit: Vector3, orientation: Basis) -> float:
	var north := orientation * frame(lon_lat(unit)).y
	return atan2(north.x, north.y)

static func restore_world(unit: Vector3, pixel: Vector2, center: Vector2, scale: float, bearing: float) -> Dictionary:
	var offset := pixel - center
	var distance_squared := offset.length_squared()
	var metric_radius := EARTH_RADIUS_KM / scale
	var radius_squared := (distance_squared + sqrt(distance_squared * distance_squared + 4.0 * pow(metric_radius, 4.0))) * 0.5
	var radius := sqrt(radius_squared)
	var xy := offset / radius
	var target := Vector3(xy.x, -xy.y, sqrt(maxf(0.000001, 1.0 - xy.length_squared())))
	var north_xy := Vector2(sin(bearing), cos(bearing))
	var north := Vector3(north_xy.x, north_xy.y, -(north_xy.x * target.x + north_xy.y * target.y) / target.z).normalized()
	var east := north.cross(target).normalized()
	var attitude := Basis(east, north, target) * frame(lon_lat(unit)).transposed()
	return {"orientation": attitude, "radius": radius}
