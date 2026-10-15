class_name FormalPersonTravel
extends RefCounted
## Host travel owns journeys; the named-person overlay owns the actual place.
## Passenger permission, fares and seats are explicit content, never cargo edges.

var error: String = ""
var _world_ref: WeakRef
var _world: WorldState:
	get: return _world_ref.get_ref() as WorldState
var _routes: Dictionary = {}
var _journeys: Dictionary = {}
var _actions: Dictionary = {}
var _shared_entries: Dictionary = {}
var _npc_policies: Array[Dictionary] = []
var _arrival_notices: Array[Dictionary] = []
var _carry_limits: Dictionary = {}

func bind(world: WorldState) -> void:
	_world_ref = weakref(world)

func configure(routes: Array) -> bool:
	var candidate: Dictionary = {}
	for raw: Variant in routes:
		if not raw is Dictionary or not _valid_route(raw) or candidate.has(raw["id"]):
			return _fail("Invalid explicit passenger connection")
		candidate[raw["id"]] = raw.duplicate(true)
	for id: String in _routes:
		if not candidate.has(id): return _fail("Passenger permission still owns journey responsibilities")
		var before := (_routes[id] as Dictionary).duplicate(true)
		var after := (candidate[id] as Dictionary).duplicate(true)
		before.erase("known_to")
		after.erase("known_to")
		if before != after: return _fail("Active passenger terms cannot be rebound")
		for person: String in _routes[id]["known_to"]:
			if not candidate[id]["known_to"].has(person): return _fail("Known passenger permission cannot be withdrawn implicitly")
	_routes = candidate
	return true

func configure_mobility(value: Dictionary) -> bool:
	if not VNextNamedPersonOverlay.valid_mobility_configuration(value): return _fail("Invalid passenger development configuration")
	var routes: Array[Dictionary] = []
	var portable: Array[String] = []
	var units: int = 0
	for good: String in value["carry_limits"]:
		if good.begins_with("native:") and int(value["carry_limits"][good]) > 0:
			portable.append(good.trim_prefix("native:"))
			units += int(value["carry_limits"][good])
	for passage: Dictionary in value["passages"]:
		routes.append({"id": passage["id"], "from_place_id": passage["from_place_id"], "to_place_id": passage["to_place_id"], "source_link_id": passage["source_link_id"], "minutes": passage["minutes"], "fare": passage["fee"], "payee_account_id": passage["payee_account_id"], "seats": 8, "portable_goods": portable.duplicate(), "carry_units": maxi(1, units), "known_to": passage["known_to"].duplicate(), "basis": "DEVELOPMENT_PASSENGER_PERMISSION"})
		if passage.has("shared_capacity"): routes.back()["shared_capacity"] = passage["shared_capacity"].duplicate(true)
	for policy: Dictionary in value["npc_policies"]:
		if not _world.person_overlay.has_person(policy["person_id"]): return _fail("Passenger policy requires a real host person")
	if not configure(routes): return false
	_npc_policies.assign(value["npc_policies"].duplicate(true))
	_arrival_notices.assign(value["arrival_notices"].duplicate(true))
	_carry_limits = value["carry_limits"].duplicate(true)
	return true

func _valid_route(row: Dictionary) -> bool:
	if not EconomySliceConfig._fields(row, ["id", "from_place_id", "to_place_id", "source_link_id", "minutes", "fare", "payee_account_id", "seats", "portable_goods", "carry_units", "known_to", "basis"], ["public_notice", "shared_capacity"]) or not row["known_to"] is Array or not row.get("public_notice", false) is bool: return false
	for field: String in ["id", "from_place_id", "to_place_id", "source_link_id", "payee_account_id"]:
		if not row[field] is String or row[field].is_empty(): return false
	for field: String in ["minutes", "fare", "seats", "carry_units"]:
		if not FormalLedgerState.valid_amount(row[field]): return false
	if int(row["minutes"]) < 1 or int(row["seats"]) < 1 or int(row["carry_units"]) < 1 or row["basis"] != "DEVELOPMENT_PASSENGER_PERMISSION" or not row["portable_goods"] is Array: return false
	if row.has("shared_capacity"):
		var shared: Variant = row["shared_capacity"]
		if not shared is Dictionary or not FormalLedgerState.exact_fields(shared,["unit","numerator","denominator","basis"]) or not shared["unit"] is String or not FormalLedgerState.valid_amount(shared["numerator"]) or shared["numerator"]<1 or not FormalLedgerState.valid_amount(shared["denominator"]) or shared["denominator"]<1 or shared["basis"]!="EXPLICIT_DEVELOPMENT_COMMON_PASSAGE" or (_world.economy_r1!=null and not _world.economy_r1._shared.passenger_unit_known(row["source_link_id"],shared["unit"])): return false
	var people: Dictionary = {}
	for person: Variant in row["known_to"]:
		if not person is String or not _world.person_overlay.has_person(person) or people.has(person): return false
		people[person] = true
	var goods: Dictionary = {}
	for good: Variant in row["portable_goods"]:
		if not good is String or good.is_empty() or goods.has(good): return false
		goods[good] = true
	if row["from_place_id"] == row["to_place_id"]: return false
	var link := _world.spatial_catalog.get_link(row["source_link_id"])
	var a := VNextSpatialCatalog.map_id_to_place_id(str(link.get("from_map_id", "")))
	var b := VNextSpatialCatalog.map_id_to_place_id(str(link.get("to_map_id", "")))
	return not link.is_empty() and ((a == row["from_place_id"] and b == row["to_place_id"]) or (b == row["from_place_id"] and a == row["to_place_id"])) and _world.population_state.place_support(a) != "UNKNOWN" and _world.population_state.place_support(b) != "UNKNOWN"

func is_present(person: String, place: String) -> bool:
	return _world.person_overlay.is_alive(person) and _world.person_overlay.current_place(person) == place and not is_in_transit(person)

func active(person: String) -> bool:
	return _journeys.get(person, {}).get("status", "") in ["TRAVELLING", "BLOCKED"]

func is_in_transit(person: String) -> bool:
	var trip := _journeys.get(person,{}) as Dictionary
	return trip.get("status")=="TRAVELLING" or trip.get("reason")=="HOST_PERSON_RELOCATION_UNAVAILABLE"

func has_action(id: String) -> bool:
	return _actions.has(id)

func action_count() -> int:
	return _actions.size()

func npc_policy(person: String) -> Dictionary:
	for policy: Dictionary in _npc_policies:
		if policy["person_id"] == person: return policy.duplicate(true)
	return {}

func npc_allowed(person: String) -> bool:
	var policy := npc_policy(person)
	if policy.is_empty() or active(person): return false
	var count: int = 0
	var latest: int = -1
	for action: Dictionary in _actions.values():
		if action["envelope"]["person"] == person and action["result"].get("accepted", false):
			count += 1
			latest = maxi(latest, int(action["result"]["journey"]["departed_minute"]))
	return count < int(policy["max_trips"]) and (latest < 0 or _world.game_clock.total_minutes()-latest >= int(policy["cooldown_days"])*1440)

func arrival_notices(place: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for notice: Dictionary in _arrival_notices:
		if notice["place_id"] == place: result.append(notice.duplicate(true))
	return result

func configure_notices(notices: Array[Dictionary]) -> void:
	# New sites add public notices; earlier lawful knowledge remains available.
	for notice: Dictionary in notices:
		if not _arrival_notices.has(notice): _arrival_notices.append(notice.duplicate(true))

func observe_place(person: String) -> void:
	var place := _world.person_overlay.current_place(person)
	if not is_present(person, place): return
	for edge: Dictionary in _routes.values():
		if edge.get("public_notice", false) and edge["from_place_id"] == place and not edge["known_to"].has(person):
			edge["known_to"].append(person)

## Arrival callbacks run after the native day cursor reaches the host boundary.
func notify_arrivals(people: Array[String]) -> void:
	for person: String in people:
		observe_place(person)
		if _world.economy_r1 != null: _world.economy_r1.person_arrived(person)

func view(person: String) -> Dictionary:
	var result := (_journeys.get(person, {}) as Dictionary).duplicate(true)
	if not result.is_empty():
		var estimate: int = int(result["next_minute"])
		for index: int in range(int(result["leg_index"])+1, result["route_ids"].size()): estimate += int(_routes[result["route_ids"][index]]["minutes"])
		result["earliest_arrival_minute"] = estimate if result["status"] != "BLOCKED" else null
		result["eta_guaranteed"] = result["status"] == "ARRIVED"
		var edge: Dictionary=_routes[result["route_ids"][mini(int(result["leg_index"]),result["route_ids"].size()-1)]]
		if edge.has("shared_capacity"):
			result["shared_capacity"]={"link_id":edge["source_link_id"],"unit":edge["shared_capacity"]["unit"],"amount":float(edge["shared_capacity"]["numerator"])/float(edge["shared_capacity"]["denominator"]),"entered":_shared_entries.has("passenger_entry:"+str(result["id"])+":"+str(result["leg_index"]))}
		result["next_stage_remaining_minutes"] = maxi(0, int(result["next_minute"])-_world.game_clock.total_minutes())
		result["remaining_minutes"] = maxi(0, estimate-_world.game_clock.total_minutes()) if result["status"] != "BLOCKED" else -1
	return result

func quote(person: String, destination: String) -> Dictionary:
	var origin := _world.person_overlay.current_place(person)
	if not _world.person_overlay.is_alive(person) or origin == destination or active(person): return {}
	# A small explicit passenger graph; no freight permission or national search.
	var queue: Array[Dictionary] = [{"place": origin, "route_ids": []}]
	var seen: Dictionary = {origin: true}
	while not queue.is_empty() and seen.size() <= 64:
		var node := queue.pop_front() as Dictionary
		if node["route_ids"].size() >= 6: continue
		for id: String in _routes:
			var edge := _routes[id] as Dictionary
			if not edge["known_to"].has(person) or edge["from_place_id"] != node["place"] or seen.has(edge["to_place_id"]): continue
			var path: Array = node["route_ids"].duplicate()
			path.append(id)
			if edge["to_place_id"] == destination:
				var duration: int = 0
				var cost: int = 0
				for leg: String in path:
					duration += int(_routes[leg]["minutes"])
					cost += int(_routes[leg]["fare"])
				return {"from_place_id": origin, "to_place_id": destination, "route_ids": path, "minutes": duration, "fare": cost, "earliest_arrival_minute": _world.game_clock.total_minutes()+duration, "basis": "DEVELOPMENT_PASSENGER_PERMISSION"}
			seen[edge["to_place_id"]] = true
			queue.append({"place": edge["to_place_id"], "route_ids": path})
	return {}

func destinations(person: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for edge: Dictionary in _routes.values():
		if not edge["known_to"].has(person) or seen.has(edge["to_place_id"]): continue
		seen[edge["to_place_id"]] = true
		var offer := quote(person, edge["to_place_id"])
		if not offer.is_empty(): result.append(offer)
	return result

## Acquisition into luggage uses explicit passenger carrying terms. A later
## journey still checks every actual segment, including its stricter limits.
func can_carry_extra(person: String, good: String, quantity: int) -> bool:
	var carried := _world.personal_economy_state.native_usable_inventory(person, true)
	carried[good] = int(carried.get(good, 0)) + quantity
	if not _carry_limits.is_empty():
		for item: String in carried:
			if int(carried[item]) > int(_carry_limits.get("native:" + item, 0)): return false
	for route: Dictionary in _routes.values():
		if not route["known_to"].has(person): continue
		var amount: int = 0
		var permitted: bool = true
		for item: String in carried:
			if int(carried[item]) > 0 and not route["portable_goods"].has(item): permitted = false
			amount += int(carried[item])
		if permitted and amount <= int(route["carry_units"]): return true
	return false

func _entry_reason(edge: Dictionary, person: String) -> String:
	if not _world.person_overlay.is_alive(person): return "HOST_PERSON_UNAVAILABLE"
	if _world.spatial_world.effective_capacity(edge["source_link_id"]) <= 0.0: return "PASSENGER_CONNECTION_CLOSED"
	var passengers: int = 0
	for other: String in _journeys:
		var trip := _journeys[other] as Dictionary
		if other != person and (trip["status"] == "TRAVELLING" or trip["reason"]=="HOST_PERSON_RELOCATION_UNAVAILABLE") and _routes[trip["route_ids"][int(trip["leg_index"])]]["source_link_id"] == edge["source_link_id"]: passengers += 1
	if passengers >= int(edge["seats"]): return "PASSENGER_SEATS_OCCUPIED"
	if not _carry_limits.is_empty() and not _world.personal_economy_state.can_carry_on_person_trip(person, _carry_limits): return "ITEMS_EXCEED_EXPLICIT_PERSON_CARRY_LIMITS"
	return _world.personal_economy_state.travel_carry_reason(person, edge["portable_goods"], int(edge["carry_units"]))

func _shared_candidate(edge: Dictionary, person: String, journey: String, leg: int) -> Dictionary:
	if not edge.has("shared_capacity"): return {"ok":true,"entries":[]}
	var shared := edge["shared_capacity"] as Dictionary
	if not _world.economy_r1._shared.passenger_window(edge["source_link_id"],shared["unit"]): return {"ok":false,"reason":"PASSENGER_SHARED_WINDOW_CLOSED"}
	var now := _world.game_clock.total_minutes()
	var id := "passenger_entry:"+journey+":"+str(leg)
	if _shared_entries.has(id): return {"ok":false,"reason":"PASSENGER_LEG_ALREADY_ENTERED"}
	var amount := float(shared["numerator"])/float(shared["denominator"])
	var request := {"request_id":id+":"+str(now/60),"link_id":edge["source_link_id"],"window_hour":now/60,"demand":amount}
	var requests: Array[Dictionary] = [request]
	var accepted := _world.spatial_world.request_capacity_batch(requests)
	if not accepted.get("success",false): return {"ok":false,"reason":"PASSENGER_SHARED_REQUEST_REJECTED"}
	var result := _world.spatial_world.reservation_results_batch(requests)
	if not result.get("success",false) or result["results"][request["request_id"]]["allocated_capacity"]+VNextInfrastructureLinkState.CAPACITY_EPSILON<amount:
		_world.spatial_world.cancel_capacity_request(request["request_id"],edge["source_link_id"],now/60)
		return {"ok":false,"reason":"PASSENGER_SHARED_CAPACITY_UNALLOCATED"}
	return {"ok":true,"request":request,"fact":{"id":id,"journey_id":journey,"person_id":person,"leg_index":leg,"route_id":edge["id"],"minute":now,"amount":amount,"unit":shared["unit"]},"entries":[{"adoption_id":id,"request_id":request["request_id"],"link_id":edge["source_link_id"],"window_hour":now/60,"amount":amount,"source_id":journey}]}

func _adopt_shared(candidate: Dictionary) -> bool:
	if candidate["entries"].is_empty(): return true
	var entries: Array[Dictionary] = []
	entries.assign(candidate["entries"])
	if not _world.spatial_world.consume_capacity_batch(entries).get("success",false):
		_world.spatial_world.cancel_capacity_request(candidate["request"]["request_id"],candidate["request"]["link_id"],candidate["request"]["window_hour"])
		return false
	_shared_entries[candidate["fact"]["id"]]=candidate["fact"]
	return true

func start(person: String, destination: String, action_id: String, internal: bool = false) -> Dictionary:
	if action_id.is_empty() or _world.economy_r1 == null or not _world.economy_r1.personal_authorized(person): return {"accepted": false, "reason": "OUTSIDE_ACTIVE_HOST_PERSON_SCOPE"}
	if (internal and not _world.economy_r1.automatic_person(person)) or (not internal and person != _world.player_state.player_id()): return {"accepted": false, "reason": "UNAUTHORIZED_PASSENGER_ACTION"}
	var envelope := {"person": person, "destination": destination}
	if _actions.has(action_id):
		return _actions[action_id]["result"].duplicate(true) if _actions[action_id]["envelope"] == envelope else {"accepted": false, "reason": "ACTION_ID_CONFLICT"}
	var offer := quote(person, destination)
	if offer.is_empty(): return {"accepted": false, "reason": "NO_PASSENGER_ROUTE_OR_ACTIVE_JOURNEY"}
	if internal:
		var policy := npc_policy(person)
		if not npc_allowed(person) or int(offer["minutes"]) > int(policy.get("max_minutes", 0)) or int(offer["fare"]) > int(policy.get("max_fee", 0)): return {"accepted": false, "reason": "NO_FINITE_NPC_PASSENGER_AUTHORIZATION"}
	if _world.military_state.active_actions.has(action_id) or (_world.economy_r1 != null and _world.economy_r1.has_economic_action(action_id)): return {"accepted": false, "reason": "DOMAIN_ACTION_ID_CONFLICT"}
	if _world.economy_r1 != null and _world.economy_r1.person_has_resident_service_booking(person): return {"accepted":false,"reason":"ON_SITE_RESIDENT_SERVICE_INTERVAL_ALREADY_BOOKED"}
	if _world.economy_r1 != null and _world.economy_r1.person_has_work_booking(person): return {"accepted": false, "reason": "WORK_INTERVAL_ALREADY_BOOKED"}
	if int(offer["minutes"]) > FormalLedgerState.MAX_AMOUNT-_world.game_clock.total_minutes() or int(offer["fare"]) > FormalLedgerState.MAX_AMOUNT: return {"accepted": false, "reason": "TRAVEL_AMOUNT_OR_TIME_LIMIT"}
	if not _world.personal_economy_state.manages_native(person) and not _world.personal_economy_state.employment(person).is_empty(): return {"accepted": false, "reason": "LEGACY_EMPLOYMENT_REQUIRES_HANDOVER"}
	var reason := _entry_reason(_routes[offer["route_ids"][0]], person)
	if not reason.is_empty(): return {"accepted": false, "reason": reason}
	var account := _world.personal_economy_state.account_id_for_person(person)
	var payments: Array[Dictionary] = []
	for index: int in offer["route_ids"].size():
		var edge := _routes[offer["route_ids"][index]] as Dictionary
		var payee := _world.ledger_state.account(edge["payee_account_id"])
		if payee.is_empty() or payee.get("denomination") != FormalLedgerState.DENOMINATION: return {"accepted": false, "reason": "NO_PASSENGER_PAYEE"}
		if int(edge["fare"]) > 0:
			payments.append({"transaction_id": "travel:fare:"+action_id+":"+str(index), "from_account_id": account, "to_account_id": edge["payee_account_id"], "amount": edge["fare"], "kind": "person_travel", "reference_id": action_id})
	if not payments.is_empty() and not _world.ledger_state.payment_ready("travel:"+action_id,payments,_world.game_clock.total_minutes()): return {"accepted":false,"reason":_world.ledger_state.error}
	var shared := _shared_candidate(_routes[offer["route_ids"][0]],person,action_id,0)
	if not shared["ok"]: return {"accepted":false,"reason":shared["reason"]}
	if not _adopt_shared(shared): return {"accepted":false,"reason":"PASSENGER_SHARED_ADOPTION_FAILED"}
	if not payments.is_empty():
		var paid: bool = _world.ledger_state.batch_payment("travel:"+action_id,payments,_world.game_clock.total_minutes(),{})
		assert(paid) # Same synchronous prechecked accounts; no interleaved action.

	var previous := _journeys.get(person, {}) as Dictionary
	if previous.get("status") == "ARRIVED": _actions[previous["id"]]["completion"] = previous.duplicate(true)
	var first := _routes[offer["route_ids"][0]] as Dictionary
	_journeys[person] = {"id": action_id, "person_id": person, "origin": offer["from_place_id"], "destination": destination, "route_ids": offer["route_ids"], "departed_minute": _world.game_clock.total_minutes(), "leg_index": 0, "status": "TRAVELLING", "next_minute": _world.game_clock.total_minutes()+int(first["minutes"]), "arrived_minute": -1, "reason": "", "paid_fare": offer["fare"]}
	var result := {"accepted": true, "reason": "TRAVEL_STARTED", "journey": view(person)}
	_actions[action_id] = {"envelope": envelope, "result": result.duplicate(true)}
	return result

func next_boundary() -> int:
	var due: int = -1
	for person: String in _journeys:
		if active(person): due = int(_journeys[person]["next_minute"]) if due < 0 else mini(due, int(_journeys[person]["next_minute"]))
	return due

func advance_time() -> Array[String]:
	var now := _world.game_clock.total_minutes()
	var arrived: Array[String] = []
	for person: String in _journeys:
		var trip := _journeys[person] as Dictionary
		if not active(person) or int(trip["next_minute"]) > now: continue
		var edge := _routes[trip["route_ids"][int(trip["leg_index"])]] as Dictionary
		if trip["status"] == "TRAVELLING" or trip["reason"]=="HOST_PERSON_RELOCATION_UNAVAILABLE":
			if not _world.person_overlay.relocate(person, edge["to_place_id"]):
				trip["status"] = "BLOCKED"
				trip["reason"] = "HOST_PERSON_RELOCATION_UNAVAILABLE"
				trip["next_minute"] = now+60
				continue
			trip["leg_index"] = int(trip["leg_index"])+1
			if int(trip["leg_index"]) == trip["route_ids"].size():
				trip["status"] = "ARRIVED"
				trip["arrived_minute"] = now
				trip["next_minute"] = now
				_actions[trip["id"]]["completion"] = trip.duplicate(true)
				arrived.append(person)
				continue
			edge = _routes[trip["route_ids"][int(trip["leg_index"])]]
		var reason := _entry_reason(edge, person)
		if reason.is_empty():
			var shared := _shared_candidate(edge,person,trip["id"],trip["leg_index"])
			if not shared["ok"]: reason=shared["reason"]
			elif not _adopt_shared(shared): reason="PASSENGER_SHARED_ADOPTION_FAILED"
		trip["reason"] = reason
		trip["status"] = "TRAVELLING" if reason.is_empty() else "BLOCKED"
		trip["next_minute"] = now+int(edge["minutes"]) if reason.is_empty() else now+60
	return arrived

func snapshot() -> Dictionary:
	return {"schema_id": "formal_person_travel_v1", "routes": _routes.values().duplicate(true), "journeys": _journeys.duplicate(true), "actions": _actions.duplicate(true), "npc_policies": _npc_policies.duplicate(true), "arrival_notices": _arrival_notices.duplicate(true), "carry_limits": _carry_limits.duplicate(true), "shared_entries":_shared_entries.duplicate(true)}

func _valid_journey(row: Variant, person: String, initial: bool = false) -> bool:
	var fields: Array[String] = ["id", "person_id", "origin", "destination", "route_ids", "departed_minute", "leg_index", "status", "next_minute", "arrived_minute", "reason", "paid_fare"]
	if not row is Dictionary or not EconomySliceConfig._fields(row, fields, ["earliest_arrival_minute", "eta_guaranteed", "next_stage_remaining_minutes", "remaining_minutes", "shared_capacity"]) or not _world.person_overlay.has_person(person) or row["person_id"] != person: return false
	for key: String in ["id", "origin", "destination", "status", "reason"]:
		if not row[key] is String: return false
	if row["id"].is_empty() or row["status"] not in ["TRAVELLING", "BLOCKED", "ARRIVED"] or not row["route_ids"] is Array or row["route_ids"].is_empty() or row["route_ids"].size() > 6: return false
	for key: String in ["departed_minute", "leg_index", "next_minute", "paid_fare"]:
		if not FormalLedgerState.valid_amount(row[key]): return false
	if typeof(row["arrived_minute"]) != TYPE_INT: return false
	var now := _world.game_clock.total_minutes()
	var departed := int(row["departed_minute"])
	var cursor := int(row["leg_index"])
	if departed > now or cursor > row["route_ids"].size(): return false
	var place := str(row["origin"])
	var visited: Dictionary = {place: true}
	var cost: int = 0
	var duration: int = 0
	var elapsed: int = 0
	for index: int in row["route_ids"].size():
		var id: Variant = row["route_ids"][index]
		if not id is String or not _routes.has(id): return false
		var edge := _routes[id] as Dictionary
		if edge["from_place_id"] != place or visited.has(edge["to_place_id"]) or not edge["known_to"].has(person): return false
		place = edge["to_place_id"]
		visited[place] = true
		cost += int(edge["fare"])
		duration += int(edge["minutes"])
		if index < cursor: elapsed += int(edge["minutes"])
	if place != row["destination"] or cost != row["paid_fare"] or cost > FormalLedgerState.MAX_AMOUNT or duration > FormalLedgerState.MAX_AMOUNT-departed: return false
	if row.has("shared_capacity"):
		var shared: Variant=row["shared_capacity"]
		var edge := _routes[row["route_ids"][mini(cursor,row["route_ids"].size()-1)]] as Dictionary
		if not shared is Dictionary or not edge.has("shared_capacity") or not FormalLedgerState.exact_fields(shared,["link_id","unit","amount","entered"]) or not shared["amount"] is float or not shared["entered"] is bool or shared["link_id"]!=edge["source_link_id"] or shared["unit"]!=edge["shared_capacity"]["unit"] or not is_equal_approx(shared["amount"],float(edge["shared_capacity"]["numerator"])/float(edge["shared_capacity"]["denominator"])): return false
		if shared["entered"]!=not _world.spatial_world.capacity_adoption("passenger_entry:"+str(row["id"])+":"+str(mini(cursor,row["route_ids"].size()-1))).is_empty(): return false
	if initial:
		return cursor == 0 and row["status"] == "TRAVELLING" and row["reason"] == "" and row["arrived_minute"] == -1 and int(row["next_minute"]) == departed+int(_routes[row["route_ids"][0]]["minutes"])
	if row["status"] == "ARRIVED":
		if cursor != row["route_ids"].size() or int(row["arrived_minute"]) < departed+duration or int(row["arrived_minute"]) > now or row["next_minute"] != row["arrived_minute"]: return false
	else:
		if cursor >= row["route_ids"].size() or row["arrived_minute"] != -1 or int(row["next_minute"]) <= now or int(row["next_minute"]) <= departed+elapsed: return false
		if row["status"] == "TRAVELLING":
			var leg := _routes[row["route_ids"][cursor]] as Dictionary
			if int(row["next_minute"]) < departed+elapsed+int(leg["minutes"]) or int(row["next_minute"])-now > int(leg["minutes"]): return false
	return true

func _same_journey(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["id", "person_id", "origin", "destination", "route_ids", "departed_minute", "paid_fare"]:
		if a[key] != b[key]: return false
	return true

func restore(value: Dictionary) -> bool:
	if not EconomySliceConfig._fields(value, ["schema_id", "routes", "journeys", "actions", "npc_policies", "arrival_notices", "carry_limits"], ["shared_entries"]) or value["schema_id"] != "formal_person_travel_v1" or not value["routes"] is Array or not value["journeys"] is Dictionary or not value["actions"] is Dictionary or not configure(value["routes"]): return _fail("Invalid host travel snapshot")
	var policies := {"passages": [], "npc_policies": value["npc_policies"], "arrival_notices": value["arrival_notices"], "carry_limits": value["carry_limits"]}
	if not VNextNamedPersonOverlay.valid_mobility_configuration(policies): return _fail("Invalid saved passenger policies")
	for policy: Dictionary in value["npc_policies"]:
		if not _world.person_overlay.has_person(policy["person_id"]): return _fail("Passenger policy has no host person")
	for notice: Dictionary in value["arrival_notices"]:
		if _world.economy_r1 == null or not _world.economy_r1.valid_arrival_notice(notice): return _fail("Arrival notice has no operating subject")
	var paid_ids: Dictionary = {}
	var latest: Dictionary = {}
	for id: Variant in value["actions"]:
		var action: Variant = value["actions"][id]
		if not id is String or not action is Dictionary or not EconomySliceConfig._fields(action, ["envelope", "result"], ["completion"]) or not action["envelope"] is Dictionary or not FormalLedgerState.exact_fields(action["envelope"], ["person", "destination"]) or not action["envelope"]["person"] is String or not action["result"] is Dictionary or action["result"].get("accepted") != true: return _fail("Invalid passenger action history")
		var trip: Variant = action["result"].get("journey")
		# Initial receipts can be older than now. Validate their start, not a future cursor.
		if not _valid_journey(trip, action["envelope"]["person"], true) or trip["id"] != id or trip["destination"] != action["envelope"]["destination"]: return _fail("Passenger action differs from journey")
		if _world.economy_r1 == null or not _world.economy_r1.travel_action_matches(id, trip["person_id"], trip): return _fail("Passenger journey has no accepted formal action")
		var person := str(trip["person_id"])
		if not latest.has(person) or int(latest[person]["departed_minute"]) < int(trip["departed_minute"]): latest[person] = trip
		if action.has("completion") and (not _valid_journey(action["completion"], trip["person_id"]) or action["completion"]["status"] != "ARRIVED" or not _same_journey(action["completion"], trip)): return _fail("Passenger completion differs from its original journey")
		var ids: Array[String] = []
		for index: int in trip["route_ids"].size():
			var edge := _routes[trip["route_ids"][index]] as Dictionary
			if int(edge["fare"]) == 0: continue
			var tx := _world.ledger_state.transaction("travel:fare:"+str(id)+":"+str(index))
			if tx.get("kind") != "person_travel" or tx.get("reference_id") != id or tx.get("amount") != edge["fare"] or tx.get("to_account_id") != edge["payee_account_id"] or tx.get("from_account_id") != _world.personal_economy_state.account_id_for_person(trip["person_id"]) or tx.get("effective_minute") != trip["departed_minute"]: return _fail("Passenger history lost actual payment")
			paid_ids[tx["transaction_id"]] = true
			ids.append(tx["transaction_id"])
		var batch := _world.ledger_state.payment_batch("travel:"+str(id))
		if (not ids.is_empty() and batch != {"transactions": ids, "releases": {}, "minute": trip["departed_minute"]}) or (ids.is_empty() and not batch.is_empty()): return _fail("Passenger fare batch differs from journey")
	for person: Variant in value["journeys"]:
		var row: Variant = value["journeys"][person]
		if not person is String or not _valid_journey(row, person) or not value["actions"].has(row["id"]) or not _same_journey(row, value["actions"][row["id"]]["result"]["journey"]): return _fail("Invalid host journey")
		var cursor := int(row["leg_index"])
		var current := str(row["destination"]) if row["status"] == "ARRIVED" else str(_routes[row["route_ids"][cursor]]["from_place_id"])
		var action := value["actions"][row["id"]] as Dictionary
		if action.has("completion") and (row["status"] != "ARRIVED" or row != action["completion"]): return _fail("Passenger is both in flight and completed")
		if current != _world.person_overlay.current_place(person): return _fail("Passenger place differs from host")
		if row["status"] != "ARRIVED" and _world.economy_r1.person_has_work_booking(person): return _fail("Unfinished journey overlaps booked work")
	for person: String in latest:
		if value["journeys"].get(person, {}).get("id") != latest[person]["id"]: return _fail("Latest passenger responsibility is missing")
	for tx: Dictionary in _world.ledger_state.transactions():
		if tx["kind"] == "person_travel" and not paid_ids.has(tx["transaction_id"]): return _fail("Passenger payment has no real journey")
	if not _restore_shared(value): return _fail("Passenger shared adoption has bad journey, unit or Spatial references")
	_journeys = value["journeys"].duplicate(true)
	_actions = value["actions"].duplicate(true)
	_npc_policies.assign(value["npc_policies"].duplicate(true))
	_arrival_notices.assign(value["arrival_notices"].duplicate(true))
	_carry_limits = value["carry_limits"].duplicate(true)
	return true

func _restore_shared(saved: Dictionary) -> bool:
	var raw: Variant = saved.get("shared_entries",{})
	if not raw is Dictionary: return false
	for id: String in raw:
		var f: Variant = raw[id]
		if not f is Dictionary or not f.get("amount") is float or not FormalLedgerState.exact_fields(f,["id","journey_id","person_id","leg_index","route_id","minute","amount","unit"]) or f["id"]!=id or not saved["actions"].has(f["journey_id"]) or not _routes.has(f["route_id"]) or not FormalLedgerState.valid_amount(f["leg_index"]) or not FormalLedgerState.valid_amount(f["minute"]) or f["minute"]>_world.game_clock.total_minutes(): return false
		var start: Dictionary = saved["actions"][f["journey_id"]]["result"]["journey"]
		if f["person_id"]!=start["person_id"] or f["leg_index"]>=start["route_ids"].size() or f["route_id"]!=start["route_ids"][f["leg_index"]] or f["minute"]<start["departed_minute"] or id!="passenger_entry:"+str(f["journey_id"])+":"+str(f["leg_index"]): return false
		var edge := _routes[f["route_id"]] as Dictionary
		if not edge.has("shared_capacity") or f["unit"]!=edge["shared_capacity"]["unit"] or not is_equal_approx(float(f["amount"]),float(edge["shared_capacity"]["numerator"])/float(edge["shared_capacity"]["denominator"])): return false
		var adoption := _world.spatial_world.capacity_adoption(id)
		if adoption.get("source_id")!=f["journey_id"] or adoption.get("link_id")!=edge["source_link_id"] or adoption.get("window_hour")!=int(f["minute"])/60 or not is_equal_approx(float(adoption.get("amount",-1.0)),float(f["amount"])): return false
	for action: Dictionary in saved["actions"].values():
		var initial := action["result"]["journey"] as Dictionary
		var current: Dictionary = action.get("completion", saved["journeys"].get(initial["person_id"],{}))
		if current.get("id")!=initial["id"]: return false
		var earliest: int=int(initial["departed_minute"])
		for i: int in initial["route_ids"].size():
			var edge := _routes[initial["route_ids"][i]] as Dictionary
			var fact: Dictionary=raw.get("passenger_entry:"+str(initial["id"])+":"+str(i),{})
			if not fact.is_empty():
				if fact["minute"]<earliest or (i==0 and fact["minute"]!=initial["departed_minute"]): return false
				earliest=int(fact["minute"])
				if i==current["leg_index"] and current["status"]=="TRAVELLING" and current["next_minute"]!=earliest+int(edge["minutes"]): return false
			earliest+=int(edge["minutes"])
			if current["status"]=="ARRIVED" and earliest>current["arrived_minute"]: return false
			if not edge.has("shared_capacity"): continue
			var required: bool = i<int(current["leg_index"]) or (i==int(current["leg_index"]) and (current["status"] in ["TRAVELLING","ARRIVED"] or current["reason"]=="HOST_PERSON_RELOCATION_UNAVAILABLE"))
			if raw.has("passenger_entry:"+str(initial["id"])+":"+str(i))!=required: return false
	_shared_entries=raw.duplicate(true)
	return true

func _fail(message: String) -> bool:
	error = message
	return false

func validate_economic_content(native: EconomyR1Slice) -> bool:
	for route: Dictionary in _routes.values():
		if route.has("shared_capacity") and not native._shared.passenger_unit_known(route["source_link_id"],route["shared_capacity"]["unit"]): return _fail("Passenger common resource requires an explicit native link and unit")
	for notice: Dictionary in _arrival_notices:
		if not native.valid_arrival_notice(notice): return _fail("Passenger arrival notice requires an admitted operating subject")
	return true
