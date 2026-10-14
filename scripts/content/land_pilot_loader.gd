class_name LandPilotLoader
extends RefCounted
## One qualified physical source and generated partition; no historical boundary inference.
const PATH: String = "res://data/land/paris_land_pilot_r1.json"
var error: String = ""
var topology: LandTopology
var initial_politics: Dictionary = {}

func load_current(gate: HistoricalProvenanceGate, politics: RuntimePoliticalEntityRegistry) -> bool:
	var errors: Array[String] = []
	var seed := ContentDocument.read(PATH,errors)
	var registry := VNextTerritorySourceRegistry.new()
	if not errors.is_empty() or not registry.configure_from_path():
		error = "France land source registry/document unavailable"
		return false
	var source := registry.source_by_id("territory_source:paris_mainland_pilot_r1")
	if source.get("production_admission_status") != "ADMITTED" or source.get("local_resource_path") != PATH:
		error = "France land source is not admitted"
		return false
	var assertion := {"subject_id":"paris_land_pilot_r1","value":seed,"unit":"qualified_physical_source_generated_partition","observation_period":{"from":"1900-01-01","to":"1900-01-01"},"spatial_scope":{"kind":"metropolitan_physical_cells","id":"country_fra"},"lower_bound":null,"upper_bound":null}
	if gate == null or not gate.admit_runtime_fact("spatial_boundary:paris_land_pilot_r1","spatial_boundary",assertion):
		error = "France land semantic source binding failed evidence admission"
		return false
	initial_politics = (seed.get("initial_politics",{}) as Dictionary).duplicate(true)
	initial_politics["land_overrides"] = seed.get("initial_land_facts",{})
	if politics == null or not politics.has_entity(str(initial_politics.get("sovereign_polity_id",""))) or not politics.has_entity(str(initial_politics.get("controller_polity_id",""))) or initial_politics.get("administrative_status") != "UNRESOLVED" or initial_politics.get("administrative_region_id") != null:
		error = "Paris retained opening facts invalid"
		return false
	topology = LandTopology.new()
	if not topology.initialize(seed):
		error = "France land geometry/topology invalid"
		return false
	return true
