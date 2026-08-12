# 개발일지 003 — M2: 적 스폰과 추적

**날짜**: 2026-08-12
**마일스톤**: M2 (적 스폰 + 추적)
**결과**: 완료. 자동 테스트 4케이스 통과 + 화면에서 적이 몰려오는 것 확인.

---

## 1. 오늘 한 일

1. `enemy.tscn` / `enemy.gd` — 플레이어를 향해 직진하는 적
2. `enemy_spawner.gd` — 화면 밖 원주에서 주기적 스폰, 상한 관리
3. `main.tscn`에 `EnemyContainer` 구조 도입
4. `tests/test_enemy_spawn` — 4케이스 자동 테스트
5. 부팅 토큰 규약 변경 (`BOOT_OK milestone=M2 ...`)

## 2. 구조 결정 — 왜 `EnemyContainer`를 따로 두는가

적을 `Main` 바로 밑에 붙여도 게임은 돌아간다. 그런데 전용 컨테이너 노드를 하나 두고 **모든 적을 반드시 그 아래에만** 붙이도록 했다. 이유는 앞으로 필요한 세 가지 때문이다.

1. **가장 가까운 적 찾기(M3)**: 자동 조준은 매 발사마다 살아 있는 적을 전부 훑어야 한다. 컨테이너가 있으면 `get_children()` 한 번이면 끝난다. 트리 전체를 재귀 탐색하거나 그룹 검색을 돌리는 것보다 명확하고 빠르다.
2. **개수 상한 관리**: `get_child_count()`가 곧 현재 적 수다. 별도 카운터 변수를 두면 적이 죽을 때마다 증감을 맞춰야 하고, 한 번 어긋나면 조용히 틀린 채로 돈다. **상태를 두 곳에 두지 않는 게 안전하다.**
3. **나중에 오브젝트 풀링으로 교체(D-006)**: 생성·소멸 지점이 스포너 한 곳에 모여 있으면 교체가 국소적이다. 호출부가 흩어지면 나중에 전부 찾아 고쳐야 한다.

그리기 순서도 신경 썼다. 씬 트리에서 **먼저 나오는 노드가 먼저 그려진다**(= 뒤에 깔린다). `EnemyContainer`를 `Player`보다 앞에 배치해서 적이 플레이어 뒤로 그려지게 했다. 서바이버류는 적이 몰리면 플레이어를 가리는데, 자기 캐릭터가 안 보이면 조작이 불가능하다.

## 3. 적 AI — 경로 탐색을 일부러 쓰지 않았다

```gdscript
var direction := (target.global_position - global_position).normalized()
velocity = direction * speed
move_and_slide()
```

Godot에는 `NavigationAgent2D`라는 경로 탐색 노드가 있지만 **쓰지 않았다.**

- 이 게임의 맵은 장애물 없는 개활지다. 최단 경로는 언제나 직선이므로 경로 탐색이 계산할 게 없다.
- 후반에 적이 100마리 이상 나온다. 매 프레임 100개의 경로를 재계산하면 프레임이 무너진다.
- 서바이버류의 적 AI는 원래 단순한 게 정답이다. 똑똑한 적이 아니라 **많은 적**이 이 장르의 압박 수단이다.

**방어 코드 하나가 중요하다**: `is_instance_valid(target)`로 매번 확인한다. 플레이어가 사라진 뒤(M4의 게임오버) 남은 적들이 해제된 객체를 참조하면 **모든 적이 동시에 에러를 뿜는다.** 아직 죽음이 없는 M2에서 미리 넣어뒀다.

## 4. 스폰 위치 — 화면 밖 원주

```gdscript
var spawn_radius := design_screen_size.length() / 2.0 + spawn_margin
var angle := randf() * TAU
enemy.global_position = screen_center + Vector2(cos(angle), sin(angle)) * spawn_radius
```

`design_screen_size.length()`는 1280×720 사각형의 **대각선 길이**(1468.6)다. 그 절반(734.3)이 화면 중심에서 가장 먼 모서리까지의 거리다. 즉 **반지름 734.3짜리 원은 화면 사각형을 완전히 감싼다.** 여기에 여유 60을 더한 794.3을 반지름으로 쓰면, 원 위의 어느 지점을 골라도 반드시 화면 바깥이다.

테스트로 확인한 실측값이 정확히 일치했다:

```
TEST_CASE spawn_position_offscreen PASS inside_count=0 spawn_count=20 minimum_center_distance=794.302
```

**M1의 교훈을 여기에 적용했다.** 화면 크기를 `get_viewport_rect()`로 읽으면 헤드리스에서 1280×1280이라는 틀린 값이 나와 스폰 위치가 어긋난다. 그래서 `ProjectSettings`에서 설계 크기를 읽는다. 덕분에 이 로직은 헤드리스에서도 정확히 검증된다.

> 사각형을 감싸는 원의 반지름 = 대각선의 절반. 화면 밖 스폰의 표준 공식이다.

## 5. 스포너 방어 코드

스포너는 씬에서 세 가지를 주입받는다: 적 씬(PackedScene), 적을 담을 컨테이너, 추적 대상. 이 연결이 하나라도 끊기면 **게임은 멀쩡히 실행되고 적만 안 나온다.** 원인을 찾기가 매우 어려운 종류의 버그다.

그래서 `_ready()`에서 전부 검사하고, 문제가 있으면 `push_error()`로 구체적인 메시지를 남긴 뒤 스폰을 비활성화한다. `push_error`는 Godot 콘솔과 stderr에 찍히므로 CLI 검증에서 바로 잡힌다. **조용한 실패를 시끄러운 실패로 바꾸는 것**이 목적이다.

## 6. 테스트에 `spawn_one()` 공개 메서드를 둔 이유

스폰은 타이머 기반이라, 테스트가 "적 20마리의 위치 분포"를 확인하려면 실제로 30초를 기다려야 한다. 그래서 **한 마리를 즉시 스폰하는 공개 메서드**를 따로 뒀다. 타이머는 이 메서드를 호출할 뿐이다.

- 타이머 경로: 실제 게임 동작
- 직접 호출 경로: 테스트가 시간을 기다리지 않고 20번 샘플링

**시간에 의존하는 로직은 시간을 건너뛸 수 있는 문을 하나 열어두면 테스트가 쉬워진다.** 반대로 이 문이 없으면 테스트가 느려지거나, 대기 시간을 줄이려고 프로덕션 값을 건드리게 된다.

타이머는 `TIMER_PROCESS_PHYSICS` 모드로 뒀다. 물리 프레임 기준으로 동작해야 테스트의 `await get_tree().physics_frame`과 같은 시간축을 쓰게 되고, 결과가 프레임률에 흔들리지 않는다.

## 7. 검증 결과

```
TEST_CASE periodic_spawning        PASS actual_count=4 interval=0.100 frames=30
TEST_CASE spawn_position_offscreen PASS inside_count=0 spawn_count=20 minimum_center_distance=794.302
TEST_CASE enemies_chase_player     PASS initial_distance=794.302 final_distance=765.301 actual_delta=29.001 expected_delta=30.000
TEST_CASE max_enemies_cap          PASS peak_count=5 final_count=5 cap=5
TEST_RESULT PASS passed=4 failed=0 skipped=0
```

추적 케이스: 30 물리 프레임(0.5초) × 속도 60 = 30px 접근이 기대값인데 실측 29.001px. M1에서 확인한 첫 틱 오차와 같은 원인이다.

화면 캡처로도 확인했다. 어두운 배경에 중앙의 하늘색 플레이어, 그 주위로 빨간 적들이 사방에서 접근하는 모습이 나왔다.

이번 마일스톤은 **시행착오 없이 한 번에 통과**했다. M1에서 얻은 두 교훈(화면 크기는 ProjectSettings에서, 테스트 기대값은 설계 의도에서)을 작업지시서에 미리 적어 보낸 것이 유효했다.

## 8. 부팅 토큰 규약 변경

M0은 `M0_BOOT_OK`, M1은 `M1_BOOT_OK`였다. 마일스톤마다 검증 명령의 기대 문자열이 바뀌면 문서를 계속 고쳐야 한다. 다음처럼 바꿨다.

```
BOOT_OK milestone=M2 actions_ok=true version=4.7.1-stable (official)
```

이제 검증은 `BOOT_OK`만 확인하면 되고, `milestone=` 값은 참고 정보가 된다.

## 9. 알려진 부채

| 내용 | 조치 시점 |
|---|---|
| 적들이 서로 겹쳐서 한 덩어리로 뭉친다 (분리 로직 없음) | M7. 지금은 적이 적어 문제가 드러나지 않고, 분리 로직은 성능과 직결되므로 밀도가 높아진 뒤 실측하며 넣는 게 맞다 |
| 적이 플레이어에 닿으면 물리적으로 밀기만 하고 아무 일도 없음 | M4 (피해 처리) |
| 화면 구석의 플레이어 근처(약 60px 밖)에 적이 생길 수 있음 | 허용. 화면 밖인 것은 보장되므로 갑툭튀는 아니다 |

## 10. 다음 단계

M3(자동 공격). 상세는 [STATUS.md](../STATUS.md).
