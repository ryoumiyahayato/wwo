extends Node
var test: SceneTree
# Minimal host fixture intentionally has no nearby vehicles.
var main: Node3D
var player_team := "blue"
func infantry_candidates(id: String) -> Array: return test.infantry_candidates(id)
func infantry_visibility(a: String,b: String) -> float: return test.infantry_visibility(a,b)
func infantry_apply_hit(event: Dictionary) -> void: test.infantry_apply_hit(event)
