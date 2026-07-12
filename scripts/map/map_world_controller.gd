class_name MapWorldController
extends Node
## Loads validated M3 world data and exposes the non-UI map control service.

signal world_ready(control_service: MapControlService)

@export_file("*.json") var world_data_path: String = "res://data/world/demo_world.json"
@export_file("*.json") var map_rules_path: String = MapRulesConfig.DEFAULT_PATH

var data_set: CoreDataSet
var rules: MapRulesConfig
var control_service: MapControlService
var initialization_error: String = ""


func _ready() -> void:
	rules = MapRulesConfig.new()
	var rules_error: Error = rules.load_from_file(map_rules_path)
	if rules_error != OK:
		initialization_error = rules.error_message
		LogService.error("MapWorldController", initialization_error)
		return
	var load_result: CoreDataLoadResult = CoreDataLoader.new().load_from_file(world_data_path)
	if not load_result.is_success():
		initialization_error = "世界数据无效：%s" % [load_result.errors]
		LogService.error("MapWorldController", initialization_error)
		return
	data_set = load_result.data_set
	control_service = MapControlService.new(data_set, rules)
	world_ready.emit(control_service)
	LogService.info("MapWorldController", "M3 世界地图已就绪：%d 个控制单元" % [
		data_set.control_units.size()
	])

