extends Node

const EXPECTED_CASE_COUNT: int = 13
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const PROJECTILE_SCRIPT: Script = preload("res://scripts/projectile.gd")
const DAMAGE_NUMBER_LIFETIME: float = preload("res://scripts/damage_number.gd").LIFETIME

var _main: Node
var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _recorded: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run_suite()


func _run_suite() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	var game_flow: Node = _main.get_node("GameFlow")
	var pause_button: Button = game_flow.get_node("PauseButton") as Button
	# LevelUpUI 는 Control 이 아니라 **CanvasLayer** 다. Control 로 캐스팅하면 조용히
	# null 이 되고, 그 뒤 호출이 전부 "null 값에 메서드 호출" 로 터진다.
	var level_up_ui: CanvasLayer = _main.get_node("LevelUpUI") as CanvasLayer
	var time_label: Label = _main.get_node("HUD/TimeLabel") as Label
	var player: Node2D = _main.get_node("Player") as Node2D
	var health_bar: ProgressBar = player.get_node("HealthBar") as ProgressBar

	await _test_pause_button_hidden_on_title(game_flow, pause_button)
	_test_pause_button_is_tappable(pause_button)
	_test_pause_button_toggles_pause(game_flow)
	_test_pause_is_refused_during_level_up(game_flow, level_up_ui)
	_test_timer_is_centred_and_large(time_label)
	_test_health_bar_starts_full(player, health_bar)
	await _test_health_bar_follows_the_player(player, health_bar)
	await _test_health_bar_reflects_damage(player, health_bar)
	await _test_health_bar_turns_red_in_danger(player, health_bar)
	await _test_damage_number_shows_the_amount()
	await _test_damage_numbers_are_capped()
	await _test_damage_numbers_expire()
	await _test_projectile_hit_makes_a_damage_number()

	get_tree().paused = false
	_main.free()
	_finish_suite()


## 타이틀 위에 일시정지 버튼이 떠 있으면 시작 버튼과 겹쳐 오작동한다.
## 버튼 표시는 _process가 매 프레임 갱신하므로 프레임을 한 번 넘겨야 반영된다.
func _test_pause_button_hidden_on_title(game_flow: Node, pause_button: Button) -> void:
	var title_visible_before: bool = bool(game_flow.call(&"is_title_visible"))
	var button_visible_before: bool = pause_button.visible
	game_flow.call(&"enable_auto_play")
	await get_tree().process_frame
	var button_visible_after: bool = pause_button.visible
	var ok: bool = title_visible_before and not button_visible_before and button_visible_after
	_record_case(
		"pause_button_hidden_on_title",
		ok,
		"title_before=%s button_before=%s button_after=%s"
		% [title_visible_before, button_visible_before, button_visible_after]
	)


## 자식이 STOP이면 그 위를 누른 손가락이 버튼에 닿지 않는다. 화면은 멀쩡해 보이고
## "가끔 안 눌린다"가 된다. 레벨업 카드에서 이미 겪었다. PASS는 부모로 흘려보내므로
## 무해하다. STOP만 걸러야 무해한 설정까지 실패로 만들어 테스트가 방해하지 않는다.
func _test_pause_button_is_tappable(pause_button: Button) -> void:
	var viewport_size: Vector2 = Arena.get_size(_main)
	var top_left: Vector2 = pause_button.global_position
	var bottom_right: Vector2 = top_left + pause_button.size
	var stop_count: int = _count_stopping_control_descendants(pause_button)
	var large_enough: bool = pause_button.size.x >= 88.0 and pause_button.size.y >= 88.0
	var inside_viewport: bool = (
		top_left.x >= 0.0
		and top_left.y >= 0.0
		and bottom_right.x <= viewport_size.x
		and bottom_right.y <= viewport_size.y
	)
	var ok: bool = large_enough and inside_viewport and stop_count == 0
	_record_case(
		"pause_button_is_tappable",
		ok,
		"size=(%.2f,%.2f) top_left=(%.2f,%.2f) bottom_right=(%.2f,%.2f) viewport=(%.2f,%.2f) stop_descendants=%d"
		% [
			pause_button.size.x,
			pause_button.size.y,
			top_left.x,
			top_left.y,
			bottom_right.x,
			bottom_right.y,
			viewport_size.x,
			viewport_size.y,
			stop_count,
		]
	)


## 한 방향만 보면 "못 푸는 일시정지"를 놓친다.
func _test_pause_button_toggles_pause(game_flow: Node) -> void:
	get_tree().paused = false
	game_flow.call(&"close_pause_menu")
	game_flow.call(&"toggle_pause")
	var paused_after_open: bool = get_tree().paused
	var menu_after_open: bool = bool(game_flow.call(&"is_pause_menu_visible"))
	game_flow.call(&"toggle_pause")
	var paused_after_close: bool = get_tree().paused
	var menu_after_close: bool = bool(game_flow.call(&"is_pause_menu_visible"))
	var ok: bool = paused_after_open and menu_after_open and not paused_after_close and not menu_after_close
	_record_case(
		"pause_button_toggles_pause",
		ok,
		"paused_open=%s menu_open=%s paused_close=%s menu_close=%s"
		% [paused_after_open, menu_after_open, paused_after_close, menu_after_close]
	)
	game_flow.call(&"close_pause_menu")
	get_tree().paused = false


## 레벨업은 자기 이유로 이미 일시정지를 걸고 있다. 그 위에서 일시정지 버튼이 또 눌리면
## 3택을 고르는 순간 게임이 멈춘 채로 남는다.
func _test_pause_is_refused_during_level_up(game_flow: Node, level_up_ui: CanvasLayer) -> void:
	game_flow.call(&"close_pause_menu")
	get_tree().paused = false
	level_up_ui.show()
	var can_pause_during_level_up: bool = bool(game_flow.call(&"can_pause"))
	game_flow.call(&"open_pause_menu")
	var menu_visible_after_request: bool = bool(game_flow.call(&"is_pause_menu_visible"))
	var ok: bool = not can_pause_during_level_up and not menu_visible_after_request
	_record_case(
		"pause_is_refused_during_level_up",
		ok,
		"level_up_visible=%s can_pause=%s menu_after_open=%s tree_paused=%s"
		% [level_up_ui.visible, can_pause_during_level_up, menu_visible_after_request, get_tree().paused]
	)
	level_up_ui.hide()
	get_tree().paused = false


## 앵커로 검사해야 한다. 헤드리스 뷰포트는 기준 해상도와 폭이 같아서 왼쪽 고정
## 오프셋과 가운데 정렬이 우연히 같은 자리에 온다. 위치만 재면 실기에서만 드러나는
## 버그를 그대로 통과시킨다. 외곽선은 밝은 적 위에서 숫자가 녹지 않게 하는 장치다.
func _test_timer_is_centred_and_large(time_label: Label) -> void:
	var font_size: int = time_label.get_theme_font_size(&"font_size")
	var outline_size: int = time_label.get_theme_constant(&"outline_size")
	var anchors_centred: bool = (
		is_equal_approx(time_label.anchor_left, 0.5)
		and is_equal_approx(time_label.anchor_right, 0.5)
	)
	var ok: bool = anchors_centred and font_size >= 40 and outline_size > 0
	_record_case(
		"timer_is_centred_and_large",
		ok,
		"anchor_left=%.3f anchor_right=%.3f font_size=%d outline_size=%d"
		% [time_label.anchor_left, time_label.anchor_right, font_size, outline_size]
	)



## 아무 일도 없었을 때 체력바가 **가득 차 있는가.**
##
## Godot 은 자식의 _ready() 를 부모보다 먼저 부른다. 그래서 체력바가 그 자리에서
## player.health 를 읽으면 아직 0.0 이고, 체력이 가득인데 바가 텅 빈 채로 남는다.
## 첫 피해를 입기 전까지는 health_changed 도 발생하지 않으므로 (재생은 만렙에서
## 신호를 쏘지 않는다) 그 상태가 계속 간다. **에러는 하나도 안 난다.**
##
## 피해를 준 뒤를 보는 케이스로는 못 잡는다 — 피해가 신호를 쏘면서 값이 고쳐지기
## 때문이다. 그래서 아무것도 하지 않은 상태를 따로 본다.
func _test_health_bar_starts_full(player: Node2D, health_bar: ProgressBar) -> void:
	var player_health: float = float(player.get(&"health"))
	var player_max: float = float(player.get(&"max_health"))
	var ok: bool = health_bar.max_value > 0.0 		and is_equal_approx(health_bar.value, health_bar.max_value) 		and is_equal_approx(health_bar.value, player_health) 		and is_equal_approx(player_health, player_max)
	_record_case(
		"health_bar_starts_full",
		ok,
		"bar=%.1f/%.1f player=%.1f/%.1f" % [health_bar.value, health_bar.max_value, player_health, player_max]
	)


## 카메라가 들어온 뒤로 세계가 흐른다. 체력바가 주인공의 자식이 아니라 화면에 붙박이면
## 주인공이 움직이는 순간 어긋나는데 에러는 하나도 안 뜬다.
func _test_health_bar_follows_the_player(player: Node2D, health_bar: ProgressBar) -> void:
	var movement: Vector2 = Vector2(500.0, 400.0)
	var player_start: Vector2 = player.global_position
	var bar_start: Vector2 = health_bar.global_position
	player.global_position = player_start + movement
	await get_tree().process_frame
	var player_delta: Vector2 = player.global_position - player_start
	var bar_delta: Vector2 = health_bar.global_position - bar_start
	var error_distance: float = bar_delta.distance_to(movement)
	var ok: bool = error_distance <= 1.0
	_record_case(
		"health_bar_follows_the_player",
		ok,
		"requested=(%.2f,%.2f) player_delta=(%.2f,%.2f) bar_delta=(%.2f,%.2f) error=%.3f"
		% [
			movement.x,
			movement.y,
			player_delta.x,
			player_delta.y,
			bar_delta.x,
			bar_delta.y,
			error_distance,
		]
	)
	player.global_position = player_start
	await get_tree().process_frame


## 재생을 끄지 않으면 표시값이 매 프레임 조금씩 올라가 정확 비교가 깨진다.
func _test_health_bar_reflects_damage(player: Node2D, health_bar: ProgressBar) -> void:
	player.set(&"health_regen", 0.0)
	var maximum: float = float(player.get(&"max_health"))
	var damage_amount: float = maximum * 0.25
	player.call(&"advance_invincibility", 10.0)
	player.call(&"take_damage", damage_amount)
	await get_tree().process_frame
	var bar_value: float = health_bar.value
	var bar_maximum: float = health_bar.max_value
	var player_health: float = float(player.get(&"health"))
	var player_maximum: float = float(player.get(&"max_health"))
	var bar_ratio: float = bar_value / bar_maximum if bar_maximum > 0.0 else -1.0
	var player_ratio: float = player_health / player_maximum if player_maximum > 0.0 else -2.0
	var ratio_error: float = absf(bar_ratio - player_ratio)
	var ok: bool = bar_maximum > 0.0 and player_maximum > 0.0 and ratio_error <= 0.01
	_record_case(
		"health_bar_reflects_damage",
		ok,
		"bar_value=%.3f bar_max=%.3f player_health=%.3f player_max=%.3f ratio_error=%.5f"
		% [bar_value, bar_maximum, player_health, player_maximum, ratio_error]
	)


## 들어가기만 하고 못 나오는 표시는 위험 표시가 아니다.
func _test_health_bar_turns_red_in_danger(player: Node2D, health_bar: ProgressBar) -> void:
	var maximum: float = float(player.get(&"max_health"))
	var current: float = float(player.get(&"health"))
	var danger_target: float = maximum * 0.1
	var damage_amount: float = maxf(current - danger_target, 0.0)
	player.call(&"advance_invincibility", 10.0)
	if damage_amount > 0.0:
		player.call(&"take_damage", damage_amount)
	await get_tree().process_frame
	var health_in_danger: float = float(player.get(&"health"))
	var danger_style_on: bool = bool(health_bar.call(&"is_danger_style"))

	player.set(&"health", maximum)
	player.emit_signal(&"health_changed", maximum, maximum)
	await get_tree().process_frame
	var restored_health: float = float(player.get(&"health"))
	var danger_style_after_restore: bool = bool(health_bar.call(&"is_danger_style"))
	var ok: bool = danger_style_on and not danger_style_after_restore
	_record_case(
		"health_bar_turns_red_in_danger",
		ok,
		"danger_health=%.3f max=%.3f style_in_danger=%s restored_health=%.3f style_restored=%s"
		% [health_in_danger, maximum, danger_style_on, restored_health, danger_style_after_restore]
	)


## 게임 코드가 그룹으로 찾으므로 테스트도 같은 길을 가야 배선이 끊긴 것을 잡는다.
func _test_damage_number_shows_the_amount() -> void:
	var effect_spawner: Node = get_tree().get_first_node_in_group(&"effect_spawner")
	var created: Node = null
	if effect_spawner != null:
		created = effect_spawner.call(&"spawn_damage_number", Vector2(100.0, 100.0), 37.0) as Node
	var in_damage_number_group: bool = created != null and created.is_in_group(&"damage_numbers")
	var amount_text: String = ""
	if created != null:
		amount_text = str(created.call(&"get_amount_text"))
	var ok: bool = effect_spawner != null and created != null and in_damage_number_group and amount_text == "37"
	_record_case(
		"damage_number_shows_the_amount",
		ok,
		"spawner_found=%s created=%s in_group=%s amount_text=%s"
		% [effect_spawner != null, created != null, in_damage_number_group, amount_text]
	)
	if created != null:
		created.queue_free()
		await get_tree().process_frame


## 적이 200마리 넘고 산탄이 7발까지 는다. 상한이 없으면 초당 수백 개의 Label이
## 생겼다 사라지며 프레임이 무너진다.
func _test_damage_numbers_are_capped() -> void:
	var effect_spawner: Node = get_tree().get_first_node_in_group(&"effect_spawner")
	var limit: int = EffectSpawner.MAX_ACTIVE_DAMAGE_NUMBERS
	var created_nodes: Array[Node] = []
	var last_result: Node = null
	if effect_spawner != null:
		for index in range(limit * 3):
			last_result = effect_spawner.call(
				&"spawn_damage_number", Vector2(100.0 + float(index), 100.0), 1.0
			) as Node
			if last_result != null:
				created_nodes.append(last_result)
	var active_count: int = -1
	if effect_spawner != null:
		active_count = int(effect_spawner.call(&"get_active_damage_number_count"))
	var last_was_null: bool = last_result == null
	var ok: bool = effect_spawner != null and active_count <= limit and last_was_null
	_record_case(
		"damage_numbers_are_capped",
		ok,
		"limit=%d attempts=%d created=%d active=%d last_was_null=%s"
		% [limit, limit * 3, created_nodes.size(), active_count, last_was_null]
	)
	for created in created_nodes:
		if is_instance_valid(created):
			created.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## 카운터가 안 줄면 몇 초 만에 상한에 걸려 피해 숫자가 영영 안 뜬다. 그런데 에러는
## 하나도 안 난다. 조용히 기능만 죽는 종류다.
func _test_damage_numbers_expire() -> void:
	var effect_spawner: Node = get_tree().get_first_node_in_group(&"effect_spawner")
	var start_count: int = -1
	var created: Node = null
	if effect_spawner != null:
		start_count = int(effect_spawner.call(&"get_active_damage_number_count"))
		created = effect_spawner.call(&"spawn_damage_number", Vector2(100.0, 100.0), 9.0) as Node
	# 생성 여부는 **기다리기 전에** 붙잡는다. Godot 에서 해제된 Object 참조는
	# `== null` 이 참이 되므로, 수명이 끝난 뒤에 `created != null` 을 물으면
	# "애초에 안 만들어졌다"와 "만들어졌다가 사라졌다"를 구별할 수 없다.
	var was_created: bool = created != null

	var lifetime: float = DAMAGE_NUMBER_LIFETIME
	var waited: float = 0.0
	while waited < lifetime + 0.3 and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()

	var node_gone: bool = not is_instance_valid(created) or not created.is_inside_tree()
	var final_count: int = -1
	if effect_spawner != null:
		final_count = int(effect_spawner.call(&"get_active_damage_number_count"))
	var ok: bool = effect_spawner != null and was_created and node_gone and final_count == start_count
	_record_case(
		"damage_numbers_expire",
		ok,
		"lifetime=%.3f waited=%.3f created=%s node_gone=%s start_count=%d final_count=%d"
		% [lifetime, waited, was_created, node_gone, start_count, final_count]
	)
	if is_instance_valid(created):
		created.queue_free()



## 스포너에 메서드가 **있는 것**과 게임이 **그것을 부르는 것**은 다른 문제다.
##
## 이 프로젝트에서 "정의는 있는데 게임에서 실행되지 않는" 버그가 세 번 나왔고
## 전부 유닛 테스트를 통과했다 (산탄·궤도구 미노출, spawn_hit 호출처 0건,
## 보스 드랍 메서드 이름 불일치). 그래서 여기서는 API 를 직접 부르지 않고
## **실제 투사체가 적에 맞았을 때** 숫자가 뜨는지를 본다.
func _test_projectile_hit_makes_a_damage_number() -> void:
	var effect_spawner: Node = get_tree().get_first_node_in_group(&"effect_spawner")
	var before: int = -1
	if effect_spawner != null:
		before = int(effect_spawner.call(&"get_active_damage_number_count"))

	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
	_main.get_node("EnemyContainer").add_child(enemy)
	var projectile: Area2D = PROJECTILE_SCRIPT.new() as Area2D
	projectile.set(&"damage", 12.0)
	_main.add_child(projectile)
	await get_tree().process_frame

	projectile.call(&"_on_body_entered", enemy)
	var after: int = -1
	if effect_spawner != null:
		after = int(effect_spawner.call(&"get_active_damage_number_count"))

	# 방금 뜬 숫자가 이 투사체의 피해량을 들고 있는가. 개수만 세면 다른 경로에서
	# 우연히 하나 생긴 것과 구별되지 않는다.
	var newest_text: String = ""
	for node in get_tree().get_nodes_in_group(&"damage_numbers"):
		if node.has_method(&"get_amount_text"):
			newest_text = str(node.call(&"get_amount_text"))

	var ok: bool = effect_spawner != null and after == before + 1 and newest_text == "12"
	_record_case(
		"projectile_hit_makes_a_damage_number",
		ok,
		"before=%d after=%d newest_text=%s" % [before, after, newest_text]
	)

	for node in get_tree().get_nodes_in_group(&"damage_numbers"):
		node.queue_free()
	if is_instance_valid(enemy):
		enemy.queue_free()
	if is_instance_valid(projectile):
		projectile.queue_free()
	await get_tree().process_frame


func _count_stopping_control_descendants(node: Node) -> int:
	var count: int = 0
	for child_value in node.get_children():
		var child: Node = child_value as Node
		if child is Control:
			var control: Control = child as Control
			if control.mouse_filter == Control.MOUSE_FILTER_STOP:
				count += 1
		count += _count_stopping_control_descendants(child)
	return count


func _record_case(case_name: String, passed: bool, detail: String) -> void:
	_recorded += 1
	if passed:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])


func _finish_suite() -> void:
	if _recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
		_failed += 1
	var all_passed: bool = _failed == 0 and _passed > 0 and _recorded == EXPECTED_CASE_COUNT
	print(
		"TEST_RESULT %s passed=%d failed=%d skipped=%d"
		% ["PASS" if all_passed else "FAIL", _passed, _failed, _skipped]
	)
	get_tree().quit(0 if all_passed else 1)
