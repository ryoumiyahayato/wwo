extends SceneTree
## Independent contract: N/2 opponents per unit means N*N/2 directed contacts.
## Initial zero ammunition/hold cannot inflict losses or keep a scope awake.
const F = preload("res://experiments/war_resolver/aggregation/fixtures.gd")
var checks: int = 0
var failures: int = 0
var evidence: Array[Dictionary] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)

func fixture(count: int, sleeping: bool) -> F.State:
	var state: F.State = F.battle(count)
	if sleeping:
		for id: String in state.units:
			state.units[id].ammunition = 0.0
			state.units[id].mobility = 0.0
			state.missions[state.units[id].mission_id].posture = "hold"
		state.totals.ammunition = 0.0 # Initial input before Authority admission.
	return state

func physical(state: F.State) -> Dictionary:
	var value: Dictionary = state.snapshot()
	value.erase("counters")
	return value

func run_case(count: int, quota: int, sleeping: bool) -> void:
	var reference: F.State = fixture(count, sleeping)
	var normal: F.Authority = F.Authority.new()
	normal.configure(reference)
	check(normal.advance(30.0).ok, "synchronous reference completes")
	var state: F.State = fixture(count, sleeping)
	var owner: F.Authority = F.Authority.new()
	owner.configure(state)
	var first: Dictionary = owner.advance_bounded(30.0, quota)
	check(first.ok and first.status == "PENDING" and state.time == 0.0, "first yield retains committed initial time")
	var result: Dictionary = first
	var calls: int = 1
	var largest: int = int(first.wall_usec)
	var bounded: bool = int(first.work_units) <= quota
	while calls < 5000000 and result.ok and result.status == "PENDING":
		result = owner.advance_bounded(30.0, quota)
		calls += 1
		largest = maxi(largest, int(result.wall_usec))
		bounded = bounded and int(result.work_units) <= quota
	check(result.ok and result.status == "COMPLETE" and state.time == 30.0, "retirement completes at original time")
	check(bounded, "each retirement call obeys counted quota")
	check(physical(state) == physical(reference), "retirement preserves synchronous physical result")
	var expected_contacts: int = count*count/2
	check(state.counters.contacts_resolved == expected_contacts, "all legal directed contacts remain computed")
	var cleanup: int = int(result.get("phase_work_counts", {}).get("release_jobs", 0))
	if sleeping:
		check(state.contacts.is_empty() and state.active_areas.is_empty(), "no-ammo stationary scope actually sleeps")
		check(cleanup >= expected_contacts, "every retired unpublished contact consumes finite cleanup work")
		check(state.totals.ammunition == 0.0 and state.totals.casualties == 0.0, "zero ammunition cannot create fire losses")
	else:
		check(state.contacts.field.size() == expected_contacts, "current published contact diagnostics survive cleanup")
	evidence.append({"units": count, "quota": quota, "sleeping": sleeping, "contacts": expected_contacts,
		"cleanup_work": cleanup, "calls": calls, "max_call_usec": largest, "result": result})

func _initialize() -> void:
	for quota: int in [1, 7, 31]:
		run_case(40, quota, true)
	run_case(400, 31, true)
	run_case(40, 7, false)
	print("RETIREMENT_EVIDENCE_JSON=" + JSON.stringify(evidence))
	print("Task9 retirement: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
