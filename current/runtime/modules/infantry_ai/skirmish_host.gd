extends "res://modules/infantry_ai/infantry_host.gd"
## Optional first-skirmish demo adapter. All gameplay tuning is fictional.
func spawn(_stage: Node3D) -> void:
 if main.get("combined_battle_enabled")==false:
  _spawn_legacy(_stage)
  return
 clear()
 register_player(main.hero,"player","blue")
 var origin: Vector3=main.hero.global_position
 for team in ["blue","red"]:
  for squad in 3:
   var center_x := (float(squad)-1.0)*36.0
   var line_z := 15.0-float(squad)*40.0 if team=="blue" else 135.0+float(squad)*40.0
   var cover_z := line_z+(8.0 if team=="blue" else -8.0)
   _spawn_cover(origin+Vector3(center_x,0,cover_z),Vector3(17,2.4,1.1),("Friendly" if team=="blue" else "Enemy")+"SquadCover%d"%squad)
   for member in 5:
    var number := squad*5+member
    var id := ("friendly_" if team=="blue" else "enemy_")+"rifle_%02d"%number
    if number==0: id="friendly_rifle" if team=="blue" else "enemy_rifle"
    if number==7: id="friendly_at" if team=="blue" else "enemy_at"
    var point:=_ground(origin+Vector3(center_x+(float(member)-2.0)*3.0,0,line_z))
    var flank_x:=center_x+(-12.0 if member<2 else 12.0)
    var flank:=_ground(origin+Vector3(flank_x,0,line_z))
    var advance:=_ground(origin+Vector3(flank_x,0,75.0 if team=="blue" else 85.0))
    var actor=spawn_actor(id,team,point,[flank,advance,flank],[])
    actor.set_meta("initial_dismounted",true)
    actor.set_meta("fireteam",squad)
    actor.engagement_delay=2.0+float(member)*.15
    actor.aim_offsets=[Vector2(.65,.15),Vector2(-.65,-.15),Vector2.ZERO]
    if number==7:
     _equip_rocket(actor)
     actor.engagement_delay=4.0

func initial_infantry_counts() -> Dictionary:
 var counts:={"blue":0,"red":0,"total":0}
 for actor in actors.values():
  if not is_instance_valid(actor) or not bool(actor.get_meta("initial_dismounted",false)): continue
  counts[actor.brain.team_id]+=1
  counts.total+=1
 return counts

func _equip_rocket(actor: CharacterBody3D) -> void:
 actor.weapon="at"
 actor.penetration=110
 actor.damage=5.0
 var rifle=actor.find_child("Rifle",true,false)
 if rifle is Node3D: rifle.visible=false
 actor.brain.shot_interval=4.5
 actor.brain.magazine_size=1
 actor.brain.ammo=1
 actor.brain.reserve_ammo=2
 actor._sync_person_state()
 var path:="res://assets/reused_combat/panzerfaust.glb"
 if ResourceLoader.exists(path):
  var equipment=load(path).instantiate()
  equipment.name="ATEquipment"
  actor.add_child(equipment)
  equipment.position=Vector3(.25,1.05,-.2)
  var muzzle_node:=Marker3D.new()
  muzzle_node.name="ATMuzzle"
  muzzle_node.position=Vector3(0,0,-.55)
  equipment.add_child(muzzle_node)
  actor.bind_weapon_geometry(equipment,muzzle_node)

func _spawn_legacy(_stage: Node3D) -> void:
 clear()
 register_player(main.hero,"player","blue")
 var center: Vector3 = main.target.global_position
 # Keep the novice spawn away from an immediate point-blank crossfire.
 # Both cover pieces are real scenery colliders; driving around them opens sightlines.
 var friendly := _ground(center+Vector3(-8,0,-5))
 var enemy := _ground(center+Vector3(9,0,9))
 var at := _ground(center+Vector3(-5,0,13))
 _spawn_cover(center+Vector3(-7,0,-2),Vector3(8,1.6,0.8),"FriendlySandbagWall")
 _spawn_cover(center+Vector3(-5,0,10),Vector3(7,1.7,0.9),"EnemyATCover")
 spawn_actor("friendly_rifle","blue",friendly,[friendly,_ground(center+Vector3(-10,0,-5))],[])
 spawn_actor("enemy_rifle","red",enemy,[enemy,_ground(center+Vector3(12,0,7))],[])
 var equipment_path := "res://assets/reused_combat/panzerfaust.glb"
 var actor = spawn_actor("enemy_at","red",at,[at,_ground(center+Vector3(-3,0,13))],[])
 actor.weapon = "at"
 actor.brain.preferred_target_id = "player"
 actors["friendly_rifle"].brain.preferred_target_id = "enemy_rifle"
 actor.penetration = 110
 actor.damage = 5.0
 var rifle_visual = actor.find_child("Rifle",true,false)
 if rifle_visual is Node3D: rifle_visual.visible = false
 actor.brain.shot_interval = 4.5
 actor.brain.magazine_size = 1
 actor.brain.ammo = 1
 actor.brain.reserve_ammo = 2
 actor._sync_person_state()
 if ResourceLoader.exists(equipment_path):
  var equipment = load(equipment_path).instantiate()
  equipment.name = "ATEquipment"
  actor.add_child(equipment)
  equipment.position = Vector3(0.25,1.05,-0.2)
  var muzzle_node := Marker3D.new()
  muzzle_node.name = "ATMuzzle"
  muzzle_node.position = Vector3(0,0,-0.55)
  equipment.add_child(muzzle_node)
  actor.bind_weapon_geometry(equipment,muzzle_node)
 else:
  var notice := Label3D.new()
  notice.text = "AT equipment pending"
  notice.position.y = 2.0
  actor.add_child(notice)

 # Fixed opening grace period and stylized spread leave time to operate the tank.
 # Every round still follows the visibly aimed muzzle ray; no hit is guaranteed.
 for id in actors:
  actors[id].engagement_delay = 12.0 if id != "enemy_at" else 22.0
  actors[id].aim_offsets = [Vector2(0.65,0.15),Vector2(-0.65,-0.15),Vector2(0,0)]

func _ground(point: Vector3) -> Vector3:
 var result := point
 result.y = main.terrain_height(point.x,point.z)+0.12
 return result

func on_stage_reset() -> void:
 clear()
 player_actor = null

func handle_player_projectile(hit: Dictionary, kind: String, ammo_name: String, _part: String = "torso") -> String:
 if hit.is_empty(): return ""
 var id := _hit_actor(hit.get("collider"))
 if fortifications.has(id):
  var observed_fort:bool=main.visibility_for_node(fortifications[id].node)=="visible"
  var fort_result: Dictionary = damage_fortification(id,kind,player_team,ammo_name)
  if not observed_fort:return "射击已结算，结果无法确认"
  return "工事已摧毁" if bool(fort_result.get("destroyed",false)) else "命中工事"
 if not actors.has(id): return ""
 if not is_instance_valid(actors[id]) or actors[id].embarked: return ""
 var identified := is_identified(id)
 var part: String = actors[id].body_part_at(hit.position)
 var result: Dictionary = rules.hit_person(persons[id],part)
 sync_actor_person(id)
 infantry_event({"kind":"infantry_hit","actor_id":id,"source_actor_id":"player","result":result,"weapon":kind,"ammo":ammo_name})
 if not identified: return "射击已结算"
 return "AI步兵已失能" if not persons[id].alive else "AI步兵受伤"

func apply_player_blast(origin: Vector3) -> void:
 for id in actors:
  var actor = actors[id]
  if not is_instance_valid(actor) or actor.brain.hp <= 0.0 or actor.embarked: continue
  var destination: Vector3 = actor.global_position+Vector3.UP*0.8
  if origin.distance_to(destination)>10.0: continue
  var start := origin+Vector3.UP*0.15
  var query := PhysicsRayQueryParameters3D.create(start,destination,1|8|128)
  var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(query)
  if hit.is_empty() or _hit_actor(hit.collider)==id:
   var amount: float = rules.explode(persons[id],100.0,origin.distance_to(destination))
   if amount>0.0:
    sync_actor_person(id)
    infantry_event({"kind":"infantry_blast","actor_id":id,"source_actor_id":"player","damage":amount})

func _hit_actor(collider: Object) -> String:
 var node := collider as Node
 while is_instance_valid(node):
  if node.has_meta("actor_id"): return str(node.get_meta("actor_id"))
  node = node.get_parent()
 return ""

func is_identified(actor_id: String) -> bool:
 if not actors.has(actor_id) or not is_instance_valid(actors[actor_id]): return false
 var actor = actors[actor_id]
 if actor.embarked: return false
 return main.observation_reason(actor.global_position+Vector3.UP*actor.aim_height,actor)=="visible"

var marker_refresh := 0.0
func _process(_delta: float) -> void:
 for id in actors:
  var actor = actors[id]
  if not is_instance_valid(actor): continue
  var marker = actor.get_node_or_null("TeamMarker")
  if marker == null:
   marker = Label3D.new()
   marker.name = "TeamMarker"
   marker.position.y = 2.0
   marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
   marker.font_size = 26
   if main.font != null: marker.font = main.font
   marker.pixel_size = 0.007
   marker.text = "友" if actor.brain.team_id==player_team else "敌"
   marker.modulate = Color("75b9ff") if actor.brain.team_id==player_team else Color("ff8c75")
   actor.add_child(marker)
  var team_text: String = "友" if actor.brain.team_id==player_team else "敌"
  marker.text = team_text+(" · 失能" if actor.brain.hp<=0.0 else (" · 伤" if actor.brain.hp<10.0 else ""))
  var identified: bool = not actor.embarked and is_identified(id)
  actor.visible = identified
  marker.visible = identified and not bool(actor.get_meta("player_controlled",false))

func _spawn_cover(point: Vector3, size: Vector3, label: String) -> void:
 var obstacle := StaticBody3D.new()
 obstacle.name = label
 obstacle.collision_layer = 1
 obstacle.collision_mask = 0
 main.stage.add_child(obstacle)
 var ground := _ground(point)
 obstacle.global_position = ground+Vector3.UP*(size.y*0.5-0.12)
 register_fortification("fort_"+label,obstacle,"red" if label.begins_with("Enemy") else "blue")
 var shape := CollisionShape3D.new()
 var box := BoxShape3D.new()
 box.size = size
 shape.shape = box
 obstacle.add_child(shape)
 # Three staggered courses read as sandbag cover rather than an invisible wall.
 var material := StandardMaterial3D.new()
 material.albedo_color = Color("897c56")
 material.roughness = 0.95
 var columns := int(ceil(size.x/1.0))
 for row in 3:
  for column in columns:
   var mesh := MeshInstance3D.new()
   var bag := BoxMesh.new()
   bag.size = Vector3(size.x/columns-0.025,size.y/3.0-0.025,size.z)
   mesh.mesh = bag
   mesh.material_override = material
   mesh.position = Vector3(-size.x*0.5+(column+0.5)*size.x/columns,-size.y*0.5+(row+0.5)*size.y/3.0,0)
   obstacle.add_child(mesh)
