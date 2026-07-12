class_name PerformanceStatsService
extends RefCounted

var metrics: Dictionary = {}


func record(metric_id: String, duration_usec: int) -> void:
	if metric_id.is_empty() or duration_usec < 0:
		return
	var metric: Dictionary = metrics.get(metric_id, {
		"count": 0, "last_usec": 0, "total_usec": 0, "max_usec": 0,
	}) as Dictionary
	metric["count"] = int(metric["count"]) + 1
	metric["last_usec"] = duration_usec
	metric["total_usec"] = int(metric["total_usec"]) + duration_usec
	metric["max_usec"] = maxi(int(metric["max_usec"]), duration_usec)
	metrics[metric_id] = metric


func get_snapshot() -> Dictionary:
	return metrics.duplicate(true)


func restore_state(state: Dictionary) -> bool:
	for raw_metric: Variant in state.values():
		if not raw_metric is Dictionary:
			return false
		var metric: Dictionary = raw_metric as Dictionary
		if int(metric.get("count", -1)) < 0 or int(metric.get("last_usec", -1)) < 0 or int(metric.get("total_usec", -1)) < 0 or int(metric.get("max_usec", -1)) < 0:
			return false
	metrics = state.duplicate(true)
	return true
