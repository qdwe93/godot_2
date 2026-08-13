extends CharacterBody2D

@onready var magnet_area: Area2D = get_node_or_null("MagnetArea") as Area2D
@onready var level_system: Node = get_node_or_null("LevelSystem")

var magnet_setup_reported: bool = false
var level_system_reported: bool = false

signal health_changed(current: float, maximum: float)
signal died()

@export var speed: float = 200.0
@export var body_radius: float = 12.0
@export var max_health: float = 100.0
@export var invincibility_time: float = 0.5
## 초당 체력 회복량.
##
## M12b에서 넣었다. 그 전까지 체력은 **오직 줄기만 했다.** 접촉 피해에 0.5초 무적이
## 걸려 있어 한 번에 죽지는 않지만, 회복 수단이 없으니 생존 시간이
## "총 체력 / 평균 잠식량"으로 못박힌다. 실측에서 적 30마리 언저리를 유지하며
## 초당 0.4씩 깎여 250초에 죽었다 — 화력을 아무리 올려도 이 상한은 안 바뀐다.
##
## 심장(heart) 업그레이드가 레벨당 이 값을 올린다.
@export var health_regen: float = 0.6

var health: float
var is_invincible: bool = false

## 체력이 이 비율 이하로 떨어지면 위험 상태다. HUD의 판정 기준과 같은 값을 쓴다.
const DANGER_HEALTH_RATIO: float = 0.3
const DANGER_BLINK_COLOUR: Color = Color(1.0, 0.25, 0.25)
const DANGER_BLINK_SPEED: float = 6.0

## 그림에 칠해진 기준 색. 스프라이트가 텍스처가 되면서 노드에서 읽을 수 없게 됐으므로
## 여기에 명시한다. docs/ASSETS.md 3-0절 표의 플레이어 색과 같아야 한다.
const BASE_SPRITE_COLOUR: Color = Color(0.55, 0.90, 1.00)

var _sprite: Sprite2D = null
var _danger_overlay: Sprite2D = null
var _base_sprite_colour: Color = BASE_SPRITE_COLOUR
var _danger_blink_time: float = 0.0
var _invincibility_remaining: float = 0.0
var _is_dead: bool = false
var _hurtbox: Area2D


func _ready() -> void:
	if magnet_area == null:
		push_error("Player is missing MagnetArea.")
		magnet_setup_reported = true
	health = max_health
	_hurtbox = get_node_or_null("Hurtbox") as Area2D
	if _hurtbox == null:
		push_error("Player is missing its Hurtbox Area2D.")
	_sprite = get_node_or_null("Sprite") as Sprite2D
	_danger_overlay = get_node_or_null("Danger") as Sprite2D


func _physics_process(delta: float) -> void:
	_poll_magnet_area()
	_update_invincibility(delta)
	if _is_dead:
		return

	_apply_regen(delta)
	_update_danger_blink(delta)

	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * speed
	move_and_slide()
	_clamp_to_screen()
	_poll_contact_damage()


## 체력이 낮으면 주인공이 빨갛게 깜빡인다.
##
## 예전에는 화면 전체를 붉은 비네트로 덮었는데, 실기 테스트 스크린샷을 보니
## **화면이 통째로 빨개져서** 적과 젬이 잘 안 보였다. 위험은 시선이 이미 가 있는
## 주인공에게 표시하는 편이 읽기 쉽고 화면도 덜 가린다.
func _update_danger_blink(delta: float) -> void:
	if _danger_overlay == null or max_health <= 0.0:
		return
	if health / max_health > DANGER_HEALTH_RATIO or _is_dead:
		if _danger_blink_time != 0.0:
			_danger_blink_time = 0.0
			_set_danger_alpha(0.0)
		return

	_danger_blink_time += delta
	# 0..1 사이를 오가는 부드러운 맥동.
	var pulse: float = (sin(_danger_blink_time * DANGER_BLINK_SPEED) + 1.0) * 0.5
	_set_danger_alpha(pulse)


func _set_danger_alpha(alpha: float) -> void:
	if _danger_overlay == null:
		return
	var tint: Color = _danger_overlay.self_modulate
	tint.a = alpha
	_danger_overlay.self_modulate = tint


func get_danger_overlay_alpha() -> float:
	return _danger_overlay.self_modulate.a if _danger_overlay != null else 0.0


func is_low_health() -> bool:
	return max_health > 0.0 and not _is_dead and health / max_health <= DANGER_HEALTH_RATIO


func get_base_sprite_colour() -> Color:
	return _base_sprite_colour


func _apply_regen(delta: float) -> void:
	if health_regen <= 0.0 or health >= max_health:
		return
	var healed: float = minf(health + health_regen * delta, max_health)
	if not is_equal_approx(healed, health):
		health = healed
		health_changed.emit(health, max_health)


func take_damage(amount: float) -> void:
	if _is_dead or is_invincible:
		return

	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	_invincibility_remaining = invincibility_time
	is_invincible = _invincibility_remaining > 0.0

	if health <= 0.0:
		_die()


func advance_invincibility(seconds: float) -> void:
	_invincibility_remaining = maxf(_invincibility_remaining - seconds, 0.0)
	is_invincible = _invincibility_remaining > 0.0


func _update_invincibility(delta: float) -> void:
	if _invincibility_remaining > 0.0:
		_invincibility_remaining = maxf(_invincibility_remaining - delta, 0.0)
	is_invincible = _invincibility_remaining > 0.0


func _clamp_to_screen() -> void:
	# 기준 해상도(1280x720)가 아니라 **실제 뷰포트**를 쓴다. stretch aspect=expand라
	# 화면비가 다른 기기에서는 플레이 영역이 더 넓다 (Arena 참고).
	var arena_size: Vector2 = Arena.get_size(self)
	global_position = Vector2(
		clampf(global_position.x, body_radius, arena_size.x - body_radius),
		clampf(global_position.y, body_radius, arena_size.y - body_radius)
	)


func _poll_contact_damage() -> void:
	if _hurtbox == null:
		return

	for body in _hurtbox.get_overlapping_bodies():
		if "contact_damage" in body:
			var damage: float = body.get("contact_damage")
			take_damage(damage)


func _die() -> void:
	if _is_dead:
		return

	_is_dead = true
	died.emit()
	hide()
	set_physics_process(false)
	if _hurtbox != null:
		_hurtbox.set_deferred("monitoring", false)


func _poll_magnet_area() -> void:
	if magnet_area == null:
		if not magnet_setup_reported:
			push_error("Player is missing MagnetArea.")
			magnet_setup_reported = true
		return
	if get("is_dead") == true:
		return
	for area: Area2D in magnet_area.get_overlapping_areas():
		if area.get("target") == null:
			area.set("target", self)


func add_experience(amount: float) -> void:
	if level_system == null:
		if not level_system_reported:
			push_error("Player is missing LevelSystem.")
			level_system_reported = true
		return
	var experience_amount: float = amount
	var upgrade_manager: Node = get_tree().get_first_node_in_group("upgrade_manager")
	if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("get_experience_multiplier"):
		experience_amount *= float(upgrade_manager.call("get_experience_multiplier"))
	level_system.call("add_experience", experience_amount)
