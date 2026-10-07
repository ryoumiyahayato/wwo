extends RefCounted
## Synthetic summaries only. A parent never calls a combat resolver.
const STOCKS: Array[String] = ["personnel_total", "effective", "casualties", "equipment",
	"equipment_lost", "ammunition", "ammo_spent"]
var stock_keys: Array[String] = STOCKS.duplicate()
var nodes: Dictionary = {}
var dirty: Dictionary = {}
var counters: Dictionary = {"spatial_nodes_examined": 0, "parent_nodes_updated": 0}

func configure() -> void:
	nodes.clear()
	_add("region_50", "", 50.0, Vector2.ZERO)
	for parent: int in range(4):
		var parent_id: String = "parent_%02d" % parent
		var origin: Vector2 = Vector2(parent % 2, parent / 2) * 25.0
		_add(parent_id, "region_50", 25.0, origin)
		for child: int in range(25):
			var cell: String = "cell_%03d" % (parent * 25 + child)
			_add(cell, parent_id, 5.0, origin + Vector2(child % 5, child / 5) * 5.0)
	for id: String in nodes:
		nodes[id].control_counts = {"": 1 if nodes[id].children.is_empty() else (100 if id == "region_50" else 25)}

func _add(id: String, parent: String, extent: float, origin: Vector2) -> void:
	var stocks: Dictionary = {}
	for key: String in stock_keys:
		stocks[key] = 0.0
	nodes[id] = {"id": id, "parent": parent, "children": {}, "extent_km": extent,
		"origin_km": [origin.x, origin.y], "stocks": stocks, "control_counts": {}, "dirty": false}
	if not parent.is_empty():
		nodes[parent].children[id] = true

func update_leaf(id: String, stocks: Dictionary, control: String) -> bool:
	if not nodes.has(id) or not nodes[id].children.is_empty():
		return false
	var leaf: Dictionary = nodes[id]
	var previous_control: String = str(leaf.get("control", ""))
	var delta: Dictionary = {}
	var changed: bool = previous_control != control
	for key: String in stock_keys:
		delta[key] = float(stocks.get(key, 0.0)) - float(leaf.stocks[key])
		changed = changed or delta[key] != 0.0
	if not changed:
		return true
	leaf.control = control
	var cursor: String = id
	while not cursor.is_empty():
		counters.spatial_nodes_examined += 1
		var node: Dictionary = nodes[cursor]
		for key: String in stock_keys:
			node.stocks[key] += float(delta[key])
		if previous_control != control:
			node.control_counts[previous_control] = int(node.control_counts.get(previous_control, 0)) - 1
			node.control_counts[control] = int(node.control_counts.get(control, 0)) + 1
		node.dirty = true
		dirty[cursor] = true
		if cursor != id:
			counters.parent_nodes_updated += 1
		cursor = str(node.parent)
	return true

func extend_stocks(keys: Array[String]) -> void:
	for key: String in keys:
		if key not in stock_keys:
			stock_keys.append(key)
			for id: String in nodes:
				nodes[id].stocks[key] = 0.0

func clear_dirty() -> void:
	for id: String in dirty:
		nodes[id].dirty = false
	dirty.clear()

func view(id: String) -> Dictionary:
	return nodes[id].duplicate(true) if nodes.has(id) else {}

func leaf_descendants(id: String) -> Array[String]:
	var result: Array[String] = []
	if not nodes.has(id):
		return result
	if nodes[id].children.is_empty():
		result.append(id)
	else:
		var children: Array = nodes[id].children.keys()
		children.sort()
		for child: String in children:
			result.append_array(leaf_descendants(child))
	return result
