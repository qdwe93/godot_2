extends Node
class_name EffectSpawner

@export var hit_effect_scene: PackedScene
@export var effect_container_path: NodePath
@export var enemy_container_path: NodePath

const HIT_SCALE: float = 0.35
const DEATH_SCALE: float = 0.55
const DEATH_TINT: Color = Color(1.0, 0.62, 0.32, 1.0)
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/damage_number.tscn")
## 동시에 떠 있을 수 있는 피해 숫자 상한.
##
## 적이 200마리 넘게 나오고 산탄이 7발까지 늘어나므로 Label이 초당 수백 개씩
## 생기는 상황에서 프레임이 무너지지 않도록, 읽을 수 없는 초과분은 만들지 않는다.
const MAX_ACTIVE_DAMAGE_NUMBERS: int = 40

var _effect_container: Node
var _enemy_container: Node
var _is_usable: bool = false
var _active_damage_number_count: int = 0


func _ready() -> void:
	add_to_group(&"effect_spawner")
	if hit_effect_scene == null:
		_disable_with_error("EffectSpawner: hit_effect_scene is not assigned.")
		return

	_effect_container = get_node_or_null(effect_container_path)
	if _effect_container == null:
		_disable_with_error("EffectSpawner: effect_container_path did not resolve to a Node.")
		return

	_enemy_container = get_node_or_null(enemy_container_path)
	if _enemy_container == null:
		_disable_with_error("EffectSpawner: enemy_container_path did not resolve to a Node.")
		return

	_is_usable = true
	_enemy_container.child_entered_tree.connect(_on_enemy_entered_tree)
	for child in _enemy_container.get_children():
		_connect_enemy(child)


func spawn_hit(at_position: Vector2) -> Node:
	return _spawn_effect(at_position, Color.WHITE, HIT_SCALE)


func spawn_death(at_position: Vector2, enemy_scale: float) -> Node:
	var scaled_size: float = DEATH_SCALE * maxf(absf(enemy_scale), 0.1)
	return _spawn_effect(at_position, DEATH_TINT, scaled_size)


func spawn_damage_number(at_position: Vector2, amount: float) -> Node:
	if not _is_usable:
		return null
	if _active_damage_number_count >= MAX_ACTIVE_DAMAGE_NUMBERS:
		return null

	var damage_number: Node = DAMAGE_NUMBER_SCENE.instantiate()
	if damage_number == null:
		push_error("EffectSpawner: damage number scene failed to instantiate.")
		return null
	# 잘못된 씬 루트가 연결돼도 런타임 호출 오류가 연쇄적으로 나지 않게 여기서 막는다.
	if not damage_number.has_method(&"configure"):
		push_error("EffectSpawner: damage number scene root has no configure() method.")
		damage_number.queue_free()
		return null

	damage_number.call(&"configure", at_position, amount)
	_active_damage_number_count += 1
	damage_number.connect(
		&"tree_exited",
		Callable(self, &"_on_damage_number_tree_exited"),
		Object.CONNECT_ONE_SHOT
	)
	_effect_container.add_child(damage_number)
	return damage_number


func get_active_damage_number_count() -> int:
	return _active_damage_number_count


func _spawn_effect(at_position: Vector2, colour: Color, size_scale: float) -> Node:
	if not _is_usable:
		return null

	var effect: Node = hit_effect_scene.instantiate()
	if effect == null:
		push_error("EffectSpawner: hit_effect_scene failed to instantiate.")
		return null
	if not effect.has_method(&"configure"):
		push_error("EffectSpawner: hit_effect_scene root has no configure() method.")
		effect.queue_free()
		return null

	effect.call(&"configure", at_position, colour, size_scale)
	# died can be emitted during a physics step. This is safe immediately because
	# HitEffect is a Sprite2D with no collision shape or physics monitoring state.
	_effect_container.add_child(effect)
	return effect


func _on_enemy_entered_tree(enemy: Node) -> void:
	_connect_enemy(enemy)


func _on_damage_number_tree_exited() -> void:
	# 예외적인 트리 정리 순서에서도 테스트용 카운터가 음수가 되지 않게 방어한다.
	_active_damage_number_count = maxi(0, _active_damage_number_count - 1)


func _connect_enemy(enemy: Node) -> void:
	if not enemy.has_signal(&"died"):
		return

	var enemy_scale: float = 1.0
	var enemy_node_2d: Node2D = enemy as Node2D
	if enemy_node_2d != null:
		enemy_scale = enemy_node_2d.scale.x

	var death_callback: Callable = Callable(self, &"spawn_death").bind(enemy_scale)
	if not enemy.is_connected(&"died", death_callback):
		enemy.connect(&"died", death_callback)


func _disable_with_error(message: String) -> void:
	push_error(message)
	_is_usable = false
	process_mode = Node.PROCESS_MODE_DISABLED
