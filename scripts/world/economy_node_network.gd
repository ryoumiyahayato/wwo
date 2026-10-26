extends RefCounted
## Derived identities and sparse access paths only. No stock, accounts, capacity
## owner, saved state or alternative transport executor lives in this graph.
const FORMAT: String = "economy_node_network_v1"
const PATH_PREFIX: String = "network_path:"
const MAX_LEGS: int = 8
const MAX_VISITS: int = 4096
const MAX_RELAXATIONS: int = 8192

var revision: int = 0
var nodes: Dictionary = {}
var adjacency: Dictionary = {}
var _routes: Dictionary = {}
var _local_id: String = ""

func rebuild(spec: Dictionary, routes: Dictionary, settings: Dictionary) -> void:
	revision += 1
	nodes.clear()
	adjacency.clear()
	_routes = routes
	_local_id = str(spec["route"]["id"])
	var ids: Array = routes.keys()
	ids.sort()
	for id: String in ids:
		var row: Dictionary = routes[id]
		var origin: String = row["from_place_id"]
		var destination: String = row["to_place_id"]
		_place_identity(origin)
		_place_identity(destination)
		if not adjacency.has(origin): adjacency[origin] = []
		adjacency[origin].append(id)
	for firm: String in spec["firms"]:
		var row: Dictionary = spec["firms"][firm]
		nodes[firm] = _identity(firm, "firm", row["place_id"], "", firm, firm, "ADMITTED_ENTERPRISE_IDENTITY")
		for site: String in row["sites"]:
			var location: String = spec["sites"][site]["place_id"]
			_place_identity(location)
			nodes[site] = _identity(site, "site", location, site, firm, site, spec["sites"][site]["basis"])
	for row: Dictionary in settings.get("transport_nodes", []):
		var place: String = row["place_id"]
		_place_identity(place)
		var id: String = "transport_node:" + place
		nodes[id] = _identity(id, "transport_node", place, "", "", place, "CONFIGURED_TRANSFER_THROUGHPUT_NOT_STOCK")

func _identity(id: String, kind: String, place: String, site: String, firm: String, source: String, basis: String) -> Dictionary:
	return {"id": id, "kind": kind, "type": kind, "place_id": place, "site_id": site, "firm_id": firm, "source_id": source, "basis": basis}

func _place_identity(place: String) -> void:
	if not nodes.has(place): nodes[place] = _identity(place, "place", place, "", "", place, "HOST_SPATIAL_CATALOG")

func edge_known(e: RefCounted, id: String, buyer: String) -> bool:
	return _routes.has(id) and (id == _local_id or _routes[id]["known_to"].has(buyer)) and e._cargo_edge_valid(_routes[id])

## IDs encode the original ordered edges, not a hash or a saved path registry.
## Resolve independently of today's cheapest path or live capacity: accepted cargo
## retains its original path after closure, a cheaper discovery or save restoration.
func resolve(e: RefCounted, buyer: String, origin: String, destination: String, id: String) -> Dictionary:
	if not id.begins_with(PATH_PREFIX): return {}
	var value: Variant = JSON.parse_string(id.trim_prefix(PATH_PREFIX))
	if not value is Array or value.is_empty() or value.size() > MAX_LEGS or id != path_id(value): return {}
	var previous: String = origin
	var seen: Dictionary = {}
	for edge: Variant in value:
		if not edge is String or seen.has(edge) or not edge_known(e, edge, buyer): return {}
		var row: Dictionary = _routes[edge]
		if row["from_place_id"] != previous: return {}
		seen[edge] = true
		previous = str(row["to_place_id"])
	if previous != destination: return {}
	return {"id": id, "from_place_id": origin, "to_place_id": destination, "edge_ids": value.duplicate()}

static func path_id(ids: Array) -> String:
	return PATH_PREFIX + JSON.stringify(ids)

## Two finite lexicographic Dijkstra searches (freight/delay and delay/freight).
## Layering by hop count preserves the eight-leg bound without a dense all-pairs
## table. Non-negative costs and positive travel times never reward a cycle.
func paths(e: RefCounted, buyer: String, origin: String, destination: String, good: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if origin == destination: return result
	var seen: Dictionary = {}
	for by_delay: bool in [false, true]:
		var path: Dictionary = _shortest(e, buyer, origin, destination, by_delay, good)
		if path.is_empty() or seen.has(path["id"]): continue
		seen[path["id"]] = true
		result.append(path)
	return result

func _shortest(e: RefCounted, buyer: String, origin: String, destination: String, by_delay: bool, good: String) -> Dictionary:
	var queue: Array[Dictionary] = []
	var initial: Dictionary = {"place": origin, "edge_ids": [], "cost": 0, "delay": 0, "primary": 0, "secondary": 0, "token": ""}
	_push(queue, initial)
	var best: Dictionary = {origin + "|0": initial}
	var visits: int = 0
	var relaxations: int = 0
	while not queue.is_empty() and visits < MAX_VISITS and relaxations < MAX_RELAXATIONS:
		var current: Dictionary = _pop(queue)
		var key: String = str(current["place"]) + "|" + str(current["edge_ids"].size())
		if best.get(key, {}).get("token", "") != current["token"]: continue
		visits += 1
		if current["place"] == destination:
			return {"id": path_id(current["edge_ids"]), "from_place_id": origin, "to_place_id": destination, "edge_ids": current["edge_ids"].duplicate()}
		if current["edge_ids"].size() >= MAX_LEGS: continue
		for id: String in adjacency.get(current["place"], []):
			relaxations += 1
			if relaxations >= MAX_RELAXATIONS: break
			if not edge_known(e, id, buyer) or current["edge_ids"].has(id): continue
			if not good.is_empty() and not e._shared.path_conditions([{"edge_id": id}], good): continue
			var row: Dictionary = _routes[id]
			if row["from_place_id"] == row["to_place_id"]: continue
			if e._shared.alias_requires_binding(id): continue
			if not e._shared.bindings.has(id) and int(e._transport.get("edges", {}).get(id, {}).get("capacity", row["capacity"])) <= 0: continue
			var ids: Array = current["edge_ids"].duplicate()
			ids.append(id)
			var cost: int = int(current["cost"]) + int(row["freight_per_unit"])
			var delay: int = int(current["delay"]) + int(row["delay"])
			if cost > FormalLedgerState.MAX_AMOUNT or delay > FormalLedgerState.MAX_AMOUNT: continue
			var next: Dictionary = {"place": row["to_place_id"], "edge_ids": ids, "cost": cost, "delay": delay, "primary": delay if by_delay else cost, "secondary": cost if by_delay else delay, "token": path_id(ids)}
			var next_key: String = str(next["place"]) + "|" + str(ids.size())
			if best.has(next_key) and not _less(next, best[next_key]): continue
			best[next_key] = next
			_push(queue, next)
	return {}

static func _less(a: Dictionary, b: Dictionary) -> bool:
	if a["primary"] != b["primary"]: return int(a["primary"]) < int(b["primary"])
	if a["secondary"] != b["secondary"]: return int(a["secondary"]) < int(b["secondary"])
	return str(a["token"]) < str(b["token"])

static func _push(queue: Array[Dictionary], row: Dictionary) -> void:
	queue.append(row)
	var index: int = queue.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if not _less(queue[index], queue[parent]): break
		var swap: Dictionary = queue[parent]
		queue[parent] = queue[index]
		queue[index] = swap
		index = parent

static func _pop(queue: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = queue[0]
	var last: Dictionary = queue.pop_back()
	if queue.is_empty(): return result
	queue[0] = last
	var index: int = 0
	while index * 2 + 1 < queue.size():
		var child: int = index * 2 + 1
		if child + 1 < queue.size() and _less(queue[child + 1], queue[child]): child += 1
		if not _less(queue[child], queue[index]): break
		var swap: Dictionary = queue[index]
		queue[index] = queue[child]
		queue[child] = swap
		index = child
	return result

## The host must authenticate the observer. Public admitted business identity
## is not permission to inspect stock, cash, plans, private knowledge or orders.
func view(e: RefCounted, observer: String, places: Array[String], limit: int) -> Dictionary:
	var result: Dictionary = {"format": FORMAT, "minute": e._world.game_clock.total_minutes(), "revision": revision, "nodes": [], "edges": [], "adjacency": {}, "truncated": false, "visibility": "PUBLIC_ADMITTED_IDENTITIES_AND_OBSERVER_KNOWN_CORRIDORS"}
	var budget: int = clampi(limit, 0, 256)
	if budget == 0: return result
	var subjects: Array[String] = [observer]
	var known_sites: Dictionary = {}
	for firm: String in e._firm_ids():
		if not e._manager(observer, firm): continue
		subjects.append(firm)
		for site: String in e._spec["firms"][firm]["sites"]:
			known_sites[site] = true
			for candidate: String in e._firm_knowledge.get(site, []): known_sites[e._candidate(candidate)["site"]] = true
	for candidate: String in e._actors[observer].get("known_suppliers", []): known_sites[e._candidate(candidate)["site"]] = true
	for job: String in e._actors[observer].get("known_jobs", []):
		var row: Dictionary = e._known_job(observer, job)
		if not str(row.get("site_id", "")).is_empty(): known_sites[row["site_id"]] = true
	var selected: Dictionary = {}
	for place: String in places:
		if e._world.spatial_catalog.has_place(place): _add_place(e, result, selected, place, budget)
	var ids: Array = nodes.keys()
	ids.sort()
	for id: String in ids:
		var row: Dictionary = nodes[id]
		if row["kind"] != "site" or (not places.is_empty() and row["place_id"] not in places): continue
		var firm: String = row["firm_id"]
		var organization: String = str(e._spec["firms"][firm].get("host_organization_id", ""))
		var public_identity: bool = not organization.is_empty() and e._world.organization_state.is_organization_active(organization)
		if not public_identity and not known_sites.has(id): continue
		_add_place(e, result, selected, row["place_id"], budget)
		var firm_row: Dictionary = nodes[firm].duplicate(true)
		firm_row["identity_basis"] = e._business_identity_basis(firm)
		firm_row["organization_id"] = organization
		firm_row["subject_id"] = firm if subjects.has(firm) else observer
		firm_row["label"] = firm
		_add_node(result, selected, firm_row, budget)
		var site_row: Dictionary = row.duplicate(true)
		site_row.merge({"identity_basis": e._business_identity_basis(firm), "organization_id": organization, "subject_id": firm if subjects.has(firm) else observer, "label": id, "visibility": "PUBLIC_ADMITTED_BUSINESS_IDENTITY" if public_identity else "OBSERVER_RECEIVED_SITE_IDENTITY"})
		_add_node(result, selected, site_row, budget)
		_add_edge(result, selected, _relation("operates:" + id, "operates", firm, id, row["place_id"], row["place_id"], id, site_row["visibility"]), budget)
		_add_edge(result, selected, _relation("located_at:" + id, "located_at", id, row["place_id"], row["place_id"], row["place_id"], id, "ADMITTED_SITE_PLACE"), budget)
	ids = _routes.keys()
	ids.sort()
	for id: String in ids:
		var row: Dictionary = _routes[id]
		if not places.is_empty() and row["from_place_id"] not in places and row["to_place_id"] not in places: continue
		var known: bool = false
		for subject: String in subjects:
			if edge_known(e, id, subject): known = true; break
		if not known: continue
		_add_place(e, result, selected, row["from_place_id"], budget)
		_add_place(e, result, selected, row["to_place_id"], budget)
		var edge: Dictionary = _relation(id, "transport", row["from_place_id"], row["to_place_id"], row["from_place_id"], row["to_place_id"], str(row.get("source_link_id", row.get("source_permission_id", id))), row.get("basis", "SYNTHETIC"))
		edge.merge({"capacity": row["capacity"], "delay": row["delay"], "freight_per_unit": row["freight_per_unit"], "carrier_id": row["carrier"], "source_link_id": row.get("source_link_id", ""), "source_permission_id": row.get("source_permission_id", ""), "status": "KNOWN_CORRIDOR_NOT_A_TRADE", "capacity_basis": "CONFIGURED_CEILING_NOT_FREE_LIVE_CAPACITY"})
		_add_edge(result, selected, edge, budget)
	for id: String in nodes:
		var row: Dictionary = nodes[id]
		if row["kind"] != "transport_node" or not selected.has(row["place_id"]): continue
		_add_node(result, selected, row.duplicate(true), budget)
		_add_edge(result, selected, _relation("located_at:" + id, "located_at", id, row["place_id"], row["place_id"], row["place_id"], row["source_id"], row["basis"]), budget)
	return result

static func _relation(id: String, kind: String, origin: String, destination: String, from_place: String, to_place: String, source: String, basis: String) -> Dictionary:
	return {"id": id, "kind": kind, "from_node_id": origin, "to_node_id": destination, "from_place_id": from_place, "to_place_id": to_place, "source_id": source, "basis": basis, "directed": true}

static func _add_node(result: Dictionary, selected: Dictionary, row: Dictionary, budget: int) -> void:
	if selected.has(row["id"]): return
	if result["nodes"].size() >= budget: result["truncated"] = true; return
	selected[row["id"]] = true
	result["nodes"].append(row)

static func _add_place(e: RefCounted, result: Dictionary, selected: Dictionary, place: String, budget: int) -> void:
	if selected.has(place): return
	var source: Dictionary = e._world.spatial_catalog.get_place(place)
	if source.is_empty(): return
	var row: Dictionary = {"id": place, "kind": "place", "type": "place", "place_id": place, "site_id": "", "firm_id": "", "source_id": str(source.get("id", place)), "basis": "HOST_SPATIAL_CATALOG", "identity_basis": "HOST_WORLD", "label": str(source.get("name_zh", source.get("name", place)))}
	_add_node(result, selected, row, budget)

static func _add_edge(result: Dictionary, selected: Dictionary, row: Dictionary, budget: int) -> void:
	if not selected.has(row["from_node_id"]) or not selected.has(row["to_node_id"]): return
	if result["edges"].size() >= budget * 2: result["truncated"] = true; return
	result["edges"].append(row)
	var origin: String = row["from_node_id"]
	if not result["adjacency"].has(origin): result["adjacency"][origin] = []
	result["adjacency"][origin].append(row["id"])
