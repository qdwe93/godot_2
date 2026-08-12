extends Node
class_name ScreenShake

@export var target_path: NodePath
@export var default_duration: float = 0.15
@export var default_strength: float = 5.0

var _target: Node2D
var _target_origin: Vector2 = Vector2.ZERO
var _duration: float = 0.0
var _strength: float = 0.0
var _elapsed: float = 0.0
var _shaking: bool = false
var _random: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"screen_shake")
	var candidate: Node = get_node_or_null(target_path)
	if candidate == null:
		_disable_with_error("ScreenShake: target_path did not resolve to a Node2D.")
		return

	_target = candidate as Node2D
	if _target == null:
		_disable_with_error("ScreenShake: target_path must point to a Node2D.")
		return

	_target_origin = _target.position
	_random.randomize()


func _physics_process(delta: float) -> void:
	if not _shaking or _target == null:
		return

	_elapsed += delta
	var remaining_ratio: float = clampf(1.0 - (_elapsed / _duration), 0.0, 1.0)
	if remaining_ratio <= 0.0:
		_target.position = _target_origin
		_shaking = false
		return

	var angle: float = _random.randf_range(0.0, TAU)
	var offset: Vector2 = Vector2.from_angle(angle) * (_strength * remaining_ratio)
	_target.position = _target_origin + offset


func shake(duration: float = -1.0, strength: float = -1.0) -> void:
	if _target == null:
		return

	if _shaking:
		_target.position = _target_origin

	_duration = default_duration if duration < 0.0 else duration
	_strength = default_strength if strength < 0.0 else strength
	_elapsed = 0.0
	if _duration <= 0.0 or _strength <= 0.0:
		_target.position = _target_origin
		_shaking = false
		return

	_shaking = true


func is_shaking() -> bool:
	return _shaking


func get_target_origin() -> Vector2:
	return _target_origin


func _disable_with_error(message: String) -> void:
	push_error(message)
	process_mode = Node.PROCESS_MODE_DISABLED

