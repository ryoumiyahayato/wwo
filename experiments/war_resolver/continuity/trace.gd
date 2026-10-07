extends RefCounted
## Bounded diagnostic ring. Authority identity/knowledge records are untouched.
const CAPACITY: int = 4096
const PAGE_MAX: int = 256
var _records: Array[Dictionary] = []
var _next: int = 0
var total: int = 0

func append(record: Dictionary) -> void:
	var value: Dictionary = record.duplicate(true)
	value.sequence = total
	total += 1
	if _records.size() < CAPACITY:
		_records.append(value)
	else:
		_records[_next] = value
		_next = (_next + 1) % CAPACITY

func page(start: int = 0, limit: int = 64) -> Dictionary:
	if start < 0 or start > _records.size() or limit < 1 or limit > PAGE_MAX:
		return {"ok": false, "error": "invalid_bounded_trace_page"}
	var values: Array[Dictionary] = []
	var end: int = mini(_records.size(), start + limit)
	for index: int in range(start, end):
		values.append(_records[(_next + index) % _records.size()].duplicate(true))
	return {"ok": true, "entries": values, "next": end if end < _records.size() else -1, "retained": _records.size(), "total": total, "diagnostic_overwritten": total - _records.size()}

func export() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	var cursor: int = 0
	while cursor >= 0:
		var batch: Dictionary = page(cursor, PAGE_MAX)
		values.append_array(batch.entries)
		cursor = int(batch.next)
	values.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time) or a.time == b.time and int(a.sequence) < int(b.sequence))
	return values

func timeline() -> String:
	var lines: PackedStringArray = []
	for record: Dictionary in export():
		var text: String = "事件" + str(record.kind)
		match str(record.kind):
			"spatial": text = "外部空间事实生效"
			"route_blocked": text = "实际路线受阻"
			"observation": text = "局部来源形成观察"
			"report_sent": text = "报告发送，等待送达"
			"report_received": text = "人物收到报告"
			"decision": text = "人物在明确机会提交" + str(record.get("input", "keep"))
			"command_sent": text = "命令发送，等待送达"
			"command_result": text = "命令送达重验：" + str(record.get("execution", ""))
			"route_arrival": text = "沿真实路段到达"
			"logistics": text = "有限补给事件结算"
			"structure": text = "有效结构关系事件结算"
		lines.append("t=%.3f | %s | %s | id=%s | cause=%s" % [float(record.time), str(record.subject), text, str(record.id), ",".join(record.cause_refs)])
	return "\n".join(lines)
