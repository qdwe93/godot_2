class_name UpgradeData
extends RefCounted

## Central definitions for the passive and weapon upgrades.
## `max_level` is enforced by the M6b level-up choice pool.
const DEFINITIONS: Dictionary = {
	"shoes": {
		"label": "신발 - 이동 속도 +10%",
		"max_level": 5,
		"multiplier": 1.10,
	},
	"heart": {
		"label": "심장 - 최대 HP +20",
		"max_level": 5,
		"flat_amount": 20.0,
	},
	"magnet": {
		"label": "자석 - 수집 범위 +30%",
		"max_level": 3,
		"multiplier": 1.30,
	},
	"gloves": {
		"label": "장갑 - 공격 쿨다운 -8%",
		"max_level": 5,
		"multiplier": 0.92,
	},
	"crown": {
		"label": "왕관 - 경험치 획득 +10%",
		"max_level": 5,
		"multiplier": 1.10,
	},
	"shotgun": {
		"label": "산탄 - 전방 3발 발사",
		"max_level": 1,
	},
	"orbital": {
		"label": "궤도구 - 주위를 도는 구체",
		"max_level": 1,
	},
}


static func get_definition(id: StringName) -> Dictionary:
	var definition: Dictionary = DEFINITIONS.get(String(id), {})
	return definition


static func get_all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in DEFINITIONS.keys():
		ids.append(StringName(key))
	return ids
