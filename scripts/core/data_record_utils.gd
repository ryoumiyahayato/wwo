class_name DataRecordUtils
extends RefCounted
## Conversion helpers used by already-validated core data records.


static func to_string_array(value: Variant) -> Array[String]:
	var output: Array[String] = []
	if not value is Array:
		return output
	for item: Variant in value as Array:
		output.append(str(item))
	return output


static func to_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

