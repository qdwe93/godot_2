# A팀 — 시니어 게임 개발자 «태호» 리뷰

> 검토 기준 커밋 `ddf6887` / 2026-08-13
> 검증 방식: 저장소 전체 열람 + 헤드리스 프로브로 런타임 동작 실측

---

## 1. 총평

코드 품질 자체는 습작 수준을 넘어섰다. 방어 코드, 에러 메시지, 테스트 하네스의 자기 의심 — 잘 훈련된 코드베이스다.
문제는 **"조용히 죽어 있는 배선"**이다. 선언된 기능 중 최소 3건이 게임에서 절대 실행되지 않는데, 80케이스 테스트는 하나도 못 잡았다.
공통 원인은 하나다. **테스트가 유닛을 직접 호출해 검증하고, 유닛을 게임에 연결하는 지점은 아무도 검증하지 않는다.**
그리고 밸런싱을 반복하려면 `wave_data.gd` 수정 → 문법 검사 → 테스트 3개 깨짐 → 테스트 수정을 매번 돌아야 한다. **튜닝 루프가 없다.**
6개월 뒤 이 코드를 받는 사람은 "무기 3종"이라는 문서를 읽고 게임을 켠 다음, 무기가 1종인 이유를 사흘쯤 찾을 것이다.

---

## 2. 강점 3가지

1. **`upgrade_manager.gd:107-137`의 재계산 방식이 옳다.** 현재값에 곱하는 대신 `_base_*`를 캡처해두고 `base × f(level)`로 매번 다시 계산한다. 부동소수 누적 오차와 중복 적용 버그를 구조적으로 차단했다. `CooldownTimer.wait_time`까지 같이 갱신한 것도 정확하다 — 이걸 빼먹으면 다음 틱까지 효과가 안 나온다.
2. **물리 스텝 회피 규약이 코드에 근거로 남아 있다.** `pickup_spawner.gd:49-51`은 왜 `call_deferred`를 쓰는지 적어놨고, `effect_spawner.gd:62-63`은 반대로 **왜 여기서는 즉시 add_child해도 안전한지**(충돌 도형이 없으므로)를 적어놨다. 규칙이 아니라 근거가 남아서 다음 사람이 판단할 수 있다.
3. **테스트 하네스가 자기 자신을 의심한다.** `passed=0`은 PASS 아님, `TEST_ERROR setup_failed` 조기 중단, 헤드리스에서 못 믿을 값은 SKIP. 대부분의 프로젝트는 여기까지 안 간다.

---

## 3. 치명적 문제 (Critical)

### E-C1. 게임에서 절대 실행되지 않는 배선이 최소 3건 — 전부 테스트를 통과했다

| # | 죽은 배선 | 증거 | 결과 |
|---|---|---|---|
| 1 | 산탄·궤도구 해금 | `level_up_ui.gd:7-13`의 `UPGRADE_POOL`에 두 id가 없음 | `upgrade_manager.gd:91-94`의 `unlock()` 호출부가 영원히 안 걸림 → **실플레이 무기 1종** |
| 2 | 피격 이펙트 | `effect_spawner.gd:39` `spawn_hit()` **호출처 0건** (전체 grep) | 적을 때려도 아무 반응 없음. `enemy.gd:84` `take_damage()`에 `modulate` 번쩍도 없음 |
| 3 | 보스 경험치 드랍 | `boss_spawner.gd:100-105` — 그룹 `pickup_spawner`에 등록된 노드 **없음**(`main.tscn`), 게다가 `spawn_pickup()` 메서드가 **PickupSpawner에 존재하지 않음**(`drop_gem`/`on_enemy_died`뿐) | 500 HP 보스가 젬을 **0개** 드랍. 조기 return이라 에러도 안 남 |

프로브 실측:

```
DEFINED_BUT_NOT_OFFERABLE=[shotgun, orbital]
```

**세 건 모두 같은 실패 유형이다.** 유닛은 정상이고, 유닛끼리 잇는 지점이 끊어져 있다. `test_new_weapons`는 `unlock()`을 직접 부르고, `test_effects`는 `spawn_death()`를 직접 부른다. **아무도 "게임을 켰을 때 이 경로가 도는가"를 묻지 않는다.**

3번이 특히 나쁘다. `boss_spawner.gd:100-105`는 조건 불일치 시 조용히 `return`한다. 실패가 로그에도 안 남는다. **에러 없이 기능만 사라지는 코드**가 이 프로젝트의 반복 패턴이다(CLAUDE.md도 같은 함정을 여러 번 경고한다).

**대책은 통합 스모크 테스트다.** `main.tscn`을 실제로 로드해 다음을 검사한다:

- `UpgradeData.get_all_ids()`의 모든 id가 실제로 제안 가능한가 (또는 명시적 제외 목록에 있는가)
- 그룹으로 조회하는 모든 이름(`upgrade_manager`, `pickup_spawner`, `projectile_container`, `screen_shake`, `effect_spawner`)이 씬에 실재하는가
- `Callable(x, "메서드명")`으로 연결하는 모든 메서드가 대상에 실재하는가

작업량 **S**. 위 3건을 전부 잡는다.

### E-C2. `wave_data.gd`의 시간 정렬이 깨졌다 — 페이즈 하나가 도달 불가

`wave_data.gd:47` 페이즈 5의 `start_time`이 **120.0**이다. 직전 페이즈 4가 180.0이므로 `get_phase_index_for_time()`(`wave_data.gd:121-129`)의 순차 스캔 + `break` 로직이 무너진다.

프로브 실측:

```
START_TIMES=[0, 30, 60, 120, 180, 120, 330, 450, 600, 780]
t=179 -> index=3 (hp 2.00)
t=180 -> index=5 (hp 3.50)
PHASE_INDICES_NEVER_SEEN=[4]
```

인덱스 4는 **어떤 입력에도 반환되지 않는다.** 죽은 데이터 40줄이 파일에 남아 있고, 180초에서 체력·스폰 간격·동시 수가 한꺼번에 튄다.

`get_phase_index_for_time()`이 정렬을 **가정**하면서 검증하지 않는 것도 문제다. 최소한 부팅 시 1회 검사가 있어야 한다.

### E-C3. `tests/test_waves.gd`가 밸런스 수치를 계약으로 못 박아 튜닝을 봉쇄한다

STATUS.md가 이미 지적한 대로, 이 테스트는 29.9초/60초/300초와 그 시점의 값을 하드코딩한다. **곡선을 건드리면 무조건 3케이스가 깨진다.** 실제로 M10에서 "시작 시점 완화를 시도했으나 테스트가 수치를 하드코딩해 되돌림"이 일어났다 — **테스트가 개발을 되돌린 사건**이다.

더 나쁜 건 이 테스트가 **E-C2 버그를 통과시켰다는 점**이다. 특정 시각의 값만 보니 순서가 깨진 걸 알 방법이 없다.

수치 대신 관계를 검사해야 한다:

```gdscript
# 1. start_time 엄격 증가 — E-C2를 바로 잡는다
for i in range(1, WaveData.PHASES.size()):
    var prev: float = float(WaveData.PHASES[i - 1]["start_time"])
    var curr: float = float(WaveData.PHASES[i]["start_time"])
    _check(curr > prev, "start_time must strictly increase at index %d" % i)

# 2. 모든 페이즈가 도달 가능 — 죽은 데이터 차단
for i in range(WaveData.PHASES.size()):
    var t: float = float(WaveData.PHASES[i]["start_time"])
    _check(WaveData.get_phase_index_for_time(t) == i, "phase %d unreachable" % i)

# 3. 경계 동작 — 시작 직전은 이전 페이즈
for i in range(1, WaveData.PHASES.size()):
    var t: float = float(WaveData.PHASES[i]["start_time"]) - 0.01
    _check(WaveData.get_phase_index_for_time(t) == i - 1, "boundary broken at %d" % i)

# 4. 단조성 — 간격은 비증가, 상한과 체력은 비감소
for i in range(1, WaveData.PHASES.size()):
    _check(WaveData.PHASES[i]["spawn_interval"] <= WaveData.PHASES[i - 1]["spawn_interval"], "interval")
    _check(WaveData.PHASES[i]["max_enemies"] >= WaveData.PHASES[i - 1]["max_enemies"], "max_enemies")
    _check(WaveData.PHASES[i]["health_multiplier"] >= WaveData.PHASES[i - 1]["health_multiplier"], "hp_mult")

# 5. weights의 id가 ENEMY_TYPES에 실재
for phase in WaveData.PHASES:
    for variant_id in phase["weights"]:
        _check(WaveData.ENEMY_TYPES.has(variant_id), "unknown variant")
```

이렇게 바꾸면 **수치를 아무리 바꿔도 테스트를 안 고쳐도 되고**, 대신 지금 있는 버그는 즉시 잡힌다. 작업량 **S**.

### E-C4. `wave_data.gd` / `upgrade_data.gd`는 데이터 주도가 아니다 — 코드 안의 상수 테이블이다

둘 다 `.gd` 파일의 `const`다. 밸런스 숫자 하나를 바꾸려면:

1. `.gd` 편집 → 2. `--check-only` 문법 검사 → 3. 테스트 3개 깨짐 → 4. 테스트 수정 → 5. 재실행

**한 번의 튜닝에 5단계.** 이 상태로 10~15분 곡선을 맞추려면 수십 번 반복해야 한다. 사실상 불가능하다.

판정: **지금은 데이터 주도가 아니다.** 다만 읽는 쪽은 이미 딕셔너리 인터페이스이므로 소스를 `.json`이나 `.tres`로 바꾸는 비용은 낮다(읽기 지점이 `enemy_spawner.gd`, `upgrade_manager.gd`, `level_up_ui.gd` 3곳). 작업량 **M**.

---

## 4. 중요 문제 (Major)

### E-M1. 콘텐츠 추가 비용이 산재해 있다 — 무기 4번째를 세어봤다

새 무기 하나를 추가할 때 손대야 하는 지점:

| # | 파일 | 무엇을 |
|---|---|---|
| 1 | `scripts/<new_weapon>.gd` | 신규 |
| 2 | `scenes/player.tscn` | 노드 추가 + ext_resource + load_steps 갱신 |
| 3 | `scripts/upgrade_data.gd` | DEFINITIONS 항목 |
| 4 | `scripts/level_up_ui.gd:7` | **UPGRADE_POOL 배열** ← 여기를 빼먹은 게 E-C1 |
| 5 | `scripts/upgrade_manager.gd:42-43` | 노드 캐시 변수 |
| 6 | `scripts/upgrade_manager.gd:91-94` | **id별 unlock 분기 (if문 증식)** |
| 7 | `scripts/upgrade_manager.gd:118-137` | 쿨다운 재계산 분기 |
| 8 | `tests/` | 신규 케이스 |

**8곳.** 그중 4·6·7은 `if id == &"shotgun"` 식 하드코딩 분기라 무기가 늘수록 선형으로 증식한다. `UPGRADE_POOL`이 `UpgradeData`와 별도로 존재하는 것 자체가 설계 실수다 — **정의 단일 출처를 표방한 파일이 있는데 목록을 두 군데서 관리하고 있다.**

최소 수정: `UPGRADE_POOL`을 지우고 `UpgradeData.get_all_ids()`를 쓰게 한다. 작업량 **S**. 이것만으로 E-C1의 1번이 해결되고 재발도 막힌다.

### E-M2. 무기·패시브에 레벨을 소급 도입하는 비용 — M, 지금 하는 게 가장 싸다

좋은 소식: `upgrade_manager._levels`는 이미 id별 레벨 딕셔너리고 `get_level(id)`도 있다. **뼈대는 이미 레벨을 지원한다.**

필요한 작업:

- `upgrade_data.gd`에 `damage_multiplier` 필드 추가, `shotgun`/`orbital`의 `max_level`을 1 → 5로
- `_recompute_stats()`에 데미지 반영 (`_base_projectile_damage` 캡처 + `_weapon.set(&"projectile_damage", ...)`)
- `orbital.gd`의 `damage`는 `@export`라 동일 방식으로 처리 가능
- `shotgun.gd`의 `pellet_count`도 레벨로 늘릴 수 있다 (3 → 5)

**핵심은 `_recompute_stats()`가 이미 "기본값 × 레벨 함수" 패턴이라 항목 추가가 값싸다는 점이다.** 작업량 **M**. 콘텐츠가 더 늘기 전인 지금이 최저가다.

### E-M3. 80케이스가 못 잡는 것들 (실제로 확인된 것만)

- **씬 배선**: 그룹 이름 오타, 존재하지 않는 메서드로의 `Callable` 연결, 노드 경로 변경 → E-C1 3건 전부
- **데이터 정합성**: `wave_data` 정렬, `weights`의 미정의 변종 id → E-C2
- **선언 대 노출**: 정의됐지만 플레이어에게 도달 못 하는 콘텐츠
- **장기 실행 상태**: 젬 무한 누적, `Orbital._last_hit_times` 증식, 10분 지점의 프레임
- **시계 일치성**: HUD 시간과 웨이브 시간이 갈라짐(E-M5)

### E-M4. 그룹·노드 이름 문자열이 검증 없이 흩어져 있다

`upgrade_manager.gd`는 `"Weapon"`, `"Shotgun"`, `"Orbital"`, `"MagnetArea/CollisionShape2D"`를 문자열로 찾는다. `player.tscn`에서 노드 이름 하나만 바꾸면 조용히 기능이 죽는다(`_shotgun`은 null 체크가 있어서 **에러조차 안 난다**).

그룹 이름도 마찬가지다: `upgrade_manager`, `pickup_spawner`, `projectile_container`, `screen_shake`, `effect_spawner`, `enemies`, `xp_gems`. 이 중 **`pickup_spawner`에는 실제로 아무 노드도 등록돼 있지 않다**(E-C1의 3번). 상수 파일로 모으고 부팅 시 1회 검사해야 한다. 작업량 **S**.

### E-M5. HUD 시계와 웨이브 시계가 갈라진다

`hud.tscn`의 `process_mode = 3`(ALWAYS) + `hud.gd:34-38`의 `_process` → **일시정지 중에도 시간이 흐른다.** 반면 `enemy_spawner.gd:71-73`의 `_elapsed_seconds`는 PAUSABLE이라 멈춘다.

레벨업 UI에서 고민한 시간만큼 두 시계가 벌어진다. 게임오버 요약의 "생존 시간"(`game_flow.gd:92`)은 HUD 시계를 쓰므로 **밸런스 측정의 기준값이 부풀려진 값**이다. M10의 74초 측정은 `--auto-play`(즉시 선택)라 영향이 작았지만, 사람이 플레이하면 어긋난다.

### E-M6. 성능 결론(풀링 불필요)은 현재 곡선에서만 유효하다

M7b 실측은 161마리/144fps다. 하지만 `wave_data`의 마지막 페이즈는 `max_enemies = 240`이고, 아무도 거기 도달하지 못해서 **측정된 적이 없다.**

`enemy.gd:42-82`의 분리 로직은 매 4프레임 `get_tree().get_nodes_in_group("enemies")`로 전체 배열을 받아 순회한다. 이웃 12개에서 `break`하지만 **12개를 못 찾으면 240개를 전부 훑는다.** 적이 흩어져 있을 때가 오히려 최악이다. 240마리 기준 프레임당 최대 240 × 240 ÷ 4 = **14,400회 거리 계산**. 재측정 없이 "풀링 불필요"를 결론으로 두면 안 된다.

### E-M7. 젬이 영원히 남는다

`xp_gem.gd`에 수명이 없다. `target`이 null이면 `_physics_process`가 즉시 return하므로 CPU는 거의 안 쓰지만 **노드와 충돌 도형은 계속 쌓인다.** 10분 플레이면 수천 개가 될 수 있다. 수명 또는 개수 상한이 필요하다. 작업량 **S**.

### E-M8. 투사체 사거리가 구현되지 않았다

GDD 6절은 "투사체는 사거리(또는 수명 3초)를 넘기면 스스로 제거된다"고 적었다. 실제 `projectile.gd`에는 **수명만 있다.** 속도 400 × 수명 3초 = **1200px**를 날아간다. `weapon.attack_range`는 350인데 투사체는 화면을 가로질러 반대편 적까지 맞힌다. 조준 사거리와 실제 사거리가 3.4배 다르다 — 밸런스 계산이 어긋나는 지점이다.

---

## 5. 개선 제안 (Minor)

- `main.gd:58` `BOOT_OK milestone=M9` — M10까지 왔다. 부팅 토큰은 자동화가 의존하는 값이니 갱신 규칙을 정하는 게 낫다.
- `main.tscn`의 `GameOverLabel`(main.gd가 표시)과 `GameFlow/GameOverPanel`이 **둘 다** 게임오버를 표시한다. M8에서 후자가 생겼는데 전자를 안 지웠다.
- `orbital.gd:54-59` `_prune_last_hit_times()`가 매 물리 프레임 전체 키를 순회한다. 주기화하거나 크기 임계값에서만 돌리면 된다.
- 플레이어 반지름 12가 `player.gd:13`, `player.tscn`의 CircleShape2D 2개, Sprite offset에 중복(STATUS 이슈 3). 상수화 시점이 지났다.
- `weapon.gd`와 `shotgun.gd`의 최근접 탐색이 거의 동일하다. 무기가 늘면 세 번째 복사본이 생긴다.

---

## 6. 대조군 분석

### G1. Vampire Survivors 대비

VS급 콘텐츠 볼륨(무기 다수 × 레벨 × 진화)은 **하드코딩 분기로는 도달 불가능한 규모**다(구조상 그렇다). 우리 `upgrade_manager`는 id마다 `if`를 늘리는 구조라 20종에서 무너진다. 부족한 건 콘텐츠 수가 아니라 **콘텐츠를 데이터로 기술하는 스키마**다.

### G2. 탕탕특공대(Survivor.io) 대비

모바일 라이브 서비스는 **밸런스를 코드 배포 없이 바꿀 수 있어야** 성립한다(구조상 그렇다). 우리는 숫자 하나에 코드 수정 + 테스트 수정이 붙는다. [범위 밖] 원격 설정은 논외지만, **로컬 데이터 파일 분리만으로도 튜닝 루프가 5단계에서 2단계로 준다.**

### G3. Brotato 대비

Brotato는 웨이브가 명확한 마디라 **웨이브 단위 상태 초기화**가 자연스럽다(구조상 그렇다). 우리는 연속 스폰이라 상태가 판 전체에 누적된다 — 젬, `_last_hit_times`, 이펙트 노드. **긴 판을 목표로 하면 누적 자원 관리가 곧 성능 문제가 된다.** 지금 74초라 안 보일 뿐이다.

---

## 7. 우선순위 표

| 순위 | 항목 | 심각도 | 작업량 | 근거 |
|---|---|---|---|---|
| 1 | `UPGRADE_POOL` 제거 → `UpgradeData.get_all_ids()` 사용 | Critical | **S** | `level_up_ui.gd:7`. 무기 2종이 살아나고 재발도 막힌다 |
| 2 | `wave_data.gd:47` start_time 수정 (120.0 → 240.0) | Critical | **S** | 프로브: 인덱스 4 도달 불가 |
| 3 | `test_waves.gd`를 불변식 기반으로 교체 | Critical | **S** | 튜닝 봉쇄 해제 + 2번 버그를 앞으로 자동 검출 |
| 4 | 씬 배선 스모크 테스트 (그룹·메서드·id 실재 검사) | Critical | **S** | E-C1 3건 전부. 이 프로젝트의 최빈 실패 유형 |
| 5 | 보스 드랍 배선 수정 (`spawn_pickup` → `on_enemy_died`, 그룹 등록) | Critical | **S** | `boss_spawner.gd:100-105` |
| 6 | 무기 레벨 + 데미지 업그레이드 도입 | Critical | **M** | 기획 리뷰 C-2와 동일 사안. `_recompute_stats` 패턴 재사용 |
| 7 | 밸런스 데이터를 외부 파일로 분리 | Major | **M** | 튜닝 루프 5단계 → 2단계 |
| 8 | HUD 시계를 웨이브 시계에 동기화 | Major | **S** | 측정 기준값 오염 |
| 9 | 젬 수명·상한, `_prune_last_hit_times` 주기화 | Major | **S** | 장기 판 대비 |
| 10 | 240마리 성능 재측정 | Major | **S** | "풀링 불필요"는 161마리 기준 결론 |
| 11 | 투사체 사거리 구현 (GDD와 일치) | Major | **S** | 조준 350 vs 실제 1200px |
| 12 | 그룹·노드 이름 상수화 | Minor | **S** | 4번에 흡수 가능 |

### 갚아야 할 부채 / 안 갚아도 되는 부채

**지금 갚아야 함**: `UPGRADE_POOL` 이중 관리(1), 테스트 하드코딩(3), 배선 검증 부재(4), 데이터 외부화(7)
— 전부 **앞으로의 작업 속도에 이자가 붙는** 항목이다.

**안 갚아도 됨**: 반지름 12 중복, 최근접 탐색 중복, `GameOverLabel` 중복, `BOOT_OK` 문자열
— 불편하지만 이자가 안 붙는다. 무기 레벨 작업 중 지나가며 정리하면 충분하다.

---

## 8. 내가 이 프로젝트의 다음 마일스톤을 정한다면

**M11a = "배선 감사와 튜닝 루프 복구"**. 전부 S 작업이고 반나절이면 끝난다: `UPGRADE_POOL` 통합 / `wave_data` 정렬 수정 / `test_waves` 불변식 전환 / 씬 배선 스모크 테스트 / 보스 드랍 수정.
이걸 먼저 하는 이유는 명확하다. **지금 밸런싱을 하면 무기 1종짜리 게임을 튜닝하게 되고, 그 측정값은 전부 버려진다.**
그 다음이 M11b(무기 레벨 + 데미지 업그레이드, M)이고 **밸런싱은 그 뒤에 한다.** 순서를 바꾸면 두 번 일한다.
