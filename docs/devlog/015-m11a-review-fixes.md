# 015 — M11a: 6인 리뷰 반영 (배선 감사 · 시각 피드백)

**날짜**: 2026-08-13
**앞 작업**: [014 M10 밸런싱](014-m10-balancing.md)
**한 줄**: 게임이 1차 완성됐다고 판단한 시점에 외부 시선 6개를 붙였더니, **문서에 "완료"로 적힌 기능 3개가 실제로는 한 번도 실행되지 않고 있었다.**

---

## 1. 무엇을 했나

M0~M10 완주 후 코드를 더 쌓기 전에 **검토**를 넣었다.
시니어 기획자 / 개발자 / 아트·UX 3인 페르소나를 정의하고, **Claude를 A팀, codex를 B팀**으로 삼아 같은 페르소나를 각각 연기시켜 **총 6개의 독립 리뷰**를 만들었다.

- 페르소나 정의: [docs/review/PERSONAS.md](../review/PERSONAS.md)
- A팀: [A-planner](../review/A-planner.md) / [A-engineer](../review/A-engineer.md) / [A-designer](../review/A-designer.md)
- B팀: [B-planner](../review/B-planner.md) / [B-engineer](../review/B-engineer.md) / [B-designer](../review/B-designer.md)

두 팀은 서로의 결과를 보지 않았다. A팀은 저장소를 직접 열람하고 헤드리스 프로브로 실측했고, B팀은 지시서에 첨부된 파일 전문만 봤다(codex는 이 PC에서 파일을 읽지 못한다).

---

## 2. 가장 큰 수확 — 양 팀이 독립적으로 같은 것을 찾았다

### 2-1. 산탄과 궤도구는 게임에서 획득이 불가능했다

`level_up_ui.gd`의 `UPGRADE_POOL`에 두 id가 없었다. `upgrade_data.gd`에 정의가 있고 `upgrade_manager.gd`에 `unlock()` 분기도 있는데, **그 분기를 호출할 경로가 존재하지 않았다.**

프로브 실측:

```
UPGRADE_POOL=[shoes, heart, magnet, gloves, crown]
UPGRADE_DATA_IDS=[shoes, heart, magnet, gloves, crown, shotgun, orbital]
DEFINED_BUT_NOT_OFFERABLE=[shotgun, orbital]
```

문서에는 "무기 3종"이라 적혀 있었고 `test_new_weapons` 5케이스가 통과하고 있었다.
**그 테스트는 `unlock()`을 직접 호출했다.** 즉 유닛은 멀쩡했고 배선만 끊겨 있었다.

M6b 산출물의 절반이 데드 콘텐츠였고, **M7·M10의 밸런스 측정은 전부 "무기 1종짜리 게임"의 수치였다.**

### 2-2. 난이도 페이즈 하나가 도달 불가능했다

`wave_data.gd`의 6번째 페이즈 `start_time`이 120.0이었다. 바로 앞이 180.0이라 시간 정렬이 깨졌고, `get_phase_index_for_time()`의 순차 스캔+`break`가 무너졌다.

```
START_TIMES=[0, 30, 60, 120, 180, 120, 330, 450, 600, 780]
t=179 -> index=3 (hp 2.00)
t=180 -> index=5 (hp 3.50)     ← 인덱스 4를 건너뜀
PHASE_INDICES_NEVER_SEEN=[4]
```

의도한 완만한 상승(2.0 → 2.8 → 3.5) 대신 180초에 체력 1.75배·스폰 1.5배·동시 3마리가 한꺼번에 튀었다.
**74초에 죽어서 아무도 180초를 못 봤기 때문에 증상이 가려져 있었다.**

### 2-3. 보스가 경험치를 하나도 안 떨어뜨렸다

`boss_spawner.gd`가 `has_method("spawn_pickup")`을 요구했는데 `pickup_spawner.gd`에는 `drop_gem`/`on_enemy_died`만 있었다. 게다가 그룹 `pickup_spawner`에 **등록된 노드도 없었다**(`main.tscn`).
조건 불일치 시 조용히 `return`이라 **에러조차 남지 않았다.**

---

## 3. 이번에 고친 것

| # | 항목 | 파일 |
|---|---|---|
| 1 | `UPGRADE_POOL` 제거 → `UpgradeData.get_all_ids()` 사용 | `scripts/level_up_ui.gd` |
| 2 | 페이즈 5 `start_time` 120.0 → 240.0 | `scripts/wave_data.gd` |
| 3 | 보스 드랍 배선 (`spawn_pickup` → `on_enemy_died`) + 실패 시 `push_error` | `scripts/boss_spawner.gd` |
| 4 | `PickupSpawner`를 `pickup_spawner` 그룹에 등록 | `scenes/main.tscn` |
| 5 | 명중 시 `EffectSpawner.spawn_hit()` 호출 (이전 호출처 0건) | `scripts/projectile.gd`, `scripts/orbital.gd` |
| 6 | 적 피격 시 0.06초 흰색 번쩍 | `scripts/enemy.gd` |
| 7 | 위험 상태(HP 30% 이하) — HP바 적색 + 화면 비네트 | `scripts/hud.gd`, `scenes/hud.tscn` |
| 8 | HP바(녹색)/경험치바(청색) 색 분리 | `scenes/hud.tscn` |
| 9 | 보스 색 `(0.1,0.1,0.12)` → `(0.95,0.35,0.95)` | `scripts/boss_spawner.gd` |
| 10 | `test_waves.gd` 불변식 기반 전환 | `tests/test_waves.gd` |
| 11 | 씬 배선 스모크 테스트 신규 | `tests/test_scene_wiring.*` |
| 12 | 시각 피드백 테스트 신규 | `tests/test_feedback.*` |

### 보스 색을 바꾼 이유 — 숫자로

WCAG 상대 휘도로 배경(`#141419`) 대비를 계산했더니 이랬다.

| 요소 | 대비 |
|---|---|
| 투사체 | 13.6 : 1 |
| 경험치 젬 | 12.8 : 1 |
| 플레이어 | 8.0 : 1 |
| 기본 적 | 4.5 : 1 |
| 탱커 | 3.4 : 1 |
| **보스** | **1.05 : 1** |

비텍스트 요소의 WCAG 최소 권장이 3:1이다. **보스는 배경과 구별이 불가능했다.**
마젠타로 바꿔 약 6.5:1을 확보했다. (밝기 위계 전면 재배치는 이번 범위에 넣지 않았다 — 4절 참고)

---

## 4. 고장 주입 검증 — 새 테스트가 정말로 실패하는가

"통과 확인만으로는 절반"이라는 이 프로젝트의 규칙대로, 6건을 일부러 고장 냈다.
**미커밋 상태였으므로 `git checkout --`을 쓰지 않고 파일 백업·복원 방식으로** 했다 (M4에서 작업이 날아간 적이 있다).

| 주입한 고장 | 결과 |
|---|---|
| `wave_data` 페이즈 정렬 되돌리기 | `all_phases_reachable` **FAIL** `broken_at=4 start=180.00 observed=5` |
| 보스 드랍을 `spawn_pickup`으로 되돌리기 | `boss_drops_experience` **FAIL** `pickup_connection=false` |
| 명중 이펙트 호출 제거 | `projectile_spawns_hit_effect` **FAIL** `before=0 after=0` |
| 적 피격 번쩍 제거 | `enemy_flashes_on_hit` **FAIL** `flashing=false` |
| 업그레이드 풀을 다시 하드코딩 | `all_upgrades_are_offerable` **FAIL** `missing_ids=shotgun,orbital` |
| HUD 위험 상태 제거 | `hud_enters_danger_state` **FAIL** |

마지막에서 두 번째가 핵심이다. **원래 버그를 그 문구 그대로 잡아낸다.**

---

## 5. 시행착오 기록

### 5-1. 배선 테스트의 첫 판은 무력했다

codex가 만든 `all_upgrades_are_offerable`이 이렇게 돼 있었다.

```gdscript
var has_testing_accessor: bool = level_up_ui.has_method(&"get_available_upgrade_ids_for_testing")
...
var ui_offers_id: bool = not has_testing_accessor or offered_ids.has(upgrade_id)
```

그런 메서드는 존재하지 않으므로 `has_testing_accessor`가 항상 false → `ui_offers_id`가 **항상 true**.
즉 **UI 목록을 전혀 검사하지 않으면서 PASS**하고 있었다. 원래 버그를 그대로 통과시켰을 것이다.

GDScript에는 진짜 private이 없으므로 `_get_available_upgrade_ids`를 직접 호출하도록 고쳤고, 그 메서드가 없으면 실패하도록 `else` 분기를 넣었다. 그 뒤에야 고장 주입에서 FAIL이 났다.

> **교훈**: 새 테스트는 "통과하는지"가 아니라 **"고장을 넣으면 실패하는지"로만** 검증한다. 이번엔 그 절차가 실제로 무력한 테스트를 하나 걸러냈다.

### 5-2. 하드코딩 문제는 한 곳이 아니었다

`UPGRADE_POOL`을 고치자 `test_upgrade_limits`의 2케이스가 깨졌다.
원인은 그 테스트가 **같은 목록을 또 하드코딩**하고 있었기 때문이다.

```gdscript
const UPGRADE_IDS: Array[StringName] = [&"shoes", &"heart", &"magnet", &"gloves", &"crown"]
```

`UpgradeData.get_all_ids()`로 바꿔 해결했다. 정의 단일 출처를 표방한 파일이 있는데 **목록이 세 군데(프로덕션 1 + 테스트 2)에 흩어져 있었던 것**이다.

### 5-3. codex에는 이미지 생성 기능이 없다

2D 게임이니 에셋을 codex 이미지 생성으로 만들자는 계획이었으나, 조사 결과 **codex CLI(0.144.6)에는 이미지 생성 기능이 없다.**

- `codex exec -i/--image`는 이미지를 **입력으로 첨부**하는 옵션이다
- 설치된 플러그인은 `documents`/`pdf`/`spreadsheets`/`presentations`/`sites`/`browser`/`visualize`. `visualize`는 차트·다이어그램용이다
- 마켓플레이스 미설치 목록에도 이미지 생성기는 없다

따라서 **실행한 프롬프트는 한 건도 없다.** 대신 나중에 다른 도구로 생성할 수 있도록 **에셋 사양과 프롬프트 원문을 [docs/ASSETS.md](../ASSETS.md)에 작성해 남겼다.**
Pillow 11.3.0이 있어 프로그램 생성은 가능하지만, A팀 디자이너가 "도형 상태에서 위계를 먼저 세우고 교체는 그 규칙을 옮기는 작업이어야 한다"고 해서 이번에는 실행하지 않았다.

### 5-4. 빌드에서 걸린 것 세 가지

빌드 절차 전체는 [docs/BUILD.md](../BUILD.md)에 있다. 막혔던 지점만:

1. **Android가 ETC2 없이 거부한다** — `rendering/textures/vram_compression/import_etc2_astc=true`가 필요했다
2. **`build/`가 프로젝트 에셋으로 재임포트된다** — 웹 산출물 PNG 3개가 다시 임포트돼 다음 pck에 섞여 들어갔다. `build/.gdignore`로 막았다
3. **Android 릴리스 서명 실패** — 릴리스 키스토어가 없다. 확인용이므로 `--export-debug`(기본 디버그 키스토어)로 전환했다

---

## 6. 결과

- 자동 테스트 **16스위트 87케이스 전부 통과** (이전 14스위트 80케이스)
- Windows / 웹 / Android 세 플랫폼 빌드 성공, 세 개 다 실행 확인
- 문서에 "완료"로 적혀 있던 기능 3개가 실제로 동작하게 됨

---

## 7. 남은 것 — 다음 마일스톤

이번에 고친 건 **배선과 피드백**이다. **75초 문제의 근본 원인은 아직 그대로다.**

A팀 기획자의 산술이 문제를 정확히 짚는다:

- 플레이어 화력 상한 = **1.52배** (공격 성장이 `장갑` 쿨다운 −8% ×5 = `0.92⁵` 하나뿐, 데미지 업그레이드 자체가 없음)
- 적 체력 배율 = **16배**
- 1:00 구간에서 스폰 3.33/s 대 처치 0.67/s → **초당 2.7마리 구조적 적자**

다만 이번 수정으로 **산탄·궤도구가 실제로 획득 가능해졌으므로 화력 상한 자체가 달라졌다.** 밸런스를 다시 재기 전에 **재측정이 먼저다.** 이전 74초 수치는 무기 1종 기준이라 더 이상 유효하지 않다.

다음 순서:

1. 봇 진단 재측정 (무기 3종이 실제로 붙은 상태에서)
2. 데미지 업그레이드 신설 + 무기 레벨 도입 (산탄·궤도구는 아직 `max_level = 1`)
3. 그 다음에야 시간 곡선 조정

**순서를 바꾸면 두 번 일한다.** 파워 상한을 안 고친 채 페이즈 시작 시점만 늦추면 "지루한 75초"가 "지루한 150초"가 될 뿐이다.
