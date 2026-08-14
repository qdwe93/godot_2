extends Node

## 실기 테스트(갤럭시 S21)에서 나온 두 문제를 고정한다.
##
## 1. **화면 잘림** — `stretch aspect=expand`라서 20:9 기기에서는 뷰포트가 1600x720이
##    되는데, 코드와 씬이 기준 해상도 1280x720을 하드코딩하고 있었다. 그래서
##    오른쪽 320px가 회색으로 남고, 적은 그 위를 돌아다니고, HUD 시계는 화면
##    오른쪽 끝이 아니라 1280 자리에 붙었다.
##    → 기기별 빌드가 아니라 **크기를 한 곳(Arena)에서만 읽으면 되는 문제**였다.
##
## 2. **화면이 계속 흔들림** — M12b에서 체력 재생을 넣으면서 `health_changed`가
##    회복 중에도 매 프레임 발생하게 됐는데, 흔들기 쪽은 피해와 회복을 구분하지
##    않았다. 즉 어지러움의 원인은 피격이 아니라 **회복**이었다.
##
## 두 문제 모두 유닛 테스트를 전부 통과한 상태에서 실기로만 드러났다.

const EXPECTED_CASE_COUNT: int = 7
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _recorded: int = 0
var _main: Node = null


func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	if _main == null:
		print("TEST_ERROR setup_failed main_scene_could_not_instantiate")
		_finish()
		return
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	# GameFlow 는 타이틀 화면에서 트리를 일시정지한다. 그대로 두면 ScreenShake 의
	# _physics_process 가 아예 돌지 않아 "흔들림이 안 끝나는" 것처럼 보인다.
	var game_flow: Node = _main.get_node_or_null("GameFlow")
	if game_flow != null and game_flow.has_method(&"enable_auto_play"):
		game_flow.call(&"enable_auto_play")
	await get_tree().process_frame

	_case_background_covers_viewport()
	_case_hud_follows_screen_width()
	_case_panels_cover_viewport()
	await _case_shake_ignores_healing()
	await _case_shake_has_minimum_interval()
	_case_low_health_shows_on_player()
	_case_level_up_ui_fits_and_is_tappable()

	_main.free()
	_finish()


func _finish() -> void:
	if _recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
		_failed += 1
	var overall: String = "PASS" if _failed == 0 and _passed > 0 and _recorded == EXPECTED_CASE_COUNT else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [overall, _passed, _failed, _skipped])
	get_tree().quit(0 if overall == "PASS" else 1)


## 배경이 뷰포트를 전부 덮는가. 안 덮으면 그 부분이 회색으로 드러난다.
func _case_background_covers_viewport() -> void:
	var background: ColorRect = _main.get_node_or_null("BackgroundLayer/Background") as ColorRect
	if background == null:
		_record("background_covers_viewport", false, "background_missing")
		return
	var arena: Vector2 = Arena.get_size(_main)
	var rect: Rect2 = Rect2(background.global_position, background.size)
	# 배경은 CanvasLayer 안에 있어 흔들리지 않으므로 딱 맞기만 해도 된다.
	var covers: bool = rect.position.x <= 0.0 and rect.position.y <= 0.0 \
		and rect.end.x >= arena.x and rect.end.y >= arena.y
	_record("background_covers_viewport", covers,
		"arena=(%.0f,%.0f) background=(%.0f,%.0f)-(%.0f,%.0f)" % [
			arena.x, arena.y, rect.position.x, rect.position.y, rect.end.x, rect.end.y])


## HUD가 화면 폭을 따라가는가.
##
## 고정 오프셋이면 넓은 화면(S21 은 1600 단위)에서 오른쪽 요소가 가운데에 떠 버린다.
## M18 에서 타이머가 우상단에서 **상단 한가운데**로 옮겨 갔으므로, 요소마다 따라가야
## 하는 기준이 다르다. 셋을 한 자리에서 본다.
func _case_hud_follows_screen_width() -> void:
	var hud: Node = _main.get_node_or_null("HUD")
	if hud == null:
		_record("hud_follows_screen_width", false, "hud_missing")
		return
	var arena: Vector2 = Arena.get_size(_main)
	var offenders: PackedStringArray = []

	# 오른쪽에 붙어 있어야 하는 것들. 화면 오른쪽 끝에서 이 거리 안이면 붙었다고 본다.
	for right_name in ["KillLabel", "ExperienceBar"]:
		var right_control: Control = hud.get_node_or_null(right_name) as Control
		if right_control == null:
			offenders.append("%s(missing)" % right_name)
			continue
		var distance: float = arena.x - (right_control.position.x + right_control.size.x)
		if distance > 60.0:
			offenders.append("%s(%.0fpx)" % [right_name, distance])

	# 타이머는 한가운데다. **앵커로 본다** — 헤드리스 뷰포트는 기준 해상도와 폭이
	# 같아서, 왼쪽 고정 오프셋과 가운데 정렬이 우연히 같은 자리에 온다.
	# 위치만 재면 실기에서만 드러나는 버그를 그대로 통과시킨다 (레벨업 UI 에서 겪었다).
	var time_label: Control = hud.get_node_or_null("TimeLabel") as Control
	if time_label == null:
		offenders.append("TimeLabel(missing)")
	else:
		if not (is_equal_approx(time_label.anchor_left, 0.5) and is_equal_approx(time_label.anchor_right, 0.5)):
			offenders.append("TimeLabel(앵커 %.2f~%.2f)" % [time_label.anchor_left, time_label.anchor_right])
		var centre_x: float = time_label.global_position.x + time_label.size.x * 0.5
		if absf(centre_x - arena.x * 0.5) > 8.0:
			offenders.append("TimeLabel(cx=%.0f)" % centre_x)

	_record("hud_follows_screen_width", offenders.is_empty(),
		"arena_width=%.0f %s" % [arena.x, "ok" if offenders.is_empty() else ",".join(offenders)])


## 타이틀·게임오버 패널이 화면 전체를 덮는가. 안 덮으면 가장자리에 게임이 비친다.
func _case_panels_cover_viewport() -> void:
	var game_flow: Node = _main.get_node_or_null("GameFlow")
	if game_flow == null:
		_record("panels_cover_viewport", false, "game_flow_missing")
		return
	var arena: Vector2 = Arena.get_size(_main)
	var offenders: PackedStringArray = []
	for panel_name in ["TitlePanel", "GameOverPanel"]:
		var panel: Control = game_flow.get_node_or_null(panel_name) as Control
		if panel == null:
			offenders.append("%s(missing)" % panel_name)
			continue
		if panel.size.x < arena.x - 1.0 or panel.size.y < arena.y - 1.0:
			offenders.append("%s(%.0fx%.0f)" % [panel_name, panel.size.x, panel.size.y])
	_record("panels_cover_viewport", offenders.is_empty(),
		"arena=(%.0f,%.0f) %s" % [arena.x, arena.y, "ok" if offenders.is_empty() else ",".join(offenders)])


## 회복으로는 화면이 흔들리면 안 된다. 이게 실기에서 어지러웠던 진짜 원인이다.
func _case_shake_ignores_healing() -> void:
	var shaker: Node = _main.get_node_or_null("ScreenShake")
	var player: Node = _main.get_node_or_null("Player")
	if shaker == null or player == null:
		_record("shake_ignores_healing", false, "shaker_or_player_missing")
		return

	# 먼저 피해를 줘서 흔들림을 한 번 소비하고, 간격 제한도 풀어 준다.
	player.call(&"take_damage", 10.0)
	await get_tree().process_frame
	if shaker.has_method(&"clear_cooldown_for_testing"):
		shaker.call(&"clear_cooldown_for_testing")
	# 흔들림이 끝날 때까지 기다린다.
	for _frame in range(40):
		await get_tree().physics_frame
	if shaker.has_method(&"clear_cooldown_for_testing"):
		shaker.call(&"clear_cooldown_for_testing")
	var shaking_before: bool = bool(shaker.call(&"is_shaking"))

	# 이제 회복만 시킨다 — health_changed 는 발생하지만 흔들리면 안 된다.
	player.set(&"health", float(player.get(&"health")) + 5.0)
	player.emit_signal(&"health_changed", float(player.get(&"health")), float(player.get(&"max_health")))
	await get_tree().process_frame
	var shaking_after: bool = bool(shaker.call(&"is_shaking"))

	_record("shake_ignores_healing", not shaking_before and not shaking_after,
		"before=%s after=%s" % [str(shaking_before).to_lower(), str(shaking_after).to_lower()])


## 피해가 연달아 들어와도 흔들림에는 최소 간격이 있어야 한다.
func _case_shake_has_minimum_interval() -> void:
	var shaker: Node = _main.get_node_or_null("ScreenShake")
	if shaker == null:
		_record("shake_has_minimum_interval", false, "shaker_missing")
		return
	var interval: float = float(shaker.get(&"minimum_interval"))
	shaker.call(&"clear_cooldown_for_testing")
	shaker.call(&"shake")
	var cooldown: float = float(shaker.call(&"get_cooldown_remaining"))
	# 흔들림이 끝난 직후에 다시 요청해도 간격 안이면 거부돼야 한다.
	for _frame in range(30):
		await get_tree().physics_frame
	var settled: bool = not bool(shaker.call(&"is_shaking"))
	shaker.call(&"shake")
	var refused: bool = not bool(shaker.call(&"is_shaking"))

	_record("shake_has_minimum_interval", interval > 0.0 and cooldown > 0.0 and settled and refused,
		"interval=%.2f cooldown_after_shake=%.2f settled=%s refused_within_interval=%s" % [
			interval, cooldown, str(settled).to_lower(), str(refused).to_lower()])


## 체력이 낮으면 주인공이 색으로 알려야 한다.
func _case_low_health_shows_on_player() -> void:
	var player: Node = _main.get_node_or_null("Player")
	if player == null or not player.has_method(&"is_low_health"):
		_record("low_health_shows_on_player", false, "player_or_api_missing")
		return
	if not player.has_method(&"get_danger_overlay_alpha"):
		_record("low_health_shows_on_player", false, "danger_overlay_api_missing")
		return

	var max_health: float = float(player.get(&"max_health"))
	player.set(&"health", max_health * 0.1)

	# M15에서 스프라이트가 텍스처가 되어 색을 직접 못 바꾼다. 같은 그림을 빨간색으로
	# 칠한 Danger 오버레이의 알파를 맥동시키므로, 그 알파가 오르는지를 본다.
	var changed: bool = false
	for _frame in range(40):
		player.call(&"_update_danger_blink", 1.0 / 60.0)
		if float(player.call(&"get_danger_overlay_alpha")) > 0.0:
			changed = true
			break

	var low: bool = bool(player.call(&"is_low_health"))
	_record("low_health_shows_on_player", low and changed,
		"is_low=%s overlay_alpha=%.2f" % [str(low).to_lower(), float(player.call(&"get_danger_overlay_alpha"))])


## 레벨업 화면이 뷰포트를 덮고, 버튼이 손가락으로 누를 만한가.
##
## 실기 2차 테스트에서 나온 지적이다. M14 에서 배경·HUD·타이틀·게임오버를 전부
## 앵커로 바꿨는데 **레벨업 UI 하나만 빠져 있었다.** Dimmer 가 1280 폭으로 고정돼
## 있어 1600 폭 화면에서 오른쪽 320 단위에 게임이 그대로 비쳤다.
##
## 버튼 크기도 같이 잰다. 48 단위는 S21 에서 약 7mm 라 엄지로 누르면 빗나간다.
func _case_level_up_ui_fits_and_is_tappable() -> void:
	var level_up_ui: Node = _main.get_node_or_null("LevelUpUI")
	if level_up_ui == null:
		_record("level_up_ui_fits_and_is_tappable", false, "level_up_ui_missing")
		return

	var arena: Vector2 = Arena.get_size(_main)
	var offenders: PackedStringArray = []

	var dimmer: Control = level_up_ui.get_node_or_null("Dimmer") as Control
	if dimmer == null:
		offenders.append("dimmer(missing)")
	elif dimmer.size.x < arena.x - 1.0 or dimmer.size.y < arena.y - 1.0:
		offenders.append("dimmer(%.0fx%.0f)" % [dimmer.size.x, dimmer.size.y])

	# 위치만 재면 헤드리스에서 놓친다. 헤드리스 뷰포트는 기준 해상도와 폭이 같아
	# **왼쪽 고정 오프셋과 가운데 정렬이 우연히 같은 자리에 온다.** 그래서 실기에서만
	# 드러나는 종류의 버그가 된다 (실제로 고장 주입에서 이 케이스를 통과했다).
	# 넓은 화면에서 왼쪽으로 쏠리는 배치인지를 **앵커 설정으로** 직접 본다.
	for anchored_name in ["Title", "Choices"]:
		var anchored: Control = level_up_ui.get_node_or_null(anchored_name) as Control
		if anchored == null:
			offenders.append("%s(missing)" % anchored_name)
			continue
		if is_zero_approx(anchored.anchor_left) and is_zero_approx(anchored.anchor_right):
			offenders.append("%s(왼쪽고정)" % anchored_name)

	# 손가락 표적 하한. 이보다 작으면 실기에서 "누르기 어렵다"가 된다.
	var minimum_touch_height: float = 90.0
	for index in range(3):
		var button: Control = level_up_ui.get_node_or_null("Choices/Choice%d" % index) as Control
		if button == null:
			offenders.append("choice%d(missing)" % index)
			continue
		if button.size.y < minimum_touch_height:
			offenders.append("choice%d(h=%.0f)" % [index, button.size.y])

	# 가운데 정렬은 카드 낱장이 아니라 **묶음**으로 본다. M17에서 카드 3장을 가로로
	# 늘어놓으면서 가운데 오는 것은 가운데 카드 하나뿐이 됐다. 낱장으로 재면
	# 바깥 두 장이 항상 어긋난 것으로 나온다.
	var choices: Control = level_up_ui.get_node_or_null("Choices") as Control
	if choices == null:
		offenders.append("choices(missing)")
	else:
		var choices_center_x: float = choices.global_position.x + choices.size.x * 0.5
		if absf(choices_center_x - arena.x * 0.5) > 8.0:
			offenders.append("choices(cx=%.0f)" % choices_center_x)

	_record("level_up_ui_fits_and_is_tappable", offenders.is_empty(),
		"arena=(%.0f,%.0f) min_touch=%.0f %s" % [
			arena.x, arena.y, minimum_touch_height,
			"ok" if offenders.is_empty() else ",".join(offenders)])


func _record(case_name: String, ok: bool, detail: String) -> void:
	_recorded += 1
	if ok:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])
