extends CharacterBody2D


signal died(enemy_position: Vector2)


@export var speed: float = 60.0
@export var max_health: float = 10.0
@export var contact_damage: float = 5.0

var target: Node2D = null
var health: float
var variant_id: StringName = &"basic"

var _dead := false


func _ready() -> void:
	health = max_health


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(target):
		velocity = Vector2.ZERO
		return

	var direction := (target.global_position - global_position).normalized()
	velocity = direction * speed
	move_and_slide()


func take_damage(amount: float) -> void:
	if _dead:
		return
	health -= amount
	if health <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	remove_from_group("enemies")
	died.emit(global_position)
	queue_free()
