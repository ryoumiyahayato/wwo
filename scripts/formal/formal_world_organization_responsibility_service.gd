class_name FormalWorldOrganizationResponsibilityService
extends RefCounted

## Authoritative operational owner for production Organization standing responsibilities.
## It consumes only detached read boundaries. It owns no Organization structure,
## Authority facts, Economy state, Person state, or player knowledge.

const SNAPSHOT_SCHEMA_ID: String = "formal_world_organization_responsibilities_v1"
const RULE_PATH: String = "res://data/vnext/organizations/formal_organization_responsibilities_1900.json"
const RULE_SCHEMA_ID: String = "formal_organization_responsibility_rules_v1"
const RESPONSIBILITY_ID: String = "economic_supply_continuity"
const BASIS_CLASS: String = "generated_simulation_assumption"
const STATUS_MONITORING: String = "MONITORING"
const STATUS_ATTENTION_REQUIRED: String = "ATTENTION_REQUIRED"
const STATUS_NO_DETAILED_ECONOMY: String = "NO_DETAILED_ECONOMY"
const STATUS_ORGANIZATION_INACTIVE: String = "ORGANIZATION_INACTIVE"
const CLOSURE_SUPPLY_RECOVERED: String = "SUPPLY_RECOVERED"
const CLOSURE_ORGANIZATION_INACTIVE: String = "ORGANIZATION_INACTIVE"
const CLOSURE_OBSERVATION_UNAVAILABLE: String = "OBSERVATION_UNAVAILABLE"
const HOURS_PER_DAY: int = 24

const _RESPONSIBILITY_FIELDS: Array[String] = [
	"organization_id",
	"represented_polity_id",
	"responsibility_id",
	"basis_class",
	"rule_version",
	"status",
	"economy_entity_id",
	"last_reviewed_day",
	"last_reviewed_hour",
	"review_count",
	"current_fulfillment_bp",
	"current_shortages",
	"episode_count",
	"closed_episode_count",
	"recovered_episode_count",
	"cumulative_attention_days",
	"max_episode_duration_days",
	"current_case",
	"last_closed_case",
]
const _CASE_FIELDS: Array[String] = [
	"case_id",
	"episode_sequence",
	"opened_day",
	"opened_hour",
	"last_reviewed_day",
	"last_reviewed_hour",
	"duration_days",
	"current_fulfillment_bp",
	"current_shortages",
	"max_shortage_count",
]
const _CLOSED_CASE_FIELDS: Array[String] = [
	"case_id",
	"episode_sequence",
	"opened_day",
	"opened_hour",
	"closed_day",
	"closed_hour",
	"duration_days",
	"closure_reason",
	"final_fulfillment_bp",
	"max_shortage_count",
]
const _STATUSES: Array[String] = [
	STATUS_MONITORING,
	STATUS_ATTENTION_REQUIRED,
	STATUS_NO_DETAILED_ECONOMY,
	STATUS_ORGANIZATION_INACTIVE,
]
const _CLOSURE_REASONS: Array[String] = [
	CLOSURE_SUPPLY_RECOVERED,
	CLOSURE_ORGANIZATION_INACTIVE,
	CLOSURE_OBSERVATION_UNAVAILABLE,
]

var initialization_error: String = ""
var _configured: bool = false
var _rule_version: String = ""
var _rule_fingerprint: String = ""
var _baseline_hour: int = 0
var _last_completed_review_day: int = 0
var _revision: int = 0
var _responsibilities: Dictionary = {}


func configure(
	organization_view: FormalWorldOrganizationView,
	organization_evidence_view: FormalWorldOrganizationEvidenceView,
	political_view: RuntimePoliticalEntityView,
	economy_view: FormalWorldEconomyView,
	baseline_hour: int
) -> bool:
	if _configured:
		return _configure_fail("Organization responsibility service is already configured")
	initialization_error = ""
	_rule_version = ""
	_rule_fingerprint = ""
	_responsibilities.clear()
	_revision = 0
	if (
		organization_view == null
		or organization_evidence_view == null
		or political_view == null
		or not political_view.is_configured()
		or economy_view == null
		or baseline_hour < 0
		or economy_view.total_hour != baseline_hour
	):
		return _configure_fail("Organization responsibility dependencies are invalid")
	if not _load_rule():
		return false

	_baseline_hour = baseline_hour
	_last_completed_review_day = int(baseline_hour / HOURS_PER_DAY)
	for organization_id: String in organization_evidence_view.organization_ids():
		if (
			not organization_view.has_organization(organization_id)
			or organization_view.organization_kind(organization_id) != "government_body"
		):
			continue
		var basis := organization_evidence_view.organization_basis(organization_id)
		var represented_polity_id := str(basis.get("represented_polity_id", ""))
		if represented_polity_id.is_empty():
			return _configure_fail(
				"Production governing Organization lacks represented polity: %s" % organization_id
			)
		var economy_entity_id := _economy_entity_for_source_polity(
			represented_polity_id, political_view, economy_view
		)
		var status := (
			STATUS_ORGANIZATION_INACTIVE
			if not organization_view.is_organization_active(organization_id)
			else (
				STATUS_NO_DETAILED_ECONOMY
				if economy_entity_id.is_empty()
				else STATUS_MONITORING
			)
		)
		_responsibilities[organization_id] = {
			"organization_id": organization_id,
			"represented_polity_id": represented_polity_id,
			"responsibility_id": RESPONSIBILITY_ID,
			"basis_class": BASIS_CLASS,
			"rule_version": _rule_version,
			"status": status,
			"economy_entity_id": economy_entity_id,
			"last_reviewed_day": -1,
			"last_reviewed_hour": -1,
			"review_count": 0,
			"current_fulfillment_bp": -1,
			"current_shortages": [],
			"episode_count": 0,
			"closed_episode_count": 0,
			"recovered_episode_count": 0,
			"cumulative_attention_days": 0,
			"max_episode_duration_days": 0,
			"current_case": {},
			"last_closed_case": {},
		}
	if not _validate_responsibility_set(
		_responsibilities,
		organization_view,
		organization_evidence_view,
		political_view,
		economy_view,
		_baseline_hour,
		_last_completed_review_day,
		_revision
	):
		return _configure_fail("Organization responsibility baseline failed validation")
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func responsibility_count() -> int:
	return _responsibilities.size()


func state_fingerprint() -> String:
	if not _configured:
		return ""
	return _state_fingerprint_for(
		_baseline_hour,
		_last_completed_review_day,
		_revision,
		_responsibilities
	)


func review_settled_day(
	settlement_hour: int,
	organization_view: FormalWorldOrganizationView,
	political_view: RuntimePoliticalEntityView,
	economy_view: FormalWorldEconomyView
) -> bool:
	if (
		not _configured
		or organization_view == null
		or political_view == null
		or not political_view.is_configured()
		or economy_view == null
		or settlement_hour <= 0
		or settlement_hour % HOURS_PER_DAY != 0
		or economy_view.total_hour != settlement_hour
	):
		return false
	var day_index := int(settlement_hour / HOURS_PER_DAY)
	if day_index != _last_completed_review_day + 1:
		return false

	var candidate := _responsibilities.duplicate(true)
	for organization_id: String in _sorted_keys(candidate):
		var record := (candidate[organization_id] as Dictionary).duplicate(true)
		record["review_count"] = int(record.get("review_count", 0)) + 1
		record["last_reviewed_day"] = day_index
		record["last_reviewed_hour"] = settlement_hour

		if (
			not organization_view.has_organization(organization_id)
			or not organization_view.is_organization_active(organization_id)
		):
			_close_current_case(
				record,
				day_index,
				settlement_hour,
				CLOSURE_ORGANIZATION_INACTIVE,
				-1
			)
			record["status"] = STATUS_ORGANIZATION_INACTIVE
			record["current_fulfillment_bp"] = -1
			record["current_shortages"] = []
			candidate[organization_id] = record
			continue

		var represented_polity_id := str(record.get("represented_polity_id", ""))
		var economy_entity_id := _economy_entity_for_source_polity(
			represented_polity_id, political_view, economy_view
		)
		record["economy_entity_id"] = economy_entity_id
		if economy_entity_id.is_empty():
			_close_current_case(
				record,
				day_index,
				settlement_hour,
				CLOSURE_OBSERVATION_UNAVAILABLE,
				-1
			)
			record["status"] = STATUS_NO_DETAILED_ECONOMY
			record["current_fulfillment_bp"] = -1
			record["current_shortages"] = []
			candidate[organization_id] = record
			continue

		var country_summary := economy_view.country_summary(economy_entity_id)
		if country_summary.is_empty():
			_close_current_case(
				record,
				day_index,
				settlement_hour,
				CLOSURE_OBSERVATION_UNAVAILABLE,
				-1
			)
			record["status"] = STATUS_NO_DETAILED_ECONOMY
			record["current_fulfillment_bp"] = -1
			record["current_shortages"] = []
			candidate[organization_id] = record
			continue

		var daily_totals_value: Variant = country_summary.get("daily_totals", {})
		if not daily_totals_value is Dictionary:
			return false
		var fulfillment_bp := int(
			(daily_totals_value as Dictionary).get("fulfillment_bp", -1)
		)
		var shortages := DataRecordUtils.to_dictionary_array(
			country_summary.get("top_shortages", [])
		)
		if fulfillment_bp < 0 or fulfillment_bp > 10000 or not _variant_is_finite(shortages):
			return false
		record["current_fulfillment_bp"] = fulfillment_bp
		record["current_shortages"] = shortages.duplicate(true)
		if shortages.is_empty():
			_close_current_case(
				record,
				day_index,
				settlement_hour,
				CLOSURE_SUPPLY_RECOVERED,
				fulfillment_bp
			)
			record["status"] = STATUS_MONITORING
		else:
			var current_case := (
				(record.get("current_case", {}) as Dictionary).duplicate(true)
			)
			if current_case.is_empty():
				var episode_sequence := int(record.get("episode_count", 0)) + 1
				current_case = {
					"case_id": _case_id(organization_id, episode_sequence),
					"episode_sequence": episode_sequence,
					"opened_day": day_index,
					"opened_hour": settlement_hour,
					"last_reviewed_day": day_index,
					"last_reviewed_hour": settlement_hour,
					"duration_days": 1,
					"current_fulfillment_bp": fulfillment_bp,
					"current_shortages": shortages.duplicate(true),
					"max_shortage_count": shortages.size(),
				}
				record["episode_count"] = episode_sequence
			else:
				current_case["last_reviewed_day"] = day_index
				current_case["last_reviewed_hour"] = settlement_hour
				current_case["duration_days"] = int(
					current_case.get("duration_days", 0)
				) + 1
				current_case["current_fulfillment_bp"] = fulfillment_bp
				current_case["current_shortages"] = shortages.duplicate(true)
				current_case["max_shortage_count"] = maxi(
					int(current_case.get("max_shortage_count", 0)),
					shortages.size()
				)
			record["cumulative_attention_days"] = int(
				record.get("cumulative_attention_days", 0)
			) + 1
			record["max_episode_duration_days"] = maxi(
				int(record.get("max_episode_duration_days", 0)),
				int(current_case.get("duration_days", 0))
			)
			record["current_case"] = current_case
			record["status"] = STATUS_ATTENTION_REQUIRED
		candidate[organization_id] = record

	var candidate_last_day := day_index
	var candidate_revision := _revision + 1
	if not _validate_runtime_records(
		candidate,
		_baseline_hour,
		candidate_last_day,
		candidate_revision
	):
		return false
	_responsibilities = candidate
	_last_completed_review_day = candidate_last_day
	_revision = candidate_revision
	return true


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	var payload := _state_payload(
		_baseline_hour,
		_last_completed_review_day,
		_revision,
		_responsibilities
	)
	payload["schema_id"] = SNAPSHOT_SCHEMA_ID
	payload["rule_fingerprint"] = _rule_fingerprint
	payload["state_fingerprint"] = state_fingerprint()
	return payload


func read_only_snapshot() -> Dictionary:
	var result := snapshot()
	if result.is_empty():
		return result
	result["coverage"] = coverage_summary()
	return result


func coverage_summary() -> Dictionary:
	var result := {
		"responsibility_count": _responsibilities.size(),
		"detailed_economy_count": 0,
		"no_detailed_economy_count": 0,
		"monitoring_count": 0,
		"attention_required_count": 0,
		"organization_inactive_count": 0,
		"total_review_count": 0,
		"attention_episodes_opened": 0,
		"closed_episode_count": 0,
		"recovered_episode_count": 0,
		"cumulative_attention_days": 0,
		"open_case_count": 0,
		"max_episode_duration_days": 0,
	}
	for organization_id: String in _sorted_keys(_responsibilities):
		var record := _responsibilities[organization_id] as Dictionary
		if str(record.get("economy_entity_id", "")).is_empty():
			result["no_detailed_economy_count"] = int(
				result["no_detailed_economy_count"]
			) + 1
		else:
			result["detailed_economy_count"] = int(result["detailed_economy_count"]) + 1
		match str(record.get("status", "")):
			STATUS_MONITORING:
				result["monitoring_count"] = int(result["monitoring_count"]) + 1
			STATUS_ATTENTION_REQUIRED:
				result["attention_required_count"] = int(
					result["attention_required_count"]
				) + 1
			STATUS_ORGANIZATION_INACTIVE:
				result["organization_inactive_count"] = int(
					result["organization_inactive_count"]
				) + 1
		result["total_review_count"] = int(result["total_review_count"]) + int(
			record.get("review_count", 0)
		)
		result["attention_episodes_opened"] = int(
			result["attention_episodes_opened"]
		) + int(record.get("episode_count", 0))
		result["closed_episode_count"] = int(result["closed_episode_count"]) + int(
			record.get("closed_episode_count", 0)
		)
		result["recovered_episode_count"] = int(
			result["recovered_episode_count"]
		) + int(record.get("recovered_episode_count", 0))
		result["cumulative_attention_days"] = int(
			result["cumulative_attention_days"]
		) + int(record.get("cumulative_attention_days", 0))
		if not (record.get("current_case", {}) as Dictionary).is_empty():
			result["open_case_count"] = int(result["open_case_count"]) + 1
		result["max_episode_duration_days"] = maxi(
			int(result["max_episode_duration_days"]),
			int(record.get("max_episode_duration_days", 0))
		)
	return result


func restore(
	snapshot_value: Dictionary,
	organization_view: FormalWorldOrganizationView,
	organization_evidence_view: FormalWorldOrganizationEvidenceView,
	political_view: RuntimePoliticalEntityView,
	economy_view: FormalWorldEconomyView,
	current_hour: int
) -> bool:
	if (
		not _configured
		or str(snapshot_value.get("schema_id", "")) != SNAPSHOT_SCHEMA_ID
		or str(snapshot_value.get("rule_fingerprint", "")) != _rule_fingerprint
		or current_hour < 0
		or economy_view == null
		or economy_view.total_hour != current_hour
		or not snapshot_value.get("responsibilities", []) is Array
	):
		return false
	var baseline_hour := int(snapshot_value.get("baseline_hour", -1))
	var last_completed_review_day := int(
		snapshot_value.get("last_completed_review_day", -1)
	)
	var revision := int(snapshot_value.get("revision", -1))
	if (
		baseline_hour < 0
		or baseline_hour > current_hour
		or last_completed_review_day < int(baseline_hour / HOURS_PER_DAY)
		or last_completed_review_day > int(current_hour / HOURS_PER_DAY)
		or revision < 0
	):
		return false

	var candidate: Dictionary = {}
	for raw_record: Variant in snapshot_value.get("responsibilities", []) as Array:
		if not raw_record is Dictionary:
			return false
		var record := (raw_record as Dictionary).duplicate(true)
		if not _has_exact_fields(record, _RESPONSIBILITY_FIELDS):
			return false
		var organization_id := str(record.get("organization_id", ""))
		if organization_id.is_empty() or candidate.has(organization_id):
			return false
		candidate[organization_id] = record

	if not _validate_responsibility_set(
		candidate,
		organization_view,
		organization_evidence_view,
		political_view,
		economy_view,
		baseline_hour,
		last_completed_review_day,
		revision
	):
		return false
	var expected_fingerprint := _state_fingerprint_for(
		baseline_hour,
		last_completed_review_day,
		revision,
		candidate
	)
	if str(snapshot_value.get("state_fingerprint", "")) != expected_fingerprint:
		return false

	_baseline_hour = baseline_hour
	_last_completed_review_day = last_completed_review_day
	_revision = revision
	_responsibilities = candidate
	return true


func _load_rule() -> bool:
	var source_text := FileAccess.get_file_as_string(RULE_PATH)
	if source_text.is_empty():
		return _configure_fail("Organization responsibility rule cannot be read")
	var parser := JSON.new()
	if parser.parse(source_text) != OK or not parser.data is Dictionary:
		return _configure_fail("Organization responsibility rule is invalid JSON")
	var document := parser.data as Dictionary
	var rule_value: Variant = document.get("standing_responsibility", {})
	if (
		str(document.get("schema_id", "")) != RULE_SCHEMA_ID
		or not rule_value is Dictionary
	):
		return _configure_fail("Organization responsibility rule schema is invalid")
	var rule := rule_value as Dictionary
	if (
		str(rule.get("responsibility_id", "")) != RESPONSIBILITY_ID
		or str(rule.get("eligible_organization_kind", "")) != "government_body"
		or str(rule.get("basis_class", "")) != BASIS_CLASS
		or str(rule.get("observation_source", ""))
		!= "FormalWorldEconomyView.country_summary"
		or str(rule.get("observation_semantics", ""))
		!= "internal_institutional_operational_observation"
		or str(rule.get("review_cadence", ""))
		!= "settled_simulation_day_boundary"
		or str(rule.get("attention_signal", ""))
		!= "top_shortages_non_empty"
	):
		return _configure_fail("Organization responsibility rule is unsupported")
	_rule_version = str(document.get("rule_version", ""))
	if _rule_version.is_empty():
		return _configure_fail("Organization responsibility rule version is missing")
	_rule_fingerprint = source_text.sha256_text()
	return true


func _validate_responsibility_set(
	candidate: Dictionary,
	organization_view: FormalWorldOrganizationView,
	organization_evidence_view: FormalWorldOrganizationEvidenceView,
	political_view: RuntimePoliticalEntityView,
	economy_view: FormalWorldEconomyView,
	baseline_hour: int,
	last_completed_review_day: int,
	revision: int
) -> bool:
	var expected_ids: Array[String] = []
	for organization_id: String in organization_evidence_view.organization_ids():
		if (
			organization_view.has_organization(organization_id)
			and organization_view.organization_kind(organization_id) == "government_body"
		):
			expected_ids.append(organization_id)
	expected_ids.sort()
	if _sorted_keys(candidate) != expected_ids:
		return false
	for organization_id: String in expected_ids:
		var record := candidate[organization_id] as Dictionary
		var basis := organization_evidence_view.organization_basis(organization_id)
		var represented_polity_id := str(basis.get("represented_polity_id", ""))
		if (
			not _has_exact_fields(record, _RESPONSIBILITY_FIELDS)
			or str(record.get("organization_id", "")) != organization_id
			or str(record.get("represented_polity_id", "")) != represented_polity_id
			or str(record.get("responsibility_id", "")) != RESPONSIBILITY_ID
			or str(record.get("basis_class", "")) != BASIS_CLASS
			or str(record.get("rule_version", "")) != _rule_version
			or str(record.get("economy_entity_id", ""))
			!= _economy_entity_for_source_polity(
				represented_polity_id, political_view, economy_view
			)
		):
			return false
	return _validate_runtime_records(
		candidate,
		baseline_hour,
		last_completed_review_day,
		revision
	)


func _validate_runtime_records(
	candidate: Dictionary,
	baseline_hour: int,
	last_completed_review_day: int,
	revision: int
) -> bool:
	var baseline_day := int(baseline_hour / HOURS_PER_DAY)
	var expected_reviews := last_completed_review_day - baseline_day
	if expected_reviews < 0 or revision != expected_reviews:
		return false
	var seen_case_ids: Dictionary = {}
	for organization_id: String in _sorted_keys(candidate):
		var record := candidate[organization_id] as Dictionary
		var status := str(record.get("status", ""))
		var review_count := int(record.get("review_count", -1))
		var last_reviewed_day := int(record.get("last_reviewed_day", -2))
		var last_reviewed_hour := int(record.get("last_reviewed_hour", -2))
		var fulfillment_bp := int(record.get("current_fulfillment_bp", -2))
		var episode_count := int(record.get("episode_count", -1))
		var closed_episode_count := int(record.get("closed_episode_count", -1))
		var recovered_episode_count := int(record.get("recovered_episode_count", -1))
		var cumulative_attention_days := int(
			record.get("cumulative_attention_days", -1)
		)
		var max_episode_duration_days := int(
			record.get("max_episode_duration_days", -1)
		)
		if (
			status not in _STATUSES
			or review_count != expected_reviews
			or episode_count < 0
			or closed_episode_count < 0
			or recovered_episode_count < 0
			or recovered_episode_count > closed_episode_count
			or cumulative_attention_days < 0
			or max_episode_duration_days < 0
			or not record.get("current_shortages", []) is Array
			or not record.get("current_case", {}) is Dictionary
			or not record.get("last_closed_case", {}) is Dictionary
			or not _variant_is_finite(record.get("current_shortages", []))
		):
			return false
		if review_count == 0:
			if last_reviewed_day != -1 or last_reviewed_hour != -1:
				return false
		else:
			if (
				last_reviewed_day != last_completed_review_day
				or last_reviewed_hour != last_completed_review_day * HOURS_PER_DAY
			):
				return false

		var current_case := record.get("current_case", {}) as Dictionary
		var last_closed_case := record.get("last_closed_case", {}) as Dictionary
		if current_case.is_empty():
			if (
				status == STATUS_ATTENTION_REQUIRED
				or episode_count != closed_episode_count
			):
				return false
		else:
			if (
				status != STATUS_ATTENTION_REQUIRED
				or episode_count != closed_episode_count + 1
				or not _validate_open_case(
					current_case,
					organization_id,
					episode_count,
					last_completed_review_day
				)
			):
				return false
			var current_case_id := str(current_case.get("case_id", ""))
			if seen_case_ids.has(current_case_id):
				return false
			seen_case_ids[current_case_id] = true
			if (
				int(current_case.get("duration_days", 0))
				> max_episode_duration_days
			):
				return false

		if not last_closed_case.is_empty():
			if not _validate_closed_case(
				last_closed_case,
				organization_id,
				episode_count,
				not current_case.is_empty()
			):
				return false
			var closed_case_id := str(last_closed_case.get("case_id", ""))
			if seen_case_ids.has(closed_case_id):
				return false
			seen_case_ids[closed_case_id] = true
			if (
				int(last_closed_case.get("duration_days", 0))
				> max_episode_duration_days
			):
				return false
		elif closed_episode_count > 0:
			return false

		var current_shortages := record.get("current_shortages", []) as Array
		if status == STATUS_ATTENTION_REQUIRED:
			if (
				current_case.is_empty()
				or current_shortages.is_empty()
				or fulfillment_bp < 0
				or fulfillment_bp > 10000
			):
				return false
		elif status == STATUS_MONITORING:
			if not current_case.is_empty() or not current_shortages.is_empty():
				return false
			# A fresh or migrated baseline has not yet performed an institutional
			# observation. It must not fabricate a fulfillment value from current
			# Economy state. After the first settled-day review, fulfillment is real.
			if review_count == 0:
				if fulfillment_bp != -1:
					return false
			elif fulfillment_bp < 0 or fulfillment_bp > 10000:
				return false
		else:
			if (
				not current_case.is_empty()
				or not current_shortages.is_empty()
				or fulfillment_bp != -1
			):
				return false
	return true


func _validate_open_case(
	current_case: Dictionary,
	organization_id: String,
	expected_episode_sequence: int,
	last_completed_review_day: int
) -> bool:
	if not _has_exact_fields(current_case, _CASE_FIELDS):
		return false
	var episode_sequence := int(current_case.get("episode_sequence", -1))
	var opened_day := int(current_case.get("opened_day", -1))
	var opened_hour := int(current_case.get("opened_hour", -1))
	var last_reviewed_day := int(current_case.get("last_reviewed_day", -1))
	var last_reviewed_hour := int(current_case.get("last_reviewed_hour", -1))
	var duration_days := int(current_case.get("duration_days", -1))
	var fulfillment_bp := int(current_case.get("current_fulfillment_bp", -1))
	var shortages: Variant = current_case.get("current_shortages", [])
	return (
		episode_sequence == expected_episode_sequence
		and str(current_case.get("case_id", ""))
		== _case_id(organization_id, episode_sequence)
		and opened_day >= 0
		and opened_hour == opened_day * HOURS_PER_DAY
		and last_reviewed_day == last_completed_review_day
		and last_reviewed_hour == last_completed_review_day * HOURS_PER_DAY
		and duration_days == last_reviewed_day - opened_day + 1
		and fulfillment_bp >= 0
		and fulfillment_bp <= 10000
		and shortages is Array
		and not (shortages as Array).is_empty()
		and int(current_case.get("max_shortage_count", 0))
		>= (shortages as Array).size()
		and _variant_is_finite(shortages)
	)


func _validate_closed_case(
	closed_case: Dictionary,
	organization_id: String,
	episode_count: int,
	has_current_case: bool
) -> bool:
	if not _has_exact_fields(closed_case, _CLOSED_CASE_FIELDS):
		return false
	var episode_sequence := int(closed_case.get("episode_sequence", -1))
	var opened_day := int(closed_case.get("opened_day", -1))
	var closed_day := int(closed_case.get("closed_day", -1))
	var duration_days := int(closed_case.get("duration_days", -1))
	var final_fulfillment_bp := int(
		closed_case.get("final_fulfillment_bp", -1)
	)
	return (
		episode_sequence > 0
		and episode_sequence <= episode_count
		and (not has_current_case or episode_sequence < episode_count)
		and str(closed_case.get("case_id", ""))
		== _case_id(organization_id, episode_sequence)
		and opened_day >= 0
		and int(closed_case.get("opened_hour", -1)) == opened_day * HOURS_PER_DAY
		and closed_day > opened_day
		and int(closed_case.get("closed_hour", -1)) == closed_day * HOURS_PER_DAY
		and duration_days > 0
		and str(closed_case.get("closure_reason", "")) in _CLOSURE_REASONS
		and final_fulfillment_bp >= -1
		and final_fulfillment_bp <= 10000
		and int(closed_case.get("max_shortage_count", 0)) > 0
	)


func _close_current_case(
	record: Dictionary,
	day_index: int,
	settlement_hour: int,
	reason: String,
	final_fulfillment_bp: int
) -> void:
	var current_case := (
		(record.get("current_case", {}) as Dictionary).duplicate(true)
	)
	if current_case.is_empty():
		return
	record["last_closed_case"] = {
		"case_id": str(current_case.get("case_id", "")),
		"episode_sequence": int(current_case.get("episode_sequence", 0)),
		"opened_day": int(current_case.get("opened_day", -1)),
		"opened_hour": int(current_case.get("opened_hour", -1)),
		"closed_day": day_index,
		"closed_hour": settlement_hour,
		"duration_days": int(current_case.get("duration_days", 0)),
		"closure_reason": reason,
		"final_fulfillment_bp": final_fulfillment_bp,
		"max_shortage_count": int(current_case.get("max_shortage_count", 0)),
	}
	record["closed_episode_count"] = int(
		record.get("closed_episode_count", 0)
	) + 1
	if reason == CLOSURE_SUPPLY_RECOVERED:
		record["recovered_episode_count"] = int(
			record.get("recovered_episode_count", 0)
		) + 1
	record["current_case"] = {}


func _economy_entity_for_source_polity(
	source_polity_id: String,
	political_view: RuntimePoliticalEntityView,
	economy_view: FormalWorldEconomyView
) -> String:
	var runtime_polity_id := political_view.runtime_id_for_source(source_polity_id)
	if runtime_polity_id.is_empty():
		return ""
	return economy_view.economy_entity_for_polity(runtime_polity_id)


func _case_id(organization_id: String, episode_sequence: int) -> String:
	return "%s/%s/episode_%06d" % [
		organization_id,
		RESPONSIBILITY_ID,
		episode_sequence,
	]


func _state_payload(
	baseline_hour: int,
	last_completed_review_day: int,
	revision: int,
	source: Dictionary
) -> Dictionary:
	return {
		"baseline_hour": baseline_hour,
		"last_completed_review_day": last_completed_review_day,
		"revision": revision,
		"responsibilities": _records(source),
	}


func _state_fingerprint_for(
	baseline_hour: int,
	last_completed_review_day: int,
	revision: int,
	source: Dictionary
) -> String:
	return JSON.stringify({
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"rule_fingerprint": _rule_fingerprint,
		"state": _state_payload(
			baseline_hour,
			last_completed_review_day,
			revision,
			source
		),
	}).sha256_text()


func _records(source: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for organization_id: String in _sorted_keys(source):
		output.append((source[organization_id] as Dictionary).duplicate(true))
	return output


func _sorted_keys(source: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for raw_key: Variant in source.keys():
		if typeof(raw_key) == TYPE_STRING:
			output.append(str(raw_key))
	output.sort()
	return output


func _has_exact_fields(record: Dictionary, fields: Array[String]) -> bool:
	if record.size() != fields.size():
		return false
	for field: String in fields:
		if not record.has(field):
			return false
	return true


func _variant_is_finite(value: Variant) -> bool:
	match typeof(value):
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for item: Variant in value as Array:
				if not _variant_is_finite(item):
					return false
			return true
		TYPE_DICTIONARY:
			for item: Variant in (value as Dictionary).values():
				if not _variant_is_finite(item):
					return false
			return true
		_:
			return true


func _configure_fail(message: String) -> bool:
	initialization_error = message
	_configured = false
	return false
