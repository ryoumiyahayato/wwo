extends RefCounted
## Deterministic variable-state generator for vNext politics tests.
## It supplies fixed, bounded external signals rather than a second simulation.


static func normal_input(seed: int, period: int) -> VNextPoliticsPressureInput:
	var low_wave: int = posmod(seed * 17 + period * 29, 16)
	var growth_wave: int = 8 + posmod(seed * 11 + period * 7, 12)
	return VNextPoliticsPressureInput.create(
		30,
		float(low_wave),
		float(posmod(seed * 13 + period * 5, 13)),
		float(posmod(seed * 19 + period * 3, 11)),
		float(posmod(seed * 23 + period * 2, 12)),
		float(growth_wave),
		0.0,
		0.0,
		0.0,
		4.0
	)


static func severe_input() -> VNextPoliticsPressureInput:
	return VNextPoliticsPressureInput.create(
		30,
		90.0,
		95.0,
		85.0,
		90.0,
		-70.0,
		82.0,
		78.0,
		88.0,
		-82.0
	)


static func recovery_input() -> VNextPoliticsPressureInput:
	return VNextPoliticsPressureInput.create(30, 0.0, 0.0, 0.0, 0.0, 12.0)
