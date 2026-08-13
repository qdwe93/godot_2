# B팀 — 태호 리뷰

## 1. 총평 (5줄 이내)

이 프로젝트의 다음 병목은 성능이 아니라, 숫자를 바꾸는 순간 테스트와 구현의 전제가 함께 깨지는 구조다.
`scripts/wave_data.gd`는 외부 데이터가 아니라 코드 안의 상수 테이블이며, 현재 `start_time` 역전까지 포함한다.
가장 심각한 사실은 `scripts/level_up_ui.gd`의 `UPGRADE_POOL`에 산탄과 궤도구가 없어 두 무기를 정상 플레이에서 선택할 수 없다는 점이다.
정지 74.0초와 봇 74.7초라는 결과는 이동 회피를 포함한 실전 루프를 아직 자동 검증하지 못한다는 뜻이다.
AI 협업 검증이라는 목적에는 지금이 좋은 전환점이다. 다음 마일스톤은 콘텐츠 추가가 아니라 실패 가능한 밸런스 계약과 재현 가능한 측정 루프를 만드는 일이어야 한다.

## 2. 강점 3가지 — 근거와 함께

### 강점 1. 적 변종의 기본 스폰 경로는 한 곳에 모여 있다

`scripts/enemy_spawner.gd`의 `_spawn_enemy()`는 `WaveData.get_enemy_type()`에서 `health`, `speed`, `contact_damage`, `scale`, `color`를 주입한다.

같은 함수가 `enemy.set("variant_id", variant_id)`와 `enemy.add_to_group("enemies")`까지 수행한다.

따라서 행동이 동일하고 스탯만 다른 적은 씬 복제 없이 추가할 수 있다.

이는 다섯 번째 적의 최소 변경 폭을 작게 만드는 실제 장점이다.

### 강점 2. 업그레이드 재계산은 누적 곱셈 버그를 피한다

`scripts/upgrade_manager.gd`의 `_recompute_stats()`는 `_base_speed`, `_base_max_health`, `_base_cooldown`을 기준으로 다시 계산한다.

신발은 `_base_speed * pow(shoes_multiplier, get_level(&"shoes"))`로 계산된다.

장갑도 기본 쿨다운에서 다시 계산하고, 실행 중인 `CooldownTimer.wait_time`까지 갱신한다.

이 방식은 선택 순서에 따라 수치가 달라지는 흔한 라이브 밸런스 버그를 막는다.

### 강점 3. 현재 부하에 맞춘 분리 로직의 상한은 명시돼 있다

`scripts/enemy.gd`의 `_update_separation_if_needed()`는 `separation_update_interval = 4`와 `separation_max_neighbours = 12`로 비용 상한을 둔다.

인스턴스 ID 위상 분산까지 넣어 모든 적이 같은 물리 프레임에 이웃 탐색하지 않게 했다.

STATUS의 161마리, 최저 144fps 측정은 이 제한이 현 단계 곡선에서 작동했다는 근거다.

단, 이 측정은 75초 사망 곡선의 측정일 뿐 10~15분 목표의 성능 보증은 아니다.

## 3. 치명적 문제 (Critical) — 이걸 안 고치면 게임이 성립하지 않는 것

### C1. 표방한 산탄·궤도구가 레벨업 선택지에 존재하지 않는다

판정: 현재 코드만 놓고 보면 무기 3종 게임이 아니라 기본 총 1종 게임이다.

근거는 `scripts/upgrade_data.gd`와 `scripts/level_up_ui.gd`의 불일치다.

`UpgradeData.DEFINITIONS`에는 `"shotgun"`과 `"orbital"`이 각각 `max_level: 1`로 정의돼 있다.

그러나 `level_up_ui.gd`의 `const UPGRADE_POOL`은 `shoes`, `heart`, `magnet`, `gloves`, `crown` 다섯 패시브만 가진다.

`_get_available_upgrade_ids()`는 바로 그 `UPGRADE_POOL`만 순회한다.

따라서 `_show_next_level_up()`이 어떤 난수를 뽑아도 `shotgun`이나 `orbital`을 `upgrade_chosen`으로 보낼 경로가 없다.

`upgrade_manager.gd`의 `_on_upgrade_chosen()` 안 `if id == &"shotgun"`과 `if id == &"orbital"` 분기는 도달 불가능한 코드다.

`shotgun.gd`의 `unlock()`과 `orbital.gd`의 `unlock()`도 정상 런에서 호출되지 않는다.

이는 75초 밸런스를 논하기 전의 기능 성립 문제다. 무기 폭과 성장 곡선의 실제 입력이 문서와 다르다.

즉시 조치(S): `UPGRADE_POOL`을 데이터에서 얻거나, 최소한 두 무기를 명시적으로 포함해 실제 선택·잠금 해제·중복 방지 통합 테스트를 추가한다.

권장 방향은 `UpgradeData.get_all_ids()`를 그대로 쓰는 것이 아니다.

선택 가능 조건, 카테고리, 가중치, 선행 조건을 정의에 넣고 `UpgradeData.get_offerable_ids(levels)`가 반환하게 해야 한다.

그래야 이후 무기 추가 때 선택 풀과 정의가 갈라지지 않는다.

### C2. 웨이브 데이터의 시간 순서가 깨져 있고, 테스트가 그 버그를 계약으로 고정한다

판정: `scripts/wave_data.gd`의 페이즈 테이블은 현재 유효한 시간축 데이터가 아니다.

`PHASES[4]`는 `start_time: 180.0`이다.

바로 다음 `PHASES[5]`는 `start_time: 120.0`이다.

`WaveData.get_phase_index_for_time()`은 순서대로 순회하고, 처음으로 아직 시작하지 않은 페이즈에서 `break`한다.

경과 180초에는 인덱스 4를 통과한 뒤 인덱스 5의 120초도 통과하므로 최종 인덱스가 5가 된다.

결과적으로 인덱스 4의 `start_time: 180.0`, `spawn_interval: 0.35`, `max_enemies: 140`, `health_multiplier: 2.8`은 선택될 시간이 없다.

인덱스 5의 실질 시작 시간은 선언값 120초가 아니라 앞 페이즈를 넘어선 180초다.

이 문제는 `tests/test_waves.gd`의 `_test_phase_lookup_boundaries()`가 `300.0 -> 5`를 기대하고 있어 잡히지 않는다.

더 나쁘게는 `_test_enemies_per_spawn_grows()`가 180초에 정확히 3마리를 기대한다.

그 기대값은 의도된 180초 페이즈의 3마리가 아니라, 시간 역전으로 덮어쓴 인덱스 5의 3마리다.

테스트가 구현을 지키는 것이 아니라 우연한 테이블 배치를 지키고 있다.

즉시 조치(S): 모든 인접 페이즈에 대해 `start_time[i] > start_time[i - 1]`를 검사하고, 실패한 뒤 테이블을 수정한다.

STATUS가 권장한 0/75/150/240/360/480/600/720/840/960초로 조정하더라도 이 불변식이 먼저 있어야 한다.

### C3. 75초 문제는 단순 수치 조절만으로 닫을 수 없다

판정: 정지 74.0초와 방사형 봇 74.7초의 0.7초 차이는 밸런스 결함이면서 측정 설계 결함이다.

`scripts/enemy.gd`는 매 물리 프레임 목표를 향해 직진하고, 분리 벡터도 결국 플레이어를 향하는 합성 방향에 더해진다.

`scripts/player.gd`는 장애물·안전 지대·돌진 예고·위험 보상 목표 없이 화면 경계 안에서만 이동한다.

`_clamp_to_screen()`은 `ProjectSettings`의 1280×720 경계로 플레이어를 제한한다.

따라서 방사형 도주는 적 무리와 경계가 만드는 포위 상태를 읽지 못하고, 실제 플레이어의 회피 경로도 대표하지 못한다.

봇의 74.7초는 "조작이 0.7초만 유효하다"의 증거이지 "플레이어가 74.7초 생존한다"의 신뢰할 수 있는 기준선은 아니다.

현재 `tests/` 80케이스에는 정지와 입력 봇의 생존 시간 차이, 피격 횟수, 포위 탈출 성공률을 검증하는 테스트가 없다.

목표가 10~15분이라면 75초에서 600~900초로 시간을 늘리기 전에 이동이 주는 생존 이득을 측정 가능한 계약으로 세워야 한다.

즉시 조치(M): 고정 시드·고정 물리 틱의 진단에서 정지/방사형/위협 반대 방향/틈새 탐색 봇을 동시에 돌리고 생존시간, 누적 피격, 평균 근접 적 수를 기록한다.

이 게임은 상용 출시가 목적이 아니라 AI 협업 과정 검증이므로, 여기서 중요한 산출물은 "정답 봇"이 아니라 같은 커밋에서 다시 실패하는 측정기다.

### C4. 보스 사망 보상 연결이 현재 PickupSpawner API와 맞지 않는다

판정: 보스는 사망해도 경험치 젬을 드롭하지 않는다.

`scripts/boss_spawner.gd`의 `_connect_pickup_spawner()`는 그룹 `pickup_spawner`에서 노드를 찾아 `has_method("spawn_pickup")`을 요구한다.

첨부된 `scripts/pickup_spawner.gd`에는 `drop_gem()`과 `on_enemy_died()`만 있고 `spawn_pickup()`은 없다.

그 결과 조건문이 즉시 반환하고 보스의 `died` 시그널은 어떤 드롭 함수에도 연결되지 않는다.

일반 적은 `enemy_spawner.gd`의 `_spawn_enemy()`에서 `Callable(pickup_spawner, "on_enemy_died")`로 연결되므로 둘의 보상 경로가 다르다.

현재 보스는 300초이고 플레이어는 약 75초에 사망하므로 플레이 중 이 결함이 가려진다.

밸런스를 늘려 보스에 도달하는 순간, 가장 큰 이벤트의 처치 보상이 사라진다.

즉시 조치(S): 보스도 `on_enemy_died`에 연결하고, 일반 적/보스의 드롭 계약을 하나의 인터페이스로 통일한다.

## 4. 중요 문제 (Major) — 재미의 상한을 누르고 있는 것

### M1. `wave_data.gd`와 `upgrade_data.gd`는 데이터 주도가 아니라 코드 안의 상수 테이블이다

판정: 둘 다 정의를 모았다는 점에서는 단일 출처지만, 진짜 데이터 주도 구조는 아니다.

`scripts/wave_data.gd`는 `const PHASES`와 `const ENEMY_TYPES`를 GDScript에 직접 선언한다.

`scripts/upgrade_data.gd`도 `const DEFINITIONS`를 GDScript에 직접 선언한다.

수치를 바꾸려면 코드 파일을 편집하고 스크립트를 다시 로드해야 하며, 데이터 유효성 검사와 디자이너용 편집 포맷이 없다.

더구나 `WaveData.get_phase_index_for_time()`은 테이블의 정렬을 신뢰하지만 검사하지 않는다.

`UpgradeData.get_definition()`은 없는 ID에 빈 Dictionary를 돌려주고, 호출자가 각자 오류 처리를 떠안는다.

이 구조는 "데이터를 코드 한 파일에 몰아 둔 하드코딩"이다.

AI 협업에는 특히 불리하다. 모델이 페이즈 숫자 한 줄을 고칠 때 시간 순서, 가중치 키, 최대 레벨, UI 선택 풀의 연관 변경을 추론으로만 기억해야 한다.

권장 조치(M): `data/waves.json`과 `data/upgrades.json` 또는 Godot `Resource` 파일로 분리한다.

JSON을 쓴다면 시작 시 스키마 검증을 수행한다.

웨이브는 시작 시간 엄격 증가, 양수 간격, 양수 상한, 양수 스폰 수, 양수 HP 배율, 비어 있지 않은 가중치가 필수다.

모든 가중치 키는 적 정의에 존재하고 각 가중치는 양수여야 한다.

업그레이드는 고유 ID, 양수 `max_level`, 표기 라벨, 카테고리, 선택 가능 조건을 가져야 한다.

중요한 구분: 외부 파일로 옮기는 것만으로 데이터 주도가 되는 것은 아니다.

로드 실패 시 명확하게 실패하고, 런타임과 테스트가 같은 검증기를 거치며, 헤드리스 배치가 파일 조합을 바꿔 측정할 수 있을 때 튜닝 루프가 된다.

### M2. 무기와 패시브의 레벨 개념은 이미 비대칭이며, 소급 도입 비용은 M이다

판정: 패시브 레벨 시스템을 무기에 그대로 얹을 수 없다.

`upgrade_manager.gd`는 `_levels[id]`를 갖고 있어 ID별 레벨 저장 자체는 공용이다.

하지만 `_recompute_stats()`는 shoes/heart/magnet/gloves 네 패시브와 기본 총·산탄의 쿨다운만 하드코딩해 계산한다.

`shotgun`은 `max_level: 1`이고 `unlock()`만 가진다.

`orbital`도 `max_level: 1`이고 `unlock()`만 가진다.

산탄의 `pellet_count`, `spread_degrees`, `projectile_damage`, `attack_range`는 `shotgun.gd` export로 흩어져 있다.

궤도구의 `damage`, `orbit_radius`, `angular_speed`, `hit_interval`은 `orbital.gd` export로 흩어져 있다.

무기 레벨 2 이상을 도입하면 "레벨 n에서 어느 필드가 어떻게 변하는가"를 현재 정의로 표현할 수 없다.

또한 `UpgradeData.DEFINITIONS`의 라벨은 `"산탄 - 전방 3발 발사"` 한 줄뿐이라 레벨별 효과를 표시할 정보도 없다.

작업량은 M이다.

S가 아닌 이유는 데이터 구조, 적용자, UI, 기존 테스트를 함께 바꿔야 하며 한 파일의 `max_level`만 올리면 무음 회귀가 생기기 때문이다.

최소 리팩터링은 `UpgradeData`에 레벨별 modifier 배열 또는 base+per_level 규칙을 추가하는 것이다.

예를 들어 산탄은 `pellet_count +1`, 피해, 쿨다운 중 어떤 축을 올릴지 명시한다.

궤도구는 피해, 공전 반경, 추가 구체 수 중 하나를 레벨별 명세로 명시한다.

`UpgradeManager`에는 타입별 `apply_upgrade(id, level, target)` 어댑터를 두고, 무기 스크립트는 `apply_level(level, definition)` 같은 명시적 메서드를 제공한다.

UI는 정의에서 현재 레벨과 다음 레벨 효과를 조합해 버튼 텍스트를 만든다.

테스트는 레벨 1 잠금 해제, 레벨 2 수치 반영, 만렙 제외, 선택 순서 독립성을 각각 실패 가능하게 검증해야 한다.

"그거 6개월 뒤에 누가 고칠 수 있어요?"라는 질문에 현재 구조의 답은 `upgrade_manager.gd`를 전부 읽은 사람뿐이다.

### M3. `test_waves.gd`는 수치가 아니라 관계를 검사해야 한다

판정: 현재 `tests/test_waves.gd`는 밸런스 회귀 테스트가 아니라 현 밸런스 스냅샷 테스트다.

`_test_phase_lookup_boundaries()`는 `[0.0, 29.9, 30.0, 59.9, 60.0, 300.0]`와 `[0, 0, 1, 1, 2, 5]`를 하드코딩한다.

시작 시간을 75초로 늦추는 정상 튜닝도 이 테스트를 깨뜨린다.

`_test_enemies_per_spawn_grows()`는 초기 1마리와 180초의 3마리를 고정한다.

`_test_health_multiplier_reaches_enemy()`도 초기 체력 10과 240초를 기준점으로 박아 둔다.

이러한 테스트는 "값을 바꾸면 테스트도 바꾸라"고 요구한다.

그 순간 테스트는 독립 검증자가 아니라 변경을 방해하는 복사본이 된다.

다음은 `_test_phase_lookup_boundaries()`와 세 수치 테스트를 대체할 수 있는 불변식 기반 구체안이다.

```gdscript
func _test_wave_invariants() -> void:
	var valid: bool = WaveData.get_phase_count() > 0
	var previous_start: float = -1.0
	var previous_interval: float = INF
	var previous_cap: int = -1
	var previous_health: float = 0.0
	for index in range(WaveData.get_phase_count()):
		var phase: Dictionary = WaveData.PHASES[index]
		var start: float = float(phase.get("start_time", -1.0))
		var interval: float = float(phase.get("spawn_interval", 0.0))
		var cap: int = int(phase.get("max_enemies", 0))
		var health: float = float(phase.get("health_multiplier", 0.0))
		var weights: Dictionary = phase.get("weights", {})
		valid = valid and start > previous_start
		valid = valid and interval > 0.0 and interval < previous_interval
		valid = valid and cap >= previous_cap and health >= previous_health
		valid = valid and not weights.is_empty()
		valid = valid and WaveData.get_phase_index_for_time(start) == index
		if index > 0:
			valid = valid and WaveData.get_phase_index_for_time(start - 0.001) == index - 1
		for enemy_id: Variant in weights.keys():
			valid = valid and WaveData.ENEMY_TYPES.has(enemy_id)
			valid = valid and int(weights[enemy_id]) > 0
		previous_start = start
		previous_interval = interval
		previous_cap = cap
		previous_health = health
	_record_case("wave_invariants", valid, "phase_count=%d" % WaveData.get_phase_count())
```

이 테스트는 30초, 60초, 300초라는 특정 튜닝 수치를 알지 못한다.

대신 현재 테이블의 180초/120초 역전을 즉시 실패시킨다.

스폰 통합 테스트도 "초기 1, 후기 3" 대신 각 페이즈의 `enemies_per_spawn`만큼 `trigger_spawn_tick_for_testing()`가 생성했는지 비교해야 한다.

체력 테스트도 특정 10 HP가 아니라, 생성된 적의 `health == enemy_type.health * phase.health_multiplier` 관계를 모든 페이즈에서 검사해야 한다.

수정 후에는 의도적으로 `start_time`을 역전시키고, 가중치에 `ghost`를 넣고, 간격을 증가시켜 각각 FAIL하는 고장 주입을 남긴다.

통과 로그만 남기면 안 된다. 실패시킬 수 있다는 기록이 이 프로젝트의 AI 협업 검증물이다.

### M4. 80케이스는 무엇을 못 잡는가

80케이스라는 총수는 품질 지표가 아니다. 현재 케이스 묶음은 단위 함수와 테스트 심을 잘 덮지만, 다음 실패를 못 잡는다.

첫째, `level_up_ui.gd`의 선택 풀에서 산탄·궤도구가 빠진 통합 결함을 못 잡는다.

`tests/test_new_weapons`의 5케이스는 STATUS 설명상 잠금 상태, 3발, 부채꼴, 추종, 적별 피해 제한을 본다.

이는 `unlock()`을 직접 호출해도 통과한다. 레벨업 UI가 실제로 무기를 제시하는지는 보장하지 않는다.

둘째, `wave_data.gd`의 180/120초 역전과 도달 불가능한 페이즈를 못 잡는다.

앞서 본 하드코딩 기대값이 오히려 이 결함과 결탁한다.

셋째, 랜덤 가중치의 분포와 재현성을 못 잡는다.

`enemy_spawner.gd`의 `_choose_variant()`은 전역 `randi_range()`를 사용한다.

테스트는 180초에 10틱, 30마리를 뽑아 타입 스탯만 확인할 뿐, 같은 시드에서 같은 결과인지와 가중치가 실제 선택 확률에 반영되는지는 확인하지 않는다.

넷째, `test_enemy_spawn`의 간헐 실패가 보여 주듯 Timer 위상과 `call_deferred("_run_spawn_tick")` 상호작용을 안정적으로 못 검증한다.

STATUS는 12회 중 1회 실패를 기록했다. 간헐 실패를 재실행으로 덮는 것은 테스트 신뢰도를 낮추는 행위다.

다섯째, 75초 이후의 장기 메모리와 부하를 못 잡는다.

`xp_gem.gd`는 대상이 없으면 영구히 남고, `pickup_spawner.gd`는 적 사망마다 젬을 만든다.

수집하지 않은 젬 수, 프로젝타일 수, 이펙트 수의 상한 또는 10분 후 노드 수를 검사하는 케이스가 없다.

여섯째, 씬 연결 계약을 못 잡는다.

`UpgradeManager`의 자식 노드 경로, 그룹 등록, `BossSpawner`의 잘못된 `spawn_pickup` 메서드명은 개별 스크립트 단위로는 살아 있어도 실제 `main.tscn`에서 실패한다.

일곱째, 재시작 후 상태 잔존을 못 잡는다.

`game_flow.gd`가 `reload_current_scene()` 전에 pause를 해제하는 것은 테스트하지만, 고정된 그룹 참조, Timer, 누적 젬, 이미 연결된 시그널이 재시작 뒤 중복되지 않는 장기 시나리오는 없다.

여덟째, 화면 경계와 카메라 도입의 계약 변화를 못 잡는다.

`player.gd`와 두 스포너가 모두 `ProjectSettings` viewport 크기와 화면 중심을 월드 좌표처럼 사용한다.

카메라를 넣으면 플레이어 경계, 적 스폰 오프스크린 판정, 보스 스폰 위치 모두 동시에 바뀌지만 이를 보호할 테스트가 없다.

### M5. `upgrade_manager.gd`의 경로·그룹 탐색은 씬 변경에 취약하다

판정: 현재 구조는 연결 실패를 `push_error`로 알리기는 하지만, 계약 자체가 문자열과 숨은 그룹에 분산돼 있다.

`_ready()`는 export된 `level_up_ui_path`, `player_path`로 두 핵심 노드를 찾는다.

그 뒤 `_player.get_node_or_null("Weapon")`, `"Shotgun"`, `"Orbital"`, `"MagnetArea/CollisionShape2D"`라는 하드코딩 경로를 다시 사용한다.

`level_up_ui.gd`와 `player.gd`는 반대로 `get_tree().get_first_node_in_group("upgrade_manager")`로 매니저를 찾는다.

`UpgradeManager._ready()`에는 스스로 `upgrade_manager` 그룹에 들어가는 코드가 없다.

즉 그룹 등록은 보이지 않는 `.tscn` 설정에 의존한다.

이름을 `Weapon`에서 `PrimaryWeapon`으로 바꾸거나 플레이어 프리팹 구조를 바꾸면 업그레이드 전체가 비활성화된다.

동시에 매니저가 둘 생기면 `get_first_node_in_group()`의 트리 순서가 규칙이 된다.

`player.gd`의 `add_experience()`는 그룹 매니저가 없으면 왕관 보너스 없이 조용히 진행한다.

`level_up_ui.gd`도 매니저가 없으면 현재 레벨을 0으로 보고 만렙 항목을 계속 제시할 수 있다.

권장 조치(M): 씬 조립부에서 명시적으로 의존성을 주입한다.

예를 들어 `LevelUpUI.configure(upgrade_catalog, upgrade_manager)`와 `Player.set_upgrade_manager(manager)`처럼 참조를 한 번 연결한다.

Godot 노드 경로를 유지해야 한다면, 최소한 `UpgradeManager`가 `_ready()`에서 `add_to_group(&"upgrade_manager")`를 수행하고, 경로 상수는 export NodePath로 올린다.

그리고 누락 시 기능을 조용히 약화하지 말고 개발 빌드에서 게임 시작을 실패시킨다.

### M6. 밸런싱 반복은 코드 수정 없는 배치 루프가 필요하다

판정: 필요하다. 목표 생존 시간이 75초에서 600~900초로 바뀌는 단계에서는 특히 필요하다.

현재는 `wave_data.gd`의 상수를 편집하고 테스트의 하드코딩 기대치를 함께 고치며, 별도 진단 씬을 매번 새로 쓴다고 STATUS가 명시한다.

이 과정은 값 하나를 바꾼 뒤 어느 변경이 생존 시간, 피격 수, 적 체류 수를 바꿨는지 남기기 어렵다.

외부 데이터 파일에 `run_id`, wave 배열, enemy 정의, 무기/업그레이드 정의를 두고, 헤드리스 진단은 파일 경로와 RNG 시드만 인자로 받게 한다.

한 배치는 최소 20 시드에서 정지·방사형·위협 반대·틈새 탐색 정책을 돌린다.

출력은 CSV 또는 JSONL로 `data_version`, `commit` 대신 데이터 해시, seed, 정책명, 생존 시간, 처치, 피격, 최고 동시 적, 젬 잔류 수를 남긴다.

여기서 git 메타데이터가 없어도 데이터 해시만 있으면 AI가 같은 입력을 재현할 수 있다.

합격선은 단일 평균이 아니라 범위로 둔다.

예: 목표 정책이 정지보다 유의미하게 길고, 난이도 곡선이 지정 시간 전 급락하지 않으며, 노드 수가 시간에 따라 무한 증가하지 않는지 확인한다.

정확한 목표 수치 자체는 디자인 결정이므로 여기서 단정하지 않는다.

### M7. 10~15분 곡선에서는 현재 성능 결론을 재검증해야 한다

판정: "풀링 불필요 확정"은 현 161마리/약 75초 측정 범위에서만 유효하다.

`enemy.gd`는 그룹 전체를 순회하되 이웃 12명에서 끊는다. 이는 적당하다.

그러나 `weapon.gd`의 `find_nearest_enemy()`는 매 발사마다 전체 `enemies` 그룹을 순회한다.

`shotgun.gd`의 `_find_nearest_target()`도 같은 순회를 한다.

`orbital.gd`는 매 물리 틱 `get_overlapping_bodies()`와 `_last_hit_times` 정리를 수행한다.

`effect_spawner.gd`는 모든 적의 사망에 새 `HitEffect`를 만들고, `hit_effect.gd`는 프레임마다 갱신한다.

10분까지 생존시 스폰 상한은 `wave_data.gd`에서 220마리, 13분에는 240마리다.

수집되지 않는 젬은 `xp_gem.gd`에서 수명이 없으므로 적 상한 밖에서 계속 축적될 수 있다.

따라서 지금 풀링을 구현하라는 결론은 아니다. 풀링은 안 갚아도 되는 부채다.

대신 10분 자동 측정에서 적·젬·투사체·이펙트 각각의 최고 노드 수와 1% low 프레임 시간을 기록하기 전에는 성능 결론을 확대 적용하면 안 된다.

### M8. 화면 경계는 카메라·사운드·풀링 도입 시 서로 다른 방식으로 무너진다

카메라: `player.gd`의 `_clamp_to_screen()`, `enemy_spawner.gd`의 `_spawn_enemy()`, `boss_spawner.gd`의 `spawn_boss_now()`가 설계 viewport 중심을 월드 중심으로 가정한다.

Camera2D로 플레이어를 따라가면 "화면 밖 원주"가 더 이상 `Vector2(640, 360)` 기준 원주가 아니다.

그 상태에서 적은 플레이어 시야 밖이 아니라 고정 화면 밖에 생성되고, 플레이어는 월드 이동을 못 한다.

사운드: `projectile.gd`의 `_on_body_entered()`, `enemy.gd`의 `_die()`, `player.gd`의 `take_damage()`, `level_up_ui.gd`의 `choose()`에 즉석 재생을 각각 넣으면 중복 AudioStreamPlayer와 음량 폭주가 생긴다.

사운드는 이벤트 버스 또는 단일 `AudioFeedback` 노드로 집계하고, 동시 재생 상한을 둬야 한다.

오브젝트 풀링: `enemy.gd`의 `_die()`와 `projectile.gd`의 수명 종료가 `queue_free()`를 호출하고, `xp_gem.gd`도 수집 즉시 `queue_free()`한다.

풀로 바꾸면 그룹 탈퇴/재가입, `died` 시그널 중복 연결, `_dead`, `_consumed`, `_last_hit_times`, `lifetime`, target 초기화를 모두 reset 계약으로 바꿔야 한다.

그래서 지금 풀링을 미루는 판단은 맞지만, 도입 시 한 줄 교체로 끝난다는 가정은 틀렸다.

## 5. 개선 제안 (Minor)

### N1. 다섯 번째 적 추가의 실제 변경 폭을 먼저 문서화한다

스탯과 색만 다른 다섯 번째 적이라는 현재 아키텍처의 범위에서는 최소 2개 파일이다.

생산 코드에서는 `scripts/wave_data.gd`의 `ENEMY_TYPES`에 정의를 추가하고, 등장시킬 `PHASES[*].weights`를 수정한다.

검증 코드에서는 `tests/test_waves.gd`의 불변식 테스트가 그 ID와 스탯 주입을 검사하도록 수정한다.

`enemy.gd`와 `enemy_spawner.gd`는 현재 일반화돼 있으므로 수정할 필요가 없다.

따라서 다섯 번째 적의 최소 변경은 기존 파일 2개다.

다만 독자 공격, 돌진, 투사체, 소환 행동을 주면 `enemy.gd`의 단일 추적 모델을 깨므로 별도 행동 스크립트·테스트·데이터 스키마까지 늘어나 L이 된다.

### N2. 네 번째 무기 추가의 실제 변경 폭은 최소 6개 파일이다

기존 구현 양식을 따르는 새 자동 무기 하나를 넣으려면 최소한 다음을 건드린다.

1. `scripts/new_weapon.gd`를 새로 만든다.

2. `scenes/player.tscn`에 무기 노드와 필요한 충돌/리소스를 추가한다.

3. `scripts/upgrade_data.gd`에 정의, 최대 레벨, 선택 메타데이터를 추가한다.

4. `scripts/level_up_ui.gd`가 해당 정의를 제시하도록 선택 풀을 바꾼다.

5. `scripts/upgrade_manager.gd`에 참조 획득, 잠금 해제, 레벨 재계산 또는 적용 어댑터를 추가한다.

6. `tests/test_new_weapons.gd`에 잠금·선택·수치·정리 테스트를 추가한다.

이는 새 파일 1개와 기존 파일 5개, 총 최소 6개 파일이다.

독립 PackedScene, 전용 이펙트, 전용 테스트 씬이 필요하면 7~9개로 늘어난다.

현재 `UPGRADE_POOL` 누락을 먼저 해결하지 않으면 이 카운트는 더 커진다. 새 무기는 같은 누락 경로에 다시 빠진다.

따라서 네 번째 무기는 지금 바로 추가하지 말고 M2의 레벨 계약 리팩터링 뒤에 넣는 것이 비용을 한 번만 낸다.

### N3. 매직 넘버를 소유자별로 모은다

STATUS가 지적한 플레이어 반지름 12의 중복은 실제 수정 후보지만 Critical은 아니다.

`player.gd`에는 `@export var body_radius = 12.0`이 있고, 충돌 씬에도 같은 반지름이 있을 가능성이 높다.

충돌 반지름, 시각 크기, 화면 clamp 반지름은 의도가 다르면 같은 숫자여도 별도 이름을 가져야 한다.

의도가 같으면 `PlayerConfig` 또는 player scene의 단일 resource에서 읽게 한다.

작업량은 S이며 아트 교체 전후로 한 번에 처리하면 된다.

### N4. 적 가중치의 난수 소유자를 명시한다

`enemy_spawner.gd`의 `_choose_variant()`은 전역 난수 `randi_range()`를 사용한다.

외부 데이터+헤드리스 배치를 도입할 때 이 전역 난수는 재현성을 흐린다.

Spawner가 `RandomNumberGenerator`를 소유하고 seed를 진단 인자로 받게 한다.

테스트는 동일 seed가 동일 variant ID 순열을 주는지, 모든 양수 가중치가 충분한 표본에서 한 번 이상 관측되는지를 분리해 검사한다.

확률의 정확한 비율 비교는 표본 설계가 필요하므로, 첫 단계에서는 결정론 계약만 잡아도 된다.

### N5. 유휴 젬의 수명 또는 회수 정책을 넣는다

`xp_gem.gd`는 `target == null`이면 아무 처리도 하지 않는다.

플레이어가 멀어졌거나 사망한 뒤에도 젬은 남는다.

`game_flow.gd`의 재시작은 씬을 통째로 다시 로드하므로 판 종료에는 해제되지만, 긴 생존 중에는 누적된다.

젬에 20~30초 수명, 최대 잔류 수, 또는 화면 밖 회수 중 하나를 데이터 정책으로 둔다.

어떤 정책을 택해도 그 손실이 경험치 경제를 바꾸므로 배치 지표에 젬 잔류·소멸 수를 함께 남긴다.

### N6. 레벨업 선택의 카테고리·중복 규칙을 정의한다

현재 `_show_next_level_up()`은 무작위 3택이며, `available.pop_at()`으로 한 화면의 중복만 막는다.

무기가 풀에 들어오면 패시브 다섯 개와 무기 세 개가 같은 확률로 경쟁하는지, 미보유 무기를 언제 우선할지 정의가 필요하다.

이 규칙을 정의하지 않으면 산탄/궤도구를 고친 뒤에도 플레이마다 무기 획득 타이밍 분산이 커져 밸런스 측정이 흔들린다.

`UpgradeData`에 `category`, `offer_weight`, `requires_unlocked` 같은 명시적 필드를 두는 편이 낫다.

### N7. UI·게임플로우의 이벤트 순서를 단일 시나리오 테스트로 묶는다

`level_system.gd`의 `add_experience()`는 한 번의 젬으로 여러 `leveled_up`를 emit할 수 있다.

`level_up_ui.gd`는 `_pending_levels`로 이를 처리한다.

`game_flow.gd`의 auto-play는 `_process()`에서 첫 선택을 누른다.

이 세 시스템을 따로 보는 현재 단위 테스트에 더해, 자동 선택 10회 후 무기와 패시브가 정상 적용되고 게임이 pause 상태에 남지 않는 시나리오가 필요하다.

### N8. 히트 이펙트의 연결 상태를 명시한다

`effect_spawner.gd`에는 `spawn_hit()`이 있지만 첨부된 `projectile.gd`의 `_on_body_entered()`는 적에게 피해만 주고 이를 호출하지 않는다.

사망 이펙트는 `_connect_enemy()`가 `died`에 연결하므로 작동 경로가 있다.

피격 이펙트도 의도했다면 적의 `take_damage()` 또는 투사체 명중 이벤트를 통해 한 번만 발행하도록 연결한다.

그렇지 않다면 쓰이지 않는 `spawn_hit()` API를 제거해 "작동한다고 믿는" 표면적을 줄인다.

## 지금 갚아야 할 기술 부채

- `level_up_ui.gd` 선택 풀과 `upgrade_data.gd` 정의의 불일치. C1이며 작업량 S.

- `wave_data.gd`의 비단조 `start_time`과 `test_waves.gd`의 숫자 하드코딩. C2이며 작업량 S.

- `boss_spawner.gd`의 `spawn_pickup`/`pickup_spawner.gd` API 불일치. C4이며 작업량 S.

- 업그레이드 레벨 계약의 패시브·무기 비대칭. 다음 무기 또는 무기 레벨 전에 M으로 갚는다.

- 그룹/문자열 경로에 숨은 업그레이드 의존성. 튜닝 루프와 함께 M으로 갚는다.

- 시드 고정과 장기 헤드리스 측정 부재. 75초를 10~15분으로 조정하기 전에 M으로 갚는다.

- 젬 잔류 수명·계측 부재. 장기 생존 측정 전에 S 또는 M으로 갚는다.

## 지금 안 갚아도 되는 기술 부채

- 오브젝트 풀링. 161마리/144fps 측정이 있고, 풀 도입은 reset·시그널 계약을 넓게 바꾼다. 10분 노드 계측 전에는 보류한다.

- Camera2D. `player.gd`, `enemy_spawner.gd`, `boss_spawner.gd`의 좌표 가정을 전부 바꾸므로, 이동 목표가 없는 현재는 보류한다.

- 플레이어 반지름 12 중복. 아트/히트박스 조정 마일스톤에 S로 묶어 처리한다.

- 사운드 시스템. 기능적 밸런스·재현성보다 뒤다. 도입할 때는 이벤트 집계 방식으로 설계한다.

- 적 행동의 전략 패턴 분리. 다섯 번째 적이 스탯형인 동안에는 `enemy.gd`의 범용 경로를 유지한다.

- [범위 밖] 세이브·메타 진행·상점·재화. PRD가 명시적으로 배제했으므로 현재 리뷰의 해결책으로 쓰지 않는다.

## 6. 대조군 분석

### G1 Vampire Survivors 대비 부족한 점

Vampire Survivors는 구조상 무기 레벨, 진화, 아이템 간 조합을 통해 같은 자동 공격 안에서도 성장 선택이 누적되는 편이다.

이 프로젝트는 `upgrade_data.gd`에 레벨 필드는 있으나 산탄·궤도구는 `max_level: 1`이며 실제 선택 풀에도 없다.

따라서 대조군의 핵심을 "이펙트가 많다"로 오해하면 안 된다.

그 구조가 긴 세션을 지탱하는 이유는 한 번 획득한 무기가 다음 레벨 선택과 다시 만나는 성장 계약에 있다.

여기서는 먼저 C1과 M2를 고쳐 한 무기가 다음 선택에서 강화될 수 있는 데이터·적용·표시 경로를 만든다.

또한 대조군은 구조상 후반 과포화를 다룰 장기 런 전제를 갖는다.

이 프로젝트의 성능 측정은 75초 사망과 161마리까지여서, `xp_gem.gd` 잔류와 효과 노드가 포함된 10분 과포화는 아직 검증하지 않았다.

무기 진화의 정확한 요구 레벨이나 수치를 본 리뷰에서 단정하지 않는다(검증 필요).

### G2 탕탕특공대(Survivor.io) 대비 부족한 점

탕탕특공대는 구조상 짧은 세션 안에서도 무기 획득·강화와 보스 이벤트를 반복해 플레이 상태를 분절하는 편이다.

이 프로젝트의 `boss_spawner.gd`는 `spawn_time = 300.0`에 정확히 한 번만 보스를 생성한다.

현재 74초에 죽으므로 그 이벤트는 일반 플레이에서 도달 불가능하다.

도달 후에도 보스 드롭 연결은 C4의 메서드명 불일치로 실패한다.

비교의 결론은 모바일용 메타 진행을 가져오자는 뜻이 아니다.

[범위 밖] 세이브·장비·영구 강화는 PRD 밖이며, AI 협업 검증의 다음 목표에도 맞지 않는다.

대신 한 판 안에서 보스 도달 전후의 데이터 계약과 보상 이벤트가 정상 작동하는지부터 검증해야 한다.

대조군의 정확한 보스 주기나 세션 수치는 여기서 단정하지 않는다(검증 필요).

### G3 Brotato 대비 부족한 점

Brotato는 구조상 웨이브 경계와 상점/재화 선택이 런의 상태를 명시적으로 끊어 주는 편이다.

이 프로젝트는 `level_up_ui.gd`의 일시정지 3택이 그 역할을 일부 맡지만, 현재 선택 풀이 패시브 5종에 제한돼 성장 상태의 폭이 작다.

`LevelSystem.add_experience()`의 연속 레벨업과 `LevelUpUI._pending_levels`는 선택을 연속으로 제공할 수 있다.

그러나 무기 선택 누락 때문에 그 연속 선택이 빌드 전환으로 이어지지 않는다.

[범위 밖] Brotato식 상점·재화·판 사이 구매를 넣자는 제안은 PRD의 상점·재화 배제와 충돌하므로 하지 않는다.

이 프로젝트에 가져올 것은 상점 자체가 아니라, 선택 전후의 상태를 데이터로 명확히 보이고 테스트하는 방식이다.

즉 레벨업 전후에 무슨 무기/레벨/스탯이 바뀌었는지 `get_stat_report()`보다 더 일반적인 build snapshot으로 남겨야 한다.

## 7. 우선순위 표

| 순위 | 항목 | 심각도 | 예상 작업량(S/M/L) | 근거 |
|---|---|---|---|---|
| 1 | 산탄·궤도구를 실제 선택 풀에 연결하고 통합 테스트 추가 | Critical | S | `level_up_ui.gd: UPGRADE_POOL`에 두 ID가 없고 `upgrade_manager.gd:_on_upgrade_chosen()` 분기가 도달 불가 |
| 2 | 웨이브 시간 정렬 불변식 추가 후 180/120초 역전 수정 | Critical | S | `wave_data.gd: PHASES[4/5]`, `get_phase_index_for_time()`의 순차 break |
| 3 | `test_waves.gd`를 수치 스냅샷에서 불변식 테스트로 교체하고 고장 주입 | Critical | S | `_test_phase_lookup_boundaries()`, `_test_enemies_per_spawn_grows()`가 튜닝 숫자를 하드코딩 |
| 4 | 보스 드롭 API를 일반 적과 통일 | Critical | S | `boss_spawner.gd:_connect_pickup_spawner()`는 없는 `spawn_pickup`, `pickup_spawner.gd`는 `on_enemy_died` |
| 5 | 고정 시드 다중 정책 헤드리스 밸런스 배치 구축 | Major | M | 74.0초/74.7초, `enemy_spawner.gd:_choose_variant()`의 전역 난수, Timer 간헐 실패 |
| 6 | 외부 웨이브·업그레이드 데이터와 시작 검증기 도입 | Major | M | `wave_data.gd: const PHASES`, `upgrade_data.gd: const DEFINITIONS`는 코드 상수 테이블 |
| 7 | 무기 레벨 modifier 계약으로 리팩터링 | Major | M | `shotgun.gd`, `orbital.gd`의 export 수치와 `upgrade_manager.gd:_recompute_stats()`의 하드코딩 비대칭 |
| 8 | 업그레이드 매니저 의존성 주입 또는 그룹 등록의 명시화 | Major | M | `upgrade_manager.gd`의 자식 경로와 `player.gd`/`level_up_ui.gd`의 `get_first_node_in_group()` |
| 9 | 10분 장기 런의 노드 수·프레임 시간·젬 잔류 계측 | Major | M | `xp_gem.gd` 수명 없음, 220~240 적 상한, 현재 측정은 161마리 |
| 10 | 젬 수명/회수 정책 추가 | Minor | S | `xp_gem.gd:_physics_process()`는 target 없을 때 영구 잔류 |
| 11 | hit 이펙트 이벤트 연결 또는 미사용 API 제거 | Minor | S | `effect_spawner.gd:spawn_hit()` 호출 경로가 `projectile.gd`에 없음 |
| 12 | 반지름·화면 좌표 상수 소유 정리 | Minor | S | `player.gd:body_radius`, `enemy_spawner.gd`/`boss_spawner.gd`의 viewport 중심 가정 |
| 13 | 풀링 도입 | 보류 | L | `queue_free()` 기반 수명과 그룹·시그널 reset 계약을 넓게 바꿔야 하며 현 측정은 충분 |
| 14 | [범위 밖] 상점·재화·메타 진행 | 범위 밖 | L | PRD가 명시적으로 세이브·상점·재화·영구 강화를 배제 |

## 8. 내가 이 프로젝트의 다음 마일스톤을 정한다면 (3줄)

M11은 "재현 가능한 밸런스 계약"이다: C1·C2·C4를 고치고, `test_waves.gd`를 불변식 기반으로 바꾼다.

그 다음 외부 데이터 파일과 고정 시드 헤드리스 배치로 정지·세 회피 정책의 결과를 같은 포맷으로 기록한다.

그 측정에서 이동 이득과 10~15분 곡선이 확인된 뒤에만 무기 레벨 리팩터링과 네 번째 무기를 추가한다.
