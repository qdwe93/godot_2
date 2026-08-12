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

var health: float
var is_invincible: bool = false

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


func _physics_process(delta: float) -> void:
	_poll_magnet_area()
	_update_invincibility(delta)
	if _is_dead:
		return

	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * speed
	move_and_slide()
	_clamp_to_screen()
	_poll_contact_damage()


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
	var viewport_width: int = ProjectSettings.get_setting("display/window/size/viewport_width")
	var viewport_height: int = ProjectSettings.get_setting("display/window/size/viewport_height")
	global_position = Vector2(
		clampf(global_position.x, body_radius, float(viewport_width) - body_radius),
		clampf(global_position.y, body_radius, float(viewport_height) - body_radius)
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
