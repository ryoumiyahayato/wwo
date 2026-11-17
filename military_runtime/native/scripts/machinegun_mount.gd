extends RefCounted
## Physical, simplified prototype coaxial MGs. These are gameplay additions,
## not claims about historical equipment. Original cannon Muzzle is untouched.
## Call immediately after model instantiation, before articulation is aimed.
## Every returned muzzle's -Z axis is the visible MG bore direction.

static func install(model:Node3D,vehicle_id:String) -> Marker3D:
	# Authored dual-gun assets must never receive a fabricated third gun.
	if model.find_child("HullMG_Muzzle",true,false)!=null or model.find_child("TurretMG_Muzzle",true,false)!=null:return null
	if vehicle_id=="armored_car_rocket":return null # No secondary MG in this loadout.
	var existing:=model.find_child("MG_Muzzle",true,false) as Marker3D
	if existing!=null:return existing
	var primary:=model.find_child("Muzzle",true,false) as Node3D
	var barrel:=model.find_child("Barrel",true,false) as Node3D
	if primary==null or barrel==null:return null
	var muzzle:=Marker3D.new();muzzle.name="MG_Muzzle"
	if vehicle_id=="armored_car_mg":
		# This loadout's primary weapon already is the physical machine gun.
		primary.add_child(muzzle)
		muzzle.set_meta("mg_mount_mode","primary_existing_machinegun")
	elif vehicle_id=="t35":
		# Source component132: narrow MG barrel x=.28,y=1.72,z=-1.55
		# in unscaled Godot coordinates; it is already grouped inside Barrel.
		var scale_xyz:=Vector3(.9142857142857144,1.464247598719317,1.5690072204458532)
		var point:=Vector3(.28,1.72,-1.55)*scale_xyz
		var turret:=model.find_child("Turret",true,false) as Node3D
		barrel.add_child(muzzle)
		muzzle.position=(turret.transform*barrel.transform).affine_inverse()*point
		muzzle.set_meta("mg_mount_mode","existing_barrel_coax")
		muzzle.set_meta("mg_source_component",132)
	else:
		var mount:=Node3D.new();mount.name="PrototypeCoaxMG"
		barrel.add_child(mount);mount.position=Vector3(.34,.06,-.04)
		mount.set_meta("fictional_prototype",true)
		var dark:=StandardMaterial3D.new();dark.albedo_color=Color("283035");dark.metallic=.65;dark.roughness=.6
		var steel:=StandardMaterial3D.new();steel.albedo_color=Color("606c70");steel.metallic=.7;steel.roughness=.5
		var receiver:=MeshInstance3D.new();receiver.name="MG_Receiver"
		var box:=BoxMesh.new();box.size=Vector3(.14,.13,.32);receiver.mesh=box
		receiver.position=Vector3(0,0,-.05);receiver.material_override=dark;mount.add_child(receiver)
		var tube:=MeshInstance3D.new();tube.name="MG_Barrel"
		var cylinder:=CylinderMesh.new();cylinder.top_radius=.025;cylinder.bottom_radius=.025;cylinder.height=.72;cylinder.radial_segments=12
		tube.mesh=cylinder;tube.rotation.x=PI*.5;tube.position=Vector3(0,0,-.52);tube.material_override=dark;mount.add_child(tube)
		var collar:=MeshInstance3D.new();collar.name="MG_MuzzleCollar"
		var collar_mesh:=CylinderMesh.new();collar_mesh.top_radius=.033;collar_mesh.bottom_radius=.033;collar_mesh.height=.10;collar_mesh.radial_segments=12
		collar.mesh=collar_mesh;collar.rotation.x=PI*.5;collar.position=Vector3(0,0,-.85);collar.material_override=steel;mount.add_child(collar)
		mount.add_child(muzzle);muzzle.position=Vector3(0,0,-.90)
		muzzle.set_meta("mg_mount_mode","fictional_prototype_coax")
	muzzle.set_meta("weapon_class","mg")
	return muzzle
