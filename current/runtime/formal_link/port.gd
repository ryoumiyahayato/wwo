extends "res://triple/port.gd"
## Formal identity is supplied by the installed world, never by the sample file.
var runtime_request: Dictionary={}

func read_request(_path: String) -> bool:
	request=runtime_request.duplicate(true)
	if request.get("source_kind")!="FORMAL_WORLD_TRAINING" or request.get("solver_owner")!="godot_local" or request.get("schema")!=SCHEMA:
		error="正式宿主没有签发训练租约";return false
	var context: Variant=request.get("formal_context")
	if not context is Dictionary or context.get("schema")!="formal_local_binding_v1" or context.get("mode")!="training" or context.get("georegistered")!=false:
		error="正式引用或训练范围不匹配";return false
	if not request.get("crew") is Array or request.crew.size()!=5 or request.crew[0].get("person_id")!=context.get("person_id"):
		error="正式人物引用缺失";return false
	return true

func install(battle: Node) -> bool:
	if not super.install(battle):return false
	# The original crew API already accepts stable IDs. Rebind its shared bodies
	# once after restore, before controls can run. No second person registry.
	battle.ai_host.clear()
	battle.crew_host.vehicle_id=FormalLocalSession.VEHICLE_ID
	battle.crew_host.bind_player()
	return true

func snapshot(battle: Node) -> Dictionary:
	var result:=super.snapshot(battle)
	result.source_kind="FORMAL_WORLD_TRAINING"
	result.issuer_id=request.get("issuer_id","")
	result.vehicle_id=FormalLocalSession.VEHICLE_ID
	result.formal_context=request.formal_context.duplicate(true)
	return result
