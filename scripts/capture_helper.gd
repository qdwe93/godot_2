extends Node


var _frames_rendered := 0


func _ready() -> void:
	var capture_path := ""
	var capture_after := 3.0

	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--capture-after="):
			var seconds_value := argument.trim_prefix("--capture-after=")
			if seconds_value.is_valid_float():
				capture_after = maxf(0.0, seconds_value.to_float())

	if capture_path.is_empty():
		return

	_frames_rendered = 0
	var started_at := Time.get_ticks_msec()
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	await get_tree().create_timer(capture_after).timeout
	RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var elapsed := float(Time.get_ticks_msec() - started_at) / 1000.0
	var save_error := image.save_png(capture_path)
	if save_error == OK:
		print(
			"CAPTURE_SAVED ",
			capture_path,
			" elapsed=%.2fs frames_rendered=%d" % [elapsed, _frames_rendered]
		)
	else:
		print("CAPTURE_FAILED ", save_error, " ", capture_path)

	get_tree().quit()


func _on_frame_post_draw() -> void:
	_frames_rendered += 1
