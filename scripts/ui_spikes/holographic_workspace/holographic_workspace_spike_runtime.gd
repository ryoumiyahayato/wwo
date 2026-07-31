extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd"
## Isolated visual spike clock. It is not loaded by the formal product scene and
## cannot write formal simulation time.

const INITIAL_TOTAL_MINUTES: int = 1688 * 60

var _local_total_minutes: int = INITIAL_TOTAL_MINUTES


func _format_sim_datetime() -> String:
	var value := V2DateTime.from_total_hour(int(_local_total_minutes / 60))
	if value.is_empty():
		return "无效时间"
	return "%04d年%02d月%02d日 %02d:%02d" % [
		int(value.get("year", 0)),
		int(value.get("month", 0)),
		int(value.get("day", 0)),
		int(value.get("hour", 0)),
		posmod(_local_total_minutes, 60),
	]


func _time_source_description() -> String:
	return "隔离样机本地时钟，不参与正式产品时间"


func _advance_simulation_minutes(minutes: int) -> void:
	if minutes > 0:
		_local_total_minutes += minutes
