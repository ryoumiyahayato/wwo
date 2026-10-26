extends RefCounted
## Fictional symmetric weapon handling, not real ballistics or target-seeking correction.
## No target position, team, health or player identity is accepted by this calculation.
static func cone_radians(speed: float, machinegun: bool) -> float:
	return deg_to_rad((0.22 if machinegun else 0.12)+clampf(absf(speed)/3.8,0.0,1.0)*(0.65 if machinegun else 0.48))

static func shot_axis(axis: Vector3, speed: float, sequence: int, index: int, machinegun: bool) -> Vector3:
	var forward := axis.normalized()
	var reference := Vector3.UP if absf(forward.dot(Vector3.UP))<0.95 else Vector3.RIGHT
	var right := forward.cross(reference).normalized()
	var up := right.cross(forward).normalized()
	# Bounded reproducible disk sampling; advancing only after an accepted physical shot.
	var phase := float(sequence+index*17)*2.399963229728653
	var radius := sqrt(fposmod(float(sequence+index*11)*0.61803398875+0.37,1.0))
	var offset := tan(cone_radians(speed,machinegun))*radius
	return (forward+(right*cos(phase)+up*sin(phase))*offset).normalized()

static func search_yaw(now: float, index: int) -> float:
	# Search around own hull heading, independent of hidden actors and world coordinates.
	return sin(now*0.22+float(index)*0.7)*deg_to_rad(100.0)
