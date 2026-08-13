extends Node


@export var enemy_scene: PackedScene
@export var spawn_time: float = 300.0
@export var enemy_container_path: NodePath
@export var target_path: NodePath
@export var spawn_margin: float = 60.0

@export var boss_health: float = 500.0
@export var boss_speed: float = 50.0
@export var boss_contact_damage: float = 25.0
@export var boss_scale: float = 3.0
@export var boss_color: Color = Color(0.95, 0.35, 0.95)

var _enemy_container: Node
var _target: Node2D
var _elapsed_time: float = 0.0
var _has_spawned: bool = false


func _ready() -> void:
	_enemy_container = get_node_or_null(enemy_container_path)
	if _enemy_container == null:
		push_error("BossSpawner requires a valid enemy_container_path.")
		set_physics_process(false)
		return

	var target_node: Node = get_node_or_null(target_path)
	if target_node == null:
		push_error("BossSpawner requires a valid target_path.")
		set_physics_process(false)
		return
	if not target_node is Node2D:
		push_error("BossSpawner target_path must point to a Node2D.")
		set_physics_process(false)
		return
	_target = target_node

	if enemy_scene == null:
		push_error("BossSpawner requires enemy_scene to be assigned.")
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _has_spawned:
		return
	_elapsed_time += delta
	if _elapsed_time >= spawn_time:
		spawn_boss_now()


func spawn_boss_now() -> Node:
	if _has_spawned or enemy_scene == null or _enemy_container == null or _target == null:
		return null

	var spawned_node: Node = enemy_scene.instantiate()
	if not spawned_node is Node2D:
		push_error("BossSpawner enemy_scene root must inherit Node2D.")
		spawned_node.queue_free()
		return null
	var boss: Node2D = spawned_node

	var viewport_width: float = float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var viewport_height: float = float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var design_screen_size: Vector2 = Vector2(viewport_width, viewport_height)
	var spawn_radius: float = design_screen_size.length() / 2.0 + spawn_margin
	var spawn_direction: Vector2 = Vector2.from_angle(randf() * TAU)
	boss.global_position = design_screen_size / 2.0 + spawn_direction * spawn_radius

	# These must be assigned before entering the tree because enemy.gd initializes
	# health from max_health in _ready().
	boss.set("max_health", boss_health)
	boss.set("speed", boss_speed)
	boss.set("contact_damage", boss_contact_damage)
	boss.set("variant_id", &"boss")
	boss.set("target", _target)
	boss.scale = Vector2.ONE * boss_scale
	var sprite_node: Node = boss.get_node_or_null("Sprite")
	if sprite_node is ColorRect:
		var sprite: ColorRect = sprite_node
		sprite.color = boss_color
	boss.add_to_group(&"enemies")

	_enemy_container.add_child(boss)
	_connect_pickup_spawner(boss)
	_has_spawned = true
	print("BOSS_SPAWNED time=" + str(_elapsed_time) + " health=" + str(boss_health) + " scale=" + str(boss_scale))
	return boss


func get_elapsed_time() -> float:
	return _elapsed_time


func has_spawned() -> bool:
	return _has_spawned


func _connect_pickup_spawner(boss: Node) -> void:
	var pickup_spawner: Node = get_tree().get_first_node_in_group(&"pickup_spawner")
	if pickup_spawner == null or not pickup_spawner.has_method("on_enemy_died"):
		push_error("BossSpawner: no node in group 'pickup_spawner' with on_enemy_died(); the boss will not drop experience.")
		return
	if boss.has_signal(&"died"):
		boss.connect(&"died", Callable(pickup_spawner, "on_enemy_died"))
