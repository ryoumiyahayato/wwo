extends SceneTree
## Regression boundary: historical evidence may bootstrap independently without becoming runtime political authority.

const SurfaceScript = preload(
	"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence_ui.gd"
)

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_standalone_bootstrap()
	_check_formal_injected_path()
	_check_fail_closed_path()
	print("Historical evidence bootstrap regression: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_standalone_bootstrap() -> void:
	var surface = SurfaceScript.new()
	_check(
		surface._bootstrap_historical_political_evidence(),
		"standalone provenance-admitted political bootstrap succeeds"
	)
	var units := surface._dated_units_document.get("units", []) as Array
	_check(units.size() == 151, "standalone bootstrap exposes 151 admitted records")
	_check(
		surface._historical_provenance_gate != null,
		"standalone bootstrap establishes a provenance gate"
	)

	surface._dated_geometry_document = surface._read_document(surface.HISTORICAL_GEOMETRY_PATH)
	surface._historical_spatial_provenance_valid = (
		HistoricalProvenanceFoundation.admit_spatial_boundary_document(
			surface._historical_provenance_gate,
			surface._dated_geometry_document
		)
	)
	_check(surface._historical_spatial_provenance_valid, "standalone spatial provenance admission succeeds")
	surface._index_dated_geometry()
	surface._rebuild_historical_political_world()
	_check(surface._history_entity_by_id.size() == 151, "standalone surface rebuilds 151 historical entities")
	_check(
		not bool(surface.historical_evidence_report().get("modern_geometry_fallback", true)),
		"standalone surface does not use modern political geometry fallback"
	)
	surface.free()


func _check_formal_injected_path() -> void:
	var formal := FormalWorldSimulation.new()
	_check(formal.initialize(), "formal simulation initializes: %s" % formal.initialization_error)
	if not formal.initialized:
		return
	var evidence_view := formal.historical_evidence_view()
	_check(evidence_view.record_count() == 151, "formal simulation exposes 151 admitted historical records")
	var runtime_count := int(formal.world_summary().get("world_political_unit_count", -1))
	_check(runtime_count == 146, "formal runtime political entity count remains 146")

	var surface = SurfaceScript.new()
	var injected_records := evidence_view.records()
	surface._dated_units_document = {"units": injected_records}
	_check(
		surface.bind_historical_provenance_gate(formal.provenance_gate()),
		"formal provenance gate binds to historical surface"
	)
	_check(
		surface._bootstrap_historical_political_evidence(),
		"injected formal path accepts existing admitted evidence"
	)
	_check(
		(surface._dated_units_document.get("units", []) as Array).size() == 151,
		"formal injected surface retains 151 historical records"
	)
	_check(
		surface._historical_provenance_foundation == null,
		"formal injected path does not create a second provenance foundation"
	)
	_check(
		surface._historical_provenance_gate == formal.provenance_gate(),
		"formal injected path keeps the composition-root provenance gate"
	)
	surface.free()


func _check_fail_closed_path() -> void:
	var surface = SurfaceScript.new()
	var invalid_gate := HistoricalProvenanceGate.new(
		HistoricalSourceRegistry.new(),
		HistoricalEvidenceCatalog.new()
	)
	_check(surface.bind_historical_provenance_gate(invalid_gate), "invalid test gate binds")
	_check(
		not surface._bootstrap_historical_political_evidence(),
		"catalog admission failure rejects standalone bootstrap"
	)
	_check(
		(surface._dated_units_document.get("units", []) as Array).is_empty(),
		"failed admission does not raw-load political_units_1900.json"
	)
	_check(surface._history_entity_by_id.is_empty(), "failed admission creates no historical entities")
	_check(
		not bool(surface.historical_evidence_report().get("modern_geometry_fallback", true)),
		"failed admission does not fall back to modern political polygons"
	)
	_check(not surface._data_errors.is_empty(), "failed admission is explicit in data errors")
	surface.free()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)
