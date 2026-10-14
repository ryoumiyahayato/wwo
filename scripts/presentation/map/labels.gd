class_name GlobeLabels
extends RefCounted
var _glyphs: Dictionary = {}
var label_rects: Array[Rect2] = []

static func font_for_name(font: Font, text: String) -> Font:
	# Use one authored face for the complete name, including its punctuation.
	var primary := font.get_rids()[0] as RID
	var server := TextServerManager.get_primary_interface()
	for character: String in text:
		if not server.font_has_char(primary,character.unicode_at(0)):
			for fallback: Font in font.fallbacks:
				var complete := true
				for item: String in text:
					if not fallback.has_char(item.unicode_at(0)): complete = false; break
				if complete: return fallback
	return font

func clear() -> void:
	label_rects.clear()
	_glyphs.clear()

func update(canvas: CanvasItem, font: Font, anchors: Dictionary, records: Dictionary, bounds: Rect2, zoom: float, selected: String, hovered: String, enabled: bool, visible: bool, exclusions: Array[Rect2] = []) -> void:
	label_rects.clear()
	for entity_id: String in _glyphs.keys():
		var record := records.get(entity_id,{}) as Dictionary
		var name := str(record.get("short_name_zh",record.get("name_zh",record.get("name",entity_id))))
		var glyph := _glyphs[entity_id] as Dictionary
		if record.is_empty() or str(glyph.name) != name:
			_glyphs.erase(entity_id)
	if not visible or not enabled: return
	var occupied: Array[Rect2] = exclusions.duplicate()
	var candidates: Array[Dictionary] = []
	for entity_id: String in anchors:
		var record := records.get(entity_id,{}) as Dictionary
		var rank := int(record.get("label_rank",record.get("rank",9)))
		if rank > (4 if zoom < 3.5 else 9) and entity_id != selected and entity_id != hovered: continue
		candidates.append({"id":entity_id,"rank":-1 if entity_id == selected or entity_id == hovered else rank})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.rank) < int(b.rank))
	for candidate: Dictionary in candidates:
		var entity_id := str(candidate.id)
		var record := records.get(entity_id,{}) as Dictionary
		var name := str(record.get("short_name_zh",record.get("name_zh",record.get("name",entity_id))))
		if not _glyphs.has(entity_id):
			var label_font := font_for_name(font,name)
			var font_size := 15 if bool(record.get("geography",false)) else 16 if int(record.get("label_rank",record.get("rank",9)))<=3 else 14
			_glyphs[entity_id] = {"name":name,"size":label_font.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size),"font":label_font,"font_size":font_size}
		var glyph := _glyphs[entity_id] as Dictionary
		var rect := Rect2((anchors[entity_id] as Vector2)-(glyph.size as Vector2)*0.5,glyph.size as Vector2)
		if not bounds.encloses(rect): continue
		var overlaps := false
		for existing: Rect2 in occupied:
			if existing.intersects(rect.grow(3.0)): overlaps = true
		if overlaps or occupied.size() >= 42: continue
		occupied.append(rect)
		label_rects.append(rect)
		# Draw current atlas glyphs through the same CanvasItem API as ordinary UI.
		canvas.draw_string(glyph.font as Font,rect.position+Vector2(0,float(glyph.font_size)-1.0),name,HORIZONTAL_ALIGNMENT_LEFT,-1,int(glyph.font_size),Color(0.92,0.88,0.77,1.0))
