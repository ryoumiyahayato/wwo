extends SceneTree

const FIXTURE_SOURCE_PATH: String = "res://project.godot"
const FIXTURE_FACT_ID: String = "fixture:population"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_production_catalog()
	_check_tamper_rejection()
	_check_binding_rejection()
	_check_review_semantics()
	_check_consumer_admission()
	print("Historical provenance foundation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_production_catalog() -> void:
	var foundation := HistoricalProvenanceFoundation.new()
	_check(foundation.load_current(), "production provenance catalog loads: %s" % foundation.initialization_error)
	if not foundation.is_loaded():
		return
	var registry := foundation.registry()
	var catalog := foundation.catalog()
	_check(registry.source_ids().size() == 3, "production catalog has three sources")
	_check(catalog.size() == 202, "production catalog has 202 facts")
	var domain_counts := {"political_identity": 0, "population_aggregate": 0, "spatial_boundary": 0}
	var review_counts := {"EVIDENCE_LINKED": 0, "BOUNDED_ESTIMATE": 0}
	for fact_id: String in catalog.fact_ids():
		var fact := catalog.fact(fact_id)
		if fact == null:
			continue
		domain_counts[fact.domain] = int(domain_counts.get(fact.domain, 0)) + 1
		review_counts[fact.review_status] = int(review_counts.get(fact.review_status, 0)) + 1
	_check(int(domain_counts.get("political_identity", 0)) == 151, "catalog has 151 political identity facts")
	_check(int(domain_counts.get("population_aggregate", 0)) == 50, "catalog has 50 population aggregate facts")
	_check(int(domain_counts.get("spatial_boundary", 0)) == 1, "catalog has one spatial boundary fact")
	_check(int(review_counts.get("EVIDENCE_LINKED", 0)) == 152, "linked review status count is preserved")
	_check(int(review_counts.get("BOUNDED_ESTIMATE", 0)) == 50, "bounded review status count is preserved")
	_check(catalog.deterministic_hash().length() == 64, "catalog emits a SHA-256 fingerprint")

	var document := _read_json(HistoricalProvenanceFoundation.EVIDENCE_CATALOG_PATH)
	var reversed_facts := (document.get("facts", []) as Array).duplicate(true)
	reversed_facts.reverse()
	document["facts"] = reversed_facts
	var reversed_catalog := HistoricalEvidenceCatalog.new()
	_check(reversed_catalog.load_document(document), "reordered production catalog loads")
	_check(
		reversed_catalog.deterministic_hash() == catalog.deterministic_hash(),
		"fact catalog hash is independent of input order"
	)


func _check_tamper_rejection() -> void:
	var source_document := _read_json(HistoricalProvenanceFoundation.SOURCE_REGISTRY_PATH)
	var tampered_sources := (source_document.get("sources", []) as Array).duplicate(true)
	var tampered_source := (tampered_sources[0] as Dictionary).duplicate(true)
	tampered_source["content_hash"] = "0".repeat(64)
	tampered_sources[0] = tampered_source
	source_document["sources"] = tampered_sources
	var registry := HistoricalSourceRegistry.new()
	_check(not registry.load_document(source_document), "tampered source content hash is rejected")
	_check(not registry.errors().is_empty(), "tampered source rejection records an error")

	var fact_document := _read_json(HistoricalProvenanceFoundation.EVIDENCE_CATALOG_PATH)
	var tampered_facts := (fact_document.get("facts", []) as Array).duplicate(true)
	var tampered_fact := (tampered_facts[0] as Dictionary).duplicate(true)
	tampered_fact["output_hash"] = "f".repeat(64)
	tampered_facts[0] = tampered_fact
	fact_document["facts"] = tampered_facts
	var catalog := HistoricalEvidenceCatalog.new()
	_check(not catalog.load_document(fact_document), "tampered fact output hash is rejected")
	_check(not catalog.errors().is_empty(), "tampered fact rejection records an error")


func _check_binding_rejection() -> void:
	var mutations := {
		"source_version": "fixture-v2",
		"source_locator": "res://other-locator.json",
		"license": "different-license",
		"input_hash": "1".repeat(64),
	}
	for field: String in mutations.keys():
		var fixture := _fixture_gate({field: mutations[field]})
		var gate := fixture.get("gate") as HistoricalProvenanceGate
		_check(
			not gate.admit_runtime_fact(
				FIXTURE_FACT_ID,
				"population_aggregate",
				fixture.get("assertion", {}) as Dictionary
			),
			"source binding mismatch is rejected: %s" % field
		)
	var missing_source := _fixture_gate({"source_id": "missing-source"})
	_check(
		not (missing_source.get("gate") as HistoricalProvenanceGate).admit_runtime_fact(
		FIXTURE_FACT_ID,
		"population_aggregate",
		missing_source.get("assertion", {}) as Dictionary
	),
	"unknown source identity is rejected"
	)


func _check_review_semantics() -> void:
	var foundation := HistoricalProvenanceFoundation.new()
	_check(foundation.load_current(), "review semantics use the production catalog")
	if not foundation.is_loaded():
		return
	var gate := foundation.gate()
	var linked := foundation.catalog().fact("political_identity:argentina_1900")
	var bounded := foundation.catalog().fact("population_aggregate:population:argentina_1900")
	_check(linked != null and linked.review_status == "EVIDENCE_LINKED", "political fact remains evidence-linked")
	_check(bounded != null and bounded.review_status == "BOUNDED_ESTIMATE", "population fact remains bounded-estimate")
	if linked != null:
		_check(
			gate.admit_runtime_fact(linked.fact_id, linked.domain, linked.output_material()),
			"evidence-linked assertion is admissible"
		)
		_check(
			not gate.is_verified(linked.fact_id, linked.domain, linked.output_material()),
			"EVIDENCE_LINKED is not VERIFIED"
		)
	if bounded != null:
		_check(
			gate.admit_runtime_fact(bounded.fact_id, bounded.domain, bounded.output_material()),
			"bounded-estimate assertion is admissible"
		)
		_check(
			not gate.is_verified(bounded.fact_id, bounded.domain, bounded.output_material()),
			"BOUNDED_ESTIMATE is not VERIFIED"
		)


func _check_consumer_admission() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "formal simulation consumes provenance-gated snapshots")
	if not simulation.initialized:
		return
	_check(simulation.provenance_gate() != null, "formal simulation exposes only its admission gate")
	var political_without_gate := HistoricalPoliticalEvidenceCatalog.new()
	_check(
		not political_without_gate.configure(),
		"political evidence cannot bypass provenance admission"
	)
	var economic_without_gate := FormalWorldEconomicEvidenceCatalog.new()
	_check(
		not economic_without_gate.configure(),
		"economic evidence cannot bypass provenance admission"
	)
	var geometry := _read_json("res://data/world_map/historical/cshapes_1900_snapshot.json")
	_check(
		HistoricalProvenanceFoundation.admit_spatial_boundary_document(
			simulation.provenance_gate(), geometry
		),
		"historical boundary document is admitted by provenance gate"
	)
	var boundary_fact := simulation.provenance_gate()
	var foundation := HistoricalProvenanceFoundation.new()
	_check(foundation.load_current(), "boundary review check loads catalog")
	if foundation.is_loaded():
		var fact := foundation.catalog().fact("spatial_boundary:world_boundaries_1900_03_12")
		_check(
			fact != null
			and not boundary_fact.is_verified(fact.fact_id, fact.domain, fact.output_material()),
			"spatial evidence-linked fact is not VERIFIED"
		)


func _fixture_gate(overrides: Dictionary) -> Dictionary:
	var source_hash := FileAccess.get_sha256(FIXTURE_SOURCE_PATH)
	var source := {
		"source_id": "fixture-source",
		"title": "Fixture source",
		"publisher": "WWO test",
		"version": "fixture-v1",
		"license": "fixture-license",
		"locator": FIXTURE_SOURCE_PATH,
		"access_metadata": {"purpose": "test"},
		"content_hash": source_hash,
	}
	var assertion := {
		"lower_bound": 90,
		"observation_period": {"from": "1900-01-01", "to": "1900-01-01"},
		"spatial_scope": {"kind": "major_economy_aggregate", "id": "fixture"},
		"subject_id": "population:fixture",
		"unit": "persons",
		"upper_bound": 110,
		"value": 100,
	}
	var fact := {
		"fact_id": FIXTURE_FACT_ID,
		"domain": "population_aggregate",
		"subject_id": "population:fixture",
		"value": 100,
		"unit": "persons",
		"source_id": "fixture-source",
		"source_version": "fixture-v1",
		"source_locator": FIXTURE_SOURCE_PATH,
		"observation_period": {"from": "1900-01-01", "to": "1900-01-01"},
		"spatial_scope": {"kind": "major_economy_aggregate", "id": "fixture"},
		"methodology": "fixture",
		"confidence": 0.5,
		"lower_bound": 90,
		"upper_bound": 110,
		"license": "fixture-license",
		"review_status": "BOUNDED_ESTIMATE",
		"generator": "historical_provenance_foundation_test",
		"input_hash": source_hash,
		"output_hash": HistoricalFactEvidence.sha256(assertion),
	}
	for field: String in overrides.keys():
		fact[field] = overrides[field]
	var registry := HistoricalSourceRegistry.new()
	var catalog := HistoricalEvidenceCatalog.new()
	registry.load_document({
		"schema_id": HistoricalSourceRegistry.SCHEMA_ID,
		"sources": [source],
	})
	catalog.load_document({
		"schema_id": HistoricalEvidenceCatalog.SCHEMA_ID,
		"facts": [fact],
	})
	return {
		"gate": HistoricalProvenanceGate.new(registry, catalog),
		"assertion": assertion,
	}


func _read_json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value as Dictionary if value is Dictionary else {}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)
