extends Node


func _ready() -> void:
	var capture_path := ""
	var capture_frames := 30

	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--capture-frames="):
			var frame_value := argument.trim_prefix("--capture-frames=")
			if frame_value.is_valid_int():
				capture_frames = maxi(1, frame_value.to_int())

	if capture_path.is_empty():
		return

	for _frame in range(capture_frames):
		await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var save_error := image.save_png(capture_path)
	if save_error == OK:
		print("CAPTURE_SAVED ", capture_path)
	else:
		print("CAPTURE_FAILED ", save_error, " ", capture_path)

	get_tree().quit()
