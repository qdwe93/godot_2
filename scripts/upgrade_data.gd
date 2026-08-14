class_name UpgradeData
extends RefCounted

## Central definitions for the passive and weapon upgrades.
## `max_level` is enforced by the M6b level-up choice pool.
const DEFINITIONS: Dictionary = {
	"shoes": {
		"category": &"passive",
		"icon": "res://assets/icons/icon_shoes.png",
		"label": "신발 - 이동 속도 +10%",
		"max_level": 5,
		"multiplier": 1.10,
	},
	"heart": {
		"category": &"passive",
		"icon": "res://assets/icons/icon_heart.png",
		"label": "심장 - 최대 HP +20, 회복 +0.4/초",
		"max_level": 5,
		"flat_amount": 20.0,
		"regen_per_level": 0.4,
	},
	"magnet": {
		"category": &"passive",
		"icon": "res://assets/icons/icon_magnet.png",
		"label": "자석 - 수집 범위 +30%",
		"max_level": 3,
		"multiplier": 1.30,
	},
	"gloves": {
		"category": &"passive",
		"icon": "res://assets/icons/icon_gloves.png",
		"label": "장갑 - 공격 쿨다운 -8%",
		"max_level": 5,
		"multiplier": 0.92,
	},
	# M12b 신설. 이전에는 공격 성장이 gloves(쿨다운) 하나뿐이라 화력 상한이
	# 3.68배에 그쳤다. 적 체력은 16배까지 갔으므로 따라갈 수가 없었다.
	"blade": {
		"category": &"passive",
		"icon": "res://assets/icons/icon_blade.png",
		"label": "칼날 - 공격력 +30%",
		"max_level": 8,
		"multiplier": 1.30,
	},
	"crown": {
		"category": &"passive",
		"icon": "res://assets/icons/icon_crown.png",
		"label": "왕관 - 경험치 획득 +10%",
		"max_level": 5,
		"multiplier": 1.10,
	},
	# M12b: 무기도 레벨로 자란다. 예전에는 max_level = 1이라 한 번 얻으면 끝이었다.
	# 산탄은 레벨마다 탄이 1발 늘어난다 (3 -> 7발).
	"shotgun": {
		"category": &"weapon",
		"icon": "res://assets/icons/icon_shotgun.png",
		"label": "산탄 - 전방 다발 발사",
		"max_level": 5,
		"pellets_per_level": 1,
	},
	# 궤도구는 레벨마다 피해량이 기본값만큼 더해진다 (1배 -> 5배).
	# 구체 개수를 늘리는 편이 보기에는 좋지만, 그러려면 Player 아래에 형제 노드를
	# 동적으로 만들어야 해서 씬 배선이 커진다. 밸런스 효과는 같으므로 피해량으로 간다.
	"orbital": {
		"category": &"weapon",
		"icon": "res://assets/icons/icon_orbital.png",
		"label": "궤도구 - 주위를 도는 구체",
		"max_level": 5,
	},
}


## 분류 값. 레벨업 화면의 보유 슬롯 바가 이 둘로 나뉜다.
const CATEGORY_WEAPON: StringName = &"weapon"
const CATEGORY_PASSIVE: StringName = &"passive"

## `label` 을 이름과 설명으로 가르는 구분자.
##
## 이름과 설명을 따로 저장하지 않는 이유는 하나다 — **두 벌이 되면 갈라진다.**
## 라벨은 전부 "이름 - 설명" 꼴이고, 그 규칙만 지키면 갈라질 곳이 없다.
const LABEL_SEPARATOR: String = " - "


static func get_definition(id: StringName) -> Dictionary:
	var definition: Dictionary = DEFINITIONS.get(String(id), {})
	return definition


static func get_all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in DEFINITIONS.keys():
		ids.append(StringName(key))
	return ids


## 카드 제목에 쓰는 짧은 이름 ("칼날").
static func get_display_name(id: StringName) -> String:
	var label: String = str(get_definition(id).get("label", str(id)))
	var separator_index: int = label.find(LABEL_SEPARATOR)
	if separator_index < 0:
		return label
	return label.substr(0, separator_index)


## 카드 본문에 쓰는 설명 ("공격력 +30%").
static func get_description(id: StringName) -> String:
	var label: String = str(get_definition(id).get("label", str(id)))
	var separator_index: int = label.find(LABEL_SEPARATOR)
	if separator_index < 0:
		return ""
	return label.substr(separator_index + LABEL_SEPARATOR.length())


static func get_max_level(id: StringName) -> int:
	return int(get_definition(id).get("max_level", 0))


static func get_category(id: StringName) -> StringName:
	return StringName(str(get_definition(id).get("category", CATEGORY_PASSIVE)))


## 해당 분류의 id 를 **정의 순서 그대로** 돌려준다.
##
## 슬롯 바가 이 함수로 칸을 만든다. 목록을 UI 쪽에 하드코딩하면 업그레이드를
## 추가했을 때 슬롯이 안 늘어나는데 에러는 안 난다 — 이 프로젝트에서 이미 두 번
## 당한 실수다 (CLAUDE.md "테스트에 목록을 하드코딩하지 말 것").
static func get_ids_in_category(category: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for upgrade_id in get_all_ids():
		if get_category(upgrade_id) == category:
			ids.append(upgrade_id)
	return ids


static func get_icon_path(id: StringName) -> String:
	return str(get_definition(id).get("icon", ""))
