extends RefCounted
## One local turret intention. It never shoots, chooses enemies, or owns damage.
const Sensor = preload("res://modules/ai_armor/visual_contact.gd")
const Roles = preload("res://modules/vehicle_crew/role_capability.gd")
const Safety = preload("res://modules/ai_safety/friendly_safety.gd")
const LOST_TTL := 8.0
var main: Node3D
var state := "idle"
var reason := "手动操炮"
var point := Vector3.ZERO
var observed_at := -1.0
var source := ""
var target_id := ""
var target_ref: WeakRef
var elapsed := 0.0
var refresh_remaining := 0.0
var contact_visible := false
var tick_usec := 0
var tick_calls := 0

func setup(host: Node3D) -> void: main=host
func active() -> bool: return state not in ["idle","cancelled","invalid"]

func cancel(why := "手动接管") -> void:
	state="cancelled"
	reason=why
	target_ref=null
	target_id=""
	contact_visible=false
	if is_instance_valid(main):main.aiming_pending=false

func _authority_reason() -> String:
	if main.garage or main.battle_finished:return "当前不在交战中"
	if is_instance_valid(main.player_infantry_controller) and main.player_infantry_controller.active():return "车长已离车"
	if not is_instance_valid(main.crew_host):return "车组未登记"
	var crew=main.crew_host
	var commander:Dictionary=crew.registry.person_ref(crew.commander_person_id())
	if commander.is_empty() or not Roles.capable(commander,"commander"):return "车长已失能"
	if commander.get("location",{}).get("kind","")!="vehicle":return "车长已离车"
	if bool(crew.takeover_status().pending):return "车长接替炮手中"
	if not crew.can_fire():return "炮手缺岗或失能，可接替炮手"
	return ""

func _actor_root(collider: Node) -> Node3D:
	var n:Node=collider
	var actor:Node3D=null
	while is_instance_valid(n):
		if n is Node3D and n.has_meta("actor_id"):actor=n
		if n==main.stage:break
		n=n.get_parent()
	return actor

func designate_from_view() -> Dictionary:
	var blocked:=_authority_reason()
	if not blocked.is_empty():reason=blocked;return {"ok":false,"reason":reason}
	var observer:Dictionary=main.observation_context()
	if observer.is_empty():return {"ok":false,"reason":"无有效观察人员"}
	var direction:Vector3=-main.camera.global_basis.z.normalized()
	var origin:Vector3=observer.origin
	var range_limit:float=minf(260.0,float(main.Visibility.WEATHER[["clear","rain","fog"][main.weather_index]].distance)*float(observer.range_multiplier))
	var end:Vector3=origin+direction*range_limit
	var query:=PhysicsRayQueryParameters3D.create(origin,end,1|8|16|32|128,observer.exclude)
	query.hit_from_inside=true
	var hit:Dictionary=main.get_world_3d().direct_space_state.intersect_ray(query)
	var chosen:Vector3=hit.get("position",end)
	var subject:Node3D=_actor_root(hit.collider) if not hit.is_empty() else null
	var observation_reason:String=main.observation_reason(chosen,subject,.12)
	if observation_reason!="visible":return {"ok":false,"reason":"无法指示："+{"smoke":"烟幕遮挡","obstacle":"观察点受阻","range":"超出视距"}.get(observation_reason,observation_reason)}
	target_ref=null;target_id=""
	if is_instance_valid(subject) and str(subject.get_meta("actor_id",""))!="player":
		if main.visibility_for_node(subject)!="visible":return {"ok":false,"reason":"目标仅部分可见，请重新观察或手动操炮"}
		var bounded:Dictionary=Sensor.observe(origin,direction,subject.global_position+Vector3.UP*1.1,str(subject.get_meta("actor_kind","vehicle")),elapsed)
		if bounded.is_empty():return {"ok":false,"reason":"目标尚无法辨认"}
		chosen=bounded.position
		target_ref=weakref(subject)
		target_id=str(subject.get_meta("actor_id",""))
	point=chosen;observed_at=elapsed;source=str(observer.sensor);contact_visible=true
	state="received";reason="炮手已接收，正在对准；开火仍需手动"
	refresh_remaining=.2
	main.clear_vehicle_fire_input()
	if is_instance_valid(main.battle_controls):
		main.battle_controls.fire_held=false;main.battle_controls.mg_held=false
	return {"ok":true,"point":point,"observed_at":observed_at,"source":source,"target_id":target_id}

func _observe_target() -> void:
	if target_id.is_empty():
		contact_visible=main.observation_reason(point,null,.15)=="visible"
		return
	contact_visible=false
	var subject:Node3D=target_ref.get_ref() if target_ref!=null else null
	if not is_instance_valid(subject):return
	# World position is only a SENSOR input. Never copy it into the drive intent
	# until the real person's LOS/smoke/range and bounded observation both pass.
	if main.visibility_for_node(subject)!="visible":return
	var observer:Dictionary=main.observation_context()
	if observer.is_empty():return
	var packet:Dictionary=Sensor.observe(observer.origin,-main.camera.global_basis.z,subject.global_position+Vector3.UP*1.1,str(subject.get_meta("actor_kind","vehicle")),elapsed)
	if packet.is_empty():return
	point=packet.position;observed_at=elapsed;source=str(observer.sensor);contact_visible=true

func tick(delta:float) -> void:
	var begin:=Time.get_ticks_usec()
	elapsed+=delta
	if active():_tick_active(delta)
	tick_usec+=Time.get_ticks_usec()-begin;tick_calls+=1

func _tick_active(delta:float) -> void:
	var blocked:=_authority_reason()
	if not blocked.is_empty():
		state="blocked";reason=blocked;main.aiming_pending=false
		if "离车" in blocked or "车长已失能" in blocked:cancel(blocked)
		return
	refresh_remaining-=delta
	if refresh_remaining<=0:
		refresh_remaining=.2
		_observe_target()
	if not target_id.is_empty() and elapsed-observed_at>LOST_TTL:
		state="invalid";reason="目标信息过期，重新观察后指示";main.aiming_pending=false;return
	main.aim_weapon(point)
	main.advance_weapon_aim(delta)
	if main.aim_contact_blocked:state="blocked";reason="真实炮管受阻，请调整车位";return
	if main.aim_limited:state="blocked";reason=str(main.aim_limit_reason);return
	if not contact_visible:state="searching";reason="观察受阻，仅朝最后已知位置搜索";return
	var muzzle:Node3D=main.weapon_muzzle(main.primary_weapon()=="mg")
	if not is_instance_valid(muzzle):state="blocked";reason="真实炮口不可用";return
	var direction:Vector3=(point-muzzle.global_position).normalized()
	if (-muzzle.global_basis.z).normalized().dot(direction)<.9995:state="slewing";reason="炮塔转动中";return
	var observer:Dictionary=main.observation_context()
	var query:=PhysicsRayQueryParameters3D.create(muzzle.global_position,point,1|8|16|32|128,observer.get("exclude",[]))
	query.hit_from_inside=true
	var hit:Dictionary=main.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var subject:Node3D=_actor_root(hit.collider)
		if Safety.collider_team(hit.collider)=="blue":
			state="blocked"
			reason="炮口前方有友军；手动射击仍会产生友伤" if is_instance_valid(subject) and main.visibility_for_node(subject)=="visible" else "炮口射界被障碍截住"
			return
		if (subject==null or str(subject.get_meta("actor_id",""))!=target_id) and muzzle.global_position.distance_to(hit.position)+1.5<muzzle.global_position.distance_to(point):state="blocked";reason="炮口射界被障碍截住";return
	var stock:Dictionary=main.vehicle_ammo.status(main.PLAYER_VEHICLE_ID,"mg" if main.primary_weapon()=="mg" else "primary")
	if not bool(stock.ready):
		state="waiting";reason="等待装填 %.1fs"%float(stock.remaining) if stock.loading!="" else "武器冷却中" if float(stock.get("cooldown",0))>0 else "所选弹药耗尽，请换弹种或武器"
		return
	state="ready";reason="已对准，可手动击发" if not target_id.is_empty() else "已朝指示方向，可手动击发"

func status_text() -> String:
	return "炮手："+reason
