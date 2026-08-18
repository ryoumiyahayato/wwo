extends SceneTree

func _initialize() -> void:
	var paths := [
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd",
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd",
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_release.gd",
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_crisp_runtime.gd",
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_hud_polish.gd",
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_final_polish.gd",
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_crisp_flags_fixed.gd",
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_flags.gd",
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence_ui.gd",
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd",
		"res://scripts/formal/formal_world_application.gd",
	]
	for path: String in paths:
		var resource := load(path)
		print("R43_LOAD %s => %s" % [path, str(resource)])
	quit(0)
