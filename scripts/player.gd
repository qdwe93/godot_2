extends CharacterBody2D


@export var speed: float = 200.0
@export var body_radius: float = 12.0


func _physics_process(_delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * speed
	move_and_slide()

	var viewport_size := get_viewport_rect().size
	global_position = global_position.clamp(
		Vector2(body_radius, body_radius),
		viewport_size - Vector2(body_radius, body_radius)
	)
