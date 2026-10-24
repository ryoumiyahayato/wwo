extends Node3D
var stage: Node3D
var armor_host: Node
var hero: Node3D
var unit := 0
var terrain_damage: Node
var smoke_root: Node3D
var weather_index := 0
var combat := {"smoke_remaining":0.0}
func _ready():
 stage = self
