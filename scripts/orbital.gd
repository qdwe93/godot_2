class_name Orbital
extends Area2D

@export var damage: float = 4.0
@export var orbit_radius: float = 70.0
@export var angular_speed: float = 2.5
@export var hit_interval: float = 0.5

var is_unlocked: bool = false

var _angle: float = 0.0
var _elapsed_time: float = 0.0
var _last_hit_times: Dictionary = {}


func _ready() -> void:

	visible = false
	set_physics_process(false)


func unlock() -> void:

	if is_unlocked:
		return
	is_unlocked = true
	visible = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:

	if not is_unlocked:
		return

	_angle += angular_speed * delta
	position = Vector2(cos(_angle), sin(_angle)) * orbit_radius
	_elapsed_time += delta
	_prune_last_hit_times()

	for body: Node2D in get_overlapping_bodies():
		if not is_instance_valid(body) or body.is_queued_for_deletion():
			continue
		if not body.has_method(&"take_damage"):
			continue
		var enemy_id: int = body.get_instance_id()
		var last_hit_time: float = float(_last_hit_times.get(enemy_id, -hit_interval))
		if _elapsed_time - last_hit_time < hit_interval:
			continue
		body.call(&"take_damage", damage)
		var effect_spawner: Node = get_tree().get_first_node_in_group(&"effect_spawner")
		if effect_spawner != null and effect_spawner.has_method(&"spawn_hit"):
			effect_spawner.call(&"spawn_hit", global_position)
		_last_hit_times[enemy_id] = _elapsed_time


func _prune_last_hit_times() -> void:

	for stored_id: Variant in _last_hit_times.keys():
		var enemy_id: int = int(stored_id)
		if not is_instance_id_valid(enemy_id):
			_last_hit_times.erase(stored_id)
