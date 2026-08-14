extends Node

## 레벨업 화면이 **실제로 어떻게 그려지는지** 눈으로 확인하기 위한 캡처용 진단.
##
## M21에서 색종이 파티클(CPUParticles2D)을 넣었는데, 텍스처 없는 파티클이 정말
## 그려지는지는 유닛 테스트로 알 수 없다. 이 프로젝트는 유닛이 다 통과하는데
## 화면에는 안 나오는 사고를 여러 번 겪었다 (보스 실루엣, 산탄 미노출,
## 반투명 카드). 그리기 경로는 캡처로 따로 확인한다.
##
## `--auto-play`를 **쓰면 안 된다.** GameFlow가 레벨업 화면을 즉시 자동 선택해
## 닫아 버려서 찍을 것이 남지 않는다. 그래서 여기서 직접 게임을 시작한다.
##
## 창 모드로만 의미가 있다:
##   Godot..._console.exe --path <project> res://tests/diag_levelup_capture.tscn \
##       --quit-after 900 -- "--capture=<경로>.png" "--capture-after=2.5"

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _ready() -> void:
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var game_flow: Node = main.get_node_or_null("GameFlow")
	if game_flow == null:
		print("DIAG_ERROR game_flow_missing")
		return
	# auto_play를 켜지 않고 시작한다. 켜면 레벨업이 뜨는 즉시 자동 선택된다.
	game_flow.call(&"start_game")

	var level_system: Node = main.get_node_or_null("Player/LevelSystem")
	if level_system == null:
		print("DIAG_ERROR level_system_missing")
		return
	# 레벨업 화면을 띄운다. 경험치 곡선이 바뀌어도 넉넉하도록 크게 준다.
	level_system.call(&"add_experience", 999.0)
	await get_tree().process_frame

	var level_up_ui: Node = main.get_node_or_null("LevelUpUI")
	if level_up_ui == null:
		print("DIAG_ERROR level_up_ui_missing")
		return

	var confetti: Node = level_up_ui.get_node_or_null("Confetti")
	print("DIAG_LEVELUP visible=%s choices=%s confetti=%s emitting=%s" % [
		str(bool(level_up_ui.get("visible"))).to_lower(),
		str(level_up_ui.call(&"get_choice_ids")),
		str(confetti != null).to_lower(),
		str(confetti != null and bool(confetti.get("emitting"))).to_lower(),
	])
