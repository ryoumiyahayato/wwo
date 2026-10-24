extends Node
## Battle-only simulation rate with coherent player render interpolation; restores prior settings.
var main:Node3D
var active:=false
var original_hz:=60
var original_interpolation:=false
var original_mode:=Node.PHYSICS_INTERPOLATION_MODE_INHERIT
var generation:=-1
func setup(owner_main:Node3D):
 main=owner_main;name='BattleSimulationRate';main.add_child(self)
 original_hz=Engine.physics_ticks_per_second
 original_interpolation=get_tree().is_physics_interpolation_enabled()
 original_mode=main.physics_interpolation_mode
 process_priority=-1000
func _process(_delta:float):
 var should_run:bool=is_instance_valid(main) and main.is_battle_active()
 if should_run and not active:
  active=true;Engine.physics_ticks_per_second=30
  main.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
  get_tree().set_physics_interpolation_enabled(true)
 if active and should_run and generation!=main.stage_generation and is_instance_valid(main.hero):
  generation=main.stage_generation
  main.hero.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_ON
  main.hero.reset_physics_interpolation()
 if active and not should_run:restore()
func restore():
 if not active:return
 active=false;generation=-1
 Engine.physics_ticks_per_second=original_hz
 if is_instance_valid(main):
  main.physics_interpolation_mode=original_mode
  if is_instance_valid(main.hero):main.hero.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_INHERIT;main.hero.reset_physics_interpolation()
 get_tree().set_physics_interpolation_enabled(original_interpolation)
func _exit_tree():restore()
