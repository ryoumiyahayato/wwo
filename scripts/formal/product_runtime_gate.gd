class_name ProductRuntimeGate
extends RefCounted
## Fail-closed data boundary for the normal formal product surface.

const MODERN_REFERENCE_PATHS: Array[String] = [
	"res://data/world_map/world_admin1.json",
	"res://data/world_map/country_flag_palettes.json",
	"res://data/world_map/city_detail/index.json",
]

var blocked_documents: Array[Dictionary] = []
var accepted_document_paths: Array[String] = []


func filter_document(path: String, document: Dictionary) -> Dictionary:
	var reason := rejection_reason(path, document)
	if not reason.is_empty():
		blocked_documents.append({"path": path, "reason": reason})
		return {}
	if path not in accepted_document_paths:
		accepted_document_paths.append(path)
	return document


func rejection_reason(path: String, document: Dictionary) -> String:
	if bool(document.get("prototype_only", false)):
		return "prototype_only"
	if document.has("prototype_notice"):
		return "prototype_notice"
	if path in MODERN_REFERENCE_PATHS or path.begins_with(
		"res://data/world_map/city_detail/"
	):
		return "modern_reference_only"
	if str(document.get("historical_status", "")) == "modern_reference_only":
		return "modern_reference_only"
	return ""


func runtime_report(
	presentation_state: Dictionary,
	domain_owner_state: Dictionary,
	entry_scene: String,
	runtime_scene: String
) -> Dictionary:
	var prototype_visible_count := int(
		presentation_state.get("prototype_visible_count", -1)
	)
	var spike_city_count := int(presentation_state.get("spike_city_count", -1))
	var false_domain_count := 0
	for domain_value: Variant in domain_owner_state.values():
		if not domain_value is Dictionary:
			continue
		var domain := domain_value as Dictionary
		if bool(domain.get("claimed_active", false)) and domain.get("owner") == null:
			false_domain_count += 1
	var spatial_owner_id := int(
		presentation_state.get("spatial_owner_instance_id", 0)
	)
	var projection_owner_id := int(
		presentation_state.get("spatial_projection_owner_instance_id", -1)
	)
	return {
		"prototype_dependency": (
			"PASS" if prototype_visible_count == 0 else "FAIL"
		),
		"prototype_visible_count": prototype_visible_count,
		"blocked_document_count": blocked_documents.size(),
		"fixture_dependency": (
			"PASS"
			if int(presentation_state.get("fixture_dependency_count", -1)) == 0
			else "FAIL"
		),
		"spike_cities": "PASS" if spike_city_count == 0 else "FAIL",
		"spike_city_count": spike_city_count,
		"false_domain_activation": (
			"PASS" if false_domain_count == 0 else "FAIL"
		),
		"false_domain_count": false_domain_count,
		"spatial_prototype_truth": (
			"PASS"
			if int(presentation_state.get("spatial_normal_product_count", -1)) == 0
			else "FAIL"
		),
		"spatial_normal_product_count": int(
			presentation_state.get("spatial_normal_product_count", -1)
		),
		"spatial_single_owner": (
			"PASS"
			if spatial_owner_id > 0 and spatial_owner_id == projection_owner_id
			else "FAIL"
		),
		"default_entry": (
			"PASS"
			if entry_scene == "res://scenes/formal/formal_world_menu.tscn"
			and runtime_scene == "res://scenes/formal/formal_world_main.tscn"
			else "FAIL"
		),
	}
