class_name AlphaV23Config
extends V23Config
## Presents the Alpha four-city network through the retained V2.3 services.

var alpha := AlphaConfig.new()


func load_all() -> Error:
	documents.clear()
	errors.clear()
	if alpha.load_all() != OK:
		errors.append_array(alpha.errors)
		return ERR_INVALID_DATA
	var communication: Dictionary = alpha.load_json(
		"res://data/v2_3/communication_channels.json"
	)
	var knowledge: Dictionary = alpha.load_json(
		"res://data/v2_3/knowledge_rules.json"
	)
	var relationships: Dictionary = alpha.load_json(
		"res://data/v2_3/relationship_rules.json"
	)
	var transport: Dictionary = alpha.load_json(
		"res://data/v2_3/transport_modes.json"
	)
	var balance: Dictionary = alpha.load_json(
		"res://data/v2_3/v2_3_balance.json"
	)
	if not alpha.errors.is_empty():
		errors.append_array(alpha.errors)
		return ERR_INVALID_DATA
	documents = {
		"locations": {
			"config_version": 1,
			"prototype_balance_value": true,
			"locations": alpha.locations.duplicate(true),
		},
		"graph": {
			"config_version": 1,
			"prototype_balance_value": true,
			"edges": alpha.transport_edges.duplicate(true),
		},
		"transport": transport,
		"communication": communication,
		"knowledge": knowledge,
		"relationships": relationships,
		"people": {
			"config_version": 1,
			"prototype_balance_value": true,
			"people": alpha.people.duplicate(true),
			"relationships": (
				alpha.world().get("relationships", []) as Array
			).duplicate(true),
		},
		"balance": balance,
		"scenario": {
			"config_version": 1,
			"prototype_balance_value": true,
			"scenario_id": "scenario:alpha_four_city_world",
			"start_datetime": str(alpha.world().get("start_datetime", "")),
			"random_seed": int(alpha.world().get("random_seed", 1001900)),
			"default_selected_person_id": "character_pierre_lefevre",
			"review_mode_default": false,
		},
	}
	_validate()
	return OK if errors.is_empty() else ERR_INVALID_DATA
