class_name RegionView
extends RefCounted
## Cached regional canvas sharing the Globe's immutable GPU geometry.

const PREPARE_BUDGET_USEC: int = 2000
var container: SubViewportContainer
var viewport: SubViewport
var surfaces: Dictionary = {}
var boundaries: Array[Dictionary] = []
var ready: bool = false
var preparing: bool = false
var preparation_usec: int = 0
var _owners: Array = []
var _cursor: int = 0
var _background: RID
var background: Dictionary = {}
var _labels: Array[Dictionary] = []
var label_prepare_count: int = 0
var glyph_submit_count: int = 0
var country_label_rects: Array[Rect2] = []

func initialize(parent: Control) -> void:
	container = SubViewportContainer.new()
	container.name = "RegionViewportContainer"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.show_behind_parent = true
	container.stretch = true
	container.visible = false
	parent.add_child(container)
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(viewport)
	_background = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_background, viewport.world_2d.canvas)
	RenderingServer.canvas_item_set_draw_index(_background, 0)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/presentation/map/relief_background.gdshader") as Shader
	RenderingServer.canvas_item_set_material(_background, material.get_rid())
	background = {"material": material, "item": _background}

func resize(viewport_size: Vector2) -> void:
	if container.size == viewport_size:
		return
	container.size = viewport_size
	RenderingServer.canvas_item_clear(_background)
	RenderingServer.canvas_item_add_rect(_background, Rect2(Vector2.ZERO, viewport_size), Color(0.10, 0.14, 0.16))

func begin(source: Dictionary) -> void:
	clear()
	_owners = source.keys()
	_cursor = 0
	preparation_usec = 0
	preparing = true

func prepare_step(source: Dictionary, lines: Array[Dictionary]) -> void:
	var started := Time.get_ticks_usec()
	while _cursor < _owners.size():
		var owner := str(_owners[_cursor])
		var original := source[owner] as Dictionary
		var material := (original.material as ShaderMaterial).duplicate() as ShaderMaterial
		material.set_shader_parameter("region_mode", true)
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, viewport.world_2d.canvas)
		RenderingServer.canvas_item_set_draw_index(item, _cursor + 1)
		RenderingServer.canvas_item_set_material(item, material.get_rid())
		surfaces[owner] = {"geometry": original.geometry, "material": material, "item": item, "texture": RID()}
		_cursor += 1
		if Time.get_ticks_usec() - started >= PREPARE_BUDGET_USEC:
			preparation_usec += Time.get_ticks_usec() - started
			return
	for original: Dictionary in lines:
		var material := (original.material as ShaderMaterial).duplicate() as ShaderMaterial
		material.set_shader_parameter("region_mode", true)
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, viewport.world_2d.canvas)
		RenderingServer.canvas_item_set_draw_index(item, LocalSpatialLayer.DRAW_ORDER + 2 if str(original.get("kind", "")) == "macro" else surfaces.size() + boundaries.size() + 1)
		RenderingServer.canvas_item_set_material(item, material.get_rid())
		RenderingServer.canvas_item_add_mesh(item, (original.geometry as GlobeBoundaryBatch).mesh.get_rid())
		boundaries.append({"geometry": original.geometry, "material": material, "item": item, "kind": original.get("kind", "")})
	preparation_usec += Time.get_ticks_usec() - started
	preparing = false
	ready = true

func clear() -> void:
	clear_labels()
	background.erase("surface_relief_style")
	background.erase("surface_appearance_style")
	for batch: Dictionary in surfaces.values():
		RenderingServer.free_rid(batch.item as RID)
	for batch: Dictionary in boundaries:
		RenderingServer.free_rid(batch.item as RID)
	surfaces.clear()
	boundaries.clear()
	ready = false
	preparing = false

func clear_labels() -> void:
	for label: Dictionary in _labels:
		if (label.item as RID).is_valid():
			RenderingServer.free_rid(label.item as RID)
	_labels.clear()

func prepare_labels(candidates: Array[Dictionary], font: Font, country_font: Font = null) -> void:
	clear_labels()
	label_prepare_count += 1
	_labels = candidates
	_labels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.rank) < int(b.rank))
	for label: Dictionary in _labels:
		label["item"] = RID()
		label["font"] = country_font if not bool(label.place) and country_font != null else font
		label["text_size"] = (label.font as Font).get_string_size(str(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(label.font_size))

func update_labels(camera: RegionCamera, controller: GlobeController, font: Font, viewport_size: Vector2, shard_places: Dictionary = {}, reserved_labels: Array[Rect2] = []) -> void:
	country_label_rects.clear()
	var occupied: Array[Rect2] = reserved_labels.duplicate()
	var axes := RegionProjection.screen_axes(camera.bearing)
	var bounds := Rect2(Vector2.ZERO, viewport_size)
	# Glyph commands survive camera changes. Only transforms/visibility and the
	# small visible collision set change; no text shaping or spherical projection.
	for label: Dictionary in _labels:
		if (label.item as RID).is_valid():
			RenderingServer.canvas_item_set_visible(label.item as RID, false)
	if camera.local_active:
		return
	for priority: int in range(3):
		for label: Dictionary in _labels:
			var place := bool(label.place)
			if place and shard_places.has(str(label.id)):
				continue
			var selected := str(label.id) == (controller.selected_place_id if place else controller.selected_polity_id)
			var hovered := str(label.id) == (controller.hovered_place_id if place else controller.hovered_polity_id)
			var order := 0 if selected else 1 if hovered else 2
			if priority != order:
				continue
			var detailed := controller.labels_enabled and (camera.km_per_pixel <= RegionCamera.PLACE_LABEL_KM_PER_PIXEL if place else true)
			if not detailed and not selected and not hovered:
				continue
			var point := camera.origin + axes * ((label.km as Vector2) / camera.km_per_pixel)
			if not place and label.has("candidates"):
				var candidates := label.candidates as Array[Dictionary]
				var index := int(label.candidate_index)
				if not bounds.grow(-40.0).has_point(point):
					var distance := INF
					for candidate_index: int in range(candidates.size()):
						var candidate_point := camera.origin + axes * ((candidates[candidate_index].km as Vector2) / camera.km_per_pixel)
						if bounds.grow(-40.0).has_point(candidate_point) and candidate_point.distance_squared_to(bounds.get_center()) < distance:
							distance = candidate_point.distance_squared_to(bounds.get_center())
							index = candidate_index
					label.candidate_index = index
				label.km = candidates[index].km
				point = camera.origin + axes * ((label.km as Vector2) / camera.km_per_pixel)
				var room := minf(float(candidates[index].clearance_km) / camera.km_per_pixel, viewport_size.y * 0.35)
				var font_size := clampi(int(room * 0.14 / 4.0) * 4, 16, 28)
				if font_size != int(label.font_size):
					if (label.item as RID).is_valid(): RenderingServer.free_rid(label.item as RID)
					label.item = RID()
					label.font_size = font_size
					label.text_size = (label.font as Font).get_string_size(str(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
			var offset := Vector2(7.0, -6.0) if place else Vector2(-(label.text_size as Vector2).x * 0.5, float(label.font_size)*0.35)
			var rect := Rect2(point + offset - Vector2(0.0, float(label.font_size)), (label.text_size as Vector2) + Vector2(0.0, 3.0))
			if not bounds.encloses(rect) or occupied.size() >= 42:
				continue
			var overlaps := false
			for existing: Rect2 in occupied:
				overlaps = overlaps or existing.intersects(rect.grow(3.0))
			if overlaps:
				continue
			occupied.append(rect)
			if not place: country_label_rects.append(rect)
			if not (label.item as RID).is_valid():
				var item := RenderingServer.canvas_item_create()
				RenderingServer.canvas_item_set_parent(item, viewport.world_2d.canvas)
				RenderingServer.canvas_item_set_draw_index(item, LocalSpatialLayer.DRAW_ORDER + 3 + _labels.find(label))
				var label_font := label.font as Font
				label_font.draw_string_outline(item, offset, str(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(label.font_size), 2, Color(0.08,0.12,0.13,0.75))
				label_font.draw_string(item, offset, str(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(label.font_size), Color(0.90, 0.91, 0.84))
				label["item"] = item
				glyph_submit_count += 1
			RenderingServer.canvas_item_set_transform(label.item as RID, Transform2D(0.0, point))
			RenderingServer.canvas_item_set_visible(label.item as RID, true)

func dispose() -> void:
	clear()
	if _background.is_valid():
		RenderingServer.free_rid(_background)
