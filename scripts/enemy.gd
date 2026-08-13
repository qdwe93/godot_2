extends CharacterBody2D


signal died(enemy_position: Vector2)


@export var speed: float = 60.0
@export var max_health: float = 10.0
@export var contact_damage: float = 5.0
## 몸 지름(60)보다 조금 큰 값. M16에서 캐릭터가 3배가 되면서 26 으로는 적들이
## 서로 파고들어 한 덩어리로 보였다.
@export var separation_radius: float = 78.0
@export var separation_weight: float = 0.6
@export var separation_update_interval: int = 4
@export var separation_max_neighbours: int = 12
## 목표에서 이만큼 멀어지면 스스로 사라진다. 0 이면 회수하지 않는다 (보스).
##
## 카메라가 들어오면서 세계가 무한해졌다. 주인공이 한 방향으로 달리면 뒤쪽 적은
## 영원히 못 따라오는데, 그대로 두면 적 수 상한만 차지하는 유령이 된다.
## **`died` 를 쏘지 않는다** — 젬도 처치 수도 주지 않는 조용한 회수다.
@export var despawn_distance: float = 0.0

var target: Node2D = null
var health: float
var variant_id: StringName = &"basic"

var _dead := false
var _despawn_check_phase: int = -1
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

	if _should_despawn():
		queue_free()
		return

	var direction: Vector2 = (target.global_position - global_position).normalized()
	if separation_weight != 0.0:
		_update_separation_if_needed()
		var combined_direction: Vector2 = direction + _separation_vector * separation_weight
		if combined_direction.length_squared() > 0.0:
			direction = combined_direction.normalized()
	velocity = direction * speed
	move_and_slide()


## 너무 뒤처졌는가. 매 프레임 잴 필요는 없어 30프레임에 한 번, 인스턴스마다
## 위상을 흩어 한 프레임에 몰리지 않게 한다.
func _should_despawn() -> bool:
	if despawn_distance <= 0.0:
		return false
	if _despawn_check_phase < 0:
		_despawn_check_phase = int(get_instance_id() % 30)
	if Engine.get_physics_frames() % 30 != _despawn_check_phase:
		return false
	return global_position.distance_to(target.global_position) > despawn_distance


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
	# 스프라이트가 텍스처가 되면서 "색을 흰색으로 바꿨다 되돌리기"를 못 쓴다.
	# modulate 는 곱셈이라 색을 더 밝게 만들 수 없기 때문이다.
	# 대신 같은 그림을 흰색으로 칠한 오버레이(Flash)의 알파를 올린다.
	var flash: Sprite2D = get_node_or_null("Flash") as Sprite2D
	if flash == null:
		return
	if not _has_base_sprite_color:
		var sprite: Sprite2D = get_node_or_null("Sprite") as Sprite2D
		if sprite != null:
			_base_sprite_color = sprite.modulate
			_has_base_sprite_color = true
	_hit_flash_remaining = HIT_FLASH_DURATION
	_set_flash_alpha(1.0)


func _update_hit_flash(delta: float) -> void:
	if _hit_flash_remaining <= 0.0:
		return
	_hit_flash_remaining = maxf(_hit_flash_remaining - delta, 0.0)
	if _hit_flash_remaining > 0.0:
		return
	_set_flash_alpha(0.0)


func _set_flash_alpha(alpha: float) -> void:
	var flash: Sprite2D = get_node_or_null("Flash") as Sprite2D
	if flash == null:
		return
	var tint: Color = flash.self_modulate
	tint.a = alpha
	flash.self_modulate = tint


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
