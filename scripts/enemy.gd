extends CharacterBody2D


@export var speed: float = 60.0
@export var max_health: float = 10.0
@export var contact_damage: float = 5.0

var target: Node2D = null


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(target):
		velocity = Vector2.ZERO
		return

	var direction := (target.global_position - global_position).normalized()
	velocity = direction * speed
	move_and_slide()
