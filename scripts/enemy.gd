extends CharacterBody2D


signal died(enemy_position: Vector2)


@export var speed: float = 60.0
@export var max_health: float = 10.0
@export var contact_damage: float = 5.0
@export var separation_radius: float = 26.0
@export var separation_weight: float = 0.6
@export var separation_update_interval: int = 4
@export var separation_max_neighbours: int = 12

var target: Node2D = null
var health: float
var variant_id: StringName = &"basic"

var _dead := false
var _separation_vector: Vector2 = Vector2.ZERO
var _hit_flash_remaining: float = 0.0
var _base_sprite_color: Color = Color.WHITE
var _has_base_sprite_color: bool = false

const HIT_FLASH_DURATION: float = 0.06


func _ready() -> void:
	health = max_health


func _physics_process(delta: float) -> void:
	_update_hit_flash(delta)
	if not is_instance_valid(target):
		velocity = Vector2.ZERO
		return

	var direction: Vector2 = (target.global_position - global_position).normalized()
	if separation_weight != 0.0:
		_update_separation_if_needed()
		var combined_direction: Vector2 = direction + _separation_vector * separation_weight
		if combined_direction.length_squared() > 0.0:
			direction = combined_direction.normalized()
	velocity = direction * speed
	move_and_slide()


func _update_separation_if_needed() -> void:
	if separation_radius <= 0.0 or separation_max_neighbours <= 0:
		_separation_vector = Vector2.ZERO
		return

	var should_update: bool = separation_update_interval <= 1
	if not should_update:
		var physics_frame: int = Engine.get_physics_frames()
		var phase: int = int(get_instance_id() % separation_update_interval)
		should_update = physics_frame % separation_update_interval == phase
	if not should_update:
		return

	var separation_sum: Vector2 = Vector2.ZERO
	var neighbours_found: int = 0
	var radius_squared: float = separation_radius * separation_radius
	var self_id: int = get_instance_id()
	for candidate in get_tree().get_nodes_in_group(&"enemies"):
		if candidate == self or not candidate is Node2D:
			continue
		var neighbour: Node2D = candidate
		if not is_instance_valid(neighbour):
			continue
		var offset: Vector2 = global_position - neighbour.global_position
		var distance_squared: float = offset.length_squared()
		if distance_squared >= radius_squared:
			continue
		if distance_squared > 0.0:
			separation_sum += offset / sqrt(distance_squared)
		else:
			var neighbour_id: int = neighbour.get_instance_id()
			separation_sum += Vector2.LEFT if self_id < neighbour_id else Vector2.RIGHT
		neighbours_found += 1
		if neighbours_found >= separation_max_neighbours:
			break

	if separation_sum.length_squared() > 0.0:
		_separation_vector = separation_sum.normalized()
	else:
		_separation_vector = Vector2.ZERO


func take_damage(amount: float) -> void:
	if _dead:
		return
	health -= amount
	if health <= 0.0:
		_die()
		return
	_start_hit_flash()


func _start_hit_flash() -> void:
	var sprite: Polygon2D = get_node_or_null("Sprite") as Polygon2D
	if sprite == null:
		return
	if not _has_base_sprite_color:
		_base_sprite_color = sprite.color
		_has_base_sprite_color = true
	_hit_flash_remaining = HIT_FLASH_DURATION
	sprite.color = Color.WHITE


func _update_hit_flash(delta: float) -> void:
	if _hit_flash_remaining <= 0.0:
		return
	_hit_flash_remaining = maxf(_hit_flash_remaining - delta, 0.0)
	if _hit_flash_remaining > 0.0:
		return
	var sprite: Polygon2D = get_node_or_null("Sprite") as Polygon2D
	if sprite != null and _has_base_sprite_color:
		sprite.color = _base_sprite_color


func is_hit_flashing() -> bool:
	return _hit_flash_remaining > 0.0


func get_base_sprite_color() -> Color:
	if _has_base_sprite_color:
		return _base_sprite_color
	var sprite: Polygon2D = get_node_or_null("Sprite") as Polygon2D
	if sprite != null:
		return sprite.color
	return Color.WHITE


func _die() -> void:
	_dead = true
	remove_from_group("enemies")
	died.emit(global_position)
	queue_free()
