extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_final_polish.gd"


func _focus_selected_country() -> void:
	super._focus_selected_country()
	_sync_moon_visibility()


func _enter_region() -> void:
	super._enter_region()
	_sync_moon_visibility()


func _enter_selected_world_admin1() -> void:
	super._enter_selected_world_admin1()
	_sync_moon_visibility()


func _go_back() -> void:
	super._go_back()
	_sync_moon_visibility()
