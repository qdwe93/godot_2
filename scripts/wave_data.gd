class_name WaveData
extends RefCounted


## 난이도 곡선 (M16 재조정)
##
## 설계 규칙 세 가지. 어기면 M12a에서 실측한 실패가 재발한다.
##
## 1. **`enemies_per_spawn`은 1로 고정한다.** 이 값을 1에서 2로 올리면 그 순간
##    스폰율이 2배가 되는데, `spawn_interval`은 (불변식이자 설계 의도상) 되돌릴 수
##    없어서 그 절벽을 흡수할 방법이 없다. 예전 곡선의 60초 지점이 정확히 이
##    문제였다 — 스폰율이 1.25에서 3.33/초로 한 단계에서 2.7배 뛰었다.
##    밀도는 오직 `spawn_interval`로만 올린다.
## 2. **연속한 두 페이즈의 스폰율 비는 1.5배를 넘지 않는다.** 아래 표는 최대 1.45배다.
## 3. **체력 배율은 플레이어 화력 성장과 나란히 간다.** 화력 상한이 71배
##    (10 -> 710 dps)이므로 체력 배율 9배 + 구성 이동(평균 체력 10 -> 27)으로
##    받는다.
##
## 이 표는 `tools/balance_sim.py`의 `build_phases(14, 900.0, 0.83, 8.0, 9.0)`이
## 생성한 값이다. **손으로 고치지 말고 그 스크립트로 다시 뽑아라.**
##
##     python tools/balance_sim.py --plan m16 --emit-gdscript
##
## M16에서 4.0/5.0 -> 8.0/9.0 으로 올린 이유
## -----------------------------------------
## 카메라가 들어와 세계에 경계가 없어지자 같은 곡선에서 판이 **1.9배** 길어졌다
## (실측 572~886초 -> 1166~1500+초). 도망이 항상 성립하기 때문이다.
##
## 8.0/9.0 은 M12b 에서 한 번 썼다가 "392초, 너무 어렵다"고 되돌린 값이다.
## 경계가 없어진 지금은 그 어려움이 상쇄된다는 것이 이 조정의 가설이고,
## 실측으로 확인한다 (devlog 019).
const PHASES: Array[Dictionary] = [
	{
		"start_time": 0.0,
		"spawn_interval": 1.20,
		"max_enemies": 40,
		"enemies_per_spawn": 1,
		"health_multiplier": 1.00,
		"weights": {&"basic": 1},
	},
	{
		"start_time": 61.0,
		"spawn_interval": 0.83,
		"max_enemies": 60,
		"enemies_per_spawn": 1,
		"health_multiplier": 1.18,
		"weights": {&"basic": 1},
	},
	{
		"start_time": 126.0,
		"spawn_interval": 0.65,
		"max_enemies": 70,
		"enemies_per_spawn": 1,
		"health_multiplier": 1.40,
		"weights": {&"basic": 4, &"fast": 1},
	},
	{
		"start_time": 193.0,
		"spawn_interval": 0.54,
		"max_enemies": 90,
		"enemies_per_spawn": 1,
		"health_multiplier": 1.66,
		"weights": {&"basic": 4, &"fast": 1},
	},
	{
		"start_time": 261.0,
		"spawn_interval": 0.45,
		"max_enemies": 100,
		"enemies_per_spawn": 1,
		"health_multiplier": 1.97,
		"weights": {&"basic": 4, &"fast": 2},
	},
	{
		"start_time": 330.0,
		"spawn_interval": 0.38,
		"max_enemies": 120,
		"enemies_per_spawn": 1,
		"health_multiplier": 2.33,
		"weights": {&"basic": 4, &"fast": 2},
	},
	{
		"start_time": 400.0,
		"spawn_interval": 0.32,
		"max_enemies": 130,
		"enemies_per_spawn": 1,
		"health_multiplier": 2.76,
		"weights": {&"basic": 3, &"fast": 2, &"tank": 1},
	},
	{
		"start_time": 470.0,
		"spawn_interval": 0.28,
		"max_enemies": 150,
		"enemies_per_spawn": 1,
		"health_multiplier": 3.26,
		"weights": {&"basic": 3, &"fast": 2, &"tank": 1},
	},
	{
		"start_time": 541.0,
		"spawn_interval": 0.24,
		"max_enemies": 160,
		"enemies_per_spawn": 1,
		"health_multiplier": 3.87,
		"weights": {&"basic": 3, &"fast": 3, &"tank": 2},
	},
	{
		"start_time": 612.0,
		"spawn_interval": 0.21,
		"max_enemies": 180,
		"enemies_per_spawn": 1,
		"health_multiplier": 4.58,
		"weights": {&"basic": 3, &"fast": 3, &"tank": 2},
	},
	{
		"start_time": 683.0,
		"spawn_interval": 0.18,
		"max_enemies": 190,
		"enemies_per_spawn": 1,
		"health_multiplier": 5.42,
		"weights": {&"basic": 2, &"fast": 3, &"tank": 3},
	},
	{
		"start_time": 755.0,
		"spawn_interval": 0.16,
		"max_enemies": 210,
		"enemies_per_spawn": 1,
		"health_multiplier": 6.42,
		"weights": {&"basic": 2, &"fast": 3, &"tank": 3},
	},
	{
		"start_time": 827.0,
		"spawn_interval": 0.14,
		"max_enemies": 220,
		"enemies_per_spawn": 1,
		"health_multiplier": 7.60,
		"weights": {&"basic": 1, &"fast": 3, &"tank": 4},
	},
	{
		"start_time": 900.0,
		"spawn_interval": 0.12,
		"max_enemies": 240,
		"enemies_per_spawn": 1,
		"health_multiplier": 9.00,
		"weights": {&"basic": 1, &"fast": 3, &"tank": 4},
	},
]


const ENEMY_TYPES: Dictionary = {
	&"basic": {
		"texture": "res://assets/sprites/enemy_basic.png",
		"health": 10.0,
		"gem_value": 1.0,
		"speed": 60.0,
		"contact_damage": 5.0,
		"color": Color(0.9, 0.22, 0.22),
		"scale": 1.0,
		"shape": &"square",
		"outline_width": 0.0,
	},
	&"fast": {
		"texture": "res://assets/sprites/enemy_fast.png",
		"health": 6.0,
		"gem_value": 1.0,
		"speed": 115.0,
		"contact_damage": 4.0,
		"color": Color(0.75, 0.32, 0.06),
		"scale": 0.85,
		"shape": &"triangle",
		"outline_width": 0.0,
	},
	&"tank": {
		"texture": "res://assets/sprites/enemy_tank.png",
		"health": 40.0,
		"gem_value": 3.0,
		"speed": 40.0,
		"contact_damage": 12.0,
		"color": Color(0.72, 0.3, 0.95),
		"scale": 1.4,
		"shape": &"hexagon",
		"outline_width": 3.0,
	},
}


static func get_phase_for_time(elapsed_seconds: float) -> Dictionary:
	var phase_index: int = get_phase_index_for_time(elapsed_seconds)
	var phase: Dictionary = PHASES[phase_index].duplicate(true)
	phase["index"] = phase_index
	return phase


static func get_phase_index_for_time(elapsed_seconds: float) -> int:
	var phase_index: int = 0
	for index in range(PHASES.size()):
		var phase_start: float = float(PHASES[index].get("start_time", 0.0))
		if elapsed_seconds >= phase_start:
			phase_index = index
		else:
			break
	return phase_index


static func get_phase_count() -> int:
	return PHASES.size()


static func get_enemy_type(variant_id: StringName) -> Dictionary:
	var enemy_type: Dictionary = ENEMY_TYPES.get(variant_id, ENEMY_TYPES[&"basic"])
	return enemy_type.duplicate(true)


static func get_shape_points(shape_id: StringName, radius: float) -> PackedVector2Array:
	match shape_id:
		&"square":
			return PackedVector2Array([
				Vector2(-radius, -radius),
				Vector2(radius, -radius),
				Vector2(radius, radius),
				Vector2(-radius, radius),
			])
		&"triangle":
			var half_width: float = radius * sqrt(3.0) * 0.5
			return PackedVector2Array([
				Vector2(0.0, -radius),
				Vector2(half_width, radius * 0.5),
				Vector2(-half_width, radius * 0.5),
			])
		&"hexagon":
			var points: PackedVector2Array = PackedVector2Array()
			for index in range(6):
				var angle: float = -PI * 0.5 + TAU * float(index) / 6.0
				points.append(Vector2(cos(angle), sin(angle)) * radius)
			return points
		&"octagon":
			var octagon_points: PackedVector2Array = PackedVector2Array()
			for octagon_index in range(8):
				var octagon_angle: float = -PI * 0.5 + TAU * float(octagon_index) / 8.0
				octagon_points.append(Vector2(cos(octagon_angle), sin(octagon_angle)) * radius)
			return octagon_points
		_:
			push_error("WaveData: unknown enemy shape id '%s'; using square." % shape_id)
			return get_shape_points(&"square", radius)
