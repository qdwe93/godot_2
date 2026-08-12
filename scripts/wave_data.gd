class_name WaveData
extends RefCounted


const PHASES: Array[Dictionary] = [
	{
		"start_time": 0.0,
		"spawn_interval": 1.2,
		"max_enemies": 40,
		"enemies_per_spawn": 1,
		"health_multiplier": 1.0,
		"weights": {&"basic": 1},
	},
	{
		"start_time": 30.0,
		"spawn_interval": 0.8,
		"max_enemies": 60,
		"enemies_per_spawn": 1,
		"health_multiplier": 1.2,
		"weights": {&"basic": 1},
	},
	{
		"start_time": 60.0,
		"spawn_interval": 0.6,
		"max_enemies": 80,
		"enemies_per_spawn": 2,
		"health_multiplier": 1.5,
		"weights": {&"basic": 3, &"fast": 1},
	},
	{
		"start_time": 120.0,
		"spawn_interval": 0.45,
		"max_enemies": 110,
		"enemies_per_spawn": 2,
		"health_multiplier": 2.0,
		"weights": {&"basic": 3, &"fast": 2},
	},
	{
		"start_time": 180.0,
		"spawn_interval": 0.35,
		"max_enemies": 140,
		"enemies_per_spawn": 3,
		"health_multiplier": 2.8,
		"weights": {&"basic": 3, &"fast": 2, &"tank": 1},
	},
	{
		"start_time": 240.0,
		"spawn_interval": 0.3,
		"max_enemies": 160,
		"enemies_per_spawn": 3,
		"health_multiplier": 3.5,
		"weights": {&"basic": 2, &"fast": 2, &"tank": 2},
	},
]

const ENEMY_TYPES: Dictionary = {
	&"basic": {
		"health": 10.0,
		"speed": 60.0,
		"contact_damage": 5.0,
		"color": Color(0.9, 0.25, 0.25),
		"scale": 1.0,
	},
	&"fast": {
		"health": 6.0,
		"speed": 115.0,
		"contact_damage": 4.0,
		"color": Color(1.0, 0.6, 0.15),
		"scale": 0.85,
	},
	&"tank": {
		"health": 40.0,
		"speed": 40.0,
		"contact_damage": 12.0,
		"color": Color(0.6, 0.25, 0.8),
		"scale": 1.4,
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
