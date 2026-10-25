class_name FormalEconomicOpening
extends RefCounted
## One bounded ordinary opening. It uses host persons/accounts and the native
## execution kernel. Saved worlds bind their saved config without genesis.
const SINGLE_PATH := "res://data/formal/paris_workshop_opening_r1.json"
const SECOND_WORKER_CASE := "FORMAL_PARIS_TWO_WORKERS_OPENING_R1"
const PATH := "res://data/formal/paris_employment_opening_r1.json"

static func for_source(source_id: String) -> Dictionary:
	if "--formal-single-employer-opening" in OS.get_cmdline_user_args(): return single_employer(source_id)
	if source_id != "country_fra": return {}
	if "--formal-second-worker-opening" in OS.get_cmdline_user_args(): return second_worker(source_id)
	var result := _load(PATH)
	# Explicit initial conditions for the finite comparison. Never changes a running world.
	if "--formal-employment-opportunity" in OS.get_cmdline_user_args():
		for row: Dictionary in result.get("information", []):
			if row["actor"] == "person:formal_generated_country_fra_0002" and row["kind"] == "job" and row["candidate"] == "job:opening_paris_bakery": row["delivery_day"] = 4
	if "--formal-employment-arrears" in OS.get_cmdline_user_args():
		result["firms"][1]["cash"] = 16
		result["opening_organizations"][1]["notice"] = str(result["opening_organizations"][1]["notice"]).replace("初始现金600", "初始现金16（隔离欠薪对照）")
	return result

## Explicit candidate only. Copy the original resident's needs, notices and arrears
## policy; firms, vacancies, recipes, cash and material mandates remain identical.
static func second_worker(source_id: String) -> Dictionary:
	if source_id != "country_fra": return {}
	var result := _load(PATH)
	result["case_id"] = SECOND_WORKER_CASE
	result["management_scope"]["id"] = "scope:formal_paris_two_workers_opening_r1"
	var original := "person:formal_generated_country_fra_0002"
	var person := "person:formal_generated_country_fra_0003"
	var resident: Dictionary = result["opening_residents"][0].duplicate(true)
	resident["person_id"] = person
	resident["claim_id"] = "formal_population_claim:country_fra:0003"
	result["opening_residents"].append(resident)
	var actor: Dictionary = result["actors"][1].duplicate(true)
	actor["id"] = person
	actor["account_id"] = FormalPersonalEconomyState.personal_account_id(person)
	result["actors"].append(actor)
	for notice: Dictionary in result["information"].duplicate(true):
		if notice["actor"] != original: continue
		notice["actor"] = person
		result["information"].append(notice)
	var response: Dictionary = result["labor_response_policies"][0].duplicate(true)
	response["actor"] = person
	result["labor_response_policies"].append(response)
	return result

static func single_employer(source_id: String) -> Dictionary:
	return _load(SINGLE_PATH) if source_id == "country_fra" else {}

static func _load(path: String) -> Dictionary:
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _integers(document) if document is Dictionary else {"case_id":"INVALID_OPENING"}

static func _integers(value: Variant) -> Variant:
	# JSON numbers cross an integer-only domain boundary. Invalid fractional
	# or out-of-range values remain invalid; do not round them into authority.
	if value is float and is_finite(value) and value==floor(value) and absf(value)<=float(FormalLedgerState.MAX_AMOUNT): return int(value)
	if value is Dictionary:
		for key:Variant in value:value[key]=_integers(value[key])
	elif value is Array:
		for index:int in value.size():value[index]=_integers(value[index])
	return value
