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
		"label": "심장 - 최대 HP +20, 회복 +0.4/초",
		"max_level": 5,
		"flat_amount": 20.0,
		"regen_per_level": 0.4,
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
	# M12b 신설. 이전에는 공격 성장이 gloves(쿨다운) 하나뿐이라 화력 상한이
	# 3.68배에 그쳤다. 적 체력은 16배까지 갔으므로 따라갈 수가 없었다.
	"blade": {
		"label": "칼날 - 공격력 +30%",
		"max_level": 8,
		"multiplier": 1.30,
	},
	"crown": {
		"label": "왕관 - 경험치 획득 +10%",
		"max_level": 5,
		"multiplier": 1.10,
	},
	# M12b: 무기도 레벨로 자란다. 예전에는 max_level = 1이라 한 번 얻으면 끝이었다.
	# 산탄은 레벨마다 탄이 1발 늘어난다 (3 -> 7발).
	"shotgun": {
		"label": "산탄 - 전방 다발 발사",
		"max_level": 5,
		"pellets_per_level": 1,
	},
	# 궤도구는 레벨마다 피해량이 기본값만큼 더해진다 (1배 -> 5배).
	# 구체 개수를 늘리는 편이 보기에는 좋지만, 그러려면 Player 아래에 형제 노드를
	# 동적으로 만들어야 해서 씬 배선이 커진다. 밸런스 효과는 같으므로 피해량으로 간다.
	"orbital": {
		"label": "궤도구 - 주위를 도는 구체",
		"max_level": 5,
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
