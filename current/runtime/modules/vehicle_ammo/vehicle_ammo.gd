extends RefCounted
## The only mutable vehicle ammunition owner. No geometry, damage, HUD or implicit refill.
const Config = preload("res://modules/vehicle_ammo/ammo_config.gd")
const VERSION := 1
var vehicles: Dictionary = {}
var schemas: Dictionary = {}
var epoch := -1
var sequence := 0
var advance_usec := 0
var advance_calls := 0

func new_battle(generation: int) -> void:
	vehicles.clear()
	schemas.clear()
	epoch = generation
	sequence = 0
	advance_usec = 0
	advance_calls = 0

func register_vehicle(id: String, loadout: Dictionary) -> bool:
	if vehicles.has(id): return false
	var mounts: Dictionary = {}
	schemas[id]=loadout.duplicate(true)
	for mount in loadout:
		var c: Dictionary = loadout[mount]
		var reserve: Dictionary = c.rounds.duplicate()
		var loaded := ""
		if str(c.kind) == "chamber" and int(reserve.get(c.initial,0)) > 0:
			loaded = str(c.initial)
			reserve[loaded] -= 1
		var spent_rounds:Dictionary={}
		for round_type in c.rounds:spent_rounds[round_type]=0
		var capacity := 0
		for count in c.rounds.values(): capacity += int(count)
		mounts[mount] = {"kind":str(c.kind),"reserve":reserve,"loaded":loaded,"loading":"","next":str(c.initial),"remaining":0.0,"duration":0.0,"cooldown":0.0,"capacity":capacity,"spent":0,"spent_rounds":spent_rounds,"last_commit":0,"burst":{},"last_reason":""}
	vehicles[id] = mounts
	return true

func request_id() -> int:
	sequence += 1
	return sequence

func _pool(id: String, mount: String) -> Dictionary:
	return vehicles.get(id,{}).get(mount,{})

func total(id: String, mount: String) -> int:
	var p := _pool(id,mount)
	if p.is_empty(): return 0
	var count := int(not str(p.loaded).is_empty()) + int(not str(p.loading).is_empty())
	for n in p.reserve.values(): count += int(n)
	return count

func status(id: String, mount: String) -> Dictionary:
	var p := _pool(id,mount)
	if p.is_empty(): return {"ready":false,"reason":"unregistered","total":0,"loaded":"","loading":"","next":"","remaining":0.0,"reserve":{}}
	var s := p.duplicate(true)
	s.total = total(id,mount)
	s.ready = not str(p.loaded).is_empty() if p.kind == "chamber" else int(p.reserve.get(p.next,0)) > 0 and float(p.cooldown) <= 0.0 and p.burst.is_empty()
	s.reason = "ready" if s.ready else "loading" if not str(p.loading).is_empty() else "cooldown" if float(p.cooldown)>0.0 else "empty_selected"
	return s

func select_next(id: String, mount: String, round_type: String, duration := 0.0) -> bool:
	var p := _pool(id,mount)
	if p.is_empty() or not p.reserve.has(round_type): return false
	p.next = round_type
	# Loaded and in-progress rounds never change type. An idle empty chamber may start loading.
	if p.kind == "chamber" and p.loaded == "" and p.loading == "": _start_load(p,duration)
	return true

func _start_load(p: Dictionary, duration: float) -> void:
	if p.loaded != "" or p.loading != "" or int(p.reserve.get(p.next,0)) <= 0: return
	p.reserve[p.next] -= 1
	p.loading = p.next
	p.duration = maxf(0.001,duration)
	p.remaining = p.duration

func advance(delta: float) -> void:
	var begin := Time.get_ticks_usec()
	for mounts in vehicles.values():
		for p in mounts.values():
			p.cooldown = maxf(0.0,float(p.cooldown)-delta)
			if p.loading != "":
				p.remaining = maxf(0.0,float(p.remaining)-delta)
				if p.remaining <= 0.0:
					p.loaded = p.loading
					p.loading = ""
	advance_usec += Time.get_ticks_usec()-begin
	advance_calls += 1

func commit_fire(id: String, mount: String, request: int, duration: float, allowed: bool, muzzle_valid: bool) -> Dictionary:
	var p := _pool(id,mount)
	if p.is_empty(): return {"ok":false,"reason":"unregistered"}
	if not allowed: return {"ok":false,"reason":"role_unavailable"}
	if not muzzle_valid: return {"ok":false,"reason":"muzzle_unavailable"}
	if request <= int(p.last_commit): return {"ok":false,"reason":"duplicate"}
	if p.kind == "burst": return {"ok":false,"reason":"burst_required"}
	var round_type := str(p.loaded) if p.kind == "chamber" else str(p.next)
	if p.kind == "chamber" and round_type == "": return {"ok":false,"reason":"loading" if p.loading != "" else "empty_selected"}
	if p.kind == "belt" and (float(p.cooldown)>0 or int(p.reserve.get(round_type,0))<=0): return {"ok":false,"reason":"cooldown" if float(p.cooldown)>0 else "empty_selected"}
	# Single synchronous commit, after all role/muzzle/safety gates, before the original shot event.
	p.last_commit = request
	p.spent += 1
	p.spent_rounds[round_type] += 1
	if p.kind == "chamber":
		p.loaded = ""
		_start_load(p,duration)
	else:
		p.reserve[round_type] -= 1
		p.cooldown = maxf(0.001,duration)
	return {"ok":true,"round":round_type,"commit":request,"vehicle_id":id,"mount":mount,"remaining_total":total(id,mount)}

func begin_burst(id: String, mount: String) -> Dictionary:
	var p := _pool(id,mount)
	if p.is_empty() or p.kind != "burst": return {"ok":false,"reason":"unregistered"}
	if not p.burst.is_empty() or float(p.cooldown)>0: return {"ok":false,"reason":"cooldown"}
	if int(p.reserve.get(p.next,0))<=0: return {"ok":false,"reason":"empty_selected"}
	var token := request_id()
	p.burst = {"id":token,"next_index":0,"round":p.next}
	return {"ok":true,"token":token}

func commit_burst_round(id: String, mount: String, token: int, index: int, duration: float, allowed: bool, muzzle_valid: bool) -> Dictionary:
	var p := _pool(id,mount)
	if p.is_empty() or p.burst.is_empty() or int(p.burst.id)!=token or int(p.burst.next_index)!=index: return {"ok":false,"reason":"invalid_burst"}
	if not allowed or not muzzle_valid: return {"ok":false,"reason":"role_unavailable" if not allowed else "muzzle_unavailable"}
	var round_type := str(p.burst.round)
	if int(p.reserve.get(round_type,0))<=0: return {"ok":false,"reason":"empty_selected"}
	var request := request_id()
	p.reserve[round_type] -= 1
	p.spent += 1
	p.spent_rounds[round_type] += 1
	p.last_commit = request
	p.burst.next_index += 1
	if index == 0: p.cooldown = duration
	return {"ok":true,"round":round_type,"commit":request,"vehicle_id":id,"mount":mount,"remaining_total":total(id,mount)}

func cancel_burst(id: String, mount: String, token := -1) -> void:
	var p := _pool(id,mount)
	if not p.is_empty() and (token<0 or int(p.burst.get("id",-2))==token): p.burst = {}

func snapshot() -> Dictionary:
	return {"version":VERSION,"config_version":Config.VERSION,"epoch":epoch,"sequence":sequence,"vehicles":vehicles.duplicate(true)}

func _integer(value) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)>=0 and float(value)<=9007199254740991.0 and float(value)==floor(float(value))

func _nonnegative(value) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)>=0

func _same_keys(a:Dictionary,b:Dictionary) -> bool:
	if a.size()!=b.size():return false
	for key in a:
		if not b.has(key):return false
	return true

func restore(data: Dictionary, live_continuation := false) -> Dictionary:
	# Restore only into independently registered current vehicle/mount schemas.
	# Snapshot bytes may never define their own capacity, compatibility or people.
	if not _integer(data.get("version")) or int(data.version)!=VERSION or str(data.get("config_version",""))!=Config.VERSION:return {"ok":false,"reason":"ammo_snapshot_missing_or_incompatible"}
	if not _integer(data.get("sequence")) or not _integer(data.get("epoch")):return {"ok":false,"reason":"invalid_sequence"}
	var incoming=data.get("vehicles")
	if not incoming is Dictionary or schemas.is_empty():return {"ok":false,"reason":"unregistered_restore"}
	if not _same_keys(incoming,schemas):return {"ok":false,"reason":"vehicle_schema_mismatch"}
	for id in incoming:
		var mounts=incoming[id]
		if not mounts is Dictionary or not _same_keys(mounts,schemas[id]):return {"ok":false,"reason":"mount_schema_mismatch"}
		for mount in mounts:
			var p=mounts[mount]
			var schema:Dictionary=schemas[id][mount]
			if not p is Dictionary:return {"ok":false,"reason":"invalid_pool"}
			for key in ["kind","reserve","loaded","loading","next","remaining","duration","cooldown","capacity","spent","spent_rounds","last_commit","burst"]:
				if not p.has(key):return {"ok":false,"reason":"incomplete_pool"}
			if p.kind!=schema.kind or not p.reserve is Dictionary or not p.spent_rounds is Dictionary:return {"ok":false,"reason":"invalid_pool"}
			if not _same_keys(p.reserve,schema.rounds) or not _same_keys(p.spent_rounds,schema.rounds):return {"ok":false,"reason":"round_schema_mismatch"}
			for key in ["loaded","loading","next"]:
				if not p[key] is String:return {"ok":false,"reason":"invalid_round_type"}
			if not p.reserve.has(p.next) or (p.loaded!="" and not p.reserve.has(p.loaded)) or (p.loading!="" and not p.reserve.has(p.loading)):return {"ok":false,"reason":"invalid_round"}
			for key in ["capacity","spent","last_commit"]:
				if not _integer(p[key]):return {"ok":false,"reason":"invalid_integer"}
			for key in ["remaining","duration","cooldown"]:
				if not _nonnegative(p[key]):return {"ok":false,"reason":"invalid_time"}
			if p.loaded!="" and p.loading!="":return {"ok":false,"reason":"double_chamber"}
			if p.kind!="chamber" and (p.loaded!="" or p.loading!="" or float(p.remaining)>0):return {"ok":false,"reason":"invalid_chamber"}
			if (p.loading!="" and (float(p.remaining)<=0 or float(p.remaining)>float(p.duration))) or (p.loading=="" and float(p.remaining)!=0):return {"ok":false,"reason":"invalid_loading"}
			var capacity:=0
			var spent:=0
			for round_type in schema.rounds:
				if not _integer(p.reserve[round_type]) or not _integer(p.spent_rounds[round_type]):return {"ok":false,"reason":"invalid_stock"}
				var count:int=int(p.reserve[round_type])+int(p.spent_rounds[round_type])+int(p.loaded==round_type)+int(p.loading==round_type)
				if count!=int(schema.rounds[round_type]):return {"ok":false,"reason":"round_conservation"}
				capacity+=int(schema.rounds[round_type]);spent+=int(p.spent_rounds[round_type])
			if int(p.capacity)!=capacity or int(p.spent)!=spent:return {"ok":false,"reason":"capacity_or_spend_mismatch"}
			if int(p.last_commit)>int(data.sequence) or (int(p.spent)>0 and int(p.last_commit)==0):return {"ok":false,"reason":"invalid_sequence"}
			if not p.burst is Dictionary:return {"ok":false,"reason":"invalid_burst"}
			if not p.burst.is_empty():
				if p.kind!="burst" or not _integer(p.burst.get("id")) or not _integer(p.burst.get("next_index")):return {"ok":false,"reason":"invalid_burst"}
				if int(p.burst.id)<=0 or int(p.burst.id)>int(data.sequence) or int(p.burst.next_index)>3 or not p.reserve.has(p.burst.get("round")):return {"ok":false,"reason":"invalid_burst"}
	# A module-only continuation cannot rewind projectiles/damage already in this live
	# world. Cold registered-module restore remains separate from a full battle save.
	if live_continuation:
		if int(data.epoch)!=epoch or int(data.sequence)<sequence:return {"ok":false,"reason":"live_ammo_rollback_rejected"}
		for id in incoming:
			for mount in incoming[id]:
				var current:Dictionary=vehicles[id][mount]
				var resumed:Dictionary=incoming[id][mount]
				if int(resumed.last_commit)<int(current.last_commit):return {"ok":false,"reason":"live_ammo_rollback_rejected"}
				for round_type in current.spent_rounds:
					if int(resumed.spent_rounds[round_type])<int(current.spent_rounds[round_type]):return {"ok":false,"reason":"live_ammo_rollback_rejected"}
	vehicles=incoming.duplicate(true)
	epoch=int(data.epoch);sequence=int(data.sequence)
	# Firing permission is not a saved action. Emitted rockets remain spent;
	# un-emitted rounds were never reserved and stay in reserve after restore.
	for mounts in vehicles.values():
		for p in mounts.values():
			if not p.burst.is_empty():p.last_reason="restore_cancelled_pending_burst"
			p.burst={}
	return {"ok":true,"pending_fire_cancelled":true}
