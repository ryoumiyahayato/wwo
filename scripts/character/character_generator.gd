class_name CharacterGenerator
extends RefCounted
## Generates one player character from injected deterministic services.

const MODE_STANDARD: String = "standard"
const MODE_FULL_POPULATION: String = "full_population"
const MODE_CATEGORY: String = "category"
const VALID_MODES: Array[String] = [MODE_STANDARD, MODE_FULL_POPULATION, MODE_CATEGORY]

var data_set: CoreDataSet
var config: CharacterGenerationConfig
var random: DeterministicRandomService
var id_service: StableIdService


func _init(
	world_data: CoreDataSet,
	generation_config: CharacterGenerationConfig,
	random_service: DeterministicRandomService,
	stable_id_service: StableIdService
) -> void:
	data_set = world_data
	config = generation_config
	random = random_service
	id_service = stable_id_service


func generate_character(
	country_id: String, mode: String, category: String = ""
) -> CharacterGenerationResult:
	var result := CharacterGenerationResult.new()
	if not config.is_valid():
		result.add_error(config.error_message)
		return result
	if country_id.is_empty() or not data_set.countries.has(country_id):
		result.add_error("必须明确选择有效国家")
		return result
	if mode not in VALID_MODES:
		result.add_error("未知的随机人物模式：%s" % mode)
		return result
	if mode == MODE_CATEGORY and category not in config.get_category_ids():
		result.add_error("分类随机模式必须选择有效类别")
		return result
	if not config.country_names.has(country_id):
		result.add_error("所选国家缺少姓名池：%s" % country_id)
		return result

	var region_id: String = ""
	var population_category: String = ""
	if mode == MODE_FULL_POPULATION:
		var population_group: PopulationGroupData = _pick_population_group(country_id)
		if population_group != null:
			region_id = population_group.region_id
			population_category = population_group.occupation_category
	else:
		region_id = _pick_region(country_id)
	var occupation: Dictionary = _pick_occupation(mode, category, population_category)
	if region_id.is_empty() or occupation.is_empty():
		result.add_error("所选条件没有可用的人物生成数据")
		return result

	var character := CharacterData.new()
	character.id = id_service.next_id("character")
	character.name = _generate_name(country_id)
	character.age = random.next_int(config.age_min, config.age_max)
	character.country_id = country_id
	character.region_id = region_id
	character.occupation_id = str(occupation["id"])
	character.occupation = str(occupation["name"])
	character.public_position = str(occupation["position"])
	character.organization_ids = []
	character.relationship_ids = []
	character.hidden_aptitudes = _generate_aptitudes()
	character.temperament_weights = _generate_temperament_weights()
	character.skills = _generate_skills(occupation)
	character.manifested_traits = _manifest_traits(
		character.age, character.temperament_weights
	)
	character.tendencies = _generate_tendencies(occupation)
	character.known_tendencies = {}
	CharacterTendencyService.new(config).refresh_known_tendencies(character)
	character.current_status = _generate_current_status(occupation)
	character.current_status["population_category"] = population_category
	character.is_active = true
	character.random_mode = mode
	character.random_category = category if mode == MODE_CATEGORY else ""
	character.is_challenge_start = bool(occupation["challenge"])
	character.generation_seed = random.get_seed()
	character.random_state = random.get_state()
	result.character = character
	return result


func _pick_region(country_id: String) -> String:
	var country: CountryData = data_set.countries[country_id] as CountryData
	var candidates: Array[Dictionary] = []
	for region_id: String in country.region_ids:
		var region: RegionData = data_set.regions[region_id] as RegionData
		var population: int = 0
		for population_id: String in region.population_group_ids:
			var group: PopulationGroupData = data_set.population_groups[population_id] as PopulationGroupData
			population += group.population_count
		candidates.append({"value": region_id, "weight": maxi(population, 1)})
	return str(_weighted_pick(candidates))


func _pick_population_group(country_id: String) -> PopulationGroupData:
	var country: CountryData = data_set.countries[country_id] as CountryData
	var candidates: Array[Dictionary] = []
	for region_id: String in country.region_ids:
		var region: RegionData = data_set.regions[region_id] as RegionData
		for population_id: String in region.population_group_ids:
			var group: PopulationGroupData = data_set.population_groups.get(population_id) as PopulationGroupData
			if group != null and group.population_count > 0:
				candidates.append({"value": group, "weight": group.population_count})
	return _weighted_pick(candidates) as PopulationGroupData


func _pick_occupation(
	mode: String, category: String, population_category: String = ""
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for occupation: Dictionary in config.occupations:
		if mode == MODE_CATEGORY and str(occupation["category"]) != category:
			continue
		var base_weight: float = (
			float(occupation["standard_weight"])
			if mode == MODE_STANDARD
			else float(occupation["population_weight"])
		)
		if mode == MODE_FULL_POPULATION:
			base_weight *= config.get_population_occupation_multiplier(
				population_category, str(occupation["id"])
			)
		var weight: int = roundi(base_weight * 100.0)
		if weight > 0:
			candidates.append({"value": occupation, "weight": weight})
	var picked: Variant = _weighted_pick(candidates)
	return {} if picked == null else picked as Dictionary


func _generate_name(country_id: String) -> String:
	var pools: Dictionary = config.country_names[country_id] as Dictionary
	var family_names: Array = pools["family_names"] as Array
	var given_names: Array = pools["given_names"] as Array
	return "%s%s" % [random.pick(family_names), random.pick(given_names)]


func _generate_aptitudes() -> Dictionary:
	var values: Dictionary = {}
	for key: String in config.aptitude_keys:
		values[key] = random.next_int(config.aptitude_min, config.aptitude_max)
	return values


func _generate_temperament_value() -> int:
	return random.next_int(0, 100)


func _generate_temperament_weights() -> Dictionary:
	var values: Dictionary = {}
	for key: String in config.trait_keys:
		values[key] = _generate_temperament_value()
	return values


func _generate_skills(occupation: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	var bases: Dictionary = occupation["skill_bases"] as Dictionary
	for key: String in config.skill_keys:
		values[key] = clampi(int(bases.get(key, 20)) + random.next_int(-7, 7), 0, 100)
	return values


func _manifest_traits(age: int, weights: Dictionary) -> Array[String]:
	var adult_age: int = int(config.trait_rules.get("adult_age", 18))
	var stable_age: int = int(config.trait_rules.get("stable_age", 25))
	if age < adult_age:
		return []
	var count_range: Array = (
		config.trait_rules.get("young_count", [1, 2]) as Array
		if age < stable_age
		else config.trait_rules.get("adult_count", [2, 4]) as Array
	)
	var count: int = random.next_int(int(count_range[0]), int(count_range[1]))
	var remaining: Array[String] = config.trait_keys.duplicate()
	var output: Array[String] = []
	while not remaining.is_empty() and output.size() < count:
		var best_index: int = 0
		for index: int in range(1, remaining.size()):
			var current: String = remaining[index]
			var best: String = remaining[best_index]
			if int(weights[current]) > int(weights[best]) or (int(weights[current]) == int(weights[best]) and current < best):
				best_index = index
		output.append(remaining[best_index])
		remaining.remove_at(best_index)
	return output


func _generate_tendencies(occupation: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	var bases: Dictionary = occupation["tendency_bases"] as Dictionary
	for raw_key: Variant in config.tendency_poles:
		var key: String = str(raw_key)
		values[key] = clampi(int(bases.get(key, 0)) + random.next_int(-10, 10), -100, 100)
	return values


func _generate_current_status(occupation: Dictionary) -> Dictionary:
	var wealth_range: Array = occupation["wealth_range"] as Array
	var reputation_range: Array = occupation["reputation_range"] as Array
	return {
		"health": random.next_int(72, 100),
		"fatigue": random.next_int(0, 24),
		"stress": random.next_int(0, 30),
		"injury": "none",
		"mood": "calm",
		"wealth": random.next_int(int(wealth_range[0]), int(wealth_range[1])),
		"reputation": random.next_int(int(reputation_range[0]), int(reputation_range[1])),
		"employment_status": str(occupation["employment_status"]),
		"debt_state": "none",
		"monitored": false,
		"detained": false,
	}


func _weighted_pick(candidates: Array[Dictionary]) -> Variant:
	var total_weight: int = 0
	for candidate: Dictionary in candidates:
		total_weight += int(candidate["weight"])
	if total_weight <= 0:
		return null
	var roll: int = random.next_int(1, total_weight)
	for candidate: Dictionary in candidates:
		roll -= int(candidate["weight"])
		if roll <= 0:
			return candidate["value"]
	return candidates.back()["value"]
