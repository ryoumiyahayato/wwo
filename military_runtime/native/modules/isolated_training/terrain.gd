extends "res://military_runtime/native/ridgevale/terrain.gd"
## One original streaming/edit/support/collision owner; host supplies the shared appearance.
var material_provider: Object
var fixed_target: Node3D
var startup_usec: Dictionary = {}

func _ridge_material(_is_far: bool) -> ShaderMaterial:
	# Ridgevale's constructor calls this before the provider can be bound.
	# No fallback yellow terrain is shown if the shared material is unavailable.
	return ShaderMaterial.new()

func configure(focus: Vector3 = Vector3.ZERO, original_mesh: MeshInstance3D = null) -> Dictionary:
	var started := Time.get_ticks_usec() if _slow_timing_enabled else 0
	if not is_instance_valid(material_provider) or not material_provider.has_method("create_surface_material"):
		return {"ok": false, "error": "shared_terrain_material_provider_required"}
	close_material = material_provider.call("create_surface_material", {
		"native_surface": true, "coverage_enabled": false, "far_mesh": false,
		"coverage_cells": 100, "detail_coverage": coverage_texture, "use_vertex_damage": true
	}) as ShaderMaterial
	far_material = material_provider.call("create_surface_material", {
		"native_surface": true, "coverage_enabled": true, "far_mesh": true,
		"coverage_cells": 100, "detail_coverage": coverage_texture, "use_vertex_damage": false
	}) as ShaderMaterial
	if close_material == null or far_material == null:
		return {"ok": false, "error": "shared_terrain_material_unavailable"}
	if started>0: startup_usec["materials"] = Time.get_ticks_usec()-started
	return super.configure(focus, original_mesh)

func _build_horizon() -> void:
	var started := Time.get_ticks_usec() if _slow_timing_enabled else 0
	super._build_horizon()
	if started>0: startup_usec["horizon"] = Time.get_ticks_usec()-started

func set_simulation_anchors(positions: Array) -> void:
	var anchors: Array = positions.duplicate()
	if is_instance_valid(fixed_target):
		anchors.append(fixed_target.global_position)
	super.set_simulation_anchors(anchors)
