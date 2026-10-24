extends RefCounted
## Military-owned custody journal and projection. No economic inventory or hit solver.
const Ammo = preload("res://modules/vehicle_ammo/vehicle_ammo.gd")
const SCHEMA := "military_material_registry_v1"
const PHYSICAL_SCHEMA := "military_material_registry_v2_practice"
const RECOVERY_SCHEMA := "military_material_registry_v3_recovery"
const PhysicalShot = preload("res://practice/shot_contract.gd")
const CONFIG := "res://custody/depot_1900.json"
const OPERATIONS := ["reserve","issue","use","return","cancel","loss","transfer","inspect","recover"]

static func config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CONFIG))

static func native(quantity: int, epoch: int) -> RefCounted:
	var a:=Ammo.new();a.new_battle(epoch)
	a.register_vehicle(config().asset_id,{"primary":{"kind":"chamber","rounds":{"ball":quantity},"initial":"ball"}})
	return a

static func empty() -> Dictionary:
	return {"schema":SCHEMA,"events":[],"view":{}}

static func error(state: Dictionary) -> String:
	if state.is_empty():return ""
	if not keys(state,["schema","events","view"]) or state.schema not in [SCHEMA,PHYSICAL_SCHEMA,RECOVERY_SCHEMA] or not state.events is Array or state.events.size()>256 or not state.view is Dictionary:return "UNKNOWN_MATERIAL_SCHEMA_OR_FIELDS"
	if state.schema==SCHEMA:
		for event: Variant in state.events:
			if event is Dictionary:
				var payload: Variant=event.get("payload")
				if payload is Dictionary and payload.has("physical"):return "PHYSICAL_SHOT_REQUIRES_V2_REGISTRY"
	var reduced:=replay(state.events)
	if not reduced.ok:return reduced.reason
	return "MATERIAL_PROJECTION_OR_INVENTORY_ROLLBACK" if state.view!=reduced.view else ""

static func append(state: Dictionary,event: Dictionary) -> Dictionary:
	if state!=empty() and not error(state).is_empty():return fail("INVALID_CURRENT_MATERIAL_STATE")
	if state.events.size()>=256:return fail("MATERIAL_JOURNAL_LIMIT")
	var events: Array=state.events.duplicate(true);events.append(event.duplicate(true))
	var result:=replay(events)
	if not result.ok:return result
	var schema: String=PHYSICAL_SCHEMA if event.get("payload",{}).has("physical") else str(state.get("schema",SCHEMA))
	if state.get("schema")==RECOVERY_SCHEMA:schema=RECOVERY_SCHEMA
	return {"ok":true,"state":{"schema":schema,"events":events,"view":result.view}}

static func replay(events: Array) -> Dictionary:
	var v: Dictionary={};var c:=config();var previous_minute:=-1
	for index: int in events.size():
		var e: Variant=events[index]
		if not e is Dictionary or not keys(e,["event_id","sequence","kind","minute","actor_id","context","payload"]):return fail("INVALID_MATERIAL_EVENT")
		if e.event_id!="%s:event:%d"%[c.source_id,index+1] or not natural(e.sequence) or e.sequence!=index+1 or not natural(e.minute) or e.minute<previous_minute or not e.payload is Dictionary or not e.context is Dictionary:return fail("MATERIAL_SEQUENCE_OR_TIME_ROLLBACK")
		previous_minute=int(e.minute)
		var p: Dictionary=e.payload;var kind:=str(e.kind)
		if index==0:
			if kind!="register" or p!=c or e.actor_id!="scenario_initializer" or not e.context.is_empty():return fail("UNREGISTERED_OR_UNKNOWN_SOURCE")
			v={"source":c.duplicate(true),"asset":{"asset_id":c.asset_id,"source_id":c.source_id,"owner_id":c.owner_id,"place_id":c.place_id,"location_basis":"depot_record","holder_id":c.owner_id,"status":"available","condition":100,"lease_id":""},"lot":{"lot_id":c.lot_id,"source_id":c.source_id,"owner_id":c.owner_id,"place_id":c.place_id,"registered":c.initial_rounds,"available":c.initial_rounds,"reserved":0,"issued":0,"consumed":0,"lost":0,"cumulative_issued":0,"cumulative_returned":0},"leases":{},"receipts":{}}
			continue
		if kind not in OPERATIONS or not keys(e.context,["person_id","acting_organization_id","appointment_id","membership_basis","represented_organization_id","authority_basis","decision_id","delegation_id"]) or not e.actor_id is String or not str(e.actor_id).begins_with("person:") or e.context.get("person_id")!=e.actor_id or e.context.get("represented_organization_id")!=v.asset.owner_id:return fail("INVALID_MATERIAL_ACTOR_OR_OWNER")
		if not e.context.membership_basis is bool:return fail("INVALID_MATERIAL_MEMBERSHIP_CONTEXT")
		for field: String in ["person_id","acting_organization_id","appointment_id","represented_organization_id","authority_basis","decision_id","delegation_id"]:
			if not e.context[field] is String:return fail("INVALID_MATERIAL_AUTHORITY_CONTEXT")
		var a: Dictionary=v.asset;var lot: Dictionary=v.lot
		var lease: Dictionary={}
		if kind not in ["reserve","transfer"]:
			if not p.get("lease_id") is String or not v.leases.has(p.lease_id):return fail("UNKNOWN_CUSTODY_LEASE")
			lease=v.leases[p.lease_id]
			if lease.status not in ["reserved","issued"] or lease.person_id!=e.actor_id or a.lease_id!=p.lease_id:return fail("LEASE_NOT_HELD_OR_TERMINAL")
		match kind:
			"reserve":
				if not keys(p,["lease_id","quantity"]) or not natural(p.quantity) or p.quantity<1:return fail("INVALID_RESERVATION_QUANTITY")
				if p.quantity>lot.available:return fail("INSUFFICIENT_SOURCE_STOCK")
				if a.status!="available":return fail("ASSET_ALREADY_HELD_OR_LOST")
				if p.lease_id!="custody:%d"%int(e.sequence) or v.leases.has(p.lease_id):return fail("DUPLICATE_CUSTODY_LEASE")
				lot.available-=p.quantity;lot.reserved+=p.quantity
				a.status="reserved";a.holder_id=e.actor_id;a.lease_id=p.lease_id
				v.leases[p.lease_id]={"lease_id":p.lease_id,"person_id":e.actor_id,"owner_id":a.owner_id,"place_id":a.place_id,"quantity":p.quantity,"status":"reserved","generation":0,"issuer_id":"","native":{}}
			"issue":
				if not keys(p,["lease_id","issuer_id"]) or lease.status!="reserved" or not token(p.issuer_id):return fail("NOT_RESERVED_OR_INVALID_ISSUER")
				lot.reserved-=lease.quantity;lot.issued+=lease.quantity;lot.cumulative_issued+=lease.quantity
				lease.status="issued";lease.issuer_id=p.issuer_id;lease.generation=1
				lease.native=native(int(lease.quantity),int(e.sequence)).snapshot();a.status="issued"
			"recover":
				if not keys(p,["lease_id","issuer_id"]) or lease.status!="issued" or not token(p.issuer_id) or lease.issuer_id==p.issuer_id:return fail("INVALID_CUSTODY_RECOVERY")
				lease.issuer_id=p.issuer_id;lease.generation+=1
			"use":
				var fields: Array=["lease_id","issuer_id","generation","receipt_id","before","after","commit"]
				if p.has("physical"):fields.append("physical")
				if not keys(p,fields) or lease.status!="issued" or p.issuer_id!=lease.issuer_id or p.generation!=lease.generation:return fail("STALE_CUSTODY_EXECUTOR")
				if p.before!=lease.native or not p.after is Dictionary or not p.commit is Dictionary:return fail("CUSTODY_NATIVE_ROLLBACK")
				var ammo:=native(int(lease.quantity),int(lease.native.epoch))
				if not ammo.restore(p.before).get("ok",false):return fail("INVALID_NATIVE_BEFORE")
				if p.has("physical"):
					if not p.physical is Dictionary:return fail("INVALID_PHYSICAL_SHOT")
					var physical_error:=PhysicalShot.error(p.physical,p,e,c)
					if not physical_error.is_empty():return fail(physical_error)
					if int(p.physical.native_preparation_usec)>0:ammo.advance(0.001)
				# Detached canonical validation calls the original owner; no live stock is decremented here.
				var result: Dictionary=ammo.commit_fire(c.asset_id,"primary",ammo.request_id(),0.001,true,true)
				var rid: String="%s:g%d:commit:%d"%[p.lease_id,int(lease.generation),int(ammo.sequence)]
				if not result.get("ok",false) or result!=p.commit or p.receipt_id!=rid or v.receipts.has(rid) or ammo.snapshot()!=p.after:return fail("INVALID_OR_DUPLICATE_NATIVE_CONSUMPTION")
				lot.issued-=1;lot.consumed+=1;lease.native=p.after.duplicate(true);v.receipts[rid]=p.duplicate(true)
			"return","cancel","loss":
				if not keys(p,["lease_id","reason"]) or not token(p.reason):return fail("MISSING_CUSTODY_OUTCOME_REASON")
				var remaining:=int(lease.quantity)
				if lease.status=="reserved":lot.reserved-=remaining
				else:
					remaining=int(lease.quantity)-int(lease.native.vehicles[c.asset_id].primary.spent)
					lot.issued-=remaining
				if kind=="loss":lot.lost+=remaining;a.status="lost";a.condition=0
				else:
					lot.available+=remaining;a.status="available"
					if lease.status=="issued":lot.cumulative_returned+=remaining
				lease.status=kind;lease.outcome_reason=p.reason;a.holder_id="" if kind=="loss" else a.owner_id;a.lease_id=""
				if kind=="loss":a.location_basis="last_known_at_loss"
			"inspect":
				if not keys(p,["lease_id","condition","reason"]) or not natural(p.condition) or p.condition<1 or p.condition>=a.condition or not token(p.reason):return fail("INVALID_CONDITION_OR_UNSOURCED_REPAIR")
				a.condition=p.condition
			"transfer":
				if not keys(p,["owner_id","place_id","reason"]) or a.status!="available" or p.owner_id not in [c.owner_id,c.receiver_id] or p.owner_id==a.owner_id or p.place_id!=c.place_id or not token(p.reason):return fail("TRANSFER_REQUIRES_AVAILABLE_KIT_AND_KNOWN_OWNER")
				a.owner_id=p.owner_id;a.holder_id=p.owner_id;a.place_id=p.place_id;lot.owner_id=p.owner_id;lot.place_id=p.place_id
		for key: String in ["registered","available","reserved","issued","consumed","lost","cumulative_issued","cumulative_returned"]:
			if not natural(lot[key]):return fail("NEGATIVE_OR_NONINTEGER_MATERIAL_STOCK")
		if lot.registered!=lot.available+lot.reserved+lot.issued+lot.consumed+lot.lost:return fail("MATERIAL_CONSERVATION_FAILED")
		var held:=0
		for other: Dictionary in v.leases.values():
			if other.status in ["reserved","issued"]:held+=1
		if held!=int(a.status in ["reserved","issued"]):return fail("DOUBLE_CUSTODY")
	if events.is_empty():return fail("MATERIAL_SOURCE_REQUIRED")
	return {"ok":true,"view":v}

static func references_error(world: WorldState) -> String:
	var s: Dictionary=world.military_state.material_registry
	if s.is_empty():return ""
	var reason:=error(s)
	if not reason.is_empty():return reason
	var c: Dictionary=s.view.source
	for org: String in [c.owner_id,c.receiver_id]:
		if not world.organization_state.has_organization(org):return "UNKNOWN_MATERIAL_OWNER"
	if world.spatial_world.get_place(c.place_id).is_empty():return "UNKNOWN_MATERIAL_PLACE"
	for lease: Dictionary in s.view.leases.values():
		if not world.person_overlay.has_person(lease.person_id):return "UNKNOWN_MATERIAL_CUSTODIAN"
	for e: Dictionary in s.events:
		if e.minute>world.game_clock.total_minutes():return "MATERIAL_EVENT_FROM_FUTURE"
		if e.kind!="register" and not world.person_overlay.has_person(e.actor_id):return "UNKNOWN_MATERIAL_ACTOR"
		if e.kind!="register":
			var grant: Dictionary=world.organization_state.authority_grant(str(e.context.authority_basis))
			if grant.get("operation")!="military.material."+str(e.kind) or not grant.get("target_scope",[]).has(c.asset_id):return "UNKNOWN_MATERIAL_AUTHORITY_REFERENCE"
		if e.payload.has("physical"):
			var physical_error:=PhysicalShot.references_error(world,e.payload.physical)
			if not physical_error.is_empty():return physical_error
	return ""

static func keys(d: Dictionary,expected: Array) -> bool:
	return d.size()==expected.size() and d.has_all(expected)

static func natural(v: Variant) -> bool:
	return typeof(v) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(v)) and float(v)>=0 and float(v)==floor(float(v)) and float(v)<=9007199254740991.0

static func token(v: Variant) -> bool:
	return v is String and not v.is_empty() and v.length()<=180

static func fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}
