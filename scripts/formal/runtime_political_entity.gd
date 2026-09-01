class_name RuntimePoliticalEntity
extends RefCounted
## Runtime identity value object. Historical records are referenced by immutable
## source IDs; historical controller fields are intentionally absent.

const STATUS_ACTIVE: String = "active"
const ORIGIN_HISTORICAL_SEED: String = "historical_seed"

var runtime_id: String = ""
var source_historical_ids: Array[String] = []
var lifecycle_status: String = STATUS_ACTIVE
var lineage: Dictionary = {}


static func historical_seed(source_historical_id: String) -> RuntimePoliticalEntity:
	var entity := RuntimePoliticalEntity.new()
	entity.runtime_id = runtime_id_for_historical_source(source_historical_id)
	entity.source_historical_ids = [source_historical_id]
	entity.lifecycle_status = STATUS_ACTIVE
	entity.lineage = {
		"origin_kind": ORIGIN_HISTORICAL_SEED,
		"origin_tick": 0,
		"predecessor_runtime_ids": [],
	}
	return entity


static func runtime_id_for_historical_source(source_historical_id: String) -> String:
	return VNextStableId.compose("state", source_historical_id)


func snapshot() -> Dictionary:
	return {
		"runtime_id": runtime_id,
		"source_historical_ids": source_historical_ids.duplicate(),
		"lifecycle_status": lifecycle_status,
		"lineage": lineage.duplicate(true),
	}
