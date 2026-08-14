extends Area2D


@export var speed: float = 400.0
@export var damage: float = 5.0
@export var lifetime: float = 3.0

var direction: Vector2 = Vector2.RIGHT

var _consumed := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func launch(from_position: Vector2, travel_direction: Vector2) -> void:
	global_position = from_position
	direction = travel_direction.normalized()


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return

	if _consumed:
		return

	global_position += direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if _consumed:
		return
	_consumed = true

	if body.has_method("take_damage"):
		body.call("take_damage", damage)
		var effect_spawner: Node = get_tree().get_first_node_in_group(&"effect_spawner")
		if effect_spawner != null:
			if effect_spawner.has_method(&"spawn_hit"):
				effect_spawner.call(&"spawn_hit", global_position)
			if effect_spawner.has_method(&"spawn_damage_number"):
				effect_spawner.call(&"spawn_damage_number", global_position, damage)
	queue_free()
