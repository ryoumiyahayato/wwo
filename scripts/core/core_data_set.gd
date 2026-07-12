class_name CoreDataSet
extends RefCounted
## Indexed, read-only-by-convention container returned only after full validation.

var countries: Dictionary = {}
var regions: Dictionary = {}
var control_units: Dictionary = {}
var population_groups: Dictionary = {}
var characters: Dictionary = {}
var organizations: Dictionary = {}
var relationships: Dictionary = {}
var actions: Dictionary = {}


func get_total_entity_count() -> int:
	return (
		countries.size()
		+ regions.size()
		+ control_units.size()
		+ population_groups.size()
		+ characters.size()
		+ organizations.size()
		+ relationships.size()
		+ actions.size()
	)


func get_counts() -> Dictionary:
	return {
		"countries": countries.size(),
		"regions": regions.size(),
		"control_units": control_units.size(),
		"population_groups": population_groups.size(),
		"characters": characters.size(),
		"organizations": organizations.size(),
		"relationships": relationships.size(),
		"actions": actions.size(),
	}

