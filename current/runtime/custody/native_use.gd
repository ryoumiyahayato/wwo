extends RefCounted
## Controlled ammunition-owner exercise only. No projectile, hit, combat or formal time delegation.
const State = preload("res://scripts/vnext/military/military_material_state.gd")

static func consume_once(request: Dictionary) -> Dictionary:
	var ammo:=State.native(int(request.quantity),int(request.before.epoch))
	var loaded: Dictionary=ammo.restore(request.before)
	if not loaded.get("ok",false):return State.fail("NATIVE_CUSTODY_RESTORE_FAILED")
	var before: Dictionary=ammo.snapshot()
	var result: Dictionary=ammo.commit_fire(State.config().asset_id,"primary",ammo.request_id(),0.001,true,true)
	if not result.get("ok",false):return result
	return {"ok":true,"receipt":{"lease_id":request.lease_id,"issuer_id":request.issuer_id,"generation":request.generation,"receipt_id":"%s:g%d:commit:%d"%[request.lease_id,int(request.generation),int(ammo.sequence)],"before":before,"after":ammo.snapshot(),"commit":result}}
