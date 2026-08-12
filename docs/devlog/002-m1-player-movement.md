# 개발일지 002 — M1: 플레이어 이동

**날짜**: 2026-08-12
**마일스톤**: M1 (플레이어 WASD 이동)
**결과**: 완료. 자동 테스트 3케이스 통과 + 실제 렌더링 화면 확인.

---

## 1. 오늘 한 일

1. WASD 입력 매핑 (물리 키코드)
2. `player.tscn` / `player.gd` — 8방향 이동, 화면 경계 제한
3. `capture_helper.gd` — 게임 화면을 PNG로 저장하는 검증 도구
4. `tests/test_player_movement.tscn` — 프로젝트 최초의 자동 테스트
5. **시행착오 ①**: 헤드리스 뷰포트 크기 오류로 테스트가 자기충족적이었던 문제 발견·수정

## 2. 입력 매핑 — 왜 "물리 키코드"인가

Godot의 InputMap은 액션 이름(`move_left`)에 실제 키를 묶는 방식이다. 키를 지정하는 방법이 두 가지인데 이 선택이 중요하다.

- `keycode`: 키가 만들어내는 **문자** 기준. QWERTY에서 A키는 'A'지만, 프랑스식 AZERTY 키보드에서 같은 위치의 키는 'Q'다.
- `physical_keycode`: 키보드에서의 **물리적 위치** 기준. 레이아웃과 무관하게 "왼쪽 새끼손가락 자리 키"를 가리킨다.

WASD는 문자 자체가 아니라 **손가락 배치**가 목적인 조작이므로 `physical_keycode`를 썼다. 이걸 `keycode`로 하면 비QWERTY 사용자는 손을 이상한 자리로 옮겨야 한다.

`project.godot`에 들어간 형태 (A키 = 65):

```
move_left={
"deadzone": 0.5,
"events": [Object(InputEventKey,"keycode":0,"physical_keycode":65)
]
}
```

**불확실했던 부분**: 이 `Object(...)` 리터럴에 어떤 속성이 필수인지 확신할 수 없었다. 에디터가 저장하면 `device`, `window_id`, `alt_pressed`, `unicode` 등 십여 개 속성이 전부 나열되지만, 손으로 쓸 때 그걸 다 맞추면 오타 위험만 커진다. **최소 속성만 쓰고 나머지는 생략하는 쪽**을 택했고, 결과적으로 정상 파싱됐다. 생략된 속성은 기본값이 적용된다.

이걸 검증하려고 `main.gd`가 부팅 시 다음을 출력하게 했다:

```
M1_BOOT_OK actions_ok=true version=4.7.1-stable (official)
```

`actions_ok`는 네 액션이 모두 존재하고 각각 이벤트가 하나 이상 바인딩됐는지를 확인한 값이다. **파일이 파싱만 되고 내용이 비어도 게임은 조용히 실행된다** — 그러면 키를 눌러도 아무 일이 없고 원인 찾기가 어렵다. 그래서 "설정이 실제로 들어갔는지"를 부팅 시점에 자가 진단하게 만들었다.

## 3. 이동 구현 — 두 가지 함정

```gdscript
func _physics_process(_delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * speed
	move_and_slide()
```

**함정 ① 대각선 속도**: 오른쪽(1,0)과 아래(0,1)를 동시에 누르면 단순 합은 (1,1)이고 길이가 1.41이다. 그대로 쓰면 대각선 이동이 41% 빨라져서, 플레이어가 항상 대각선으로만 움직이는 게임이 된다. `Input.get_vector()`는 **길이를 1로 제한해서 돌려주므로** 별도 정규화가 필요 없다. (직접 축을 읽어 더할 때는 반드시 `.normalized()`를 해야 한다.)

**함정 ② `_physics_process` vs `_process`**: 이동을 `_process`에 넣으면 화면 주사율에 따라 호출 횟수가 달라져, 144Hz 모니터에서 60Hz보다 빠르게 움직인다. `_physics_process`는 초당 60회로 고정 호출되므로 하드웨어와 무관하게 같은 속도가 나온다.

## 4. 시각 검증 도구 — 게임이 스스로 스크린샷을 찍게 하기

헤드리스 모드는 렌더링을 하지 않아서 화면을 볼 수 없다. 그렇다고 매번 사람이 실행해 보는 건 자동화가 안 된다. 그래서 게임 안에 캡처 기능을 넣었다(`scripts/capture_helper.gd`).

```powershell
& "...\Godot_v4.7.1-stable_win64_console.exe" --path "<프로젝트>" -- "--capture=<경로>.png" "--capture-frames=30"
```

- `--` 뒤의 인자는 엔진이 아니라 **게임에 전달**된다. 게임 안에서 `OS.get_cmdline_user_args()`로 읽는다.
- `--capture=`가 없으면 이 노드는 아무것도 하지 않는다. 평소 플레이에는 전혀 영향이 없다.
- 캡처 후 스스로 종료하므로 CLI가 멈추지 않는다.

**핵심 제약**: 화면을 읽기 전에 렌더링이 끝나기를 기다려야 한다. 안 그러면 아직 그려지지 않은 빈 버퍼를 읽는다. `await RenderingServer.frame_post_draw`로 실제 그리기 완료 시점까지 기다린 뒤 `get_viewport().get_texture().get_image()`로 가져온다.

**또 하나의 제약**: 이 방법은 `--headless`에서는 작동하지 않는다. 렌더링 자체를 안 하기 때문이다. 캡처가 필요하면 `--headless`를 빼고 실제 창을 띄워야 한다.

결과 확인: 어두운 배경 가운데에 하늘색 정사각형(플레이어), 상단에 안내 라벨. 의도대로였다.

## 5. 시행착오 ① — "항상 통과하는 테스트"를 만들 뻔했다

### 문제 발견

이동 테스트 3케이스를 만들어 헤드리스로 돌렸더니 전부 PASS였다. 그런데 로그의 숫자가 이상했다.

```
TEST_CASE screen_bounds_clamp PASS positive=(1268.000,1268.000) viewport=(1280.000,1280.000)
```

**뷰포트가 1280×1280**으로 나왔다. 프로젝트 설정은 1280×**720**이다. 세로가 틀렸는데도 테스트는 PASS였다.

### 원인 추적

같은 테스트를 창 모드로 돌려 비교했다.

| 실행 모드 | 런타임 뷰포트 | 클램프 결과 |
|---|---|---|
| `--headless` | (1280, **1280**) | (1268, **1268**) |
| 창 모드 | (1280, 720) | (1268, 708) |

**헤드리스 모드에서는 뷰포트 높이가 실제 설정과 다르게 보고된다.** 실제 창이 없으니 신뢰할 수 있는 화면 크기가 없는 것이다.

진짜 문제는 그 다음이었다. `player.gd`는 `get_viewport_rect().size`로 경계를 계산하고, **테스트도 똑같이 `get_viewport_rect().size`로 기대값을 계산**했다. 즉 틀린 값끼리 비교하니 언제나 일치한다. 이 테스트는 **절대 실패할 수 없는 테스트**였다.

> 항상 통과하는 테스트는 없는 것보다 나쁘다. 검증했다는 착각을 주기 때문이다.

### 해결

1. 테스트의 기대값 출처를 **런타임 값이 아니라 설계 의도**(`ProjectSettings`의 `viewport_width`/`viewport_height`)로 바꿨다. 검증이란 "구현이 설계와 일치하는가"를 보는 것이지, 구현을 구현과 비교하는 게 아니다.
2. 헤드리스에서는 이 케이스를 **SKIP**으로 처리하고 이유를 출력하게 했다. `DisplayServer.get_name() == "headless"`로 판별한다. 검증 못 한 것을 PASS라고 하지 않는다.
3. 결과 형식을 `TEST_CASE <이름> <PASS|FAIL|SKIP>` / `TEST_RESULT <PASS|FAIL> passed=n failed=n skipped=n`으로 확장했다. **SKIP은 passed에 포함하지 않는다.**

수정 후:

```
# 헤드리스
TEST_CASE screen_bounds_clamp SKIP headless does not report a correct viewport size ...
TEST_RESULT PASS passed=2 failed=0 skipped=1

# 창 모드
TEST_CASE screen_bounds_clamp PASS positive=(1268.000,708.000) project_settings=(1280.000,720.000) ...
TEST_RESULT PASS passed=3 failed=0 skipped=0
```

### 교훈

- **화면 크기에 의존하는 검증은 헤드리스에서 할 수 없다.** 창 모드로 돌려야 한다.
- 테스트 기대값은 구현이 참조하는 것과 **다른 출처**에서 가져와야 한다. 같은 출처를 쓰면 검증이 아니라 동어반복이다.
- 전부 PASS라도 로그의 숫자를 읽어야 한다. 이번엔 숫자를 안 봤으면 그냥 넘어갔을 문제다. 그래서 테스트가 PASS일 때도 측정값을 전부 출력하게 설계한 게 결정적이었다.

## 6. 측정값 참고

- 30 물리 프레임 동안 이동 거리: **96.666 px** (이론값 200px/s × 0.5s = 100px)
  - 약 3.3% 차이는 `physics_frame` 시그널이 물리 처리 **직전**에 발생해 첫 틱이 한 번 덜 계산되는 데서 온다. codex가 미리 예측해서 알려준 부분이고, 허용 오차 5% 안이라 그대로 뒀다.
- 대각선 이동 거리 99.999 px, x·y 성분 각각 70.710 — 정규화가 정확히 작동한다(70.71 × √2 ≈ 100).

## 7. 알려진 부채

| 내용 | 조치 시점 |
|---|---|
| 플레이어 크기 값(12)이 세 곳에 중복 — 충돌 원 반지름, ColorRect 오프셋, `body_radius` | M9 아트 교체 때 정리. 지금 바꾸면 실익 없이 구조만 복잡해짐 |
| 화면 경계를 뷰포트로 계산 중 | M2에서 카메라 도입 시 월드 경계로 교체 (DECISIONS D-007) |

## 8. 다음 단계

M2(적 스폰 + 추적). 상세는 [STATUS.md](../STATUS.md).
