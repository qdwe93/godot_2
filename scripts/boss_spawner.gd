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
@export var boss_color: Color = Color(0.95, 0.45, 0.95)
@export var boss_texture_path: String = "res://assets/sprites/enemy_boss.png"
## 보스는 한 판에 한 마리뿐이므로 잡으면 확실한 보상이 되어야 한다.
@export var boss_gem_value: float = 30.0

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

	# 실제 뷰포트 기준 (Arena 참고). 기준 해상도로 계산하면 넓은 화면에서
	# 보스가 화면 안에 튀어나온다.
	var spawn_radius: float = Arena.get_spawn_radius(self, spawn_margin)
	var spawn_direction: Vector2 = Vector2.from_angle(randf() * TAU)
	boss.global_position = Arena.get_center(self) + spawn_direction * spawn_radius

	# These must be assigned before entering the tree because enemy.gd initializes
	# health from max_health in _ready().
	boss.set("max_health", boss_health)
	boss.set("speed", boss_speed)
	boss.set("contact_damage", boss_contact_damage)
	boss.set("variant_id", &"boss")
	boss.set("target", _target)
	boss.scale = Vector2.ONE * boss_scale
	# 보스는 전용 그림을 쓴다. 예전에는 Polygon2D 에 팔각형 점과 색을 주입했는데,
	# 스프라이트로 바뀌면서 그 경로는 **에러 없이 조용히 죽는다**. 그래서 텍스처가
	# 없으면 push_error 로 알린다.
	var boss_texture: Texture2D = load(boss_texture_path) as Texture2D
	if boss_texture == null:
		push_error("BossSpawner: could not load boss texture '%s'." % boss_texture_path)
	else:
		var sprite: Sprite2D = boss.get_node_or_null("Sprite") as Sprite2D
		if sprite != null:
			sprite.texture = boss_texture
		var flash: Sprite2D = boss.get_node_or_null("Flash") as Sprite2D
		if flash != null:
			flash.texture = boss_texture
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
		boss.connect(&"died", Callable(pickup_spawner, "on_enemy_died").bind(boss_gem_value))
