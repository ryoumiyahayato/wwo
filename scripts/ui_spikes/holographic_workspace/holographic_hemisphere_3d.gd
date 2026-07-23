extends Node3D

@onready var _surface: MeshInstance3D = $Surface
var _angle: float = 0.0
var _tilt: float = -0.24

func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.0
	sphere.radial_segments = 96
	sphere.rings = 24
	_surface.mesh = sphere
	var shader := load("res://shaders/ui_spikes/holographic_workspace/hemisphere_surface.gdshader") as Shader
	var material := ShaderMaterial.new()
	material.shader = shader
	_surface.material_override = material
	_apply_rotation()

func set_orbit(angle: float, tilt: float) -> void:
	_angle = angle
	_tilt = tilt
	_apply_rotation()

func _apply_rotation() -> void:
	rotation = Vector3(_tilt, _angle, 0.0)
