extends RefCounted
## Bounded cosmetic choreography only. No collision, damage, ammo or hidden-target lookup.
const SHADER=preload("res://scripts/battle_vfx_billows.gdshader")
const LAYERS:=8
const DEBRIS:=4
static func material(color:Color,seed_value:float=0.0)->ShaderMaterial:
 var result:=ShaderMaterial.new();result.shader=SHADER
 result.set_shader_parameter("tint",color);result.set_shader_parameter("seed",seed_value)
 return result
static func warm(parent:Node3D,quad:QuadMesh)->Array[MeshInstance3D]:
 var result:Array[MeshInstance3D]=[]
 for i in range(LAYERS):
  var node:=MeshInstance3D.new();node.mesh=quad
  node.material_override=material(Color(.41,.37,.30,.8),float(i)*3.73)
  node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  parent.add_child(node);node.hide();result.append(node)
 return result
static func warm_debris(parent:Node3D)->Array[MeshInstance3D]:
 var result:Array[MeshInstance3D]=[]
 var mesh:=BoxMesh.new();mesh.size=Vector3(.055,.055,.19)
 var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.3,.25,.19);mat.roughness=1.0
 for i in range(DEBRIS):
  var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=mat
  node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  parent.add_child(node);node.hide();result.append(node)
 return result
static func reset(event:Dictionary)->void:
 for node in event.debris:
  node.hide()
  node.material_override.albedo_color=Color(1,.65,.17) if event.surface=="metal" else Color(.3,.25,.19)
  node.material_override.emission_enabled=event.surface=="metal"
  node.material_override.emission=Color(1,.4,.05)
 for node in event.layers:node.hide()
static func update(event:Dictionary,camera:Camera3D,load_count:int)->void:
 var elapsed:float=event.impact_age
 var normal:Vector3=event.get("feedback",{}).get("normal",Vector3.UP)
 if normal.length_squared()<.001:normal=Vector3.UP
 var plane:Basis=preload("res://scripts/hit_response_layers.gd").axes(normal)
 var explosive:bool=event.profile=="he" or event.rocket or event.kind=="mortar"
 var visual:Dictionary=event.get("visual",preload("res://scripts/weapon_vfx_profile.gd").resolve({},event.kind,event.profile))
 var radius:float=.55 if event.mg else 2.4 if explosive else .6 if event.surface=="metal" else 1.1
 radius*=float(visual.dust_radius)
 var distance:float=0.0 if camera==null else camera.global_position.distance_to(event.end)
 # Hard per-event tier, plus density backoff. Main contact flash remains available.
 var count:int=8 if distance<45.0 else 5 if distance<110.0 else 2
 count=mini(count,int(visual.layers))
 if load_count>12:count=mini(count,4)
 if event.mg or event.surface=="metal" and not explosive:count=mini(count,3)
 var lifetime:float=minf(2.6,float(visual.dust_life)+(.4 if explosive else 0.0))
 var sensor:Callable=event.get("point_visibility",Callable())
 for i in range(DEBRIS):
  var node:MeshInstance3D=event.debris[i]
  node.visible=event.contact and (not event.mg or event.surface=="metal") and not bool(visual.low) and distance<65.0 and load_count<16 and elapsed<.65
  if not node.visible:continue
  var a:float=float(i)*2.399963+float(event.sequence%7)*.7
  var velocity:Vector3=(plane.x*cos(a)*2.7+normal*(3.0+float(i)*.45)+plane.y*sin(a)*2.7)*radius*float(visual.debris_speed)
  node.global_position=event.end+Vector3.UP*.12+velocity*elapsed+Vector3.DOWN*7.5*elapsed*elapsed
  node.scale=Vector3.ONE*(1.0-elapsed/.75)
  node.rotation=Vector3(elapsed*8.0,a,elapsed*5.0)
  if sensor.is_valid():node.visible=bool(sensor.call(node.global_position))
 for i in range(LAYERS):
  var node:MeshInstance3D=event.layers[i]
  var delay:float=.04+float(i%3)*(.065 if visual.tier=="large" else .03 if visual.tier=="small" else .045)
  var t:float=elapsed-delay
  node.visible=event.contact and i<count and t>0.0 and t<lifetime
  if not node.visible:continue
  var a:float=float(i)*2.399963+float(event.sequence%11)*.41
  var radial:Vector3=plane.x*cos(a)+plane.y*sin(a)
  var fraction:float=float(i)/float(maxi(1,count-1))
  # Initial low ground jet loses momentum, then a smaller buoyant smoke column rises.
  var outward:float=(1.0-exp(-t*3.2))*radius*(.55+fraction*.85)
  var height:float=(.12+t*(.55+fraction*.55))*radius
  if i%3==0:height=.10+radius*.16;outward*=1.35
  node.global_position=event.end+radial*outward+normal*height+Vector3.UP*t*.2
  node.scale=Vector3.ONE*radius*(.45+sqrt(t)*(.7+fraction*.3))
  var fade:float=smoothstep(0.0,.13,t)*(1.0-smoothstep(lifetime*.28,lifetime,t))
  var heat:float=(1.0-smoothstep(.03,.28,t)) if explosive and i%3!=0 else 0.0
  var tint:Color=Color(.23,.24,.24,.85) if explosive and i%3!=0 else Color(.49,.43,.33,.72)
  if event.surface in ["stone","metal"]:tint=Color(.48,.49,.48,.62)
  if event.surface=="wood":tint=Color(.45,.32,.18,.65)
  node.material_override.set_shader_parameter("opacity",fade)
  node.material_override.set_shader_parameter("age",t)
  node.material_override.set_shader_parameter("heat",heat)
  node.material_override.set_shader_parameter("tint",tint)
  if sensor.is_valid():node.visible=bool(sensor.call(node.global_position))
