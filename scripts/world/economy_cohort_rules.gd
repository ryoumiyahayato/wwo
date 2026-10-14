class_name EconomyCohortRules
extends RefCounted
## Stateless aggregation. Population, money, goods and employment remain in
## their existing host/core authorities. Profiles are explicit development data.

static func profile(actor: Dictionary) -> Dictionary:
	return actor.get("cohort_profile", {})

static func labor_members(actor: Dictionary) -> int:
	return int(profile(actor).get("labor_members", actor["members"]))

static func contracts(value: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value.is_empty(): return result
	if value.has("allocations"):
		var ids: Array = value["allocations"].keys()
		ids.sort()
		for id: String in ids: result.append(value["allocations"][id])
	else: result.append(value)
	return result

static func contract(value: Dictionary, job: String) -> Dictionary:
	if value.has("allocations"): return value["allocations"].get(job, {})
	return value if value.get("job") == job else {}

static func employed(value: Dictionary) -> int:
	var count: int = 0
	for row: Dictionary in contracts(value): count += int(row["workers"])
	return count

## Worker slots refer to disjoint portions of the cohort's declared labor pool.
static func free_span(actor: Dictionary, value: Dictionary) -> Vector2i:
	var rows := contracts(value)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["labor_start"]) < int(b["labor_start"]))
	var cursor: int = 0
	for row: Dictionary in rows:
		if int(row["labor_start"]) > cursor: return Vector2i(cursor, int(row["labor_start"])-cursor)
		cursor = int(row["labor_start"])+int(row["workers"])
	return Vector2i(cursor, labor_members(actor)-cursor)

static func allows_job(actor: Dictionary, job: String) -> bool:
	var policy := profile(actor)
	return policy.is_empty() or policy["job_ids"].has(job)

## Cumulative integer floors preserve rational flow needs across successive days.
## Durable quantities remain holding targets and are never destroyed daily.
static func required_total(actor: Dictionary, category: String, mode: String, days: int) -> int:
	if days <= 0: return 0
	var rate: Dictionary = profile(actor).get("need_rates", {}).get(category, {})
	if rate.is_empty(): return int(actor["members"])*int(actor.get("needs", {}).get(category, 0))*days
	var numerator := int(actor["members"])*int(rate["numerator"])
	return (numerator/int(rate["denominator"]))*days if mode == "durable" else numerator*days/int(rate["denominator"])

static func category_order(actor: Dictionary, defaults: Array[String]) -> Array[String]:
	var result: Array[String] = []
	result.assign(profile(actor).get("category_priority", []))
	for category: String in defaults:
		if category not in result: result.append(category)
	return result

static func valid(actor: Dictionary, settings: Dictionary, jobs: Dictionary) -> bool:
	if not actor.has("cohort_profile"): return true
	var row: Variant = actor["cohort_profile"]
	if actor["kind"] != "cohort" or not row is Dictionary or not EconomySliceConfig._fields(row, ["stratum_id", "label", "occupation", "labor_members", "max_jobs", "job_ids", "job_search_days", "basis"], ["need_rates", "category_priority", "goods_preference"]): return false
	for key: String in ["stratum_id", "label", "occupation"]:
		if not row[key] is String or row[key].is_empty(): return false
	if row["basis"] != "EXPLICIT_DEVELOPMENT_COHORT_STRATUM" or not EconomySliceConfig._number(row["labor_members"]) or int(row["labor_members"]) > int(actor["members"]) or not EconomySliceConfig._number(row["max_jobs"], 1) or int(row["max_jobs"]) > 8 or not EconomySliceConfig._number(row["job_search_days"], 1) or int(row["job_search_days"]) > 30: return false
	if not row["job_ids"] is Array or row["job_ids"].size() > 16: return false
	var seen: Dictionary = {}
	for id: Variant in row["job_ids"]:
		if not id is String or seen.has(id) or not jobs.has(id): return false
		seen[id] = true
	var categories := EconomySliceConfig.categories(settings)
	var services := EconomySliceConfig.consumption(settings)
	if not row.get("need_rates", {}) is Dictionary or not row.get("goods_preference", {}) is Dictionary or not row.get("category_priority", []) is Array: return false
	for category: Variant in row.get("need_rates", {}):
		var rate: Variant = row["need_rates"][category]
		if not categories.has(category) or not rate is Dictionary or not FormalLedgerState.exact_fields(rate, ["numerator", "denominator"]) or not EconomySliceConfig._number(rate["numerator"]) or not EconomySliceConfig._number(rate["denominator"], 1): return false
		# Preserve the existing bounded integer daily goods/needs envelope.
		if int(actor["members"])*int(rate["numerator"]) > 1000000*int(rate["denominator"]): return false
	seen.clear()
	for category: Variant in row.get("category_priority", []):
		if not categories.has(category) or seen.has(category): return false
		seen[category] = true
	for category: Variant in row.get("goods_preference", {}):
		if not categories.has(category) or not row["goods_preference"][category] is Array or row["goods_preference"][category].size() > 64: return false
		seen.clear()
		for good: Variant in row["goods_preference"][category]:
			if not good is String or seen.has(good) or int(services.get(good, {}).get(category, 0)) <= 0: return false
			seen[good] = true
	return true
