extends RefCounted
## The installed WorldState owns the saved extension. The desktop's Rust
## process evaluates candidate changes using facts from this same world.

const FOLDER_ENV := "WWO_FORMAL_CHARACTER_BRIDGE"
const SAVE_FIELD := "rust_character"
const MAX_BYTES := 32 * 1024 * 1024
static var _serial_mutex := Mutex.new()
static var _serial := 0

static func enabled() -> bool:
	return not OS.get_environment(FOLDER_ENV).is_empty()

static func restore(world: WorldState, value: Variant = null) -> String:
	if not enabled():
		return "此存档需要 Rust 人物运行时。" if value != null else ""
	var day := world.game_clock.current_day()
	var saved := ""
	if value != null:
		if not value is String or value.is_empty() or value.length() > MAX_BYTES:
			return "Rust 人物存档字段无效。"
		saved = value
	var response := _request(world, "restore", day, day, saved)
	if not response.get("ok", false): return str(response.error)
	_install(world, response.payload)
	return ""

static func settle_day(world: WorldState) -> String:
	if not enabled(): return ""
	var day := world.game_clock.current_day()
	if world.rust_character_day == day: return ""
	var response := _request(world, "day", day, world.rust_character_day, world.rust_character_state)
	if not response.get("ok", false): return str(response.error)
	_install(world, response.payload)
	return ""

static func purchase(world: WorldState, quote: Dictionary) -> Dictionary:
	if not enabled() or not quote.get("success", false): return {}
	var player := world.player_state.player_id()
	var currency := str(quote.get("denomination", FormalLedgerState.DENOMINATION))
	var account := world.ledger_state.owner_account(player, currency)
	var total := int(quote.get("amount", 0))
	var market := str(quote.get("seller_site", quote.get("market_id", "")))
	if total <= 0 or market.is_empty(): return {}
	var terms := {"currency": currency, "amount": total, "market": market, "accessible": true,
		"available": world.ledger_state.available_balance(account) if not account.is_empty() else null}
	var day := world.game_clock.current_day()
	return _request(world, "purchase", day, world.rust_character_day, world.rust_character_state, terms)

static func commit_purchase(world: WorldState, response: Dictionary) -> void:
	if response.get("ok", false):
		_install(world, response.payload)
		world.rust_character_profile["assessment"] = response.payload.assessment

static func profile(world: WorldState) -> Dictionary:
	if world.rust_character_profile.is_empty(): return {}
	var value := world.rust_character_profile.duplicate(false)
	value["social"] = _social(world)
	value["settled_day"] = world.rust_character_day
	return value

static func _install(world: WorldState, payload: Dictionary) -> void:
	world.rust_character_day = int(payload.day)
	world.rust_character_state = str(payload.state)
	world.rust_character_profile = payload.profile
	world.rust_character_profile["age_years"] = int(world.rust_character_profile.age_years)
	world.rust_character_work_allowed = bool(payload.able_to_work)

static func _request(world: WorldState, operation: String, day: int, settled_day: int, state: String, quote: Variant = null) -> Dictionary:
	var people: Dictionary = {}
	var nutrition: Dictionary = {}
	var work: Array[String] = []
	var economy := world.economy_r1
	var player := world.player_state.player_id()
	for person: String in world.person_overlay.person_ids():
		var identity := world.person_overlay.person(person)
		var facts: Dictionary = identity.basic_demographic_identity
		var year := int(facts.get("birth_year", -1))
		if year < 1700 or year > 9999:
			return _failure("正式人物缺少可用出生年："+person)
		var birth_day := GameCalendar.absolute_day_index(year, 1, 1)-GameCalendar.absolute_day_index(GameCalendar.START_YEAR, 1, 1)
		people[person] = {"birth_day": birth_day, "alive": identity.alive,
			"name": str(identity.get("name_zh", identity.get("name", identity.get("display_name", "姓名未记录")))),
			"basis": str(facts.get("basis", "opening_birth_year_assumption"))}
		if operation == "day" and economy != null:
			var need: Dictionary = economy._needs.get(person, {})
			var food: Dictionary = need.get("categories", {}).get("food", {})
			if int(need.get("day", -1)) == day and int(food.get("required", 0)) > 0:
				var fraction := float(food.satisfied) / float(food.required)
				nutrition[person] = clampi(roundi(fraction * 1000.0), 0, 1000)
	if operation == "day" and economy != null:
		for id: String in economy._capital_work_ids:
			var person := str(economy._work_records[id].actor)
			if people.has(person) and not work.has(person): work.append(person)
	var opening_person := world.person_overlay.person(player)
	var provenance: Dictionary = opening_person.get("provenance", {})
	var opening := str(provenance.get("opening_polity_source_id", ""))
	var claim := str(opening_person.get("claim_id", ""))
	if not people.has(player) or opening.is_empty() or claim.is_empty():
		return _failure("无法对应正式开局人物。")
	var request := {"operation": operation, "day": day, "settled_day": settled_day,
		"state": state, "world": opening+"|"+player, "people": people, "player": player,
		"nutrition": nutrition, "work": work, "quote": quote}
	return _exchange(request)

static func _exchange(request: Dictionary) -> Dictionary:
	var folder := OS.get_environment(FOLDER_ENV)
	# Slot candidates can be validated on the existing loading worker.
	_serial_mutex.lock()
	var result := _exchange_locked(folder, request)
	_serial_mutex.unlock()
	return result

static func _exchange_locked(folder: String, request: Dictionary) -> Dictionary:
	_serial += 1
	var response_path := folder.path_join("character-response.json")
	if FileAccess.file_exists(response_path) and DirAccess.remove_absolute(response_path) != OK:
		return _failure("无法清理上次 Rust 人物响应。")
	var target := folder.path_join("character-request.json")
	var temporary := target+".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _failure("无法写入 Rust 人物请求。")
	file.store_string(JSON.stringify({"serial": _serial, "request": request}))
	file.close()
	if DirAccess.rename_absolute(temporary, target) != OK:
		return _failure("无法提交 Rust 人物请求。")
	var timeout := Time.get_ticks_msec()+4000
	while Time.get_ticks_msec() < timeout:
		if FileAccess.file_exists(response_path):
			var response: Variant = JSON.parse_string(FileAccess.get_file_as_string(response_path))
			if response is Dictionary and int(response.get("serial", -1)) == _serial:
				return response if response.get("ok", false) else _failure(str(response.get("error", "Rust 人物处理失败。")))
		OS.delay_msec(12)
	return _failure("Rust 人物运行时没有响应。")

static func _social(world: WorldState) -> Dictionary:
	var player := world.player_state.player_id()
	var finance := world.personal_economy_state.person_economy(player)
	var economic: Variant = null
	if typeof(finance.get("cash")) == TYPE_INT:
		economic = "现金 %s · 可用 %s %s" % [finance.cash, finance.get("available", finance.cash),
			FormalEconomicText.currency(str(finance.get("denomination", FormalLedgerState.DENOMINATION)))]
	var employment: Dictionary = finance.get("employment", {})
	var occupation: Variant = null
	var job := str(employment.get("job", employment.get("job_id", "")))
	if not job.is_empty(): occupation = FormalEconomicText.job(job)
	elif not employment.is_empty(): occupation = "有正式工作记录"
	var assets: Array[String] = []
	for holding: Dictionary in world.personal_economy_state.holding_rows(player, 8, 0):
		assets.append(FormalEconomicText.good(str(holding.commodity_id)))
	var relationships: Array[String] = []
	var positions: Array[String] = []
	for membership: Dictionary in world.organization_state.memberships_for_person(player):
		var id := str(membership.organization_id)
		var organization := world.organization_state.organization(id)
		relationships.append(str(organization.get("name_zh", organization.get("name", id))))
	for appointment: Dictionary in world.organization_state.appointments_for_person(player):
		var id := str(appointment.get("position_id", ""))
		if not id.is_empty(): positions.append(id)
	return {"occupation": occupation, "economic_situation": economic,
		"relationships": relationships, "positions": positions, "assets": assets}

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
