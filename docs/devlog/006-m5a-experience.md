# 개발일지 006 — M5a: 경험치 젬과 자석 수집

**날짜**: 2026-08-13
**마일스톤**: M5a (경험치 드랍 / 자석 수집 / 레벨 곡선)
**결과**: 완료. 테스트 5스위트 24케이스 통과.
**시행착오 6건** — 이번 마일스톤은 시행착오 자체가 성과다. 절반은 **협업 도구의 한계**에서 나왔다.

---

## 1. 오늘 한 일

1. `xp_gem.tscn` / `xp_gem.gd` — 초록 젬, 자석에 끌려오다 수집되면 경험치 지급
2. `pickup_spawner.gd` — 적 사망 시 젬 드랍
3. 플레이어 `MagnetArea` (반경 60) — 범위 안 젬을 끌어당김
4. `level_system.gd` — 경험치 곡선 `5 + (레벨-1) × 3`, 다중 레벨업 처리
5. `tests/test_experience` — 5케이스

## 2. M5를 둘로 쪼갠 이유

원래 M5는 "경험치 + 레벨업 UI"였는데 **M5a(수집)와 M5b(UI)로 분리**했다.

레벨업 UI는 `get_tree().paused = true`로 트리를 멈추는데, 여기에 Godot 특유의 함정이 있다(`process_mode` 문제). 수집 로직과 일시정지 UI를 한 번에 넣으면 문제가 생겼을 때 **어느 쪽이 원인인지 가려내기 어렵다.** 실제로 M5a만으로도 시행착오가 6건 나왔으니 분리 판단은 옳았다.

## 3. 구조 — 적은 젬을 모른다

```
적 사망 → died(위치) 시그널 → EnemySpawner가 연결해 둔 PickupSpawner.on_enemy_died()
                            → 젬 생성 → 자석 범위 진입 → 플레이어로 이동 → 수집 → add_experience()
                            → LevelSystem이 곡선 계산 → leveled_up 시그널
```

**적 스크립트는 젬의 존재를 모른다.** 자기가 죽었다고 알릴 뿐이다. 시그널 연결은 적을 만드는 쪽(`EnemySpawner`)이 그 자리에서 한다. 이렇게 하면 나중에 "보스는 젬 5개를 떨군다"거나 "특정 적은 회복 아이템을 떨군다" 같은 변경이 적 스크립트를 건드리지 않고 가능하다.

젬도 마찬가지로 **플레이어의 내부 구조를 모른다.** `target.add_experience(value)`만 호출하고, 플레이어가 그걸 내부 `LevelSystem`으로 넘긴다. 젬이 `Player/LevelSystem` 경로를 알고 있으면 플레이어 씬 구조를 바꿀 때마다 젬이 깨진다.

자석은 M4의 허트박스와 같은 이유로 **시그널이 아니라 폴링**이다. 이미 겹쳐 있는 젬은 `area_entered`를 다시 쏘지 않는다.

## 4. 시행착오 ① — 스크립트에 함수를 중복 선언

M5a 로직이 `main.gd`에 **두 번째 `_process()`로 덧붙여졌다.** 기존 `_process()`는 생존 시간을 세고 있었다.

```
Parse Error: Function "_process" has the same name as a previously declared function.
ERROR: Failed to load script "res://scripts/main.gd" with error "Parse error".
```

M4에서 추가한 "스크립트 변경 후 `--check-only` 문법 검사" 절차가 **즉시** 잡아냈다. 절차 하나가 값을 한 셈이다.

덧붙여진 코드에는 구조적 문제도 있었다.
- 레벨 시스템 시그널 연결을 `_process` 안에서 플래그로 재시도 — `_ready()`에서 한 번이면 될 일
- 정적 라벨 텍스트를 **매 프레임** 재할당
- 기존 부팅 줄은 `milestone=M4`인데 `BOOT_MILESTONE M5a`를 따로 출력
- 식별자에 마일스톤 번호(`m5a_boot_logged`) — 한 마일스톤만 지나도 의미 없는 이름

전부 되돌려 보내 정리했다.

## 5. 시행착오 ② — 씬 파일의 섹션 순서

같은 "덧붙이기" 패턴이 이번엔 씬 파일에서 났다.

```
ERROR: res://scenes/player.tscn:13 - Parse Error: Unknown tag 'ext_resource' in file.
```

`.tscn`은 섹션 순서가 엄격하다.

```
[gd_scene ...]        ← 헤더
[ext_resource ...]    ← 외부 리소스 전부
[sub_resource ...]    ← 내부 리소스 전부
[node ...]            ← 노드 전부
```

새 `ext_resource`가 `sub_resource` 뒤에 끼어들어 **씬 전체가 로드 실패**했다. 덤으로 `load_steps=6`도 틀렸다(정답 8). 이 값은 `ext_resource 개수 + sub_resource 개수 + 1`이라 리소스를 추가하면 반드시 같이 고쳐야 한다.

> 이때 강화해 둔 테스트 하네스가 제 값을 했다. `TEST_ERROR setup_failed player_scene missing` + 종료 코드 1로 즉시 멈췄다. M4 이전이었다면 조용히 PASS였을 상황이다.

## 6. 시행착오 ③ — GDScript 람다는 값으로 캡처한다

레벨 곡선 테스트가 실패했다.

```
TEST_CASE multiple_levels_from_one_grant FAIL level=4 remainder=6.000 level_up_signals=0
```

레벨 4, 잔여 6은 **정답이다**. 30 경험치로 5 → 8 → 11을 소모하면 정확히 그렇게 된다. 틀린 건 `level_up_signals=0` 하나뿐이었다.

```gdscript
var level_up_count: int = 0
level_up_signal.connect(func(_new_level: int) -> void: level_up_count += 1)
```

**GDScript의 람다는 지역 변수를 값으로 캡처한다.** 람다 안의 `level_up_count`는 자기만의 복사본이고, 바깥 변수는 영원히 0이다. 에러도 경고도 없이 그냥 틀린 숫자가 나온다.

`Array` 같은 참조형을 상자로 쓰거나 멤버 변수를 써야 한다. 구현이 아니라 **테스트가 틀렸던 경우**다. 측정 도구를 먼저 의심하는 습관이 여기서 값을 했다(M3의 캡처 도구 사건과 같은 교훈).

## 7. 시행착오 ④ — 씬 파일에서 `script`보다 먼저 온 속성은 버려진다

테스트는 다 통과하는데 실제 게임에서 **젬이 하나도 안 떨어졌다.** 30초 스크린샷에 초록 젬이 전무했다.

원인 중 하나가 이것이었다.

```
[node name="EnemySpawner" type="Node" parent="."]
pickup_spawner_path = NodePath("../PickupSpawner")   ← script보다 먼저
script = ExtResource("5_spawner")
enemy_scene = ExtResource("4_enemy")                  ← script 뒤라 정상
```

`.tscn`의 속성은 **파일에 적힌 순서대로** 적용된다. `script`가 할당되기 전에는 그 노드가 그냥 `Node`라서 스크립트가 선언한 `pickup_spawner_path` 같은 속성이 존재하지 않는다. 그래서 그 값은 **조용히 버려진다.**

에러도 경고도 없다. 스포너는 멀쩡히 적을 생성하고, 젬 관련 기능만 죽어 있다. 나머지 세 속성은 `script` 뒤에 있어서 정상 작동했기 때문에 더 헷갈렸다.

> **규칙: 노드 블록에서 `script = ExtResource(...)`는 스크립트가 선언한 어떤 속성보다도 먼저 와야 한다.**

## 8. 시행착오 ⑤ — 전역 훅으로 시그널을 연결하면 안 된다

같은 문제를 파다가 두 번째 원인을 발견했다. 작업지시서에는 "적을 생성할 때 그 자리에서 `died`를 연결하라"고 적었는데, 실제 구현은 이랬다.

```gdscript
func _enter_tree() -> void:
	get_tree().node_added.connect(_on_tree_node_added)

func _on_tree_node_added(node: Node) -> void:
	if not node.has_signal("died"):
		return
	node.get("died").connect(Callable(pickup_spawner, "on_enemy_died"))
```

`get_tree().node_added`는 **씬 트리에 노드가 추가될 때마다** 호출된다. 투사체, 젬, UI, 전부. 게임 내내 도는 전역 콜백이다.

더 나쁜 건 판정 기준이다. "`died`라는 이름의 시그널을 가진 노드"에 전부 연결하는데, **플레이어도 `died` 시그널을 갖고 있다.** 플레이어의 `died`는 인자가 없고 적의 것은 위치를 넘긴다. 플레이어가 죽는 순간 인자 개수가 안 맞는 핸들러가 불린다.

객체를 만드는 쪽에서 그 자리에서 연결하도록 되돌렸다. **연결 지점이 생성 지점과 같으면 무엇이 무엇에 연결되는지 한눈에 보인다.**

## 9. 시행착오 ⑥ — 물리 처리 중에는 충돌 노드를 추가할 수 없다

두 배선 문제를 고치자 젬이 떨어지기 시작했는데, 이번엔 새 에러가 나왔다.

```
ERROR: Can't change this state while flushing queries.
       Use call_deferred() or set_deferred() to change monitoring state instead.
   at: area_set_shape_disabled (godot_physics_server_2d.cpp:354)
   GDScript backtrace:
       [0] drop_gem (res://scripts/pickup_spawner.gd:42)
       [1] on_enemy_died (res://scripts/pickup_spawner.gd:49)
```

호출 사슬을 따라가면 원인이 명확하다.

```
물리 스텝 진행 중
 └ 투사체의 body_entered 시그널 발생        ← 물리 스텝 '안'이다
    └ enemy.take_damage() → 사망 → died 발생
       └ PickupSpawner.drop_gem()
          └ 충돌 도형을 가진 Area2D(젬)를 트리에 추가  ← 물리 서버가 거부
```

Godot의 물리 서버는 스텝을 처리하는 동안 충돌 객체 목록이 바뀌는 것을 허용하지 않는다. **물리 스텝 중에 발생하는 시그널 안에서 충돌 도형을 가진 노드를 추가하거나 `monitoring`을 직접 바꾸면 안 된다.**

```gdscript
func on_enemy_died(enemy_position: Vector2) -> void:
	drop_gem.call_deferred(enemy_position)   # 물리 스텝이 끝난 뒤 실행
```

같은 위험이 있는 곳을 함께 점검했다.

| 위치 | 판정 |
|---|---|
| `pickup_spawner.on_enemy_died` → 젬 추가 | **수정** — `call_deferred` |
| `player._die()` → `_hurtbox.monitoring = false` | **수정** — `set_deferred("monitoring", false)`. 접촉 피해 폴링이 `_physics_process`에서 돌므로 같은 위험 |
| `projectile` 자기 해제 (`body_entered` 안) | 안전 — `queue_free()`는 원래 프레임 끝까지 미뤄진다 |
| `xp_gem` 자기 해제 (`_physics_process` 안) | 안전 — 같은 이유 |

`queue_free()`가 안전한 이유가 핵심이다. 이 함수는 즉시 지우지 않고 **프레임 끝에 지우도록 예약**한다. 반면 `add_child()`와 속성 직접 대입은 즉시 반영되므로 위험하다.

## 10. 시행착오 ⑦ — codex는 이 PC에서 파일을 읽지 못한다

가장 큰 워크플로 발견이다. 작업을 두 번 거부당했다.

> "I can't safely edit this under the standing constraint: this session has no file-read tool besides shell access, and you explicitly prohibited shell commands."

M0에서 codex의 샌드박스가 프로세스를 못 띄운다는 걸 확인하고 "셸 금지"를 표준 제약으로 넣었는데, **codex는 파일을 읽을 때도 셸을 쓴다.** 즉 codex는 이 PC에서 기존 파일을 볼 수 없다.

그런데도 M1~M4는 잘 굴러갔다. 대부분의 작업이 **새 파일 생성**이었거나, 작업지시서에 필요한 맥락을 충분히 적어놨기 때문이다. 기존 파일을 정확히 읽어야 하는 순간(중복 함수 정리, 씬 순서 교정)에야 한계가 드러났다.

### 대응

**작업지시서에 수정 대상 파일의 현재 내용을 통째로 붙여 넣는다.** 이 방식으로 다시 보내자 즉시 처리됐다.

| 작업 종류 | 방식 |
|---|---|
| 새 파일 생성 | 명세만 적어 위임 (기존과 동일) |
| 기존 파일 수정 | **파일 전문을 지시서에 첨부**해 위임 |
| 한두 줄 자명한 수정 | Claude가 직접 (왕복 비용이 이득보다 큼) |

이번의 `call_deferred` 수정 두 줄은 마지막 경우라 직접 처리했다. 거부 두 번으로 이미 왕복을 낭비한 상태였고, 수정 내용이 완전히 확정적이었다.

## 11. 부수 관찰 — 프레임률이 실행마다 극단적으로 다르다

M3에서 캡처 도구를 시간 기준으로 바꾸면서 `frames_rendered`를 함께 찍게 해뒀는데, 그 값이 이렇게 나왔다.

| 실행 | 경과 | 렌더 프레임 | 실효 fps |
|---|---|---|---|
| M4 캡처 | 19.99초 | 1,199 | **60** |
| M5a 캡처 | 29.96초 | 176,081 | **5,877** |

같은 PC, 같은 게임인데 100배 차이다. 창 포커스나 vsync 상태에 따라 갈리는 것으로 보이지만 확증은 없다.

중요한 건 **이 변동을 지금은 감지할 수 있다는 것**이다. M3에서 프레임 수를 기준으로 기다렸다면 어떤 실행은 30초를, 어떤 실행은 0.3초를 기다렸을 것이고, 그 차이를 알 방법조차 없었을 것이다. 시간 기준으로 바꾼 판단(D-011)이 여기서 검증됐다.

## 12. 알려진 부채

| 내용 | 조치 시점 |
|---|---|
| 젬은 적이 죽은 자리(약 350px 밖)에 떨어지는데 자석 반경은 60px | 정상 동작이다. 플레이어가 이동해 주워야 한다. 다만 **가만히 있으면 레벨업이 불가능**하므로 M5b 검증에는 강제 경험치 지급이 필요하다 |
| 안 주운 젬이 무한히 쌓인다 (수명 없음) | 장르 관행상 정상이나, 장시간 방치 시 노드 증가. M7 성능 측정에서 재검토 |
| 업그레이드 선택이 없어 레벨업의 의미가 없음 | M5b / M6 |

## 13. 다음 단계

M5b(레벨업 일시정지 UI). 상세는 [STATUS.md](../STATUS.md).
