class_name EconomyStockLots
extends RefCounted
## One physical stock authority. Quantity tables are rebuilt projections. Sources
## survive splits, ownership changes and consumption; no ages/costs are inferred.
var sources: Dictionary = {}
var portions: Dictionary = {}
var losses: Dictionary = {}
var next_id: int = 1
var costs: RefCounted
var _by_location: Dictionary = {}
var _by_owner: Dictionary = {}
var _reservations: Dictionary = {}
var _projection: Dictionary = {}
var _view: Dictionary = {}
var _view_dirty: bool = true
var _goods: Array[String] = []
var _actors: Array[String] = []

func configure(goods: Array[String], actors: Array[String]) -> void:
	_goods.assign(goods)
	_actors.assign(actors)

func projection() -> Dictionary:
	if _view_dirty:
		_view = _projection.duplicate()
		_view.make_read_only()
		_view_dirty = false
	return _view

func ensure_subject(subject: String) -> void:
	if not _projection.has(subject):
		var row: Dictionary = {}
		for good: String in _goods: row[good] = 0
		row.make_read_only()
		_projection[subject] = row
		_view_dirty = true

func _project_key(p: Dictionary) -> String:
	if _actors.has(p["owner"]): return p["owner"]
	return str(p["location"]).trim_prefix("SITE|") if str(p["location"]).begins_with("SITE|") else ""

func _index(p: Dictionary, sign: int) -> void:
	if not _by_owner.has(p["owner"]): _by_owner[p["owner"]] = {}
	if sign > 0 and int(p["remaining"]) > 0: _by_owner[p["owner"]][p["id"]] = true
	else: _by_owner[p["owner"]].erase(p["id"])
	var loc := str(p["location"])
	var key := loc+"#"+str(p["good"])
	if not _by_location.has(key): _by_location[key] = {}
	if sign > 0 and int(p["remaining"]) > 0: _by_location[key][p["id"]] = true
	else: _by_location[key].erase(p["id"])
	var subject := _project_key(p)
	if not subject.is_empty():
		ensure_subject(subject)
		var row := (_projection[subject] as Dictionary).duplicate()
		row[p["good"]] = int(row[p["good"]])+sign*int(p["remaining"])
		row.make_read_only()
		_projection[subject] = row
		_view_dirty = true

func create(source_id: String, good: String, unit: String, quantity: int, owner: String, location: String, place: String, minute: int, basis: String, inputs: Array[Dictionary] = [], acquisition: String = "") -> bool:
	if source_id.is_empty() or sources.has(source_id) or good not in _goods or unit.is_empty() or quantity <= 0 or not FormalLedgerState.valid_amount(quantity) or owner.is_empty() or location.is_empty() or basis.is_empty(): return false
	sources[source_id] = {"id": source_id, "good": good, "unit": unit, "quantity": quantity, "formed_minute": minute, "basis": basis, "inputs": inputs.duplicate(true)}
	_add(source_id, quantity, owner, location, place, location.trim_prefix("SITE|") if location.begins_with("SITE|") else owner, acquisition, minute)
	return true

func _add(source: String, quantity: int, owner: String, location: String, place: String, custodian: String, acquisition: String, minute: int, reserved: String = "", parent: String = "") -> String:
	if location == "PERSON|"+owner+"|CARRIED": place = "" # Actual carried position follows the host person, not a second stored location.
	var id := "portion:"+str(next_id)
	next_id += 1
	var s := sources[source] as Dictionary
	var p := {"id": id, "parent_portion_id": parent, "source_id": source, "good": s["good"], "unit": s["unit"], "quantity": quantity, "remaining": quantity, "consumed": 0, "lost": 0, "moved": 0, "owner": owner, "custodian": custodian, "location": location, "place_id": place, "acquisition_id": acquisition, "reserved_for": reserved, "opened_minute": minute, "closed_minute": -1}
	portions[id] = p
	if costs != null: costs.portion_added(p)
	_index(p, 1)
	if not reserved.is_empty():
		if not _reservations.has(reserved): _reservations[reserved] = {}
		_reservations[reserved][id] = true
	return id

func selection(location: String, good: String, quantity: int, reserved: String = "", acquisition: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var left := quantity
	var ids: Array = _by_location.get(location+"#"+good, {}).keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("portion:")) < int(b.trim_prefix("portion:")))
	for id: String in ids:
		var p := portions[id] as Dictionary
		if p["reserved_for"] != reserved or (not acquisition.is_empty() and p["acquisition_id"] != acquisition): continue
		var q := mini(left, int(p["remaining"]))
		if q > 0: result.append({"portion_id": id, "source_id": p["source_id"], "quantity": q})
		left -= q
		if left == 0: break
	if quantity <= 0 or left != 0: result.clear()
	return result

func ready(rows: Array[Dictionary]) -> bool:
	if rows.is_empty(): return false
	var amounts: Dictionary = {}
	for r: Dictionary in rows:
		if not FormalLedgerState.exact_fields(r, ["portion_id", "source_id", "quantity"]) or not portions.has(r.get("portion_id")) or r["source_id"] != portions[r["portion_id"]]["source_id"] or not FormalLedgerState.valid_amount(r.get("quantity")) or int(r["quantity"]) <= 0: return false
		var id := str(r["portion_id"])
		amounts[id] = int(amounts.get(id, 0))+int(r["quantity"])
	for id: String in amounts:
		if amounts[id] > int(portions[id]["remaining"]): return false
	return true

func _subtract(p: Dictionary, q: int, field: String, minute: int) -> void:
	_index(p, -1)
	p["remaining"] = int(p["remaining"])-q
	p[field] = int(p[field])+q
	if int(p["remaining"]) == 0:
		p["closed_minute"] = minute
		if not str(p["reserved_for"]).is_empty(): _reservations.get(p["reserved_for"], {}).erase(p["id"])
	_index(p, 1)

func move(rows: Array[Dictionary], location: String, place: String, minute: int, owner: String = "", acquisition: String = "", reservation: String = "", custodian: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not ready(rows): return result
	for r: Dictionary in rows:
		var p := portions[r["portion_id"]] as Dictionary
		var q := int(r["quantity"])
		_subtract(p, q, "moved", minute)
		var id := _add(p["source_id"], q, owner if not owner.is_empty() else p["owner"], location, place, custodian if not custodian.is_empty() else p["custodian"], acquisition if not acquisition.is_empty() else p["acquisition_id"], minute, reservation, p["id"])
		result.append({"portion_id": id, "source_id": p["source_id"], "quantity": q})
	return result

func reserve(ref: String, location: String, good: String, quantity: int, minute: int) -> bool:
	if _reservations.has(ref): return false
	var rows := selection(location, good, quantity)
	if rows.is_empty(): return false
	return not move(rows, location, str(portions[rows[0]["portion_id"]]["place_id"]), minute, "", "", ref).is_empty()

func reserved_selection(ref: String, quantity: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var left := quantity
	var ids: Array = _reservations.get(ref, {}).keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("portion:")) < int(b.trim_prefix("portion:")))
	for id: String in ids:
		var p := portions[id] as Dictionary
		var q := mini(left, int(p["remaining"]))
		if q > 0: result.append({"portion_id": id, "source_id": p["source_id"], "quantity": q})
		left -= q
		if left == 0: break
	if quantity <= 0 or left != 0: result.clear()
	return result

func release(ref: String, quantity: int, minute: int) -> bool:
	var rows := reserved_selection(ref, quantity)
	if rows.is_empty(): return false
	for r: Dictionary in rows:
		var p := portions[r["portion_id"]] as Dictionary
		move([r], p["location"], p["place_id"], minute)
	return true

func consume(rows: Array[Dictionary], minute: int) -> bool:
	if not ready(rows): return false
	for r: Dictionary in rows: _subtract(portions[r["portion_id"]], int(r["quantity"]), "consumed", minute)
	return true

func record_loss(id: String, rows: Array[Dictionary], minute: int, basis: String, process: String) -> bool:
	var fact := {"id": id, "portions": rows.duplicate(true), "minute": minute, "basis": basis, "process": process}
	if losses.has(id): return losses[id] == fact
	if id.is_empty() or basis.is_empty() or process.is_empty() or not ready(rows): return false
	if costs != null: costs.lost(id, rows)
	for r: Dictionary in rows: _subtract(portions[r["portion_id"]], int(r["quantity"]), "lost", minute)
	losses[id] = fact
	return true

func snapshot() -> Dictionary:
	return {"sources": sources.duplicate(true), "portions": portions.duplicate(true), "losses": losses.duplicate(true), "next_id": next_id}

func restore(raw: Variant, expected: Dictionary, units: Dictionary, valid_owners: Array[String], valid_places: Array[String], minute: int) -> bool:
	if not raw is Dictionary or not FormalLedgerState.exact_fields(raw, ["sources", "portions", "losses", "next_id"]) or not raw["sources"] is Dictionary or not raw["portions"] is Dictionary or not raw["losses"] is Dictionary or not FormalLedgerState.valid_amount(raw["next_id"]) or int(raw["next_id"]) < 1: return false
	var totals: Dictionary = {}
	for id: String in raw["sources"]:
		var s: Variant = raw["sources"][id]
		if not s is Dictionary or not FormalLedgerState.exact_fields(s, ["id", "good", "unit", "quantity", "formed_minute", "basis", "inputs"]) or s["id"] != id or not units.has(s["good"]) or s["unit"] != units[s["good"]] or not FormalLedgerState.valid_amount(s["quantity"]) or int(s["quantity"]) <= 0 or typeof(s["formed_minute"]) != TYPE_INT or int(s["formed_minute"]) > minute or int(s["formed_minute"]) < -1 or not s["basis"] is String or s["basis"].is_empty() or not s["inputs"] is Array: return false
	for id: String in raw["portions"]:
		var p: Variant = raw["portions"][id]
		if not p is Dictionary or not FormalLedgerState.exact_fields(p, ["id", "parent_portion_id", "source_id", "good", "unit", "quantity", "remaining", "consumed", "lost", "moved", "owner", "custodian", "location", "place_id", "acquisition_id", "reserved_for", "opened_minute", "closed_minute"]) or p["id"] != id or not id.begins_with("portion:") or not id.trim_prefix("portion:").is_valid_int() or int(id.trim_prefix("portion:")) >= int(raw["next_id"]) or not raw["sources"].has(p["source_id"]) or p["owner"] not in valid_owners or (p["place_id"] not in valid_places and not (p["place_id"] == "" and p["location"] == "PERSON|"+str(p["owner"])+"|CARRIED")): return false
		var s := raw["sources"][p["source_id"]] as Dictionary
		if p["unit"] != s["unit"] or p["good"] != s["good"]: return false
		for k: String in ["quantity", "remaining", "consumed", "lost", "moved"]:
			if not FormalLedgerState.valid_amount(p[k]): return false
		if int(p["quantity"]) != int(p["remaining"])+int(p["consumed"])+int(p["lost"])+int(p["moved"]) or int(p["quantity"]) == 0 or typeof(p["opened_minute"]) != TYPE_INT or int(p["opened_minute"]) > minute or typeof(p["closed_minute"]) != TYPE_INT or int(p["closed_minute"]) > minute or (int(p["remaining"]) == 0) != (int(p["closed_minute"]) >= 0): return false
		for k: String in ["location", "custodian", "acquisition_id", "reserved_for"]:
			if not p[k] is String: return false
		totals[p["source_id"]] = int(totals.get(p["source_id"], 0))+int(p["remaining"])+int(p["consumed"])+int(p["lost"])
	var moved: Dictionary = {}
	var roots: Dictionary = {}
	for p: Dictionary in raw["portions"].values():
		if not p["parent_portion_id"] is String: return false
		var parent := str(p["parent_portion_id"])
		if parent.is_empty():
			roots[p["source_id"]] = int(roots.get(p["source_id"], 0))+int(p["quantity"])
		else:
			if not raw["portions"].has(parent) or int(parent.trim_prefix("portion:")) >= int(str(p["id"]).trim_prefix("portion:")) or raw["portions"][parent]["source_id"] != p["source_id"] or int(p["opened_minute"]) < int(raw["portions"][parent]["opened_minute"]): return false
			moved[parent] = int(moved.get(parent, 0))+int(p["quantity"])
	for id: String in raw["portions"]:
		if raw["portions"][id]["moved"] != moved.get(id, 0): return false
	for id: String in raw["sources"]:
		if roots.get(id, 0) != raw["sources"][id]["quantity"] or totals.get(id, 0) != raw["sources"][id]["quantity"]: return false
	for s: Dictionary in raw["sources"].values():
		for r: Variant in s["inputs"]:
			if not r is Dictionary or not raw["portions"].has(r.get("portion_id")) or r.get("source_id") != raw["portions"][r["portion_id"]]["source_id"] or not FormalLedgerState.valid_amount(r.get("quantity")) or int(r["quantity"]) > int(raw["portions"][r["portion_id"]]["consumed"]): return false
	var lost: Dictionary = {}
	for id: String in raw["losses"]:
		var f: Variant = raw["losses"][id]
		if not f is Dictionary or not FormalLedgerState.exact_fields(f, ["id", "portions", "minute", "basis", "process"]) or f["id"] != id or not f["portions"] is Array or f["portions"].is_empty() or not f["basis"] is String or f["basis"].is_empty() or not f["process"] is String or f["process"].is_empty() or not FormalLedgerState.valid_amount(f["minute"]) or int(f["minute"]) > minute: return false
		for r: Variant in f["portions"]:
			if not r is Dictionary or not FormalLedgerState.exact_fields(r, ["portion_id", "source_id", "quantity"]) or not raw["portions"].has(r.get("portion_id")) or r["source_id"] != raw["portions"][r["portion_id"]]["source_id"] or not FormalLedgerState.valid_amount(r.get("quantity")) or int(r["quantity"]) <= 0: return false
			lost[r["portion_id"]] = int(lost.get(r["portion_id"], 0))+int(r["quantity"])
	for id: String in raw["portions"]:
		if raw["portions"][id]["lost"] != lost.get(id, 0): return false
	sources = raw["sources"].duplicate(true)
	portions = raw["portions"].duplicate(true)
	losses = raw["losses"].duplicate(true)
	next_id = raw["next_id"]
	_by_location.clear()
	_by_owner.clear()
	_reservations.clear()
	_projection.clear()
	_view_dirty = true
	for subject: String in expected: ensure_subject(subject)
	for p: Dictionary in portions.values():
		_index(p, 1)
		if int(p["remaining"]) > 0 and not str(p["reserved_for"]).is_empty():
			if not _reservations.has(p["reserved_for"]): _reservations[p["reserved_for"]] = {}
			_reservations[p["reserved_for"]][p["id"]] = true
	return _projection == expected

func quantity_at(location: String, good: String) -> int:
	var q := 0
	for id: String in _by_location.get(location+"#"+good, {}): q += int(portions[id]["remaining"])
	return q

func reserved_quantity(ref: String) -> int:
	var q := 0
	for id: String in _reservations.get(ref, {}): q += int(portions[id]["remaining"])
	return q

func lost_at(location: String, good: String, reservation: String = "") -> int:
	var q := 0
	for p: Dictionary in portions.values():
		if p["location"] == location and p["good"] == good and (reservation.is_empty() or p["reserved_for"] == reservation): q += int(p["lost"])
	return q
