extends Control
## M4 setup UI. Country choice is explicit; generation remains in CharacterGenerator.

const WORLD_PATH: String = "res://data/world/demo_world.json"

@onready var country_option: OptionButton = %CountryOption
@onready var mode_option: OptionButton = %ModeOption
@onready var category_option: OptionButton = %CategoryOption
@onready var seed_input: LineEdit = %SeedInput
@onready var generate_button: Button = %GenerateButton
@onready var enter_button: Button = %EnterButton
@onready var back_button: Button = %BackButton
@onready var preview_label: RichTextLabel = %PreviewLabel
@onready var status_label: Label = %StatusLabel

var _data_set: CoreDataSet
var _config: CharacterGenerationConfig
var _generated_character: CharacterData


func _ready() -> void:
	_config = CharacterGenerationConfig.load_from_file()
	var load_result: CoreDataLoadResult = CoreDataLoader.new().load_from_file(WORLD_PATH)
	if not _config.is_valid() or not load_result.is_success():
		status_label.text = _config.error_message if not _config.is_valid() else "\n".join(load_result.errors)
		generate_button.disabled = true
		return
	_data_set = load_result.data_set
	_populate_options()
	mode_option.item_selected.connect(_on_mode_selected)
	generate_button.pressed.connect(_on_generate_pressed)
	enter_button.pressed.connect(_on_enter_pressed)
	back_button.pressed.connect(_on_back_pressed)
	status_label.text = "请明确选择国家，再生成角色。"


func _populate_options() -> void:
	country_option.add_item("请选择国家")
	country_option.set_item_metadata(0, "")
	var country_ids: Array[String] = []
	for raw_id: Variant in _data_set.countries:
		country_ids.append(str(raw_id))
	country_ids.sort()
	for country_id: String in country_ids:
		var country: CountryData = _data_set.countries[country_id] as CountryData
		country_option.add_item(country.name)
		country_option.set_item_metadata(country_option.item_count - 1, country_id)

	_add_option(mode_option, "标准随机（推荐）", CharacterGenerator.MODE_STANDARD)
	_add_option(mode_option, "全人口随机（含困难开局）", CharacterGenerator.MODE_FULL_POPULATION)
	_add_option(mode_option, "按类别随机", CharacterGenerator.MODE_CATEGORY)
	for category_id: String in _config.get_category_ids():
		_add_option(category_option, _config.get_label("categories", category_id), category_id)
	category_option.disabled = true


func _on_mode_selected(_index: int) -> void:
	category_option.disabled = _selected_metadata(mode_option) != CharacterGenerator.MODE_CATEGORY


func _on_generate_pressed() -> void:
	var seed_value: int = 19000101
	if seed_input.text.is_valid_int():
		seed_value = seed_input.text.to_int()
	else:
		status_label.text = "种子必须是整数。"
		return
	var generator := CharacterGenerator.new(
		_data_set,
		_config,
		DeterministicRandomService.new(seed_value),
		StableIdService.new()
	)
	var mode: String = _selected_metadata(mode_option)
	var category: String = _selected_metadata(category_option) if mode == CharacterGenerator.MODE_CATEGORY else ""
	var result: CharacterGenerationResult = generator.generate_character(
		_selected_metadata(country_option), mode, category
	)
	if not result.is_success():
		status_label.text = "\n".join(result.errors)
		enter_button.disabled = true
		return
	_generated_character = result.character
	GameSessionService.set_player(_generated_character)
	_render_preview()
	enter_button.disabled = false
	status_label.text = "人物已按种子确定生成。"


func _render_preview() -> void:
	var country: CountryData = _data_set.countries[_generated_character.country_id] as CountryData
	var region: RegionData = _data_set.regions[_generated_character.region_id] as RegionData
	var challenge: String = " · 困难开局" if _generated_character.is_challenge_start else ""
	preview_label.text = "[font_size=24]%s[/font_size]\n%s · %d岁 · %s%s\n%s\n\n性格表现：%s\n\n可见技能\n%s\n\n已知倾向\n%s" % [
		_generated_character.name,
		country.name,
		_generated_character.age,
		_generated_character.occupation,
		challenge,
		region.name,
		_format_labeled_keys(_generated_character.manifested_traits, "traits"),
		_format_dictionary(_generated_character.skills, "skills"),
		_format_dictionary(_generated_character.known_tendencies, "tendencies"),
	]


func _format_labeled_keys(keys: Array[String], group: String) -> String:
	var parts: Array[String] = []
	for key: String in keys:
		parts.append(_config.get_label(group, key))
	return "、".join(parts) if not parts.is_empty() else "尚未显现"


func _format_dictionary(values: Dictionary, label_group: String) -> String:
	var keys: Array[String] = []
	for raw_key: Variant in values:
		keys.append(str(raw_key))
	keys.sort()
	var lines: Array[String] = []
	for key: String in keys:
		var label: String = _config.get_label(label_group, key)
		lines.append("%s  %s" % [label, values[key]])
	return "\n".join(lines)


func _on_enter_pressed() -> void:
	if _generated_character != null:
		get_tree().change_scene_to_file("res://scenes/map/strategic_map_view.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


static func _add_option(option: OptionButton, label: String, metadata: String) -> void:
	option.add_item(label)
	option.set_item_metadata(option.item_count - 1, metadata)


static func _selected_metadata(option: OptionButton) -> String:
	return str(option.get_item_metadata(option.selected))

