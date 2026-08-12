class_name UpgradeManager
extends Node

@export var level_up_ui_path: NodePath
@export var player_path: NodePath

var _level_up_ui: Node
var _player: Node
var _weapon: Node
var _magnet_shape: CircleShape2D
var _levels: Dictionary = {}

var _base_speed: float = 0.0
var _base_max_health: float = 0.0
var _base_cooldown: float = 0.0
var _base_magnet_radius: float = 0.0
var _is_disabled: bool = false


func _ready() -> void:
	_level_up_ui = get_node_or_null(level_up_ui_path)
	if _level_up_ui == null:
		_disable_with_error("UpgradeManager: level_up_ui_path does not resolve to a node.")
		return

	_player = get_node_or_null(player_path)
	if _player == null:
		_disable_with_error("UpgradeManager: player_path does not resolve to a node.")
		return

	if not _level_up_ui.has_signal(&"upgrade_chosen"):
		_disable_with_error("UpgradeManager: LevelUpUI is missing the upgrade_chosen signal.")
		return

	_weapon = _player.get_node_or_null("Weapon")
	if _weapon == null:
		_disable_with_error("UpgradeManager: Player is missing its Weapon node.")
		return

	var magnet_collision: CollisionShape2D = _player.get_node_or_null("MagnetArea/CollisionShape2D") as CollisionShape2D
	if magnet_collision == null:
		_disable_with_error("UpgradeManager: Player is missing MagnetArea/CollisionShape2D.")
		return

	var source_shape: CircleShape2D = magnet_collision.shape as CircleShape2D
	if source_shape == null:
		_disable_with_error("UpgradeManager: MagnetArea collision shape is not a CircleShape2D.")
		return

	# The shape resource can be shared by player instances, so give this player
	# a private copy before any upgrade changes its radius.
	var private_shape: CircleShape2D = source_shape.duplicate() as CircleShape2D
	if private_shape == null:
		_disable_with_error("UpgradeManager: failed to duplicate the magnet CircleShape2D.")
		return
	magnet_collision.shape = private_shape
	_magnet_shape = private_shape

	_base_speed = float(_player.get(&"speed"))
	_base_max_health = float(_player.get(&"max_health"))
	_base_cooldown = float(_weapon.get(&"cooldown"))
	_base_magnet_radius = _magnet_shape.radius

	var connection_result: int = _level_up_ui.connect(&"upgrade_chosen", Callable(self, "_on_upgrade_chosen"))
	if connection_result != OK:
		_disable_with_error("UpgradeManager: failed to connect LevelUpUI.upgrade_chosen (error %d)." % connection_result)


func _disable_with_error(message: String) -> void:
	push_error(message)
	_is_disabled = true
	process_mode = Node.PROCESS_MODE_DISABLED


func _on_upgrade_chosen(id: StringName) -> void:
	if _is_disabled:
		return
	if UpgradeData.get_definition(id).is_empty():
		push_error("UpgradeManager: unknown upgrade id '%s'." % id)
		return

	_levels[id] = get_level(id) + 1
	_recompute_stats()

	if id == &"heart":
		var heart_definition: Dictionary = UpgradeData.get_definition(&"heart")
		var heal_amount: float = float(heart_definition.get("flat_amount", 0.0))
		var current_health: float = float(_player.get(&"health"))
		var maximum_health: float = float(_player.get(&"max_health"))
		_player.set(&"health", minf(current_health + heal_amount, maximum_health))

	var report: Dictionary = get_stat_report()
	print("UPGRADE_APPLIED id=%s level=%d speed=%.4f max_health=%.4f cooldown=%.4f magnet_radius=%.4f xp_mult=%.4f" % [id, get_level(id), float(report["speed"]), float(report["max_health"]), float(report["cooldown"]), float(report["magnet_radius"]), float(report["experience_multiplier"])])


func _recompute_stats() -> void:
	var shoes_definition: Dictionary = UpgradeData.get_definition(&"shoes")
	var heart_definition: Dictionary = UpgradeData.get_definition(&"heart")
	var magnet_definition: Dictionary = UpgradeData.get_definition(&"magnet")
	var gloves_definition: Dictionary = UpgradeData.get_definition(&"gloves")

	var shoes_multiplier: float = float(shoes_definition.get("multiplier", 1.0))
	var heart_amount: float = float(heart_definition.get("flat_amount", 0.0))
	var magnet_multiplier: float = float(magnet_definition.get("multiplier", 1.0))
	var gloves_multiplier: float = float(gloves_definition.get("multiplier", 1.0))

	var computed_speed: float = _base_speed * pow(shoes_multiplier, get_level(&"shoes"))
	var computed_max_health: float = _base_max_health + heart_amount * get_level(&"heart")
	var computed_cooldown: float = _base_cooldown * pow(gloves_multiplier, get_level(&"gloves"))
	var computed_magnet_radius: float = _base_magnet_radius * pow(magnet_multiplier, get_level(&"magnet"))

	_player.set(&"speed", computed_speed)
	_player.set(&"max_health", computed_max_health)
	_weapon.set(&"cooldown", computed_cooldown)
	_magnet_shape.radius = computed_magnet_radius

	var cooldown_timer: Timer = _weapon.get_node_or_null("CooldownTimer") as Timer
	if cooldown_timer != null:
		cooldown_timer.wait_time = computed_cooldown


func get_experience_multiplier() -> float:
	var crown_definition: Dictionary = UpgradeData.get_definition(&"crown")
	var crown_multiplier: float = float(crown_definition.get("multiplier", 1.0))
	return pow(crown_multiplier, get_level(&"crown"))


func grant_experience(amount: float) -> void:
	# M6a exposes this integration point, but the existing gem -> player -> level
	# path cannot be rewired without editing player.gd. That wiring is deferred to M6b.
	if _is_disabled:
		return
	var level_system: Node = _player.get_node_or_null("LevelSystem")
	if level_system == null:
		push_error("UpgradeManager: Player is missing its LevelSystem node.")
		return
	level_system.call(&"add_experience", amount * get_experience_multiplier())


func get_level(id: StringName) -> int:
	return int(_levels.get(id, 0))


func get_stat_report() -> Dictionary:
	var speed: float = float(_player.get(&"speed")) if _player != null else 0.0
	var max_health: float = float(_player.get(&"max_health")) if _player != null else 0.0
	var cooldown: float = float(_weapon.get(&"cooldown")) if _weapon != null else 0.0
	var magnet_radius: float = _magnet_shape.radius if _magnet_shape != null else 0.0
	return {
		"speed": speed,
		"max_health": max_health,
		"cooldown": cooldown,
		"magnet_radius": magnet_radius,
		"experience_multiplier": get_experience_multiplier(),
	}
