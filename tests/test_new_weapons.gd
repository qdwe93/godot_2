extends Node

const EXPECTED_CASE_COUNT: int = 5
const EPSILON: float = 0.05


class TestLevelUpUI:
	extends Node

	signal upgrade_chosen(id: StringName)


class TestEnemy:
	extends CharacterBody2D

	var health: float = 100.0

	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		add_to_group(&"enemies")

	func configure_collision(radius: float) -> void:
		var collision: CollisionShape2D = CollisionShape2D.new()
		var shape: CircleShape2D = CircleShape2D.new()
		shape.radius = radius
		collision.shape = shape
		add_child(collision)

	func take_damage(amount: float) -> void:
		health -= amount


var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0

var _projectile_container: Node
var _enemy_container: Node
var _player: Node2D
var _manager: UpgradeManager
var _shotgun: Shotgun
var _orbital: Orbital


func _ready() -> void:

	call_deferred("_run")


func _run() -> void:

	await _build_scene()
	if _player == null or _manager == null or _shotgun == null or _orbital == null:
		print("TEST_ERROR setup_failed missing required player, manager, shotgun, or orbital node")
		_finish()
		return

	var enemy: TestEnemy = _make_enemy(Vector2(100.0, 0.0), 12.0)
	var health_before: float = enemy.health
	var locked_projectiles: Array[Node] = _shotgun.try_fire()
	await _advance_physics_frames(3)
	var locked_projectile_count: int = _projectile_container.get_child_count()
	_record(
		"locked_weapons_do_nothing",
		locked_projectiles.is_empty() and locked_projectile_count == 0 and is_equal_approx(enemy.health, health_before),
		"projectiles=%d health=%.2f" % [locked_projectile_count, enemy.health]
	)

	_manager.call(&"_on_upgrade_chosen", &"shotgun")
	var pellets: Array[Node] = _shotgun.try_fire()
	var pellet_count: int = _projectile_container.get_child_count()
	_record(
		"shotgun_fires_exactly_three_pellets",
		pellets.size() == 3 and pellet_count == 3,
		"projectiles=%d" % pellet_count
	)

	var angles: Array[float] = []
	for pellet: Node in pellets:
		var direction: Vector2 = pellet.get_meta(&"shotgun_direction")
		angles.append(rad_to_deg(direction.angle()))
	var fan_is_valid: bool = angles.size() == 3
	if fan_is_valid:
		fan_is_valid = not is_equal_approx(angles[0], angles[1]) and not is_equal_approx(angles[1], angles[2])
		fan_is_valid = fan_is_valid and absf((angles[2] - angles[0]) - _shotgun.spread_degrees) <= EPSILON
	_record(
		"pellets_fan_out",
		fan_is_valid,
		"angles=%.2f,%.2f,%.2f degrees" % [_angle_at(angles, 0), _angle_at(angles, 1), _angle_at(angles, 2)]
	)

	enemy.queue_free()
	await _advance_physics_frames(2)
	_manager.call(&"_on_upgrade_chosen", &"orbital")
	await _advance_physics_frames(2)
	var distance_before: float = _orbital.global_position.distance_to(_player.global_position)
	var orbital_position_before: Vector2 = _orbital.global_position
	_player.global_position += Vector2(80.0, -35.0)
	await _advance_physics_frames(3)
	var distance_after: float = _orbital.global_position.distance_to(_player.global_position)
	var orbital_displacement: float = _orbital.global_position.distance_to(orbital_position_before)
	_record(
		"orbital_follows_player",
		absf(distance_before - _orbital.orbit_radius) <= EPSILON and absf(distance_after - _orbital.orbit_radius) <= EPSILON and orbital_displacement > 0.0,
		"distance_before=%.3f distance_after=%.3f displacement=%.3f" % [distance_before, distance_after, orbital_displacement]
	)

	# Silence every damage source except the orbital. The basic Weapon auto-fires
	# at anything within range and would otherwise add its own damage to the
	# measurement below; clearing existing projectiles is not enough while a
	# producer keeps running.
	var basic_weapon: Node = _player.get_node_or_null("Weapon")
	if basic_weapon != null:
		basic_weapon.queue_free()
	if _shotgun != null:
		_shotgun.queue_free()
	for leftover_projectile: Node in _projectile_container.get_children():
		leftover_projectile.queue_free()
	await _advance_physics_frames(2)
	var leftover_count: int = _projectile_container.get_child_count()

	# A large enemy collider continuously covers the orbit path. This makes the
	# expected per-enemy interval independent of the moment an orbital pass begins.
	var contact_enemy: TestEnemy = _make_enemy(_player.global_position, _orbital.orbit_radius + 30.0)
	# 주인공의 물리를 멈춘다. 이 적은 주인공과 같은 자리에 겹쳐 있어서 move_and_slide
	# 의 겹침 해소가 주인공을 밀어내는데, 그러면 궤도구가 적의 콜라이더 밖으로 나가
	# 타격 창을 하나 놓친다. M16 전에는 `_clamp_to_screen()` 이 매 프레임 주인공을
	# 같은 자리로 되돌려 놓아 이 밀림이 **우연히** 가려져 있었다.
	# 이 케이스가 재는 것은 궤도구의 적별 타격 간격이지 주인공의 이동이 아니다.
	_player.set_physics_process(false)
	await _advance_physics_frames(2)
	contact_enemy.health = 100.0
	_orbital._elapsed_time = 0.0
	_orbital._last_hit_times.clear()
	var contact_health_before: float = contact_enemy.health
	var physics_frames: int = Engine.physics_ticks_per_second + 3
	await _advance_physics_frames(physics_frames)
	var inferred_hits: int = roundi((contact_health_before - contact_enemy.health) / _orbital.damage)
	var expected_hits: int = 3
	_record(
		"orbital_contact_damage_is_per_enemy_rate_limited",
		inferred_hits == expected_hits and leftover_count == 0 and is_equal_approx(contact_enemy.health, contact_health_before - _orbital.damage * float(expected_hits)),
		"health_before=%.2f health_after=%.2f frames=%d hits=%d leftover_projectiles=%d" % [contact_health_before, contact_enemy.health, physics_frames, inferred_hits, leftover_count]
	)

	_finish()


func _build_scene() -> void:

	_projectile_container = Node2D.new()
	_projectile_container.name = &"ProjectileContainer"
	_projectile_container.add_to_group(&"projectile_container")
	add_child(_projectile_container)

	_enemy_container = Node2D.new()
	_enemy_container.name = &"EnemyContainer"
	add_child(_enemy_container)

	var player_scene: PackedScene = preload("res://scenes/player.tscn")
	_player = player_scene.instantiate() as Node2D
	_player.name = &"Player"
	add_child(_player)

	var level_up_ui: TestLevelUpUI = TestLevelUpUI.new()
	level_up_ui.name = &"LevelUpUI"
	add_child(level_up_ui)

	_manager = UpgradeManager.new()
	_manager.name = &"UpgradeManager"
	_manager.level_up_ui_path = NodePath("../LevelUpUI")
	_manager.player_path = NodePath("../Player")
	add_child(_manager)

	await _advance_physics_frames(1)
	_shotgun = _player.get_node_or_null("Shotgun") as Shotgun
	_orbital = _player.get_node_or_null("Orbital") as Orbital


func _make_enemy(enemy_position: Vector2, collision_radius: float) -> TestEnemy:

	var enemy: TestEnemy = TestEnemy.new()
	enemy.configure_collision(collision_radius)
	_enemy_container.add_child(enemy)
	enemy.global_position = enemy_position
	return enemy


func _advance_physics_frames(frame_count: int) -> void:

	for frame_index: int in range(frame_count):
		await get_tree().physics_frame


func _angle_at(angles: Array[float], index: int) -> float:

	if index < angles.size():
		return angles[index]
	return 0.0


func _record(case_name: String, passed: bool, detail: String) -> void:

	if passed:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])


func _finish() -> void:

	var recorded: int = _passed + _failed + _skipped
	if recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, recorded])
		_failed += 1
	var overall_passed: bool = _failed == 0 and _passed > 0 and recorded == EXPECTED_CASE_COUNT
	var status: String = "PASS" if overall_passed else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [status, _passed, _failed, _skipped])
	get_tree().quit(0 if overall_passed else 1)
