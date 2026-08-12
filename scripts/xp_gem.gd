extends Area2D

@export var value: float = 1.0
@export var attract_speed: float = 320.0
@export var collect_radius: float = 14.0

var target: Node2D = null


func _ready() -> void:
	add_to_group("xp_gems")


func _physics_process(delta: float) -> void:
	if target == null:
		return
	if not is_instance_valid(target):
		target = null
		return

	global_position = global_position.move_toward(target.global_position, attract_speed * delta)
	if global_position.distance_to(target.global_position) < collect_radius:
		if target.has_method("add_experience"):
			target.call("add_experience", value)
		queue_free()
