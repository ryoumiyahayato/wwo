extends RefCounted
## Deterministic variable-state generator for vNext politics tests.
## It supplies fixed, bounded external signals rather than a second simulation.


static func normal_input(seed: int, period: int, period_days: int = 30) -> VNextPoliticsPressureInput:
	var low_wave: int = posmod(seed * 17 + period * 29, 16)
	var growth_wave: int = 8 + posmod(seed * 11 + period * 7, 12)
	return VNextPoliticsPressureInput.create(
		period_days,
		float(low_wave),
		float(posmod(seed * 13 + period * 5, 13)),
		float(posmod(seed * 19 + period * 3, 11)),
		float(posmod(seed * 23 + period * 2, 12)),
		float(growth_wave),
		0.0, 0.0, 0.0, 4.0
	)


static func severe_input(period_days: int = 30) -> VNextPoliticsPressureInput:
	return VNextPoliticsPressureInput.create(
		period_days, 90.0, 95.0, 85.0, 90.0, -70.0, 82.0, 78.0, 88.0, -82.0
	)


static func economic_crisis_input(period_days: int = 30) -> VNextPoliticsPressureInput:
	return VNextPoliticsPressureInput.create(
		period_days, 92.0, 96.0, 88.0, 90.0, -72.0, 0.0, 0.0, 0.0, 0.0
	)


static func war_crisis_input(period_days: int = 30) -> VNextPoliticsPressureInput:
	return VNextPoliticsPressureInput.create(
		period_days, 8.0, 10.0, 52.0, 18.0, -8.0, 96.0, 88.0, 92.0, -80.0
	)


static func recovery_input(period_days: int = 30) -> VNextPoliticsPressureInput:
	return VNextPoliticsPressureInput.create(period_days, 0.0, 0.0, 0.0, 0.0, 14.0, 0.0, 0.0, 0.0, 8.0)
