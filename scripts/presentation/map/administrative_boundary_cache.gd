class_name AdministrativeBoundaryCache
extends RefCounted
## Presentation-only seam for a future detached administrative-membership view.
## Region identity is a mutable grouping of territory IDs, not a source polygon.
## No sovereignty/control inference, membership mutation or polygon union here.
var _revisions: Dictionary = {}
var _dirty: Dictionary = {}
var _geometry: Dictionary = {}

func membership_changed(affected_region_ids: Array[String], revision: int) -> void:
	for region_id: String in affected_region_ids:
		if revision <= int(_revisions.get(region_id, -1)):
			continue
		_revisions[region_id] = revision
		_dirty[region_id] = true
		_geometry.erase(region_id)

func store(region_id: String, revision: int, geometry: Array[Dictionary]) -> bool:
	if not _dirty.has(region_id) or int(_revisions.get(region_id, -1)) != revision:
		return false
	_geometry[region_id] = geometry.duplicate(true)
	_dirty.erase(region_id)
	return true

func dirty_regions() -> Array[String]:
	var result: Array[String] = []
	result.assign(_dirty.keys())
	result.sort()
	return result

func boundaries(region_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign((_geometry.get(region_id, []) as Array).duplicate(true))
	return result
