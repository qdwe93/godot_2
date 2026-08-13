extends Node

@export var gem_scene: PackedScene
@export var gem_container_path: NodePath

var gem_container: Node = null
var is_configured: bool = false


func _ready() -> void:
	if gem_scene == null:
		push_error("PickupSpawner requires a gem_scene.")
		set_process(false)
		set_physics_process(false)
		return
	if gem_container_path.is_empty():
		push_error("PickupSpawner requires a gem_container_path.")
		set_process(false)
		set_physics_process(false)
		return

	gem_container = get_node_or_null(gem_container_path)
	if gem_container == null:
		push_error("PickupSpawner could not find gem container at %s." % gem_container_path)
		set_process(false)
		set_physics_process(false)
		return
	is_configured = true


func drop_gem(at_position: Vector2, value: float = 1.0) -> Node:
	if not is_configured or gem_scene == null or gem_container == null:
		return null

	var gem: Node = gem_scene.instantiate()
	if not gem is Node2D:
		push_error("PickupSpawner gem_scene must instantiate a Node2D.")
		gem.queue_free()
		return null

	var gem_node: Node2D = gem as Node2D
	gem_container.add_child(gem)
	gem_node.global_position = at_position
	gem_node.set("value", value)
	return gem


func on_enemy_died(enemy_position: Vector2, gem_value: float = 1.0) -> void:
	# 적의 died는 물리 스텝 중(투사체 body_entered)에 발생한다.
	# 그 시점에 충돌 도형을 가진 젬을 트리에 추가하면 물리 서버가 거부하므로 다음 프레임으로 미룬다.
	#
	# gem_value는 시그널이 아니라 **연결하는 쪽에서 bind()로** 실어 보낸다.
	# died의 인자를 늘리면 이 시그널에 붙은 HUD와 보스 스포너까지 전부 고쳐야 하는데,
	# 값을 아는 곳은 적을 만든 스포너뿐이므로 bind가 맞는 도구다.
	drop_gem.call_deferred(enemy_position, gem_value)
