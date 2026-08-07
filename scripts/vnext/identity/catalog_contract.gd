class_name VNextCatalogContract
extends RefCounted


static func validate(catalog_records: Array) -> bool:
	var seen_canonical_ids: Array[String] = []
	for catalog_record_value: Variant in catalog_records:
		if typeof(catalog_record_value) != TYPE_DICTIONARY:
			return false
		var catalog_record: Dictionary = catalog_record_value
		if not catalog_record.has("id"):
			return false
		var canonical_id_value: Variant = catalog_record.get("id")
		if typeof(canonical_id_value) != TYPE_STRING:
			return false
		var canonical_id: String = canonical_id_value
		if not VNextStableId.is_valid(canonical_id):
			return false
		if seen_canonical_ids.has(canonical_id):
			return false
		seen_canonical_ids.append(canonical_id)
	return true


static func record_by_id(catalog_records: Array, canonical_id: String) -> Variant:
	if not VNextStableId.is_valid(canonical_id):
		return null
	if not validate(catalog_records):
		return null
	for catalog_record_value: Variant in catalog_records:
		var catalog_record: Dictionary = catalog_record_value
		if catalog_record.get("id") == canonical_id:
			return catalog_record
	return null
