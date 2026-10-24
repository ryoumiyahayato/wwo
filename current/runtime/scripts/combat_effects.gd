extends Node3D
# Cosmetic pool: ammunition, ray hits and damage never depend on allocation.
const WeaponVFX=preload("res://scripts/weapon_vfx_profile.gd")
var low_quality:bool=bool(ProjectSettings.get_setting("rendering/vfx/low_quality",false))
const Response=preload("res://scripts/hit_response_layers.gd")
const HitFeedback=preload("res://scripts/hit_feedback.gd")
var feedback_audit:Array[Dictionary]=[]
const Layers=preload("res://scripts/battle_vfx_layers.gd")
const SmokeCloud=preload("res://scripts/smoke_cloud.gd")
const MAX_EVENTS:=24
const ADS_CLEARANCE:=1.4
var events:Array[Dictionary]=[]
var pool:Array[Dictionary]=[]
var mg_counter:=0
var dropped_visuals:=0
var emitted_visuals:=0
var player_shot_sequence:=0
var last_player_kind:=""
var sphere:SphereMesh
var quad:QuadMesh
var hot:StandardMaterial3D
var initialized:=false

func _ready()->void:
	warm_pool()

func glow(color:Color)->StandardMaterial3D:
	var mat:=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=color;mat.emission_enabled=true;mat.emission=color
	return mat

func _mesh(parent:Node3D,geometry:Mesh,material:Material)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.mesh=geometry;node.material_override=material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node);return node

func warm_pool()->void:
	if initialized:return
	initialized=true
	sphere=SphereMesh.new();sphere.radius=1;sphere.height=2;sphere.radial_segments=8;sphere.rings=4
	quad=QuadMesh.new();quad.size=Vector2.ONE
	hot=glow(Color(1,.86,.36))
	# All shaders/materials/meshes/nodes are allocated once, never in fire/impact.
	var flash_template:=Layers.material(Color(1,.73,.24,.98))
	var dust_template:=Layers.material(Color(.53,.49,.40,.65))
	for i in range(MAX_EVENTS):
		var root:=Node3D.new();add_child(root);root.hide()
		var slot:Dictionary={"root":root,"active":false}
		for key in ["flash","gas","trail","dust"]:
			slot[key]=_mesh(root,quad,(flash_template if key=="flash" else dust_template).duplicate())
		for key in ["core","projectile","spark"]:slot[key]=_mesh(root,sphere,hot)
		slot["layers"]=Layers.warm(root,quad)
		slot["debris"]=Layers.warm_debris(root)
		slot["response"]=Response.warm(root)
		pool.append(slot)

func _retire(event:Dictionary)->void:
	event.root.hide();event.active=false;events.erase(event)

func fire(origin:Vector3,endpoint:Vector3,kind:String="cannon",contact:bool=true,surface:String="ground",show_muzzle:bool=true,priority:bool=false,point_visibility:Callable=Callable(),profile:String="kinetic",feedback:Dictionary={})->bool:
	warm_pool()
	if priority:player_shot_sequence+=1;last_player_kind=kind
	if events.size()>=MAX_EVENTS:
		dropped_visuals+=1
		if not priority:return false
		# Prefer dropping AI cosmetics rather than a newer player shot.
		var retired:Dictionary=events[0]
		for item in events:
			if not item.priority:retired=item;break
		_retire(retired)
	var event:Dictionary={}
	for slot in pool:
		if not slot.active:event=slot;break
	if event.is_empty():return false
	var visual:Dictionary=WeaponVFX.resolve(feedback.get("visual_weapon",{}),kind,profile,low_quality)
	var mg:=kind=="mg"
	if mg:mg_counter+=1
	var direction:Vector3=(endpoint-origin).normalized()
	if direction.length_squared()<.001:direction=Vector3.FORWARD
	var distance:=origin.distance_to(endpoint)
	var travel:=clampf(distance/(45.0 if kind=="rocket" else 160.0 if mg else 90.0),.09,.75 if mg else .65)
	event.merge({"visual":visual,"feedback":feedback.duplicate(),"profile":profile,"kind":kind,"sequence":emitted_visuals,"point_visibility":point_visibility,"active":true,"age":0.0,"travel":travel,"origin":origin,"end":endpoint,"direction":direction,"distance":distance,"mg":mg,"rocket":kind=="rocket","contact":contact and kind!="smoke","surface":surface,"impact_started":false,"impact":null,"ads":priority and not show_muzzle,"tracer":not mg or mg_counter%2==1,"priority":priority,"show_muzzle":show_muzzle,"flash_frames":0,"tracer_frames":0,"tracer_samples":0,"impact_age":0.0},true)
	event.root.show()
	Layers.reset(event)
	event.response.mark.hide()
	for jet in event.response.jets:jet.hide()
	for key in ["flash","core","gas","projectile","trail","dust","spark"]:event[key].hide()
	event.flash.global_position=origin+direction*(.14 if mg else .35)
	event.flash.scale=Vector3(float(visual.flash_width),float(visual.flash_width),1.0);event.flash.visible=show_muzzle
	event.flash.material_override.set_shader_parameter("opacity",1.0)
	event.flash.material_override.set_shader_parameter("heat",1.0)
	event.core.global_position=event.flash.global_position
	event.core.scale=Vector3(.065,.065,.20) if mg else Vector3(.18,.18,.45)
	event.core.scale.z*=float(visual.flash_length)
	event.core.visible=show_muzzle
	event.gas.global_position=origin
	event.gas.visible=show_muzzle and not mg
	event.projectile.global_position=origin
	# Short finite segment, never an origin-to-hit beam. Thick enough for mobile.
	event.projectile.scale=Vector3(.065,.065,minf(1.25,distance*.20)) if mg else Vector3(.09,.09,minf(.7,distance*.20))
	for key in ["core","projectile"]:
		if absf(direction.dot(Vector3.UP))<.99:event[key].look_at(event[key].global_position+direction)
	event.projectile.visible=event.tracer and not event.ads
	_apply_visibility(event)
	events.append(event);emitted_visuals+=1
	return true

# Reuse the same bounded choreography for existing rocket/mortar callbacks.
# These helpers never create a projectile or alter the collision/damage event.
func impact_at(point:Vector3,sensor:Callable=Callable(),visual_weapon:Dictionary={})->bool:
	if not fire(point,point,"rocket",true,"ground",false,false,sensor,"he",{"visual_weapon":visual_weapon}):return false
	begin_impact(events.back())
	_apply_visibility(events.back())
	return true

func muzzle_at(point:Vector3,direction:Vector3,sensor:Callable=Callable(),visual_weapon:Dictionary={})->bool:
	return fire(point,point+direction.normalized()*.5,"smoke",false,"ground",true,false,sensor,"muzzle_only",{"visual_weapon":visual_weapon})

# Project each cosmetic point independently. An observed impact does not reveal
# the hidden firing position, and a visible muzzle does not reveal a hidden hit.
# This callback has no access to or effect on ammunition, damage or simulation.
func _apply_visibility(event:Dictionary,keys:Array=["flash","core","gas","projectile","trail","dust","spark"])->void:
	var sensor:Callable=event.get("point_visibility",Callable())
	if not sensor.is_valid():return
	for key in keys:
		# Own muzzle feedback is already known and retains existing ADS clearance.
		if event.priority and key in ["flash","core","gas"]:continue
		if event[key].visible:event[key].visible=bool(sensor.call(event[key].global_position))

func begin_impact(event:Dictionary)->void:
	event.impact_started=true;event.impact_age=0.0;event.projectile.hide();event.trail.hide()
	if not event.contact:return
	event.impact=event.dust
	event.dust.global_position=event.end;event.dust.scale=Vector3.ONE*(.2 if event.mg else .8);event.dust.show()
	event.dust.material_override.set_shader_parameter("opacity",1.0)
	event.spark.global_position=event.end;event.spark.scale=Vector3.ONE*(.035 if event.mg else .12);event.spark.visible=event.surface=="metal"
	Response.update(event,events.size())

func _process(delta:float)->void:
	for i in range(events.size()-1,-1,-1):
		var event:Dictionary=events[i]
		event.age+=maxf(0,delta)
		var age:float=event.age
		# Present one pulse even when the first simulation delta exceeds its life.
		# On the following rendered frame use wall age, so flashes cannot stick on.
		var flash_alive:bool=age<float(event.visual.pulse) or event.flash_frames==0
		event.flash.visible=event.show_muzzle and flash_alive
		event.core.visible=event.show_muzzle and flash_alive
		event.flash_frames+=1
		event.gas.visible=event.show_muzzle and not event.mg and age<float(event.visual.gas_life)
		if event.gas.visible:
			event.gas.global_position=event.origin+event.direction*(.25+age*float(event.visual.gas_speed))+Vector3.UP*age*.35
			event.gas.scale=Vector3.ONE*(float(event.visual.gas_width)+age*float(event.visual.gas_speed))
			event.gas.material_override.set_shader_parameter("opacity",maxf(0,1-age/float(event.visual.gas_life)))
		if not event.impact_started:
			var sample_age:float=age
			if event.tracer and event.tracer_samples==0:
				sample_age=minf(age,event.travel*minf(.5,18.0/maxf(.01,event.distance)))
			var progress:float=clampf(sample_age/event.travel,0,1)
			# Entire segment stays inside the real muzzle-to-impact interval.
			var half_length:float=event.projectile.scale.z
			var along:float=clampf(progress*event.distance,half_length,maxf(half_length,event.distance-half_length))
			if event.ads and sample_age<age and event.distance>ADS_CLEARANCE+half_length*2:
				along=maxf(along,ADS_CLEARANCE+half_length+.001)
			event.projectile.global_position=event.origin+event.direction*along
			var clear:bool=not event.ads or along-half_length>=ADS_CLEARANCE
			event.projectile.visible=event.tracer and clear and event.distance>.01
			event.tracer_samples+=1
			_apply_visibility(event,["projectile"])
			if event.projectile.visible:event.tracer_frames+=1
			event.trail.visible=event.rocket and event.projectile.visible
			if event.trail.visible:event.trail.global_position=event.projectile.global_position;event.trail.scale=Vector3.ONE*.7
			var shown:bool=not event.tracer or event.tracer_frames>1 or (not event.projectile.visible and event.tracer_samples>1) or event.ads and event.distance<=ADS_CLEARANCE+half_length*2
			# Hold the first visible segment for this frame; impact begins next frame.
			if age>=event.travel and shown and (sample_age==age or not event.projectile.visible):begin_impact(event)
		else:
			event.impact_age+=maxf(0,delta)
			var impact_age:float=event.impact_age
			event.dust.visible=event.contact and impact_age<(.12 if event.mg else .24)
			event.spark.visible=event.contact and event.surface=="metal" and impact_age<.08
			if event.dust.visible:
				event.dust.scale=Vector3.ONE*((.2 if event.mg else .8)+impact_age*2.0)
				event.dust.material_override.set_shader_parameter("opacity",maxf(0,1-impact_age/(.12 if event.mg else .24)))
			Layers.update(event,get_viewport().get_camera_3d(),events.size())
			Response.update(event,events.size())
			if (not event.contact and age>maxf(.9,float(event.visual.gas_life))) or impact_age>(.85 if event.mg else 2.85):_retire(event)
		# Projectile was already filtered before tracer/impact decisions above.
		# It cannot become visible again later in this update; avoid a duplicate LOS.
		_apply_visibility(event,["flash","core","gas","trail","dust","spark"])

func set_impact_result(shot_id:int,result:Dictionary,observable:bool=true)->bool:
	if shot_id<0:return false
	for event in events:
		if int(event.feedback.get("shot_id",-1))!=shot_id:continue
		var fact:Dictionary=HitFeedback.outcome(result,observable)
		event.feedback.merge(fact,true)
		feedback_audit.append({"shot_id":shot_id,"surface":event.surface,"normal":event.feedback.get("normal",Vector3.ZERO),"outcome":fact.outcome,"result_known":fact.result_known,"source_kind":fact.get("source_kind","unknown")})
		if feedback_audit.size()>64:feedback_audit.pop_front()
		return true
	return false
