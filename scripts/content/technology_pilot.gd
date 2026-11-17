extends RefCounted
## Starting evidence and one admitted engineering project. World actions,
## labor, stocks and equipment remain in the native economy.

const FRANCE := "country_fra"
const BRITAIN := "british_empire"
const FIRM := "firm:network:mill1"
const SITE := "site:network:mill1"
const MILL := "activity:network:mill1"
const TRIAL := "activity:network:electric_motor_trial"
const LAB := "investment:network:electric_test_bench"
const INSTALL := "investment:network:electric_mill_drive"
const MOTOR := "electric_mill_motor"
const COMPONENTS := "electric_trial_components"
const TRIAL_CAPACITY := 3
const COUNTRIES := {FRANCE:"法国", BRITAIN:"英国"}
const FOUNDATIONS := {
	FRANCE: {
		"industrial_electric_drive":"工业动力 · 有电力传动与工场电气化经验",
		"roller_milling":"食品加工 · 已有辊式磨粉工艺",
		"urban_electric_construction":"城市交通 · 巴黎电力地铁工程已开工",
	},
	BRITAIN: {
		"urban_steam_service":"城市交通 · 有蒸汽地铁运营经验",
		"urban_electric_service":"电气牵引 · 伦敦已有电力地铁运营",
	},
}
const ELECTRIC_MILL_REQUIREMENTS := ["industrial_electric_drive","roller_milling"]

static func admit(configuration: Dictionary, country: String) -> void:
	var knowledge: Dictionary = FOUNDATIONS.get(country,{})
	for id: String in ELECTRIC_MILL_REQUIREMENTS:
		if not knowledge.has(id): return
	var site: Dictionary = {}
	for firm: Dictionary in configuration["firms"]:
		if firm["id"] == FIRM:
			site = firm["sites"][0]
			break
	if site.is_empty(): return
	configuration["goods"].append_array([
		{"id":MOTOR,"needs":{},"unit_id":"development_piece","unit_name_zh":"台",
			"capital_uses":["INSTALLABLE_EQUIPMENT"]},
		{"id":COMPONENTS,"needs":{},"unit_id":"development_piece","unit_name_zh":"套",
			"capital_uses":["INSTALLATION_INPUT"]},
	])
	var empty := {MOTOR:0, COMPONENTS:0}
	for actor: Dictionary in configuration["actors"]:
		actor["stock"].merge(empty)
	for firm: Dictionary in configuration["firms"]:
		for branch: Dictionary in firm["sites"]:
			branch["stock"].merge(empty)
			branch["targets"].merge(empty)
			for activity: Dictionary in branch["activities"]:
				activity["materials"].merge(empty)
	# One finite opening kit for the mill's engineering program. No extra cash or jobs.
	site["stock"][COMPONENTS] = 2
	site["stock"]["tools"] = 1
	site["targets"][MOTOR] = 1
	site["targets"]["flour"] = 8
	site["activities"][0]["process"]["max_batches_per_cycle"] = 4
	for job: Dictionary in configuration["jobs"]:
		if job["id"] == "job:network:mill1":
			job["hours"] = 8
			job["skill"] = 2
			break
	for actor: Dictionary in configuration["actors"]:
		if actor["id"] == "cohort:network:mill1":
			actor["skill"] = 2
			break
	var materials: Dictionary = site["stock"].duplicate()
	for good: String in materials: materials[good] = 0
	materials[COMPONENTS] = 1
	var output := {MOTOR:1}
	site["activities"].append({
		"id":TRIAL,"place_id":"place:paris","outputs":output,"materials":materials,
		"hours":4,"capacity_units":TRIAL_CAPACITY,"enabled":false,"basis":"DEVELOPMENT_CONFIGURATION",
		"process":{"format":"production_process_v1","technology_id":"technology:electric_mill_drive",
			"batch_unit":"development_batch","source":{"id":"paris_mill_electrical_engineering",
				"basis":"EXPLICIT_DEVELOPMENT_ESTIMATE_NOT_HISTORICAL_RATE","estimated":true,
				"hours_unit":"person_hour","capacity_unit":"capacity_unit_per_eligible_day"},
			"gross_outputs":output.duplicate(),"rejects":{MOTOR:0},"first_day":1,
			"cycle_days":1,"max_batches_per_cycle":1,"lifetime_batch_limit":1,"constraints":[]},
	})
	var templates: Array = configuration["capital_investment"]["templates"]
	templates.append(_installation(LAB,"electric_test_bench",TRIAL,{"tools":1,COMPONENTS:1}))
	templates.append(_installation(INSTALL,"electric_mill_drive",MILL,{MOTOR:1}))

static func _installation(id: String, equipment: String, activity: String, materials: Dictionary) -> Dictionary:
	return {"id":id,"firm":FIRM,"site_id":SITE,"kind":"INSTALL","asset_type":equipment,
		"capacity":TRIAL_CAPACITY if id==LAB else 2,"activities":[activity],"materials":materials,"hours":4,"hours_per_day":2,
		"duration_minutes":2880,"max_projects":1,"budget":24,"cash_floor":20,
		"denomination":FormalLedgerState.DENOMINATION,"basis":"DEVELOPMENT_CAPITAL_PERMISSION",
		"requires_materials_at_start":true}
