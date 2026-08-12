extends Node2D


func _ready() -> void:
	var actions_ok := true
	for action_name: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		if not InputMap.has_action(action_name) or InputMap.action_get_events(action_name).is_empty():
			actions_ok = false

	var version_string := str(Engine.get_version_info().get("string", "unknown"))
	print("M1_BOOT_OK actions_ok=%s version=%s" % [actions_ok, version_string])
