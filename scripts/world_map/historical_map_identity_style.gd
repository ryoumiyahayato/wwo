class_name HistoricalMapIdentityStyle
extends RefCounted
## Reusable visual identity encoding for entities that share similar map colors.

const PATTERN_PREFIX: String = "identity:"
const PATTERN_SEPARATOR: String = "::"
const CODE_MIN_U: float = 0.585
const CODE_MIN_V: float = 0.625
const CODE_RADIUS: float = 0.037
const CODE_PLATE_COLOR: Color = Color(0.08, 0.10, 0.10, 1.0)
const CODE_PLATE_BLEND: float = 0.34
const CODE_COLUMN_CENTERS: Array[float] = [0.625, 0.708333, 0.791667, 0.875]
const CODE_ROW_CENTERS: Array[float] = [0.6875, 0.8125]


static func encode_entity_pattern(
	entity_id: String,
	base_pattern: String,
	entity_records: Dictionary,
	eligible_entities: Dictionary
) -> String:
	var entity: Dictionary = entity_records.get(entity_id, {}) as Dictionary
	if entity.is_empty() or bool(entity.get("provisional", false)):
		return base_pattern
	var ordinal: int = _eligible_entity_ordinal(
		entity_id, entity_records, eligible_entities
	)
	return "%s%d%s%s" % [
		PATTERN_PREFIX, ordinal, PATTERN_SEPARATOR, base_pattern,
	]


static func decode_pattern(pattern: String) -> Dictionary:
	if not pattern.begins_with(PATTERN_PREFIX):
		return {}
	var separator_index: int = pattern.find(PATTERN_SEPARATOR)
	if separator_index < 0:
		return {}
	var ordinal_text: String = pattern.substr(
		PATTERN_PREFIX.length(),
		separator_index - PATTERN_PREFIX.length()
	)
	if not ordinal_text.is_valid_int():
		return {}
	return {
		"ordinal": int(ordinal_text),
		"base_pattern": pattern.substr(
			separator_index + PATTERN_SEPARATOR.length()
		),
	}


static func apply_identity_code(
	base: Color,
	colors: PackedColorArray,
	ordinal: int,
	u: float,
	v: float,
	contrast_provider: Callable
) -> Color:
	if u < CODE_MIN_U or v < CODE_MIN_V:
		return base
	var plate: Color = base.lerp(CODE_PLATE_COLOR, CODE_PLATE_BLEND)
	var contrast: Color = contrast_provider.call(colors, plate)
	var code: int = ordinal + 1
	var bit: int = 0
	for row: float in CODE_ROW_CENTERS:
		for column: float in CODE_COLUMN_CENTERS:
			if Vector2(u, v).distance_to(Vector2(column, row)) < CODE_RADIUS:
				return contrast if (code & (1 << bit)) != 0 else plate
			bit += 1
	return plate


static func _eligible_entity_ordinal(
	entity_id: String,
	entity_records: Dictionary,
	eligible_entities: Dictionary
) -> int:
	var ids: Array[String] = []
	for entity_key: Variant in eligible_entities.keys():
		var candidate_id: String = str(entity_key)
		var entity: Dictionary = (
			entity_records.get(candidate_id, {}) as Dictionary
		)
		if not entity.is_empty() and not bool(entity.get("provisional", false)):
			ids.append(candidate_id)
	ids.sort()
	return maxi(0, ids.find(entity_id))
