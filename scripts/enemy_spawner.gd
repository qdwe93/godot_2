extends Node

@export var pickup_spawner_path: NodePath

var pickup_spawner: Node = null


@export var enemy_scene: PackedScene
@export var spawn_interval: float = 1.5
@export var max_enemies: int = 30
@export var spawn_margin: float = 60.0
@export var enemy_container_path: NodePath
@export var target_path: NodePath
@export var use_wave_data: bool = true

## 스폰 반지름의 몇 배까지 벗어나면 적을 회수하는가.
## 1.0 이면 화면 가장자리에서 바로 사라져 눈에 띈다. 넉넉히 잡는다.
const DESPAWN_RADIUS_FACTOR: float = 1.8

var _enemy_container: Node2D = null
var _target: Node2D = null
var _spawn_timer: Timer = null
var _spawning_enabled := false
var _elapsed_seconds: float = 0.0
var _last_announced_phase_index: int = -1


func _ready() -> void:
	if not pickup_spawner_path.is_empty():
		pickup_spawner = get_node_or_null(pickup_spawner_path)
	var container_node := get_node_or_null(enemy_container_path)
	var target_node := get_node_or_null(target_path)
	var configuration_valid := true

	if container_node == null:
		push_error("EnemySpawner: enemy_container_path does not resolve to a node.")
		configuration_valid = false
	elif not container_node is Node2D:
		push_error("EnemySpawner: enemy_container_path must resolve to a Node2D.")
		configuration_valid = false

	if target_node == null:
		push_error("EnemySpawner: target_path does not resolve to a node.")
		configuration_valid = false
	elif not target_node is Node2D:
		push_error("EnemySpawner: target_path must resolve to a Node2D.")
		configuration_valid = false

	if enemy_scene == null:
		push_error("EnemySpawner: enemy_scene is not assigned.")
		configuration_valid = false

	if spawn_interval <= 0.0:
		push_error("EnemySpawner: spawn_interval must be greater than zero.")
		configuration_valid = false

	if not configuration_valid:
		return

	_enemy_container = container_node as Node2D
	_target = target_node as Node2D
	_spawning_enabled = true
	_elapsed_seconds = 0.0

	_spawn_timer = Timer.new()
	_spawn_timer.name = "SpawnTimer"
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.one_shot = false
	_spawn_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)
	_spawn_timer.start()


func _process(delta: float) -> void:
	if _spawning_enabled:
		_elapsed_seconds += delta


func spawn_one() -> Node:
	if not _spawning_enabled:
		return null
	if use_wave_data:
		var phase: Dictionary = _apply_current_wave_phase()
		var weights: Dictionary = phase.get("weights", {})
		return _spawn_enemy(_choose_variant(weights), float(phase.get("health_multiplier", 1.0)), true)
	return _spawn_enemy(&"basic", 1.0, false)


func _spawn_enemy(variant_id: StringName, health_multiplier: float, apply_variant: bool) -> Node:
	if _enemy_container.get_child_count() >= max_enemies:
		return null

	var enemy: Node2D = enemy_scene.instantiate() as Node2D
	if enemy == null:
		push_error("EnemySpawner: enemy_scene root must inherit Node2D.")
		return null
	if apply_variant:
		var enemy_type: Dictionary = WaveData.get_enemy_type(variant_id)
		enemy.set("variant_id", variant_id)
		enemy.set("max_health", float(enemy_type.get("health", 10.0)) * health_multiplier)
		enemy.set("speed", float(enemy_type.get("speed", 60.0)))
		enemy.set("contact_damage", float(enemy_type.get("contact_damage", 5.0)))
		enemy.scale = Vector2.ONE * float(enemy_type.get("scale", 1.0))
		_apply_variant_texture(enemy, enemy_type)

	# 화면 중앙의 **월드 좌표** 기준. 카메라가 주인공을 따라다니므로 get_center()
	# 를 쓰면 주인공이 멀리 가도 적은 계속 월드 원점 근처에서만 태어난다.
	var screen_center: Vector2 = Arena.get_view_center(self)
	var spawn_radius: float = Arena.get_spawn_radius(self, spawn_margin)
	var angle: float = randf() * TAU
	var spawn_offset: Vector2 = Vector2(cos(angle), sin(angle)) * spawn_radius

	enemy.set("target", _target)
	# 세계가 무한해지면서 "뒤에 남겨진 적"이 생긴다. 주인공(200)이 적(40~115)보다
	# 빠르므로 한 방향으로 달리면 뒤쪽 적은 영원히 못 따라온다. 그대로 두면
	# max_enemies 를 시체처럼 차지해 앞쪽 밀도가 오히려 낮아진다.
	enemy.set("despawn_distance", spawn_radius * DESPAWN_RADIUS_FACTOR)
	if pickup_spawner != null and enemy.has_signal("died"):
		var died_signal: Signal = enemy.get("died")
		var gem_value: float = 1.0
		if apply_variant:
			gem_value = float(WaveData.get_enemy_type(variant_id).get("gem_value", 1.0))
		died_signal.connect(Callable(pickup_spawner, "on_enemy_died").bind(gem_value))
	_enemy_container.add_child(enemy)
	enemy.global_position = screen_center + spawn_offset
	enemy.add_to_group("enemies")
	return enemy


## 변종에 맞는 그림을 스프라이트와 번쩍임 오버레이 양쪽에 넣는다.
##
## 예전에는 Polygon2D 의 color / polygon 을 주입했다. 스프라이트로 바꾸면서 그 경로가
## 통째로 사라졌는데, **에러 없이 조용히 죽는 종류의 변경**이라 여기 한곳으로 모았다.
func _apply_variant_texture(enemy: Node, enemy_type: Dictionary) -> void:
	var texture_path: String = str(enemy_type.get("texture", ""))
	if texture_path.is_empty():
		return
	var texture: Texture2D = load(texture_path) as Texture2D
	if texture == null:
		push_error("EnemySpawner: could not load enemy texture '%s'." % texture_path)
		return
	var sprite: Sprite2D = enemy.get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		sprite.texture = texture
	var flash: Sprite2D = enemy.get_node_or_null("Flash") as Sprite2D
	if flash != null:
		flash.texture = texture


func stop() -> void:
	_spawning_enabled = false
	if is_instance_valid(_spawn_timer):
		_spawn_timer.stop()


func _on_spawn_timer_timeout() -> void:
	call_deferred("_run_spawn_tick")


func _run_spawn_tick() -> void:
	if not _spawning_enabled:
		return
	if not use_wave_data:
		spawn_one()
		return
	var phase: Dictionary = _apply_current_wave_phase()
	var weights: Dictionary = phase.get("weights", {})
	var health_multiplier: float = float(phase.get("health_multiplier", 1.0))
	var enemies_per_spawn: int = int(phase.get("enemies_per_spawn", 1))
	for _index in range(enemies_per_spawn):
		if _spawn_enemy(_choose_variant(weights), health_multiplier, true) == null:
			break


func _apply_current_wave_phase() -> Dictionary:
	var phase: Dictionary = WaveData.get_phase_for_time(_elapsed_seconds)
	var phase_index: int = WaveData.get_phase_index_for_time(_elapsed_seconds)
	var phase_interval: float = float(phase.get("spawn_interval", spawn_interval))
	max_enemies = int(phase.get("max_enemies", max_enemies))
	if is_instance_valid(_spawn_timer) and not is_equal_approx(_spawn_timer.wait_time, phase_interval):
		_spawn_timer.wait_time = phase_interval
	if phase_index > _last_announced_phase_index:
		_last_announced_phase_index = phase_index
		print("WAVE_PHASE index=%d time=%.2f interval=%.2f max_enemies=%d per_spawn=%d hp_mult=%.2f" % [phase_index, _elapsed_seconds, phase_interval, max_enemies, int(phase.get("enemies_per_spawn", 1)), float(phase.get("health_multiplier", 1.0))])
	return phase


func _choose_variant(weights: Dictionary) -> StringName:
	var total_weight: int = 0
	for variant_key in weights:
		total_weight += int(weights.get(variant_key, 0))
	if total_weight <= 0:
		return &"basic"
	var roll: int = randi_range(1, total_weight)
	var running_weight: int = 0
	for variant_key in weights:
		running_weight += int(weights.get(variant_key, 0))
		if roll <= running_weight:
			return StringName(variant_key)
	return &"basic"


func get_elapsed_time() -> float:
	return _elapsed_seconds


func get_current_phase_index() -> int:
	return WaveData.get_phase_index_for_time(_elapsed_seconds)


# Test seam: enables deterministic phase selection without waiting in real time.
func set_elapsed_time_for_testing(elapsed_seconds: float) -> void:
	_elapsed_seconds = maxf(elapsed_seconds, 0.0)


# Test seam: executes the normal tick synchronously, outside the physics-timer signal.
func trigger_spawn_tick_for_testing() -> void:
	_run_spawn_tick()
