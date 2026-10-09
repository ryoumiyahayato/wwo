class_name GlobeLabels
extends RefCounted
var _glyphs: Dictionary = {}

func clear() -> void:
	for glyph: Dictionary in _glyphs.values():
		if (glyph.item as RID).is_valid(): RenderingServer.free_rid(glyph.item as RID)
	_glyphs.clear()

func update(parent: RID, font: Font, anchors: Dictionary, records: Dictionary, bounds: Rect2, zoom: float, selected: String, hovered: String, enabled: bool, visible: bool) -> void:
	for glyph: Dictionary in _glyphs.values():
		if (glyph.item as RID).is_valid(): RenderingServer.canvas_item_set_visible(glyph.item as RID,false)
	if not visible: return
	var occupied: Array[Rect2] = []
	var candidates: Array[Dictionary] = []
	for entity_id: String in anchors:
		var record := records.get(entity_id,{}) as Dictionary
		if not enabled and entity_id != selected and entity_id != hovered: continue
		if int(record.get("label_rank",9)) > (4 if zoom < 3.5 else 9) and entity_id != selected and entity_id != hovered: continue
		candidates.append({"id":entity_id,"rank":-1 if entity_id == selected or entity_id == hovered else int(record.get("label_rank",9))})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.rank) < int(b.rank))
	for candidate: Dictionary in candidates:
		var entity_id := str(candidate.id)
		var record := records.get(entity_id,{}) as Dictionary
		var name := str(record.get("short_name_zh",record.get("name_zh",entity_id)))
		if not _glyphs.has(entity_id):
			_glyphs[entity_id] = {"item":RID(),"size":font.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,16)}
		var glyph := _glyphs[entity_id] as Dictionary
		var rect := Rect2((anchors[entity_id] as Vector2)-(glyph.size as Vector2)*0.5,glyph.size as Vector2)
		if not bounds.encloses(rect): continue
		var overlaps := false
		for existing: Rect2 in occupied:
			if existing.intersects(rect.grow(3.0)): overlaps = true
		if overlaps or occupied.size() >= 42: continue
		occupied.append(rect)
		if not (glyph.item as RID).is_valid():
			glyph.item = RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(glyph.item as RID,parent)
			RenderingServer.canvas_item_set_draw_index(glyph.item as RID,900000)
			font.draw_string(glyph.item as RID,Vector2.ZERO,name,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(0.90,0.91,0.84,1.0))
		RenderingServer.canvas_item_set_transform(glyph.item as RID,Transform2D(0.0,rect.position+Vector2(0,15)))
		RenderingServer.canvas_item_set_visible(glyph.item as RID,true)

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
		var text_size := font.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,16)
		var rect := Rect2(point - text_size * .5, text_size)
		if not bounds.encloses(rect):
			continue
		var overlaps := false
		for existing: Rect2 in occupied:
			if existing.intersects(rect.grow(3.0)):
				overlaps = true
		if overlaps or occupied.size() >= 42:
			continue
		occupied.append(rect)
		UIDrawing.label(canvas, font, rect.position + Vector2(0.0, 15.0), name, 16)
