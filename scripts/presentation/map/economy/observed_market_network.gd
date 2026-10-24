## Reused from economy-consumer-access-20261022/merchant/merchant_market_network.gd; value projection only.
extends RefCounted
## Detached, observer-scoped projection of the existing local stock/cargo authority.
## No inventory, cash, routing, country warehouse or price state is owned here.
## Stable place IDs are independent of optional jurisdiction/centre annotations.

static func _node(nodes: Dictionary, place: String, jurisdictions: Dictionary, centres: Dictionary) -> void:
	if place.is_empty() or nodes.has(place): return
	nodes[place] = {"node_id": place, "place_id": place, "jurisdiction": jurisdictions.get(place, ""), "centre": centres.get(place, ""), "known_own_sites": [], "known_own_stock_by_good": {}, "known_own_free_by_good": {}, "known_own_reserved_by_good": {}}

static func _add(target: Dictionary, source: Dictionary) -> void:
	for good: String in source:
		target[good] = int(target.get(good, 0)) + int(source[good])

static func project(firm: Dictionary, jurisdictions: Dictionary = {}, centres: Dictionary = {}) -> Dictionary:
	var nodes: Dictionary = {}
	var sites: Dictionary = {}
	var orders: Dictionary = {}
	var cargo: Dictionary = {}
	var edges: Dictionary = {}
	var issues: Array[String] = []
	var stock: Dictionary = {}
	var in_transit: Dictionary = {}
	for operation: Dictionary in firm.get("operations", []):
		var site: String = str(operation.get("site_id", ""))
		var place: String = str(operation.get("stock_place_id", ""))
		if site.is_empty() or place.is_empty(): issues.append("SITE_IDENTITY_MISSING"); continue
		if sites.has(site): issues.append("DUPLICATE_SITE:" + site); continue
		sites[site] = place
		_node(nodes, place, jurisdictions, centres)
		var n: Dictionary = nodes[place]
		n["known_own_sites"].append(site)
		_add(n["known_own_stock_by_good"], operation.get("inventory", {}))
		_add(n["known_own_free_by_good"], operation.get("free_inventory", {}))
		_add(n["known_own_reserved_by_good"], operation.get("committed_inventory", {}))
		_add(stock, operation.get("inventory", {}))
	var buy_orders: Array = firm.get("orders") if firm.get("orders") is Array else []
	var sale_orders: Array = firm.get("sales_orders") if firm.get("sales_orders") is Array else []
	for order: Dictionary in buy_orders + sale_orders:
		var id: String = str(order.get("id", ""))
		if id.is_empty(): issues.append("ORDER_IDENTITY_MISSING"); continue
		if orders.has(id): continue # Own transfer may be in both authorized lists.
		orders[id] = true
		var origin: String = str(order.get("from_place_id", ""))
		var destination: String = str(order.get("to_place_id", ""))
		_node(nodes, origin, jurisdictions, centres)
		_node(nodes, destination, jurisdictions, centres)
		var good: String = str(order.get("good", ""))
		var edge: Dictionary = {"order_id": id, "from_node": origin, "to_node": destination, "good": good, "route_id": order.get("route_id", ""), "pending_responsibility": order.get("pending", 0), "transit_responsibility": order.get("transit", 0), "delivered": order.get("delivered", 0), "cargo_ids": []}
		for shipment: Dictionary in order.get("shipments", []):
			var sid: String = str(shipment.get("id", ""))
			if sid.is_empty(): issues.append("CARGO_IDENTITY_MISSING"); continue
			if cargo.has(sid):
				if cargo[sid]["order_id"] != id: issues.append("CARGO_REFERENCED_BY_MULTIPLE_ORDERS:" + sid)
				continue
			# Contract quantity is NOT a substitute for actual surviving portions.
			var actual: Variant = shipment.get("physical_quantity")
			if not actual is int or actual < 0: issues.append("PHYSICAL_CARGO_UNKNOWN:" + sid); continue
			_node(nodes, str(shipment.get("place_id", "")), jurisdictions, centres)
			cargo[sid] = {"cargo_id": sid, "order_id": id, "good": good, "physical_quantity": actual, "place_id": shipment.get("place_id", ""), "from_node": origin, "to_node": destination, "stage": shipment.get("stage", "UNKNOWN"), "earliest_arrival_day": shipment.get("earliest_arrival_day"), "arrival_blocked_reason": shipment.get("arrival_blocked_reason", "")}
			edge["cargo_ids"].append(sid)
			in_transit[good] = int(in_transit.get(good, 0)) + int(actual)
		edges[id] = edge
	return {"schema": "merchant_local_network_projection_v1", "scope": "AUTHORIZED_OWN_SITES_AND_OWN_CONTRACTS_NOT_ALL_MARKET", "nodes": nodes, "edges": edges, "cargo": cargo, "known_own_stock_by_good": stock, "known_contract_cargo_by_good": in_transit, "issues": issues, "physical_authority": "EXISTING_STOCK_LOTS", "aggregate_warehouse_created": false, "price_propagation_implemented": false}
