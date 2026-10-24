extends SceneTree
## Historical identities run through real Content; editable land is explicitly synthetic.
const EXPERIMENT = preload("res://tests/fixtures/administration/synthetic_administrative_state.gd")
const A: String = "administrative_region:fixture_a"
const B: String = "administrative_region:fixture_b"
const C: String = "administrative_region:fixture_c"
const X: String = "territory_unit:fixture_x"
const Y: String = "territory_unit:fixture_y"
const Z: String = "territory_unit:fixture_z"
const W: String = "territory_unit:fixture_w"
var test := FormalTestCase.new()

func _initialize() -> void:
	_run.call_deferred()

func _catalog() -> VNextTerritoryUnitCatalog:
	var catalog := VNextTerritoryUnitCatalog.new()
	test.expect(catalog.configure("synthetic-administration-r1"), "Synthetic catalog is explicit")
	for id: String in [X,Y,Z,W]:
		var unit := VNextTerritoryUnit.new()
		test.expect(unit.configure(id,"synthetic-administration-r1","fixture://geometry/"+id,"fixture://source/administration"), "Stable synthetic land identity")
		test.expect(catalog.add_unit(unit), "Synthetic catalog admits detached unit")
	test.expect(catalog.seal(), "Synthetic catalog seals")
	return catalog

func _run() -> void:
	var started := Time.get_ticks_usec()
	var built := WorldBootstrap.new().build()
	test.expect(built.success, "Current formal world builds")
	if not built.success:
		test.finish(self,"Administrative foundation R1")
		return
	var world := built.world
	var source_registry := VNextTerritorySourceRegistry.new()
	test.expect(source_registry.configure_from_path(),"Existing territory source admission registry loads")
	test.equal(source_registry.admitted_sources().size(),1,"Qualified Paris physical source is admitted; administrative geometry remains unresolved")
	test.expect(world.spatial_catalog.get_place("place:versailles").is_empty(),"Local capital identity does not imply formal Spatial land coverage")
	print("FORMAL_SPATIAL_PLACE_FACT_COUNT=",world.spatial_catalog.place_map_ids().size())
	var loader := AdministrativeLoader.new()
	test.expect(loader.load_current(world.provenance.gate()), "Historical identity is admitted by existing Evidence gate")
	var historical := loader.administration_for("country_fra","1900-01-01")
	test.equal(historical.coverage_status,"PARTIAL_IDENTITY_ONLY", "Dossier declares partial coverage")
	test.equal(historical.geometry_status,"ADMIN_BOUNDARY_DATA_GAP", "Historical identity admits no polygon")
	test.equal(historical.membership_status,"BLOCKED_SPATIAL_MODEL", "Historical identity admits no members")
	test.equal((historical.units as Array).size(),2,"Two reviewed identities, not a France-wide claim")
	test.equal(historical.units[0].capital_place_id,"place:paris","Paris existing ID is reused")
	test.equal(historical.units[1].capital_place_id,"place:versailles","Versailles existing Local Content ID is reused")
	test.expect(loader.administration_for("country_fra","1901-01-01").is_empty(),"1900 evidence is not extrapolated")
	historical.units[0]["historical_name"] = "Yvelines"
	test.equal(loader.administration_for("country_fra","1900-01-01").units[0].historical_name,"Seine","Historical view is detached")
	var persistence := FormalPersistence.new(world)
	test.equal(FormalPersistence.SCHEMA_ID,"formal_world_simulation_v15","Formal land state upgrades v15 without administrative membership")
	test.expect(not persistence.snapshot().has("administration"),"No empty administrative owner installed in save")
	_test_synthetic(_catalog(),world.political_registry_view)
	print("ADMINISTRATIVE_FOUNDATION_REVIEW_USEC=",Time.get_ticks_usec()-started)
	test.finish(self,"Administrative foundation R1")

func _test_synthetic(catalog: VNextTerritoryUnitCatalog, politics: RuntimePoliticalEntityView) -> void:
	var state := EXPERIMENT.new(catalog,["place:paris","place:fixture_capital"],["state:country_fra","state:german_empire"])
	for id: String in [A,B,C]:
		test.expect(state.create_region(id,"state:country_fra","Synthetic "+id,"departement","place:paris"),"Create synthetic region")
	test.expect(not state.create_region(A,"state:country_fra","Duplicate","departement"),"Duplicate identity rejected")
	test.expect(not state.create_region("administrative_region:bad","state:missing","Bad","state"),"Unknown polity rejected")
	test.expect(state.transfer([X,Y],A) and state.transfer([Z],B) and state.transfer([W],C),"Explicit initial synthetic members")
	var geometry: Dictionary = {}
	var index := 0
	for id: String in [X,Y,Z,W]:
		var x := float(index)
		geometry[id] = PackedVector2Array([Vector2(x,0),Vector2(x+1,0),Vector2(x+1,1),Vector2(x,1)])
		index += 1
	var cache := AdministrativeBoundaryCache.new()
	for id: String in [A,B,C]:
		cache.membership_changed([id],int(state.region(id).membership_revision))
		test.expect(cache.store(id,int(state.region(id).membership_revision),state.boundary_edges(id,geometry)),"Boundary from synthetic land edges")
	test.equal(cache.boundaries(A).size(),6,"Internal shared land edge is absent")
	# Synthetic administration still uses the isolated non-production ledger fixture.
	# Production TerritoryState now requires an admitted authoritative land scope.
	var control := VNextTerritorialControlLedger.create(catalog,politics)
	var assignments: Array[Dictionary] = []
	for id: String in [X,Y,Z,W]:
		assignments.append(VNextTerritorialControlLedger.controlled_assignment(id,"state:country_fra"))
	test.expect(control.initialize_assignments(assignments,0),"Independent synthetic control facts")
	var sovereignty := {X:"state:country_fra",Y:"state:country_fra",Z:"state:country_fra",W:"state:country_fra"}
	var admin_before := state.snapshot()
	test.expect(control.adopt_candidate(control.prepare_control_change(X,VNextTerritorialControlLedger.CONTROLLED,"state:german_empire",control.revision())),"Partial synthetic occupation")
	test.equal(state.snapshot(),admin_before,"Controller change leaves all administrative facts intact")
	test.equal(control.controller_for_territory(Y).controller_id,"state:country_fra","Other member is not occupied automatically")
	test.expect(not state.region(A).has("controller_id"),"No duplicated administrative controller")
	var controls_before := control.snapshot()
	var sovereign_before := sovereignty.duplicate(true)
	var c_before := cache.boundaries(C)
	var a_before := cache.boundaries(A)
	var b_before := cache.boundaries(B)
	var stale_revision := int(state.region(A).membership_revision)
	var update_started := Time.get_ticks_usec()
	test.expect(state.transfer([X],B),"Transfer X from A to B atomically")
	test.equal(state.membership(X),B,"Forward membership changes")
	test.equal(state.members(A),[Y],"Old region loses only X")
	test.equal(state.members(B),[X,Z],"New region receives X")
	test.equal(state.affected_regions,[A,B],"Only old and new regions affected")
	cache.membership_changed(state.affected_regions,state.revision)
	test.expect(not cache.store(A,stale_revision,a_before),"Old async result rejected")
	for id: String in state.affected_regions:
		test.expect(cache.store(id,state.revision,state.boundary_edges(id,geometry)),"Affected boundary regenerated")
	print("SYNTHETIC_ADMIN_BOUNDARY_UPDATE_USEC=",Time.get_ticks_usec()-update_started)
	test.expect(cache.boundaries(A) != a_before,"Old boundary reflects new members")
	test.expect(cache.boundaries(B) != b_before,"New boundary reflects received land")
	test.equal(cache.boundaries(C),c_before,"Unrelated cache retained")
	test.equal(control.snapshot(),controls_before,"Membership change leaves controllers intact")
	test.equal(sovereignty,sovereign_before,"Membership change leaves sovereignty intact")
	test.equal(state.members(C),[W],"Unrelated land membership retained")
	var old_metrics := cache.metrics()
	var member_revision := state.revision
	test.expect(state.rename(B,"Renamed synthetic region") and state.set_capital(B,"place:fixture_capital"),"Name and capital are mutable")
	test.equal(state.membership(X),B,"Rename cannot change land identity or assignment")
	test.equal(state.revision,member_revision,"Metadata changes do not rebuild boundaries")
	test.expect(state.transfer([X],B),"Same membership is an idempotent no-op")
	test.equal(state.revision,member_revision,"No-op keeps revision")
	cache.membership_changed([A,B],member_revision)
	test.equal(cache.metrics(),old_metrics,"Unchanged revisions do not invalidate cache")
	var unchanged := state.snapshot()
	test.expect(not state.transfer([Y,"territory_unit:missing"],B),"Mixed valid/invalid transfer rejected")
	test.equal(state.snapshot(),unchanged,"Failed batch leaves both indices unchanged")
	test.expect(not state.transfer([Y,Y],B),"Duplicate batch membership rejected")
	test.expect(not state.deactivate(B),"Nonempty region cannot deactivate")
	test.expect(not state.set_capital(B,"place:unknown"),"Unknown capital rejected")
	test.equal(state.snapshot(),unchanged,"Failed metadata/deactivation preserves state")
	var restored := EXPERIMENT.new(catalog,["place:paris","place:fixture_capital"],["state:country_fra","state:german_empire"])
	var binary_snapshot := bytes_to_var(var_to_bytes(state.snapshot())) as Dictionary
	test.expect(restored.restore(binary_snapshot),"Independent fixture serialization roundtrip")
	test.equal(restored.snapshot(),state.snapshot(),"Transfer/name/capital/revisions survive exact restore")
	test.equal(restored.boundary_edges(B,geometry),cache.boundaries(B),"Restored members reproduce current boundary")
	var detached := state.region(B)
	detached["current_name"] = "Illicit rename"
	test.equal(state.region(B).current_name,"Renamed synthetic region","Region view cannot mutate state")
	var reverse := EXPERIMENT.new(catalog,["place:paris","place:fixture_capital"],["state:country_fra","state:german_empire"])
	test.expect(reverse.restore(binary_snapshot),"Independent restore is deterministic")
	test.equal(var_to_bytes(reverse.snapshot()),var_to_bytes(restored.snapshot()),"Canonical exact bytes match across independent restores")
	var corrupt := state.snapshot()
	corrupt.regions[2].members.append(X)
	test.expect(not restored.restore(corrupt),"Conflicting same-level restore rejected")
	test.equal(restored.snapshot(),state.snapshot(),"Failed restore leaves prior state intact")
	corrupt = state.snapshot()
	corrupt.regions[1]["capital_place_id"] = "place:unknown"
	test.expect(not restored.restore(corrupt),"Corrupt capital restore rejected")
	corrupt = state.snapshot()
	corrupt.regions[1]["membership_revision"] = state.revision+1
	test.expect(not restored.restore(corrupt),"Future region revision rejected")
	corrupt = state.snapshot()
	corrupt.regions[1].erase("parent_region_id")
	corrupt.regions[1]["unexpected"] = null
	test.expect(not restored.restore(corrupt),"Missing fields cannot be replaced by arbitrary fields")
	test.expect(state.transfer([Y],B),"Merge experiment moves final A member")
	test.expect(state.deactivate(A),"Empty region can deactivate")
	test.expect(cache.retire(A,state.revision),"Retirement clears display and retains tombstone")
	test.equal(cache.boundaries(A),[],"Retired region has no geometry")
	test.expect(not cache.store(A,member_revision,a_before),"In-flight result cannot revive retired region")
	test.expect(not state.transfer([Z],A),"Inactive region cannot receive members")
	test.expect(not state.create_region(A,"state:country_fra","Reused","departement"),"Retired identity cannot be reused")
	var many := EXPERIMENT.new(catalog,["place:paris"],["state:country_fra"])
	for number: int in range(2000):
		if not many.create_region("administrative_region:synthetic_%d" % number,"state:country_fra","Synthetic %d" % number,"departement"):
			test.expect(false,"Scale fixture creates regions")
	var scale_started := Time.get_ticks_usec()
	test.expect(many.transfer([X],"administrative_region:synthetic_0") and many.transfer([X],"administrative_region:synthetic_1999"),"Transfer among 2000 synthetic regions")
	test.equal(many.touched_members,1,"Mutation touches only the changed land")
	test.equal(many.affected_regions.size(),2,"Mutation affects only two regions at scale")
	print("SYNTHETIC_ADMIN_2000_REGIONS_TRANSFER_USEC=",Time.get_ticks_usec()-scale_started)
