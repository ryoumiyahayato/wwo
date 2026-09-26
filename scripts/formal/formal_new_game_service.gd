class_name FormalNewGameService
extends RefCounted
## Narrow product transaction for selecting exactly one population-backed player.
## Preview owns no FormalWorldSimulation and uses a private generation RNG.

const RULES_VERSION: String = "formal_player_generation_v1"
const CANDIDATE_COUNT: int = 3
const DEFAULT_BIRTH_YEAR_MIN: int = 1860
const DEFAULT_BIRTH_YEAR_MAX: int = 1882
const SUPPORTED_FIELDS: Array[String] = [
	"population_origin_id",
	"start_place_id",
	"birth_year_min",
	"birth_year_max",
	"random_origin",
	"locked_fields",
	"seed",
	"rules_version",
	"draft_index",
]
const UNSUPPORTED_FIELDS: Array[String] = [
	"social_origin",
	"occupation",
	"officer",
	"civil_servant",
	"worker",
	"skills",
	"aptitude",
	"wage",
	"wealth",
	"relationships",
	"challenge",
]

var _catalog: Dictionary = {}
var _catalog_error: String = ""
var _preview_epoch: int = 0
var _candidates_by_token: Dictionary = {}
var _consumed_tokens: Dictionary = {}
var _completed_requests: Dictionary = {}


func start_catalog() -> Dictionary:
	if _catalog.is_empty() and not _build_catalog():
		return {
			"available": false,
			"reason": _catalog_error,
			"rules_version": RULES_VERSION,
		}
	return _catalog.duplicate(true)


func preview_player_candidates(request: Dictionary) -> Dictionary:
	var catalog := start_catalog()
	if not bool(catalog.get("available", false)):
		return _fail("catalog_unavailable", str(catalog.get("reason", "")))
	var validation_error := _validate_preview_request(request)
	if not validation_error.is_empty():
		return _fail("invalid_request", validation_error)

	_preview_epoch += 1
	_candidates_by_token.clear()
	var locked := request.get("locked_fields", {}) as Dictionary
	var seed_value := int(request.get("seed", 0))
	var draft_index := int(request.get("draft_index", 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ (draft_index * 104729) ^ RULES_VERSION.hash()
	var candidates: Array[Dictionary] = []
	for candidate_index: int in CANDIDATE_COUNT:
		var candidate := _generate_candidate(
			request, locked, rng, seed_value, draft_index, candidate_index
		)
		if candidate.is_empty():
			return _fail("candidate_generation_failed", _catalog_error)
		var token_payload := candidate.duplicate(true)
		var token := JSON.stringify({
			"catalog": _catalog.get("source_catalog_fingerprint", ""),
			"epoch": _preview_epoch,
			"candidate": token_payload,
		}).sha256_text()
		candidate["candidate_token"] = token
		candidate["display_label"] = _stable_label_for_token(token)
		_candidates_by_token[token] = {
			"epoch": _preview_epoch,
			"population_fingerprint": _catalog.get("population_fingerprint", ""),
			"place_mapping_fingerprint": _catalog.get("place_mapping_fingerprint", ""),
			"candidate": candidate.duplicate(true),
		}
		candidates.append(candidate)
	return {
		"success": true,
		"rules_version": RULES_VERSION,
		"draft_index": draft_index,
		"candidate_count": candidates.size(),
		"candidates": candidates,
		"population_fingerprint": _catalog.get("population_fingerprint", ""),
		"place_mapping_fingerprint": _catalog.get("place_mapping_fingerprint", ""),
	}


func create_new_game(candidate_token: String, request_id: String) -> Dictionary:
	if request_id.is_empty():
		return _fail("invalid_request_id", "新局 request_id 不能为空。")
	if _completed_requests.has(request_id):
		return (_completed_requests[request_id] as Dictionary).duplicate()
	if candidate_token.is_empty() or not _candidates_by_token.has(candidate_token):
		return _fail("stale_candidate", "候选已失效，请重新预览。")
	if _consumed_tokens.has(candidate_token):
		return _fail("stale_candidate", "候选已经用于另一项新局事务。")
	var record := _candidates_by_token[candidate_token] as Dictionary
	if (
		int(record.get("epoch", -1)) != _preview_epoch
		or str(record.get("population_fingerprint", ""))
		!= str(_catalog.get("population_fingerprint", ""))
		or str(record.get("place_mapping_fingerprint", ""))
		!= str(_catalog.get("place_mapping_fingerprint", ""))
	):
		return _fail("stale_candidate", "人口或地点目录已经变化，请重新预览。")
	var candidate := (record.get("candidate", {}) as Dictionary).duplicate(true)
	var origin_id := str(candidate.get("population_origin_id", ""))
	var origin := _origin_by_id(origin_id)
	if origin.is_empty() or int(origin.get("anonymous_population", 0)) <= 0:
		return _fail("population_exhausted", "所选人口来源没有可覆盖的匿名人口。")
	var place_id := str(candidate.get("start_place_id", ""))
	if not _origin_has_place(origin, place_id):
		return _fail("incompatible_source_place", "人口来源与起始地点不相容。")

	var suffix := candidate_token.left(12)
	var person_id := "person:formal_player_%s" % suffix
	var claim_id := "formal_population_claim:%s:%s" % [origin_id, suffix]
	var start_plan := {
		"person_id": person_id,
		"claim_id": claim_id,
		"population_source_id": origin_id,
		"start_place_id": place_id,
		"basic_demographic_identity": {
			"birth_year": int(candidate.get("birth_year", 0)),
			"sex": "unspecified",
			"basis": "generated_simulation_assumption",
			"joint_distribution_claimed": false,
		},
		"provenance": {
			"kind": "generated",
			"basis": "simulation_assumption",
			"population_source_kind": "formal_population_evidence_aggregate",
			"population_source_revision": _catalog.get("population_revision", ""),
			"population_source_fingerprint": _catalog.get("population_fingerprint", ""),
			"territory_mutation_converged": false,
			"prototype_character_source": false,
			"legacy_loran_vesta_source": false,
			"generation_rules_version": RULES_VERSION,
			"generation_seed": int(candidate.get("seed", 0)),
			"accepted_draft_index": int(candidate.get("draft_index", 0)),
			"source_catalog_fingerprint": _catalog.get("source_catalog_fingerprint", ""),
		},
	}
	var world := FormalWorldSimulation.new(null, [], [], start_plan)
	if not world.initialize():
		return _fail("world_initialization_failed", world.initialization_error)
	var context := world.player_context_view()
	var claim := world.formal_person_population_claim(person_id)
	var population_total := int(origin.get("population", 0))
	var claimed_count := population_total - world.formal_person_anonymous_population(origin_id)
	if (
		world.formal_person_count() != 1
		or world.player_person_id() != person_id
		or str(claim.get("claim_id", "")) != claim_id
		or not bool(claim.get("active", false))
		or claimed_count != 1
		or world.formal_person_anonymous_population(origin_id) + claimed_count
		!= population_total
		or str(context.get("person_id", "")) != person_id
	):
		return _fail("final_validation_failed", "新局最终人物/人口守恒验证失败。")
	var result := {
		"success": true,
		"world": world,
		"player_person_id": person_id,
		"claim_id": claim_id,
		"candidate": candidate,
		"population_total": population_total,
		"active_claim_count": claimed_count,
		"anonymous_population": world.formal_person_anonymous_population(origin_id),
	}
	_consumed_tokens[candidate_token] = request_id
	_completed_requests[request_id] = result
	return result.duplicate()


func _build_catalog() -> bool:
	_catalog_error = ""
	var provenance := HistoricalProvenanceFoundation.new()
	if not provenance.load_current():
		_catalog_error = provenance.initialization_error
		return false
	var evidence := FormalWorldEconomicEvidenceCatalog.new()
	if not evidence.configure(provenance.gate()):
		_catalog_error = evidence.initialization_error
		return false
	var population := FormalWorldPopulationInputView.new(evidence.population_snapshot())
	var economic := FormalWorldEconomicStaticView.new(evidence.economic_snapshot())
	var spatial := VNextSpatialCatalog.new()
	if not population.is_configured() or not economic.is_configured():
		_catalog_error = "正式人口证据不可用。"
		return false
	if not spatial.load_legacy_world_map():
		_catalog_error = "正式 Spatial 地点目录不可用。"
		return false
	var polity_ids_by_origin: Dictionary = {}
	for origin_id: String in population.economy_entity_ids():
		if spatial.has_country(origin_id):
			polity_ids_by_origin[origin_id] = [origin_id]
	for crosswalk: Dictionary in economic.crosswalk_records():
		var origin_id := str(crosswalk.get("economy_entity_id", ""))
		if not origin_id.is_empty():
			polity_ids_by_origin[origin_id] = DataRecordUtils.to_string_array(
				crosswalk.get("polity_ids", [])
			)

	var all_places: Array[Dictionary] = []
	all_places.append_array(spatial.regions())
	all_places.append_array(spatial.cities())
	all_places.append_array(spatial.ports())
	var origins: Array[Dictionary] = []
	var mapping_facts: Array[Dictionary] = []
	for origin_id: String in population.economy_entity_ids():
		var population_total := population.population(origin_id)
		var polity_ids := (
			polity_ids_by_origin.get(origin_id, []) as Array
		).duplicate()
		polity_ids.sort()
		if population_total <= 0 or polity_ids.is_empty():
			continue
		var places: Array[Dictionary] = []
		for place: Dictionary in all_places:
			if str(place.get("parent_country_id", "")) not in polity_ids:
				continue
			places.append({
				"id": str(place.get("place_id", "")),
				"map_id": str(place.get("map_id", "")),
				"name": str(place.get("name", place.get("display_name_zh", ""))),
				"object_level": str(place.get("object_level", "")),
				"spatial_kind": str(place.get("spatial_kind", "")),
				"parent_country_id": str(place.get("parent_country_id", "")),
			})
		places.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("id", "")) < str(b.get("id", ""))
		)
		if places.is_empty():
			continue
		origins.append({
			"id": origin_id,
			"population": population_total,
			"anonymous_population": population_total,
			"polity_ids": polity_ids,
			"places": places,
		})
		mapping_facts.append({"origin_id": origin_id, "polity_ids": polity_ids, "places": places})
	origins.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	if origins.is_empty():
		_catalog_error = "没有人口证据与 Spatial 地点共同证明的合法起点。"
		return false
	var place_mapping_fingerprint := JSON.stringify(mapping_facts).sha256_text()
	_catalog = {
		"available": true,
		"rules_version": RULES_VERSION,
		"candidate_count": CANDIDATE_COUNT,
		"population_revision": population.revision(),
		"population_fingerprint": population.fingerprint(),
		"place_mapping_fingerprint": place_mapping_fingerprint,
		"source_catalog_fingerprint": JSON.stringify({
			"rules": RULES_VERSION,
			"population": population.fingerprint(),
			"mapping": place_mapping_fingerprint,
		}).sha256_text(),
		"supported_fields": SUPPORTED_FIELDS.duplicate(),
		"unsupported_fields": UNSUPPORTED_FIELDS.duplicate(),
		"origins": origins,
	}
	return true


func _validate_preview_request(request: Dictionary) -> String:
	if str(request.get("rules_version", RULES_VERSION)) != RULES_VERSION:
		return "不支持的生成规则版本。"
	for field_name: String in UNSUPPORTED_FIELDS:
		if request.has(field_name):
			return "字段尚无 Formal owner：%s" % field_name
	for raw_field: Variant in request.get("required_unsupported_fields", []):
		return "字段尚无 Formal owner：%s" % str(raw_field)
	if typeof(request.get("seed", 0)) != TYPE_INT:
		return "seed 必须是整数。"
	if int(request.get("draft_index", 0)) < 0:
		return "draft_index 不能为负。"
	var birth_min := int(request.get("birth_year_min", DEFAULT_BIRTH_YEAR_MIN))
	var birth_max := int(request.get("birth_year_max", DEFAULT_BIRTH_YEAR_MAX))
	if birth_min < 1800 or birth_max > 1899 or birth_min > birth_max:
		return "出生年范围无效。"
	var locked_value: Variant = request.get("locked_fields", {})
	if typeof(locked_value) != TYPE_DICTIONARY:
		return "locked_fields 必须是对象。"
	for raw_key: Variant in (locked_value as Dictionary).keys():
		if str(raw_key) not in ["population_origin_id", "start_place_id", "birth_year"]:
			return "不能锁定未支持字段：%s" % str(raw_key)
	var requested_origin := str((locked_value as Dictionary).get(
		"population_origin_id", request.get("population_origin_id", "")
	))
	if not requested_origin.is_empty() and _origin_by_id(requested_origin).is_empty():
		return "未知人口来源：%s" % requested_origin
	var requested_place := str((locked_value as Dictionary).get(
		"start_place_id", request.get("start_place_id", "")
	))
	if not requested_place.is_empty():
		if requested_origin.is_empty():
			return "指定地点时必须指定人口来源。"
		if not _origin_has_place(_origin_by_id(requested_origin), requested_place):
			return "人口来源与起始地点不相容。"
	if not bool(request.get("random_origin", false)) and requested_origin.is_empty():
		return "必须选择人口来源或启用随机来源。"
	return ""


func _generate_candidate(
	request: Dictionary,
	locked: Dictionary,
	rng: RandomNumberGenerator,
	seed_value: int,
	draft_index: int,
	candidate_index: int
) -> Dictionary:
	var origins := _catalog.get("origins", []) as Array
	var origin_id := str(locked.get(
		"population_origin_id", request.get("population_origin_id", "")
	))
	if origin_id.is_empty() and bool(request.get("random_origin", false)):
		origin_id = str((origins[rng.randi_range(0, origins.size() - 1)] as Dictionary).get("id", ""))
	var origin := _origin_by_id(origin_id)
	if origin.is_empty():
		_catalog_error = "候选人口来源不可用。"
		return {}
	var places := origin.get("places", []) as Array
	var place_id := str(locked.get("start_place_id", request.get("start_place_id", "")))
	if place_id.is_empty():
		place_id = str((places[rng.randi_range(0, places.size() - 1)] as Dictionary).get("id", ""))
	if not _origin_has_place(origin, place_id):
		_catalog_error = "候选人口来源与地点不相容。"
		return {}
	var birth_year: int
	if locked.has("birth_year"):
		birth_year = int(locked.get("birth_year", 0))
	else:
		birth_year = rng.randi_range(
			int(request.get("birth_year_min", DEFAULT_BIRTH_YEAR_MIN)),
			int(request.get("birth_year_max", DEFAULT_BIRTH_YEAR_MAX))
		)
	return {
		"population_origin_id": origin_id,
		"start_place_id": place_id,
		"birth_year": birth_year,
		"approximate_age": 1900 - birth_year,
		"seed": seed_value,
		"rules_version": RULES_VERSION,
		"draft_index": draft_index,
		"candidate_index": candidate_index,
	}


func _origin_by_id(origin_id: String) -> Dictionary:
	for origin: Dictionary in _catalog.get("origins", []):
		if str(origin.get("id", "")) == origin_id:
			return origin
	return {}


func _origin_has_place(origin: Dictionary, place_id: String) -> bool:
	for place: Dictionary in origin.get("places", []):
		if str(place.get("id", "")) == place_id:
			return true
	return false


func _stable_label_for_token(token: String) -> String:
	var person_id := "person:formal_player_%s" % token.left(12)
	return "人物 %s" % person_id.sha256_text().left(4).to_upper()


func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message}
