# 개발일지 005 — M4: 접촉 피해와 체력

**날짜**: 2026-08-13
**마일스톤**: M4 (충돌 피해 / HP / 무적시간 / 사망)
**결과**: 완료. 테스트 20케이스 통과.
**시행착오 3건** — 그중 하나는 **테스트 하네스가 거짓 통과를 보고한 것**, 하나는 **내가 작업물을 날린 것**이다.

---

## 1. 오늘 한 일

1. 플레이어 HP 100, 무적 0.5초, `take_damage()`, `died` 시그널
2. `Hurtbox` (Area2D) 기반 접촉 피해 판정
3. 사망 시 스포너 정지 + 게임오버 라벨 (최소 구현, 정식은 M8)
4. **테스트 하네스 전면 강화** — 거짓 통과 차단
5. M1 경계 테스트의 헤드리스 SKIP 해제

## 2. 접촉 판정을 `Area2D` 폴링으로 한 이유

두 가지 선택지가 있었다.

| 방식 | 문제 |
|---|---|
| `move_and_slide()` 후 `get_slide_collision_count()` | 플레이어와 적이 서로 밀어내며 미끄러져 접촉이 프레임마다 끊긴다 |
| `Area2D` 겹침 감지 | 안정적. 히트박스 크기를 시각 크기와 따로 조절 가능 |

Area2D를 골랐다. 그런데 **Area2D를 쓰더라도 시그널만으로는 부족하다.**

`body_entered` 시그널은 **들어오는 순간** 한 번만 발생한다. 다음 상황을 보자.

1. 적이 플레이어에 닿는다 → `body_entered` 발생 → 피해 5, 무적 0.5초 시작
2. 적은 계속 겹쳐 있다 (떨어지지 않았다)
3. 0.5초 뒤 무적이 풀린다 → **아무 시그널도 안 온다.** 이미 들어와 있으니까
4. 플레이어는 적 무리 한가운데서 영원히 무사하다

그래서 `_physics_process`마다 `get_overlapping_bodies()`를 **폴링**한다. "지금 겹쳐 있는 것들"을 매 프레임 확인하므로 3번 상황에서 정상적으로 피해가 들어간다. 테스트 케이스 3(`damage_resumes_after_invincibility`)이 정확히 이 시나리오를 검사한다 — 적을 제거했다가 다시 넣지 않고 **계속 겹친 상태로 유지**하므로, 시그널 방식 구현은 이 케이스를 절대 통과할 수 없다.

**무적 시간은 선택이 아니라 필수다.** 없으면 초당 60번 피해를 입어 HP 100이 1.7초에 증발한다. 그래서 피해 구현과 같은 변경에 함께 넣도록 작업지시서에 못박았다.

한 가지 측정된 특성: **Area2D의 겹침 목록은 노드를 만들거나 순간이동시킨 직후 프레임에는 갱신되지 않는다.** 실측 4프레임 뒤에 반영됐다. 물리 스텝 내 정해진 시점에 갱신되기 때문이다. 테스트에서 "적을 배치하자마자 피해를 확인"하면 실패한다.

## 3. 시행착오 ① — Godot 4.7은 "Variant 추론"을 에러로 취급한다

M4 코드를 받아 테스트를 돌렸더니 이런 게 나왔다.

```
SCRIPT ERROR: Parse Error: The variable type is being inferred from a Variant value,
so it will be typed as Variant. (Warning treated as error.)
ERROR: Failed to load script "res://scripts/player.gd" with error "Parse error".
```

문제의 줄:

```gdscript
var contact_damage := _contact_damage_from(body)   # 이 함수의 반환 타입이 Variant
```

`:=`는 우변에서 타입을 추론하는데, 우변이 Variant면 추론할 게 없다. Godot 4.7은 이걸 **경고가 아니라 에러로 승격**시킨다. 결과적으로 `player.gd` 전체가 로드되지 않았고, **플레이어는 스크립트 없는 빈 노드가 됐다.** 움직이지도, 체력을 갖지도 않는다.

수정은 한 글자 수준이다:

```gdscript
var contact_damage: Variant = _contact_damage_from(body)
```

`get()`, `ProjectSettings.get_setting()`, Dictionary 접근 등 **Variant를 돌려주는 모든 것에 `:=`를 쓰면 안 된다.** 이후 모든 스크립트를 훑어 같은 패턴을 제거했고, 검증 절차에 "스크립트 변경 후 `--check-only` 문법 검사"를 추가했다.

## 4. 시행착오 ② — 테스트 하네스가 거짓 통과를 보고했다 (가장 중요)

### 증상

위의 파싱 에러로 게임이 완전히 망가진 상태에서 테스트를 돌린 결과다.

```
--- test_player_movement
ERROR: Failed to load script "res://scripts/player.gd" with error "Parse error".
TEST_CASE diagonal_speed PASS actual_distance=0.000 case_1_distance=0.000 ...
TEST_RESULT PASS passed=1 failed=0 skipped=0     ← 종료 코드 0

--- test_player_damage
ERROR: Failed to load script "res://scripts/player.gd" ...
TEST_RESULT PASS passed=0 failed=0 skipped=0     ← 종료 코드 0
```

**게임이 통째로 부서졌는데 모든 스위트가 PASS와 종료 코드 0을 냈다.**

두 가지 구멍이 겹쳤다.

1. **실행되지 않은 케이스는 아무 기록도 남기지 않는다.** 케이스 함수가 런타임 에러로 중단되면 결과 집계에 아예 등장하지 않고, 요약은 "실패 0건"이라고 보고한다. `passed=0 failed=0` → PASS.
2. **0과 0을 비교해서 통과했다.** `diagonal_speed`는 "대각선 이동 거리가 직선 이동 거리의 5% 이내인가"를 본다. 플레이어가 움직이지 않아 둘 다 0.000이 됐고, 0은 0의 5% 이내이므로 PASS. 아무것도 안 움직였는데 "정규화가 정확하다"고 보고한 셈이다.

### 왜 이게 최악인가

M1에서 "항상 통과하는 테스트는 없는 것보다 나쁘다"고 적었는데, 이번 건은 그보다 한 단계 더 나쁘다. **부서진 빌드를 초록불로 바꿔준다.** 만약 여기서 로그를 안 읽고 종료 코드만 봤다면, 스크립트조차 로드되지 않는 상태를 "M4 완료"로 커밋했을 것이다.

### 해결 — 네 스위트 전부에 적용

1. **기대 케이스 수 선언**: 각 스위트가 `const EXPECTED_CASE_COUNT`를 갖고, `passed + failed + skipped`가 그 수와 다르면 강제 FAIL한다.
   ```
   TEST_ERROR missing_cases expected=<n> recorded=<m>
   ```
2. **`passed=0`은 절대 PASS가 아니다.** 최소 한 개는 실행돼야 한다.
3. **사전 점검**: 케이스를 돌리기 전에 의존 대상이 제대로 로드됐는지 확인한다(플레이어에 스크립트가 붙었는지, 호출할 메서드가 있는지). 아니면 즉시 중단한다.
   ```
   TEST_ERROR setup_failed player script did not load
   ```
4. **0값 통과 차단**: 거리·이동량·개수를 비교하는 케이스는 측정값이나 기준값이 0이면 FAIL이다.

### 고장을 일부러 주입해서 검증했다

"고쳤다"는 주장을 믿을 근거가 필요했다. `player.gd`에 일부러 파싱 에러를 넣고 돌렸다.

```
ERROR: Failed to load script "res://scripts/player.gd" with error "Parse error".
TEST_ERROR setup_failed player script did not load
exit=1
```

같은 상황에서 이전에는 `TEST_RESULT PASS` / `exit=0`이었다. 이제는 시끄럽게 실패한다.

> **테스트를 고쳤으면 고장을 주입해서 실제로 실패하는지 봐야 한다.** 통과하는 것만 확인하는 것은 절반이다. 실패해야 할 때 실패하는지를 확인하지 않으면, 그 테스트가 무엇을 보증하는지 알 수 없다.

## 5. 시행착오 ③ — `git checkout`으로 커밋 안 한 작업을 날렸다

위의 고장 주입 실험을 하면서 이렇게 했다.

```powershell
# 1. player.gd 끝에 일부러 에러를 추가
# 2. 테스트 실행 → TEST_ERROR 확인 (성공)
# 3. 원상복구
git checkout -- scripts/player.gd
```

3번이 사고였다. `git checkout -- <파일>`은 **마지막 커밋 상태로 되돌린다.** 그런데 M4 작업은 아직 커밋 전이었다. 되돌아간 곳은 "내가 방금 추가한 에러 이전"이 아니라 **M3 시점의 player.gd**였다. 체력·무적·Hurtbox 폴링·사망 처리가 전부 사라졌다(12줄짜리 M1 버전으로 복귀).

복구는 어렵지 않았다. 살아남은 파일들(`player.tscn`의 Hurtbox, `main.gd`, 테스트 스위트)이 필요한 인터페이스를 전부 규정하고 있었기 때문이다. 테스트 코드에서 호출하는 메서드·속성 이름을 뽑아 정확한 명세를 만들고 다시 생성했다. **테스트가 명세 역할을 해준 셈이다.**

### 교훈

- **고장을 주입하기 전에 먼저 커밋한다.** 커밋되지 않은 작업이 있는 상태에서 `git checkout --`을 쓰면 안 된다. 되돌리려면 실험 전 상태를 커밋해 두거나, `git stash`로 대피시켜야 한다.
- 이번 프로젝트의 원칙("작은 단위로 자주 커밋")을 내가 어긴 결과다. M4는 구현부터 검증까지 한 덩어리로 진행하다가 사고를 냈다. 복구 직후 곧바로 커밋했다.
- 그나마 피해가 작았던 이유는 **테스트와 씬 파일이 인터페이스를 문서화하고 있었기** 때문이다. 잘 쓴 테스트는 회귀 방지 장치일 뿐 아니라 복구용 명세이기도 하다.

## 6. 발견 — 지금 밸런스로는 가만히 있어도 안 죽는다

테스트는 다 통과했지만 실제 게임을 90초 돌려도 `PLAYER_HEALTH` 로그가 한 줄도 안 나왔다. M3의 교훈대로 진단 스크립트로 측정했다.

| 조건 | 결과 |
|---|---|
| 기본 (무기 켜짐) | 60초 동안 **최근접 239px**, 피해 0, HP 100 유지 |
| 무기 제거 | **27초에 첫 피격**, 최근접 21.5px, HP 95 |

계산해 보면 당연한 결과다.

- 무기 DPS = 데미지 5 ÷ 쿨다운 0.5초 = **초당 10**
- 적 HP 10 → 한 마리 처치에 **1초**
- 스폰 간격 1.5초 → **초당 0.67마리 생성**

처치 속도(1.0/초)가 생성 속도(0.67/초)를 앞선다. 적이 쌓이질 못하니 플레이어에게 도달하는 개체가 없다. **게임이 성립은 하지만 질 수가 없다.**

이건 버그가 아니라 밸런스 문제이고, 난이도 상승(M7)과 밸런싱(M10)에서 다룰 사안이다. GDD 8절에 실측값과 함께 기록해 뒀다. 지금 수치를 만지면 M7에서 다시 만져야 하므로 건드리지 않았다.

다만 **M4의 피해·사망 경로 자체는 실제 씬에서 검증됐다.** 무기를 끄면 정상적으로 피격되고 `PLAYER_HEALTH` 로그가 찍힌다.

## 7. M1 경계 테스트의 SKIP 해제

M1에서 화면 경계 테스트를 헤드리스에서 SKIP 처리했다. 이유는 "런타임 뷰포트 크기가 틀리게 보고돼서(1280×1280) 검증이 불가능"이었다.

M4에서 플레이어의 경계 계산이 `ProjectSettings` 기반으로 바뀌면서 **이 전제가 사라졌다.** 이제 구현이 런타임 뷰포트를 아예 참조하지 않으므로 헤드리스에서도 정확히 검증된다. SKIP을 해제했다.

```
TEST_CASE screen_bounds_clamp PASS positive=(1268.000,708.000)
  project_settings=(1280.000,720.000) runtime_viewport=(1280.000,1280.000)
```

런타임 뷰포트가 여전히 1280×1280으로 찍히는 것을 **일부러 로그에 남겨뒀다.** 구현이 이 잘못된 값에 의존하지 않는다는 증거이자, 누군가 다시 `get_viewport_rect()`로 바꾸면 즉시 드러나게 하는 장치다.

## 8. 검증 결과 — 전체 20케이스

| 스위트 | 케이스 | 결과 |
|---|---|---|
| test_player_movement | 3 | PASS (SKIP 0) |
| test_enemy_spawn | 4 | PASS |
| test_weapon | 7 | PASS |
| test_player_damage | 5 | PASS |

```
TEST_CASE contact_deals_damage PASS before=100.000 after=95.000 contact_damage=5.000 frame_to_hit=4
TEST_CASE invincibility_blocks_repeat_damage PASS health=95.000
TEST_CASE damage_resumes_after_invincibility PASS before=95.000 after=90.000
TEST_CASE death_at_zero PASS health=0.000 signal_count=1
TEST_CASE enemies_survive_player_death PASS enemy_count_before=3 enemy_count_after=3
```

`enemies_survive_player_death`는 M2에서 미리 넣어둔 `is_instance_valid(target)` 가드가 실제로 동작하는지 확인한다. 플레이어가 죽어도 남은 적들이 에러를 뿜지 않는다.

## 9. 알려진 부채

| 내용 | 조치 시점 |
|---|---|
| 현재 밸런스로는 플레이어가 죽지 않는다 | M7 난이도 상승 / M10 밸런싱 |
| 사망 시 게임오버 라벨만 표시, 재시작 불가 | M8 |
| 피격 시 시각 피드백 없음(깜빡임 등) | M9 |
| 적이 죽어도 경험치를 안 남김 | M5 |

## 10. 다음 단계

M5(경험치와 레벨업). 상세는 [STATUS.md](../STATUS.md).
