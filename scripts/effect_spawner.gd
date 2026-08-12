extends Node
class_name EffectSpawner

@export var hit_effect_scene: PackedScene
@export var effect_container_path: NodePath
@export var enemy_container_path: NodePath

const HIT_SCALE: float = 0.35
const DEATH_SCALE: float = 0.55
const DEATH_TINT: Color = Color(1.0, 0.62, 0.32, 1.0)

var _effect_container: Node
var _enemy_container: Node
var _is_usable: bool = false


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
