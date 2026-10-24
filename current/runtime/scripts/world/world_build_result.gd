class_name WorldBuildResult
extends RefCounted
## Construction/restore result only. No runtime queries, mutation or lookup API.

var world: WorldState = WorldState.new()
var success: bool = false
var error: String = ""
var operation: SaveOperationResult
var economy_simulation: FormalWorldEconomySimulation
var simulation_step: SimulationStep
var persistence: FormalPersistence
var organization_person_reference_ids: Array[String] = []
var organization_place_reference_ids: Array[String] = []
var explicit_organization_reference_injection: bool = false
