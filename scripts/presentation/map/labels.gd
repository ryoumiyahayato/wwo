class_name GlobeLabels
extends RefCounted

static func draw(canvas: CanvasItem, font: Font, anchors: Dictionary, records: Dictionary, bounds: Rect2, zoom: float, selected: String, hovered: String, enabled: bool) -> void:
	var occupied: Array[Rect2] = []
	var candidates: Array[Dictionary] = []
	for raw_id: Variant in anchors:
		var entity_id := str(raw_id)
		var record := records.get(entity_id, {}) as Dictionary
		if not enabled and entity_id != selected and entity_id != hovered:
			continue
		if int(record.get("label_rank", 9)) > (4 if zoom < 3.5 else 9) and entity_id != selected and entity_id != hovered:
			continue
		candidates.append({"id": entity_id, "rank": -1 if entity_id == selected or entity_id == hovered else int(record.get("label_rank", 9))})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.rank) < int(b.rank))
	for candidate: Dictionary in candidates:
		var entity_id := str(candidate.id)
		var record := records.get(entity_id, {}) as Dictionary
		var point := anchors[entity_id] as Vector2
		var name := str(record.get("short_name_zh", record.get("name_zh", entity_id)))
		var rect := Rect2(point + Vector2(8.0, -15.0), Vector2(maxf(42.0, name.length() * 10.5), 18.0))
		if not bounds.encloses(rect):
			continue
		var overlaps := false
		for existing: Rect2 in occupied:
			if existing.intersects(rect.grow(3.0)):
				overlaps = true
		if overlaps or occupied.size() >= 42:
			continue
		occupied.append(rect)
		UIDrawing.label(canvas, font, rect.position + Vector2(0.0, 13.0), name, 11)
