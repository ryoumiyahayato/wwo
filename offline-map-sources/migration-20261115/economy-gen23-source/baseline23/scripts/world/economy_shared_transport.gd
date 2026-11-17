class_name EconomySharedTransport
extends RefCounted
## Finite explicit departure windows. Spatial owns all link capacity. This object
## owns carrier work, explicit node occupancy and references to irrevocable entries.
var error: String = ""
var bindings: Dictionary = {}
var handling: Dictionary = {}
var entries: Dictionary = {}
var facilities: Dictionary = {} # Explicit node facilities at admitted host sites.
var node_uses: Dictionary = {}
var _active_node_uses: Dictionary = {}
var _node_throughput: Dictionary = {}
var _total_hours: Dictionary = {}
var _hours: Dictionary = {} # Derived by site/day, never a workforce authority.
var _vehicle_usage: Dictionary = {}
var _active_vehicles: Dictionary = {} # Derived live occupancy IDs; historical throughput stays in Spatial.
var _ref: WeakRef

func economy() -> RefCounted:
	return _ref.get_ref() if _ref != null else null

static func valid_configuration(raw: Variant) -> bool:
	if not raw is Array or raw.size() > 32: return false
	var ids: Dictionary = {}
	for r: Variant in raw:
		if not r is Dictionary or not EconomySliceConfig._fields(r, ["edge_id", "source_link_id", "entry_minutes", "weight_unit", "vehicle_id", "vehicle_payload", "handling_site", "handling_hours_per_unit", "basis"], ["window_minutes", "loading_minutes", "travel_minutes", "vehicle_hold_minutes", "node_resources", "legacy_node_limit_basis"]) or ids.has(r["edge_id"]): return false
		for k: String in ["edge_id", "source_link_id", "weight_unit", "vehicle_id", "handling_site", "basis"]:
			if not r[k] is String or r[k].is_empty(): return false
		if not r["entry_minutes"] is Array or r["entry_minutes"].is_empty() or r["entry_minutes"].size() > 256 or not FormalLedgerState.valid_amount(r["vehicle_payload"]) or int(r["vehicle_payload"]) <= 0 or not FormalLedgerState.valid_amount(r["handling_hours_per_unit"]) or int(r["handling_hours_per_unit"]) <= 0: return false
		var timed: bool = r.has("window_minutes") or r.has("loading_minutes") or r.has("travel_minutes") or r.has("vehicle_hold_minutes")
		if timed:
			for k: String in ["window_minutes", "loading_minutes", "travel_minutes", "vehicle_hold_minutes"]:
				if not FormalLedgerState.valid_amount(r.get(k)): return false
			if r["window_minutes"] < 1 or r["window_minutes"] > 60 or r["travel_minutes"] < 1 or r["vehicle_hold_minutes"] < r["loading_minutes"]+r["travel_minutes"]: return false
		if r.has("legacy_node_limit_basis") and r["legacy_node_limit_basis"]!="EXPLICIT_DAILY_BUSINESS_QUANTITY_LIMIT": return false
		if r.has("node_resources"):
			var n: Variant = r["node_resources"]
			if not timed or not n is Dictionary or not FormalLedgerState.exact_fields(n, ["origin_handling", "origin_berth", "destination_handling", "destination_berth", "destination_storage", "unloading_minutes", "unloading_hours_per_unit"]): return false
			for key: String in ["origin_handling", "origin_berth", "destination_handling", "destination_berth", "destination_storage"]:
				if not n[key] is String or n[key].is_empty(): return false
			if not FormalLedgerState.valid_amount(n["unloading_minutes"]) or n["unloading_minutes"] < 1 or not FormalLedgerState.valid_amount(n["unloading_hours_per_unit"]) or n["unloading_hours_per_unit"] < 1: return false
		var last := -1
		for minute: Variant in r["entry_minutes"]:
			if not FormalLedgerState.valid_amount(minute) or int(minute)%60 != 0 or int(minute) <= last: return false
			last = minute
		ids[r["edge_id"]] = true
	return true

static func valid_facilities(raw: Variant) -> bool:
	if not raw is Array or raw.size() > 64: return false
	var ids: Dictionary = {}
	for f: Variant in raw:
		if not f is Dictionary or not EconomySliceConfig._fields(f, ["id","site_id","kind","unit","windows","basis"], ["capital_asset_id", "asset_types"]) or not f["id"] is String or not f["id"].begins_with("facility:") or ids.has(f["id"]) or not f["site_id"] is String or f["kind"] not in ["HANDLING_THROUGHPUT","BERTH_OCCUPANCY","STORAGE_OCCUPANCY"] or not f["unit"] is String or f["unit"].is_empty() or f["basis"] != "EXPLICIT_DEVELOPMENT_TRANSPORT_FACILITY" or not f["windows"] is Array or f["windows"].is_empty() or f["windows"].size() > 256: return false
		if f.has("asset_types") and (not f["asset_types"] is Array or f["asset_types"].is_empty()): return false
		if f.has("capital_asset_id") and (not f["capital_asset_id"] is String or not f["capital_asset_id"].begins_with("capital_asset:")): return false
		var last := -1
		for w: Variant in f["windows"]:
			if not w is Dictionary or not FormalLedgerState.exact_fields(w,["start_minute","end_minute","capacity"]) or not FormalLedgerState.valid_amount(w["start_minute"]) or not FormalLedgerState.valid_amount(w["end_minute"]) or not FormalLedgerState.valid_amount(w["capacity"]) or w["start_minute"] < last or w["end_minute"] <= w["start_minute"] or (f["kind"] == "HANDLING_THROUGHPUT" and (w["start_minute"]%60 != 0 or w["end_minute"]-w["start_minute"] > 60)): return false
			last = int(w["end_minute"])
		ids[f["id"]] = true
	return true

func _node_capacity(id: String, now: int) -> float:
	var f := facilities[id] as Dictionary
	if not economy()._site_operating(f["site_id"]): return 0.0
	if f.has("capital_asset_id"):
		var asset: Dictionary = economy()._capital.assets.get(f["capital_asset_id"], {})
		if asset.get("status") != "ACTIVE" or asset.get("site_id") != f["site_id"]: return 0.0
	for window: Dictionary in f["windows"]:
		if now >= int(window["start_minute"]) and now < int(window["end_minute"]): return float(window["capacity"])
	return 0.0

func _node_used(id: String, now: int) -> float:
	var used := float(_node_throughput.get(id+"|"+str(now/60), 0.0)) if facilities[id]["kind"] == "HANDLING_THROUGHPUT" else 0.0
	for use_id: String in _active_node_uses.keys():
		var use := node_uses[use_id] as Dictionary
		if int(use["end_minute"]) >= 0 and int(use["end_minute"]) <= now: _active_node_uses.erase(use_id); continue
		if use["facility_id"] == id: used += float(use["amount"])-float(use["released_amount"])
	return used+economy()._service_market.shared_occupancy(id,now)

func _node_available(id: String, now: int) -> float:
	return maxf(0.0, _node_capacity(id,now)-_node_used(id,now))

func service_intake_ready(id: String, now: int) -> bool:
	return facilities.has(id) and _node_used(id,now)<=_node_capacity(id,now)+VNextInfrastructureLinkState.CAPACITY_EPSILON

func _node_amount(id: String, good: Variant, quantity_value: int) -> float:
	return float(quantity_value)*weight(good,{"weight_unit":facilities[id]["unit"]})

func _node_use(id: String, shipment_id: String, leg: int, facility: String, good: Variant, quantity_value: int, minute: int, end: int) -> void:
	assert(not node_uses.has(id))
	var amount := _node_amount(facility, good, quantity_value)
	node_uses[id] = {"id":id,"shipment_id":shipment_id,"leg_index":leg,"facility_id":facility,"good":good,"quantity":quantity_value,"amount":amount,"minute":minute,"end_minute":end,"released_amount":0.0,"releases":{}}
	if good is Dictionary:
		node_uses[id].erase("good"); node_uses[id]["asset_id"]=good["asset_id"]
	if facilities[facility]["kind"] == "HANDLING_THROUGHPUT":
		var key := facility+"|"+str(minute/60)
		_node_throughput[key] = float(_node_throughput.get(key,0.0))+amount
	else: _active_node_uses[id] = true

func _storage_use(shipment_id: String) -> String:
	for id: String in _active_node_uses:
		if node_uses[id]["shipment_id"] == shipment_id and facilities[node_uses[id]["facility_id"]]["kind"] == "STORAGE_OCCUPANCY": return id
	return ""

func release_storage(shipment_id: String, good: Variant, quantity_value: int, event_id: String) -> void:
	var id := _storage_use(shipment_id)
	if id.is_empty(): return
	var use := node_uses[id] as Dictionary
	if use["releases"].has(event_id): return
	var amount := _node_amount(use["facility_id"],good,quantity_value)
	assert(amount <= float(use["amount"])-float(use["released_amount"])+VNextInfrastructureLinkState.CAPACITY_EPSILON)
	use["releases"][event_id] = {"amount":amount,"minute":economy()._world.game_clock.total_minutes()}
	use["released_amount"] += amount
	if is_equal_approx(float(use["released_amount"]),float(use["amount"])): _active_node_uses.erase(id)

func _node_entry_limit(binding: Dictionary, good: Variant, now: int) -> int:
	if not binding.has("node_resources"): return FormalLedgerState.MAX_AMOUNT
	var n := binding["node_resources"] as Dictionary
	var result := FormalLedgerState.MAX_AMOUNT
	for key: String in ["origin_handling","origin_berth"]:
		var weight_value := _node_amount(n[key],good,1)
		if weight_value <= 0.0: return 0
		result = mini(result,int(floor(_node_available(n[key],now)/weight_value)))
	return result

## Arrival is at the actual vehicle/node, never an unbounded warehouse.
func arrive(shipment: Dictionary, order: Dictionary) -> bool:
	var r: Dictionary = bindings.get(order["route_legs"][shipment["leg_index"]]["edge_id"], {})
	if not r.has("node_resources"): return true
	var now: int = economy()._world.game_clock.total_minutes()
	var prefix := "node:"+str(shipment["id"])+":"+str(shipment["leg_index"])+":"
	if shipment["stage"] == "UNLOADING": return int(shipment["unloading_end_minute"]) <= now
	var n := r["node_resources"] as Dictionary
	var q := int(shipment["quantity"])
	var hkey := str(economy().day)+"|"+str(r["edge_id"])+"|arrival"
	var h := handling.get(hkey,{}) as Dictionary
	if int(h.get("hours",0))-int(h.get("used",0)) < q*handling_units(load_of(order))*int(n["unloading_hours_per_unit"]): return false
	for key: String in ["destination_handling","destination_berth","destination_storage"]:
		var amount := _node_amount(n[key],load_of(order),q)
		if amount <= 0.0 or amount > _node_available(n[key],now)+VNextInfrastructureLinkState.CAPACITY_EPSILON: return false
	var end := now+int(n["unloading_minutes"])
	for key: String in ["destination_handling","destination_berth","destination_storage"]:
		_node_use(prefix+key,shipment["id"],shipment["leg_index"],n[key],load_of(order),q,now,-1 if key=="destination_storage" else end)
	h["used"] += q*handling_units(load_of(order))*int(n["unloading_hours_per_unit"])
	shipment["unloading_end_minute"] = end
	shipment["stage"] = "UNLOADING"
	return false

func labor_needed_arrival(edge_id: String) -> int:
	var e := economy()
	var r := bindings[edge_id] as Dictionary
	if not r.has("node_resources"): return 0
	var total := 0
	for id: String in e._moving_shipments:
		var c := e._shipments[id] as Dictionary
		var o := e._orders[c["order_id"]] as Dictionary
		if o["route_legs"][c["leg_index"]]["edge_id"] == edge_id and c["stage"] in ["TRANSIT","LOADING","WAITING_UNLOAD"]:
			total += int(c["quantity"])*int(r["node_resources"]["unloading_hours_per_unit"])
	for id: String in e._pending_orders:
		var o := e._orders[id] as Dictionary
		if o["route_legs"][0]["edge_id"]!=edge_id: continue
		var q: int = e._lots.quantity_at("PERSON|"+str(o["buyer"])+"|FREIGHT|"+str(o["id"]),o["good"]) if o["kind"]=="PERSONAL_FREIGHT" else e._lots.reserved_quantity(id)
		total += mini(int(o["pending"]),q)*int(r["node_resources"]["unloading_hours_per_unit"])
	return total+e._capital_transport.needed(edge_id,true)*int(r["node_resources"]["unloading_hours_per_unit"])

func bind(e: RefCounted) -> bool:
	_ref = weakref(e)
	if not valid_configuration(e.config.get("shared_transport", [])) or not valid_facilities(e.config.get("transport_facilities", [])): return false
	for f: Dictionary in e.config.get("transport_facilities", []):
		if not e._spec["sites"].has(f["site_id"]): return false
		facilities[f["id"]] = f.duplicate(true)
	for r: Dictionary in e.config.get("shared_transport", []):
		var edge: Dictionary = e._all_routes().get(r["edge_id"], {})
		var site: Dictionary = e._spec["sites"].get(r["handling_site"], {})
		if edge.is_empty() or site.is_empty() or e._owner(r["handling_site"]) != edge.get("carrier") or e._place(r["handling_site"]) != edge["from_place_id"] or not e._world.spatial_catalog.has_link(r["source_link_id"]): return false
		var link: Dictionary = e._world.spatial_catalog.get_link(r["source_link_id"])
		var origin := str(link.get("from_place_id", VNextSpatialCatalog.map_id_to_place_id(str(link.get("from_map_id", "")))))
		var destination := str(link.get("to_place_id", VNextSpatialCatalog.map_id_to_place_id(str(link.get("to_map_id", "")))))
		if not ((origin == edge["from_place_id"] and destination == edge["to_place_id"]) or (destination == edge["from_place_id"] and origin == edge["to_place_id"])): return false
		for other: Dictionary in bindings.values():
			if other["vehicle_id"] == r["vehicle_id"] and (other["vehicle_payload"] != r["vehicle_payload"] or other["weight_unit"] != r["weight_unit"]): return false
			if other["vehicle_id"] == r["vehicle_id"] and other.has("vehicle_hold_minutes") != r.has("vehicle_hold_minutes"): return false
		if r.has("node_resources"):
			for node: Dictionary in e.config.get("transport_nodes",[]):
				if node["place_id"] in [edge["from_place_id"],edge["to_place_id"]] and r.get("legacy_node_limit_basis")!="EXPLICIT_DAILY_BUSINESS_QUANTITY_LIMIT":
					error="A mapped physical node requires an explicit distinct basis for its legacy daily limit"
					return false
			for key: String in ["origin_handling","origin_berth","destination_handling","destination_berth","destination_storage"]:
				var f: Dictionary = facilities.get(r["node_resources"][key], {})
				var expected := "HANDLING_THROUGHPUT" if key.ends_with("handling") else "BERTH_OCCUPANCY" if key.ends_with("berth") else "STORAGE_OCCUPANCY"
				if f.is_empty() or f["kind"] != expected or e._place(f["site_id"]) != edge["from_place_id" if key.begins_with("origin") else "to_place_id"]: return false
			if facilities[r["node_resources"]["origin_handling"]]["site_id"] != r["handling_site"]: return false
		bindings[r["edge_id"]] = r.duplicate(true)
	return true

func alias_requires_binding(edge_id: String) -> bool:
	if bindings.has(edge_id): return false
	var edge: Dictionary = economy()._all_routes().get(edge_id, {})
	for binding: Dictionary in bindings.values():
		if edge.get("source_link_id", "") == binding["source_link_id"]: return true
	return false

func window_open(binding: Dictionary, now: int) -> bool:
	for start: int in binding["entry_minutes"]:
		if binding.has("window_minutes"):
			if now >= start and now < start+int(binding["window_minutes"]): return true
		elif now == start: return true
	return false

func _vehicle_available(binding: Dictionary, now: int) -> float:
	var used := float(_vehicle_usage.get(str(binding["vehicle_id"])+"|"+str(now/60), 0.0))
	if binding.has("vehicle_hold_minutes"):
		used = 0.0
		for id: String in _active_vehicles.keys():
			var a := entries[id] as Dictionary
			var cargo: Dictionary = cargo(a["shipment_id"])
			var aboard: bool = bindings[a["edge_id"]].has("node_resources") and cargo.get("leg_index") == a["leg_index"] and cargo.get("stage") in ["LOADING","TRANSIT","WAITING_UNLOAD","UNLOADING"]
			if maxi(int(a["release_minute"]),node_completion_minute(a["shipment_id"],a["leg_index"])) <= now and not aboard: _active_vehicles.erase(id); continue
			if a["vehicle_id"] == binding["vehicle_id"]: used += float(a["quantity"])*weight(load_of(a), bindings[a["edge_id"]])
	return maxf(0.0, float(binding["vehicle_payload"])-used)

func next_boundary(after: int) -> int:
	var e := economy()
	var next := -1
	var active_edges: Dictionary = {}
	for id: String in e._pending_orders:
		var o := e._orders[id] as Dictionary
		var edge_id := str(o["route_legs"][0]["edge_id"])
		var earliest := maxi(after+1, e._earliest_dispatch(o)*1440)
		active_edges[edge_id] = mini(int(active_edges.get(edge_id, earliest)), earliest)
	for id: String in e._moving_shipments:
		var cargo := e._shipments[id] as Dictionary
		if cargo["stage"] in ["WAITING", "WAITING_UNLOAD"]:
			var o := e._orders[cargo["order_id"]] as Dictionary
			active_edges[o["route_legs"][cargo["leg_index"]]["edge_id"]] = after+1
		for field: String in ["loading_end_minute", "arrival_minute", "unloading_end_minute"]:
			if cargo.has(field) and int(cargo[field]) > after and (next < 0 or int(cargo[field]) < next): next = int(cargo[field])
	for t: Dictionary in e._capital_transport.tasks.values():
		if t["stage"]=="WAITING": active_edges[e._capital_transport.offer(t["offer_id"])["legs"][t["leg_index"]]["edge_id"]]=after+1
		for field: String in ["loading_end_minute","arrival_minute","unloading_end_minute"]:
			if t[field]>after and (next<0 or t[field]<next): next=t[field]
	for edge_id: String in active_edges:
		if not bindings.has(edge_id): continue
		var r := bindings[edge_id] as Dictionary
		for start: int in r["entry_minutes"]:
			var candidate := maxi(start, int(active_edges[edge_id]))
			if r.has("window_minutes") and candidate > start: candidate = ((candidate+59)/60)*60
			if candidate < after+1 or not window_open(r, candidate): continue
			if next < 0 or candidate < next: next = candidate
	for id: String in _active_vehicles:
		var end := maxi(int(entries[id]["release_minute"]),node_completion_minute(entries[id]["shipment_id"],entries[id]["leg_index"]))
		if end > after and (next < 0 or end < next): next = end
	if not e._moving_shipments.is_empty() or not e._capital_transport.tasks.is_empty():
		for f: Dictionary in facilities.values():
			for w: Dictionary in f["windows"]:
				if int(w["start_minute"]) > after and (next<0 or int(w["start_minute"])<next): next=int(w["start_minute"])
	return next

func _has_window(binding: Dictionary, earliest: int) -> bool:
	for minute: int in binding["entry_minutes"]:
		if minute >= earliest or (binding.has("window_minutes") and minute+int(binding["window_minutes"]) > earliest): return true
	return false

func _needed_hours(edge_id: String) -> int:
	var e := economy()
	var r := bindings[edge_id] as Dictionary
	var total := 0
	var unit := int(r["handling_hours_per_unit"])
	for order_id: String in e._pending_orders:
		var o := e._orders[order_id] as Dictionary
		if o["route_legs"][0]["edge_id"] != edge_id or weight(o["good"], r) <= 0.0: continue
		var physical: int = e._lots.quantity_at("PERSON|"+str(o["buyer"])+"|FREIGHT|"+str(o["id"]), o["good"]) if o["kind"] == "PERSONAL_FREIGHT" else e._lots.reserved_quantity(o["id"])
		var quantity := mini(int(o["pending"]), physical)
		if quantity > (FormalLedgerState.MAX_AMOUNT-total)/unit: return FormalLedgerState.MAX_AMOUNT
		total += quantity*unit
	for cargo_id: String in e._moving_shipments:
		var cargo := e._shipments[cargo_id] as Dictionary
		var o := e._orders[cargo["order_id"]] as Dictionary
		if cargo["stage"] != "WAITING" or o["route_legs"][cargo["leg_index"]]["edge_id"] != edge_id or weight(o["good"], r) <= 0.0: continue
		var quantity := int(cargo["quantity"])
		if quantity > (FormalLedgerState.MAX_AMOUNT-total)/unit: return FormalLedgerState.MAX_AMOUNT
		total += quantity*unit
	return total+e._capital_transport.needed(edge_id,false)*unit

func weight(good: Variant, binding: Dictionary) -> float:
	if good is Dictionary: return economy()._capital_transport.weight(str(good.get("asset_id","")),str(binding["weight_unit"]))
	var e := economy()
	for g: Dictionary in e.config.get("goods", []):
		if g["id"] != good: continue
		var m: Dictionary = g.get("unit_weight", {})
		if m.is_empty() or m["unit"] != binding["weight_unit"] or int(m["numerator"]) <= 0: return -1.0
		return float(m["numerator"])/float(m["denominator"])
	return -1.0 # Unknown weight never becomes zero-weight cargo.

func allocated_hours(site: String, day: int = -1) -> int:
	return int(_total_hours.get(site, 0)) if day < 0 else int(_hours.get(site, {}).get(day, 0))

func prepare_labor(capital_used: Dictionary) -> void:
	var e := economy()
	var used := capital_used.duplicate(true)
	for edge_id: String in bindings:
		var r := bindings[edge_id] as Dictionary
		if not _has_window(r, e._world.game_clock.total_minutes()):
			if r.has("node_resources"): _prepare_arrival_labor(r,used)
			continue
		var id := str(e.day)+"|"+edge_id
		if handling.has(id):
			if r.has("node_resources"): _prepare_arrival_labor(r,used)
			continue
		var wanted := mini(_needed_hours(edge_id), int(e._labor.get(r["handling_site"], 0)))
		var rows: Array[Dictionary] = []
		var hours := 0
		for work_id: String in e._capital_work_ids:
			var work := e._work_records[work_id] as Dictionary
			if e._spec["jobs"][work["job"]]["site_id"] != r["handling_site"]: continue
			var amount := mini(wanted-hours, int(work["hours"])-int(used.get(work_id, 0)))
			if amount <= 0: continue
			rows.append({"work_id": work_id, "hours": amount})
			used[work_id] = int(used.get(work_id, 0))+amount
			hours += amount
			if hours == wanted: break
		handling[id] = {"day": e.day, "edge_id": edge_id, "hours": hours, "used": 0, "work": rows}
		if e._costs.enabled:
			for row: Dictionary in rows: e._costs.assign_work(row["work_id"], row["hours"], "HANDLING", id)
		if not _hours.has(r["handling_site"]): _hours[r["handling_site"]] = {}
		_hours[r["handling_site"]][e.day] = int(_hours[r["handling_site"]].get(e.day, 0))+hours
		_total_hours[r["handling_site"]] = int(_total_hours.get(r["handling_site"], 0))+hours
		e._labor[r["handling_site"]] = int(e._labor.get(r["handling_site"], 0))-hours
		if r.has("node_resources"): _prepare_arrival_labor(r,used)

func _prepare_arrival_labor(r: Dictionary, used: Dictionary) -> void:
	var e := economy()
	var site := str(facilities[r["node_resources"]["destination_handling"]]["site_id"])
	var id := str(e.day)+"|"+str(r["edge_id"])+"|arrival"
	if handling.has(id): return
	var wanted := mini(labor_needed_arrival(r["edge_id"]),int(e._labor.get(site,0)))
	if wanted<=0: return
	var rows: Array[Dictionary] = []
	var hours := 0
	for work_id: String in e._capital_work_ids:
		var work := e._work_records[work_id] as Dictionary
		if e._spec["jobs"][work["job"]]["site_id"] != site: continue
		var amount := mini(wanted-hours,int(work["hours"])-int(used.get(work_id,0)))
		if amount<=0: continue
		rows.append({"work_id":work_id,"hours":amount})
		used[work_id]=int(used.get(work_id,0))+amount
		hours+=amount
		if hours==wanted: break
	handling[id]={"day":e.day,"edge_id":r["edge_id"],"hours":hours,"used":0,"work":rows,"operation":"ARRIVAL"}
	if e._costs.enabled:
		for row: Dictionary in rows: e._costs.assign_work(row["work_id"], row["hours"], "HANDLING", id)
	if not _hours.has(site): _hours[site]={}
	_hours[site][e.day]=int(_hours[site].get(e.day,0))+hours
	_total_hours[site]=int(_total_hours.get(site,0))+hours
	e._labor[site]=int(e._labor.get(site,0))-hours

func quantity(edge_id: String, good: Variant, requested: int) -> int:
	if not bindings.has(edge_id): return requested
	var e := economy()
	var r := bindings[edge_id] as Dictionary
	var now: int = e._world.game_clock.total_minutes()
	if not window_open(r, now) or e._world.spatial_world.current_hour() != now/60 or not e._site_operating(r["handling_site"]): return 0
	var w := weight(good, r)
	if w <= 0.0: return 0
	var h := handling.get(str(e.day)+"|"+edge_id, {}) as Dictionary
	var labor_limit := maxi(0, int(h.get("hours", 0))-int(h.get("used", 0)))/(handling_units(good)*int(r["handling_hours_per_unit"]))
	var payload := _vehicle_available(r, now)
	var available: float = minf(payload, e._world.spatial_world.remaining_capacity(r["source_link_id"]))
	return mini(_node_entry_limit(r,good,now), mini(requested, mini(labor_limit, int(floor(minf(float(requested), available/w))))))

func enter(shipment_id: String, leg_index: int, edge_id: String, good: Variant, quantity_value: int) -> bool:
	if not bindings.has(edge_id): return true
	var e := economy()
	var r := bindings[edge_id] as Dictionary
	var now: int = e._world.game_clock.total_minutes()
	var id := "economy_entry:"+shipment_id+":"+str(leg_index)
	if entries.has(id): return false # Actual leg may enter only once.
	if quantity(edge_id, good, quantity_value) < quantity_value: return false
	var request_id := id+":"+str(now/60)
	var q := float(quantity_value)*weight(good, r)
	var requests: Array[Dictionary] = [{"request_id": request_id, "link_id": r["source_link_id"], "window_hour": now/60, "demand": q}]
	if not e._world.spatial_world.request_capacity_batch(requests).get("success", false): return false
	var check: Dictionary = e._world.spatial_world.reservation_results_batch(requests)
	if not check.get("success", false) or float(check["results"][request_id]["allocated_capacity"])+VNextInfrastructureLinkState.CAPACITY_EPSILON < q:
		e._world.spatial_world.cancel_capacity_request(request_id, r["source_link_id"], now/60)
		return false
	var adopts: Array[Dictionary] = [{"adoption_id": id, "request_id": request_id, "link_id": r["source_link_id"], "window_hour": now/60, "amount": q, "source_id": shipment_id}]
	if not e._world.spatial_world.consume_capacity_batch(adopts).get("success", false):
		e._world.spatial_world.cancel_capacity_request(request_id, r["source_link_id"], now/60)
		return false
	if r.has("node_resources"):
		for key: String in ["origin_handling","origin_berth"]:
			_node_use("node:"+shipment_id+":"+str(leg_index)+":"+key,shipment_id,leg_index,r["node_resources"][key],good,quantity_value,now,now+int(r["loading_minutes"]))
	release_storage(shipment_id,good,quantity_value,id)
	var hours := quantity_value*handling_units(good)*int(r["handling_hours_per_unit"])
	var h := handling[str(e.day)+"|"+edge_id] as Dictionary
	h["used"] = int(h["used"])+hours
	var vehicle_key: String = r["vehicle_id"]+"|"+str(now/60)
	_vehicle_usage[vehicle_key] = float(_vehicle_usage.get(vehicle_key, 0.0))+q
	entries[id] = {"adoption_id": id, "shipment_id": shipment_id, "leg_index": leg_index, "edge_id": edge_id, "good": good, "quantity": quantity_value, "minute": now, "handling_hours": hours, "vehicle_id": r["vehicle_id"]}
	if good is Dictionary:
		entries[id].erase("good"); entries[id]["asset_id"]=good["asset_id"]
	if r.has("window_minutes"):
		entries[id].merge({"loading_end_minute": now+int(r["loading_minutes"]), "arrival_minute": now+int(r["loading_minutes"])+int(r["travel_minutes"]), "release_minute": now+int(r["vehicle_hold_minutes"])})
		_active_vehicles[id] = true
	return true

func node_completion_minute(shipment_id: String, leg: int) -> int:
	return int(node_uses.get("node:"+shipment_id+":"+str(leg)+":destination_berth",{}).get("end_minute",-1))

func has_node_arrival(shipment_id: String, leg: int) -> bool:
	return node_uses.has("node:"+shipment_id+":"+str(leg)+":destination_handling")

func shipment_node_view(shipment_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _active_node_uses:
		var use := node_uses[id] as Dictionary
		if use["shipment_id"] == shipment_id:
			result.append({"facility_id":use["facility_id"],"kind":facilities[use["facility_id"]]["kind"],"unit":facilities[use["facility_id"]]["unit"],"occupied":float(use["amount"])-float(use["released_amount"]),"end_minute":use["end_minute"]})
	return result

func arrival_wait_reason(shipment: Dictionary, order: Dictionary) -> String:
	if shipment["stage"]=="UNLOADING": return "ACTUAL_NODE_UNLOADING"
	var r: Dictionary = bindings.get(order["route_legs"][shipment["leg_index"]]["edge_id"],{})
	if not r.has("node_resources"): return "NO_EXPLICIT_NODE_RESOURCE_BINDING"
	var n := r["node_resources"] as Dictionary
	var h := handling.get(str(economy().day)+"|"+str(r["edge_id"])+"|arrival",{}) as Dictionary
	if int(h.get("hours",0))-int(h.get("used",0)) < int(shipment["quantity"])*handling_units(load_of(order))*int(n["unloading_hours_per_unit"]): return "WAITING_ACTUAL_UNLOADING_LABOR"
	for key: String in ["destination_handling","destination_berth","destination_storage"]:
		if _node_amount(n[key],load_of(order),shipment["quantity"]) > _node_available(n[key],economy()._world.game_clock.total_minutes()): return "WAITING_NODE_RESOURCE:"+str(n[key])
	return "NODE_READY_AT_NEXT_EXECUTION_BOUNDARY"

func _restore_nodes(raw: Dictionary, saved: Dictionary) -> bool:
	var source: Variant = raw.get("node_uses",{})
	if not source is Dictionary: return false
	for f: Dictionary in facilities.values():
		if f.has("capital_asset_id"):
			var asset: Dictionary = economy()._capital.assets.get(f["capital_asset_id"],{})
			if asset.is_empty() or asset.get("site_id")!=f["site_id"]: return false
	var throughput: Dictionary = {}
	var active: Dictionary = {}
	var physical: Dictionary = {}
	for p: Variant in saved.get("stock_lots",{}).get("portions",{}).values():
		if p is Dictionary and str(p.get("location","")).begins_with("CARGO|") and FormalLedgerState.valid_amount(p.get("remaining")):
			physical[p["location"]]=int(physical.get(p["location"],0))+int(p["remaining"])
	for id: String in source:
		var use: Variant = source[id]
		if not use is Dictionary or not EconomySliceConfig._fields(use,["id","shipment_id","leg_index","facility_id","quantity","amount","minute","end_minute","released_amount","releases"],["good","asset_id"]) or not valid_load(use) or use["id"]!=id or not facilities.has(use["facility_id"]) or not FormalLedgerState.valid_amount(use["leg_index"]) or not FormalLedgerState.valid_amount(use["quantity"]) or use["quantity"]<=0 or not FormalLedgerState.valid_amount(use["minute"]) or use["minute"]>economy()._world.game_clock.total_minutes() or typeof(use["end_minute"])!=TYPE_INT or not use["releases"] is Dictionary: return false
		var entry: Variant = raw["entries"].get("economy_entry:"+str(use["shipment_id"])+":"+str(use["leg_index"]))
		if not entry is Dictionary or not bindings.has(entry.get("edge_id")) or not bindings[entry["edge_id"]].has("node_resources") or load_of(use)!=load_of(entry) or use["quantity"]>entry.get("quantity",0) or use["minute"]<entry.get("minute",0): return false
		var n := bindings[entry["edge_id"]]["node_resources"] as Dictionary
		var role := id.trim_prefix("node:"+str(use["shipment_id"])+":"+str(use["leg_index"])+":")
		if role not in ["origin_handling","origin_berth","destination_handling","destination_berth","destination_storage"] or n[role]!=use["facility_id"] or not is_equal_approx(float(use["amount"]),_node_amount(use["facility_id"],load_of(use),use["quantity"])): return false
		if role.begins_with("origin") and (use["minute"]!=entry["minute"] or use["quantity"]!=entry["quantity"] or use["end_minute"]!=entry.get("loading_end_minute")): return false
		if role.begins_with("destination"):
			if use["minute"]<entry.get("arrival_minute",FormalLedgerState.MAX_AMOUNT) or use["end_minute"]!=(-1 if role=="destination_storage" else use["minute"]+n["unloading_minutes"]): return false
		var released := 0.0
		for event_id: String in use["releases"]:
			var event: Variant = use["releases"][event_id]
			if role!="destination_storage" or not event is Dictionary or not FormalLedgerState.exact_fields(event,["amount","minute"]) or not event["amount"] is float or event["amount"]<=0 or not FormalLedgerState.valid_amount(event["minute"]) or event["minute"]<use["minute"] or event["minute"]>economy()._world.game_clock.total_minutes(): return false
			var quantity_value := -1
			if event_id.begins_with("capital_delivery:"):
				var trade: Dictionary=saved.get("capital_formation",{}).get("resale",{}).get("trades",{}).get(event_id.trim_prefix("capital_delivery:"),{})
				if not use.has("asset_id") or trade.get("asset_id")!=use["asset_id"] or trade.get("state")!="DELIVERED" or trade.get("delivered_minute")!=event["minute"]: return false
				quantity_value=1
			elif event_id.begins_with("delivery:"):
				var receipt: Dictionary = saved["delivery_receipts"].get(event_id.trim_prefix("delivery:"),{})
				if receipt.get("shipment_id",receipt.get("id"))!=use["shipment_id"] or int(receipt.get("delivered_minute",int(receipt.get("delivered_day",-1))*1440))!=event["minute"]: return false
				quantity_value=int(receipt.get("quantity",-1))
			elif event_id.begins_with("loss:"):
				var loss: Dictionary = saved.get("cargo_fulfilment",{}).get("losses",{}).get(event_id.trim_prefix("loss:"),{})
				if loss.get("shipment_id")!=use["shipment_id"] or loss.get("adopted_minute")!=event["minute"]: return false
				quantity_value=int(loss.get("quantity",-1))
			elif raw["entries"].has(event_id):
				var next: Dictionary = raw["entries"][event_id]
				if next.get("shipment_id")!=use["shipment_id"] or next.get("leg_index")!=use["leg_index"]+1 or next.get("minute")!=event["minute"]: return false
				quantity_value=int(next.get("quantity",-1))
			if not event_id.begins_with("loss:") and int(event["minute"])<int(use["minute"])+int(n["unloading_minutes"]): return false
			if quantity_value<=0 or not is_equal_approx(float(event["amount"]),_node_amount(use["facility_id"],load_of(use),quantity_value)): return false
			released+=float(event["amount"])
		if not is_equal_approx(released,float(use["released_amount"])) or released>float(use["amount"]): return false
		var f := facilities[use["facility_id"]] as Dictionary
		if f["kind"]=="HANDLING_THROUGHPUT":
			var key := str(use["facility_id"])+"|"+str(int(use["minute"])/60)
			throughput[key]=float(throughput.get(key,0.0))+float(use["amount"])
		elif (use["end_minute"]<0 or use["end_minute"]>economy()._world.game_clock.total_minutes()) and released<float(use["amount"]):
			active[id]=true
			if role=="destination_storage" and not is_equal_approx(float(use["amount"])-released,_node_amount(use["facility_id"],load_of(use),(1 if use.has("asset_id") else physical.get("CARGO|"+str(use["shipment_id"]),0)))): return false
	# Check historical overlap at actual adoption boundaries; no daily history scan.
	for use: Dictionary in source.values():
		var f := facilities[use["facility_id"]] as Dictionary
		var capacity_value := 0.0
		for w: Dictionary in f["windows"]:
			if use["minute"]>=w["start_minute"] and use["minute"]<w["end_minute"]: capacity_value=float(w["capacity"])
		var occupied := 0.0
		if f["kind"]=="HANDLING_THROUGHPUT": occupied=float(throughput.get(str(use["facility_id"])+"|"+str(int(use["minute"])/60),0.0))
		else:
			for other: Dictionary in source.values():
				if other["facility_id"]!=use["facility_id"] or other["minute"]>use["minute"] or (other["end_minute"]>=0 and other["end_minute"]<=use["minute"]): continue
				var amount:=float(other["amount"])
				for event: Dictionary in other["releases"].values():
					if event["minute"]<=use["minute"]: amount-=float(event["amount"])
				occupied+=amount
		occupied+=economy()._service_market.shared_occupancy(use["facility_id"],use["minute"])
		if occupied>capacity_value+VNextInfrastructureLinkState.CAPACITY_EPSILON: return false
	# A warehouse may be the only user of a mapped facility. Validate its real
	# reservation/intake boundaries too, even when no cargo entered that node.
	for facility_id: String in economy()._service_market._facility_history:
		var mapped: String=economy()._service_market._facilities[facility_id]["shared_storage_id"]
		if mapped.is_empty(): continue
		var f:=facilities.get(mapped,{}) as Dictionary
		if f.is_empty(): return false
		var dates: Dictionary={}
		for contract_id: String in economy()._service_market._facility_history[facility_id]:
			var c:=economy()._service_market.contracts[contract_id] as Dictionary
			dates[c["accepted_minute"]]=true
			if c["started_minute"]>=0: dates[c["started_minute"]]=true
		for minute: int in dates:
			var capacity_value:=0.0
			for window: Dictionary in f["windows"]:
				if minute>=window["start_minute"] and minute<window["end_minute"]: capacity_value=float(window["capacity"])
			var occupied: float=economy()._service_market.shared_occupancy(mapped,minute)
			for use: Dictionary in source.values():
				if use["facility_id"]!=mapped or use["minute"]>minute or (use["end_minute"]>=0 and use["end_minute"]<=minute): continue
				occupied+=float(use["amount"])
				for event: Dictionary in use["releases"].values():
					if event["minute"]<=minute: occupied-=float(event["amount"])
			if occupied>capacity_value+VNextInfrastructureLinkState.CAPACITY_EPSILON: return false
	for entry: Dictionary in raw["entries"].values():
		if not bindings.get(entry.get("edge_id"),{}).has("node_resources"): continue
		var prefix := "node:"+str(entry["shipment_id"])+":"+str(entry["leg_index"])+":"
		for key: String in ["origin_handling","origin_berth"]:
			if not source.has(prefix+key): return false
		var cargo: Dictionary = saved_cargo(saved,entry["shipment_id"])
		var progressed: bool = raw["entries"].has("economy_entry:"+str(entry["shipment_id"])+":"+str(int(entry["leg_index"])+1)) or int(cargo.get("leg_index",-1))>int(entry["leg_index"]) or (cargo.get("stage")=="AWAITING_RECIPIENT" and cargo.get("leg_index")==entry["leg_index"])
		for receipt: Dictionary in saved["delivery_receipts"].values():
			if receipt.get("shipment_id",receipt["id"])==entry["shipment_id"]: progressed=true
		if progressed and not source.has(prefix+"destination_handling"): return false
		if cargo.get("stage")=="UNLOADING":
			if not source.has(prefix+"destination_berth") or cargo.get("unloading_end_minute")!=source[prefix+"destination_berth"]["end_minute"]: return false
		if source.has(prefix+"destination_handling"):
			for key: String in ["destination_berth","destination_storage"]:
				if not source.has(prefix+key) or source[prefix+key]["minute"]!=source[prefix+"destination_handling"]["minute"] or source[prefix+key]["quantity"]!=source[prefix+"destination_handling"]["quantity"]: return false
	node_uses=source.duplicate(true)
	_active_node_uses=active
	_node_throughput=throughput
	return true

func snapshot() -> Dictionary:
	return {"handling": handling.duplicate(true), "entries": entries.duplicate(true), "node_uses":node_uses.duplicate(true)}

func restore(raw: Variant, saved: Dictionary) -> bool:
	if raw == null: return bindings.is_empty()
	if not raw is Dictionary or not EconomySliceConfig._fields(raw, ["handling", "entries"], ["node_uses"]) or not raw["handling"] is Dictionary or not raw["entries"] is Dictionary: return false
	for key: String in ["orders", "shipments", "delivery_receipts", "work_records"]:
		if not saved.get(key) is Dictionary: return false
	var e := economy()
	if not _restore_nodes(raw,saved): return false
	var used: Dictionary = {}
	var hours: Dictionary = {}
	for p: Variant in saved.get("capital_formation", {}).get("projects", {}).values():
		if not p is Dictionary or not p.get("work") is Array: return false
		for work: Variant in p["work"]:
			if not work is Dictionary or not work.get("id") is String or not FormalLedgerState.valid_amount(work.get("hours")): return false
			used[work["id"]] = int(used.get(work["id"], 0))+int(work["hours"])
	for id: String in raw["handling"]:
		var h: Variant = raw["handling"][id]
		if not h is Dictionary or not EconomySliceConfig._fields(h, ["day", "edge_id", "hours", "used", "work"], ["operation"]) or not bindings.has(h["edge_id"]) or id != str(h["day"])+"|"+str(h["edge_id"])+("|arrival" if h.get("operation")=="ARRIVAL" else "") or not FormalLedgerState.valid_amount(h["day"]) or h["day"] > saved["day"] or not FormalLedgerState.valid_amount(h["hours"]) or not FormalLedgerState.valid_amount(h["used"]) or int(h["used"]) > int(h["hours"]) or not h["work"] is Array: return false
		var sum_hours := 0
		var site := str(facilities[bindings[h["edge_id"]]["node_resources"]["destination_handling"]]["site_id"]) if h.get("operation")=="ARRIVAL" else str(bindings[h["edge_id"]]["handling_site"])
		for work: Variant in h["work"]:
			if not work is Dictionary or not FormalLedgerState.exact_fields(work, ["work_id", "hours"]) or not saved["work_records"].has(work["work_id"]) or not FormalLedgerState.valid_amount(work["hours"]): return false
			var fact := saved["work_records"][work["work_id"]] as Dictionary
			if not e._spec["jobs"].has(fact.get("job")) or not FormalLedgerState.valid_amount(fact.get("hours")) or fact.get("day") != h["day"] or e._spec["jobs"][fact["job"]]["site_id"] != site: return false
			used[work["work_id"]] = int(used.get(work["work_id"], 0))+int(work["hours"])
			if int(used[work["work_id"]]) > int(fact["hours"]): return false
			sum_hours += int(work["hours"])
		if sum_hours != int(h["hours"]): return false
		if not hours.has(site): hours[site] = {}
		hours[site][h["day"]] = int(hours[site].get(h["day"], 0))+sum_hours
	var handling_used: Dictionary = {}
	var vehicles: Dictionary = {}
	for id: String in raw["entries"]:
		var a: Variant = raw["entries"][id]
		if not a is Dictionary or not EconomySliceConfig._fields(a, ["adoption_id", "shipment_id", "leg_index", "edge_id", "quantity", "minute", "handling_hours", "vehicle_id"], ["good", "asset_id", "loading_end_minute", "arrival_minute", "release_minute"]) or not valid_load(a) or a["adoption_id"] != id or not bindings.has(a["edge_id"]) or not FormalLedgerState.valid_amount(a["quantity"]) or int(a["quantity"]) <= 0 or not FormalLedgerState.valid_amount(a["minute"]) or int(a["minute"]) > e._world.game_clock.total_minutes(): return false
		var r := bindings[a["edge_id"]] as Dictionary
		var fact: Dictionary = e._world.spatial_world.capacity_adoption(id)
		if fact.is_empty() or fact["source_id"] != a["shipment_id"] or fact["link_id"] != r["source_link_id"] or fact["window_hour"] != int(a["minute"])/60 or not window_open(r, int(a["minute"])) or not is_equal_approx(float(fact["amount"]), float(a["quantity"])*weight(load_of(a), r)) or a["handling_hours"] != int(a["quantity"])*handling_units(load_of(a))*int(r["handling_hours_per_unit"]) or a["vehicle_id"] != r["vehicle_id"]: return false
		var hkey := str(int(a["minute"])/1440)+"|"+str(a["edge_id"])
		handling_used[hkey] = int(handling_used.get(hkey, 0))+int(a["handling_hours"])
		var vkey := str(a["vehicle_id"])+"|"+str(int(a["minute"])/60)
		vehicles[vkey] = float(vehicles.get(vkey, 0.0))+float(fact["amount"])
		if not r.has("window_minutes") and float(vehicles[vkey]) > float(r["vehicle_payload"]): return false
		if r.has("window_minutes"):
			if a.get("loading_end_minute") != int(a["minute"])+int(r["loading_minutes"]) or a.get("arrival_minute") != int(a["loading_end_minute"])+int(r["travel_minutes"]) or a.get("release_minute") != int(a["minute"])+int(r["vehicle_hold_minutes"]): return false
		elif a.has("release_minute") or a.has("loading_end_minute") or a.has("arrival_minute"): return false
	for use_id: String in node_uses:
		if not use_id.ends_with(":destination_handling"): continue
		var use := node_uses[use_id] as Dictionary
		var entry := raw["entries"]["economy_entry:"+str(use["shipment_id"])+":"+str(use["leg_index"])] as Dictionary
		var key := str(int(use["minute"])/1440)+"|"+str(entry["edge_id"])+"|arrival"
		handling_used[key]=int(handling_used.get(key,0))+int(use["quantity"])*handling_units(load_of(use))*int(bindings[entry["edge_id"]]["node_resources"]["unloading_hours_per_unit"])
	for id: String in handling_used:
		if not raw["handling"].has(id): return false
	for id: String in raw["handling"]:
		if raw["handling"][id]["used"] != handling_used.get(id, 0): return false
	var batches: Dictionary = {}
	var cargo_rows: Array = saved["shipments"].values()
	cargo_rows.append_array(saved["delivery_receipts"].values())
	for cargo: Variant in cargo_rows:
		if not cargo is Dictionary or not cargo.get("id") is String or not saved["orders"].has(cargo.get("order_id")) or not cargo.get("departures") is Array or not FormalLedgerState.valid_amount(cargo.get("quantity")): return false
		if cargo.has("departure_quantities"):
			if not cargo["departure_quantities"] is Array or cargo["departure_quantities"].size() != cargo["departures"].size(): return false
			for q: Variant in cargo["departure_quantities"]:
				if not FormalLedgerState.valid_amount(q) or int(q) <= 0: return false
		var shipment_id := str(cargo.get("shipment_id", cargo["id"]))
		if not batches.has(shipment_id): batches[shipment_id] = {"order_id": cargo["order_id"], "quantity": 0, "departures": cargo["departures"], "departure_quantities": cargo.get("departure_quantities", [])}
		elif batches[shipment_id]["departures"] != cargo["departures"] or batches[shipment_id]["departure_quantities"] != cargo.get("departure_quantities", []): return false
		batches[shipment_id]["quantity"] += int(cargo["quantity"])
	for id: String in raw["entries"]:
		var a := raw["entries"][id] as Dictionary
		if a.has("asset_id"):
			if not economy()._capital_transport.valid_entry(a,raw,saved): return false
			continue
		if not batches.has(a["shipment_id"]): return false
		var batch := batches[a["shipment_id"]] as Dictionary
		var order := saved["orders"][batch["order_id"]] as Dictionary
		if not order.get("route_legs") is Array or not FormalLedgerState.valid_amount(a["leg_index"]) or int(a["leg_index"]) >= batch["departures"].size() or int(a["leg_index"]) >= order["route_legs"].size() or not order["route_legs"][a["leg_index"]] is Dictionary or order["route_legs"][a["leg_index"]].get("edge_id") != a["edge_id"] or batch["departures"][a["leg_index"]] != int(a["minute"])/1440 or (batch["departure_quantities"][a["leg_index"]] if not batch["departure_quantities"].is_empty() else batch["quantity"]) != a["quantity"]: return false
	for shipment_id: String in batches:
		var batch := batches[shipment_id] as Dictionary
		var order := saved["orders"][batch["order_id"]] as Dictionary
		if not order.get("route_legs") is Array or batch["departures"].size() > order["route_legs"].size(): return false
		for i: int in batch["departures"].size():
			if bindings.has(order["route_legs"][i]["edge_id"]) and not raw["entries"].has("economy_entry:"+shipment_id+":"+str(i)): return false
	handling = raw["handling"].duplicate(true)
	entries = raw["entries"].duplicate(true)
	_hours = hours
	_total_hours.clear()
	for site: String in hours:
		for q: int in hours[site].values(): _total_hours[site] = int(_total_hours.get(site, 0))+q
	_vehicle_usage = vehicles
	_active_vehicles.clear()
	for id: String in entries:
		var a := entries[id] as Dictionary
		if not a.has("release_minute"): continue
		var occupied := 0.0
		for other: Dictionary in entries.values():
			if other.has("release_minute") and other["vehicle_id"] == a["vehicle_id"] and int(other["minute"]) <= int(a["minute"]) and _restored_vehicle_end(other,saved) > int(a["minute"]): occupied += float(other["quantity"])*weight(load_of(other), bindings[other["edge_id"]])
		if occupied > float(bindings[a["edge_id"]]["vehicle_payload"])+VNextInfrastructureLinkState.CAPACITY_EPSILON: return false
		if _restored_vehicle_end(a,saved) > e._world.game_clock.total_minutes(): _active_vehicles[id] = true
	return true

func _restored_vehicle_end(entry: Dictionary, saved: Dictionary) -> int:
	var end := maxi(int(entry["release_minute"]),node_completion_minute(entry["shipment_id"],entry["leg_index"]))
	var cargo: Dictionary = saved_cargo(saved,entry["shipment_id"])
	if cargo.get("leg_index")==entry["leg_index"] and cargo.get("stage") in ["LOADING","TRANSIT","WAITING_UNLOAD","UNLOADING"]:
		end=maxi(end,economy()._world.game_clock.total_minutes()+1)
	return end

func labor_needed(site: String) -> int:
	var e := economy()
	var total := 0
	for edge_id: String in bindings:
		var r := bindings[edge_id] as Dictionary
		if r["handling_site"] == site and _has_window(r, e._world.game_clock.total_minutes()):
			total += mini(FormalLedgerState.MAX_AMOUNT-total, _needed_hours(edge_id))
		if r.has("node_resources") and facilities[r["node_resources"]["destination_handling"]]["site_id"]==site:
			total += mini(FormalLedgerState.MAX_AMOUNT-total,labor_needed_arrival(edge_id))
	return total

func path_conditions(legs: Array, good: String) -> bool:
	for leg: Dictionary in legs:
		if bindings.has(leg["edge_id"]) and (weight(good, bindings[leg["edge_id"]]) <= 0.0 or not _has_window(bindings[leg["edge_id"]], economy()._world.game_clock.total_minutes())): return false
	return true


func site_keeper_reason(site: String) -> String:
	var e := economy()
	var now: int=e._world.game_clock.total_minutes()
	for id: String in _active_node_uses:
		var use := node_uses[id] as Dictionary
		if facilities[use["facility_id"]]["site_id"]==site and (use["end_minute"]<0 or use["end_minute"]>now) and float(use["released_amount"])<float(use["amount"]): return "ACTIVE_TRANSPORT_FACILITY_CUSTODY_OR_OCCUPANCY"
	for t: Dictionary in e._capital_transport.tasks.values():
		if t["stage"]=="DELIVERED": continue
		for leg: Dictionary in e._capital_transport.offer(t["offer_id"])["legs"]:
			var b: Dictionary=bindings[leg["edge_id"]]
			for facility: String in b["node_resources"].values().filter(func(v: Variant)->bool: return v is String):
				if facilities[facility]["site_id"]==site: return "ACCEPTED_EQUIPMENT_CARRIAGE_REQUIRES_FACILITY"
	for id: String in e._moving_shipments:
		var cargo := e._shipments[id] as Dictionary
		var order := e._orders[cargo["order_id"]] as Dictionary
		var binding: Dictionary=bindings.get(order["route_legs"][cargo["leg_index"]]["edge_id"],{})
		if not binding.has("node_resources"): continue
		for facility: String in ["destination_handling","destination_berth","destination_storage"]:
			if facilities[binding["node_resources"][facility]]["site_id"]==site: return "ACCEPTED_CARGO_REQUIRES_DESTINATION_FACILITY"
	for id: String in e._pending_orders:
		var order := e._orders[id] as Dictionary
		var binding: Dictionary=bindings.get(order["route_legs"][0]["edge_id"],{})
		if binding.get("handling_site")==site: return "ACCEPTED_CARGO_REQUIRES_ORIGIN_HANDLING"
	return ""

func site_resource_view(site: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for f: Dictionary in facilities.values():
		if f["site_id"]!=site: continue
		result.append({"id":f["id"],"kind":f["kind"],"unit":f["unit"],"basis":f["basis"],"available":_node_available(f["id"],economy()._world.game_clock.total_minutes())})
	return result

## Passenger/weight equivalence is explicit; seats and payload remain separate.
func passenger_window(link: String, unit: String) -> bool:
	for r: Dictionary in bindings.values():
		if r["source_link_id"]==link and r["weight_unit"]==unit and window_open(r,economy()._world.game_clock.total_minutes()): return true
	return false

func passenger_unit_known(link: String, unit: String) -> bool:
	for r: Dictionary in bindings.values():
		if r["source_link_id"]==link and r["weight_unit"]==unit: return true
	return false


func load_of(row: Dictionary) -> Variant:
	return {"asset_id":row["asset_id"]} if row.has("asset_id") else row.get("good","")

func handling_units(load: Variant) -> int:
	return economy()._capital_transport.handling_units(load.get("asset_id","")) if load is Dictionary else 1

func valid_load(row: Dictionary) -> bool:
	if row.has("asset_id"):
		return not row.has("good") and row["asset_id"] is String and not economy()._capital_transport.load_rule(row["asset_id"]).is_empty() and row.get("quantity")==1
	return row.get("good") is String and economy()._goods.has(row["good"])

func cargo(id: String) -> Dictionary:
	return economy()._capital_transport.tasks.get(id,economy()._shipments.get(id,{}))

func saved_cargo(saved: Dictionary, id: String) -> Dictionary:
	return saved.get("capital_transport",{}).get(id,saved["shipments"].get(id,{}))
