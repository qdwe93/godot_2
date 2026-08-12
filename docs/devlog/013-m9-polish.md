# 개발일지 013 — M9: 폴리시

**날짜**: 2026-08-13
**마일스톤**: M9 (타격 피드백 / 화면 흔들림 / 가독성)
**결과**: 완료. **14스위트 80케이스 통과.** 시행착오 0건.

---

## 1. 오늘 한 일

1. CC0 VFX 스프라이트시트 확보 — **다운로드 없이**
2. `hit_effect.tscn` / `hit_effect.gd` — 플립북 1회 재생 후 자가 해제
3. `effect_spawner.gd` — 적 사망 시 이펙트 생성
4. `screen_shake.gd` — 피격 시 화면 흔들림
5. `tests/test_effects` — 6케이스

## 2. 에셋 — 받기 전에 있는 것부터 확인했다

외부 CC0 에셋 다운로드를 허가받았지만, 먼저 **PC에 이미 있는 것**을 확인했다. M0의 환경 조사에서 `C:\Program Files (x86)\Godot\`에 에셋 팩 zip 몇 개가 있는 걸 기록해뒀기 때문이다.

`brackeys_vfx_bundle.zip`(26.9MB) 안에 PNG가 199개 있었고, 라이선스 파일을 열어보니 이랬다.

```
LICENSE for all assets: Creative Commons Zero (CC0)

CREDIT:
PARTICLE TEXTURES by: Picster, Kenney (https://kenney.nl/assets/particle-pack)
FLIPBOOKS by Thomas Iché
PRE-DRAWN SPRITESHEETS by CodeManu (https://codemanu.itch.io/vfx-free-pack)
```

**CC0이고 이미 있다.** 다운로드가 불필요해졌다. 필요한 두 장만 프로젝트로 추출했다.

| 파일 | 크기 | 격자 | 용도 |
|---|---|---|---|
| `impact_white_6x4.png` | 36KB | 6×4 (24프레임) | 사망 이펙트 |
| `electric_ring_6x5.png` | 28KB | 6×5 (30프레임) | 예비 |

라이선스 원문도 `assets/vfx/LICENSE.txt`로 함께 넣었다. **에셋을 쓰면 라이선스를 저장소 안에 같이 둔다** — 나중에 출처를 되짚을 때 zip 파일이 남아 있으리라는 보장이 없다.

> 26.9MB짜리 팩 전체를 넣지 않고 64KB만 가져온 이유: 저장소는 필요한 것만 담아야 하고, 안 쓰는 197장은 나중에 "이거 어디서 쓰지?" 하는 혼란만 만든다.

## 3. 플립북 재생 — `AnimatedSprite2D` 대신 `Sprite2D`

스프라이트시트 애니메이션의 정석은 `AnimatedSprite2D` + `SpriteFrames` 리소스다. 하지만 `SpriteFrames`는 프레임을 하나씩 등록해야 하는 리소스라, 손으로 `.tscn`에 쓰면 24줄이 넘고 오타 위험도 크다.

대신 `Sprite2D`의 `hframes` / `vframes`를 쓰면 격자 정보만 주고 `frame` 인덱스를 코드로 넘기면 된다.

```gdscript
hframes = 6
vframes = 4
frame = int(elapsed * frames_per_second)   # 0..23
```

24프레임 애니메이션이 속성 두 개와 한 줄로 끝난다. 게다가 `texture_columns` / `texture_rows`를 익스포트로 빼두면 **6×5짜리 다른 시트도 같은 씬을 재사용**할 수 있다.

**자가 해제가 핵심이다.** 이펙트는 적이 죽을 때마다 생기므로, 마지막 프레임 뒤 `queue_free()`를 빠뜨리면 누수가 빠르게 쌓인다. 테스트 케이스 1이 이것만 검사한다.

## 4. 이펙트를 적의 자식으로 붙이면 안 된다

사망 이펙트를 죽은 적의 자식으로 붙이는 건 자연스러워 보이지만 **동작하지 않는다.** 적은 죽는 즉시 `queue_free()`되고, 자식도 함께 사라진다. 이펙트는 화면에 나타나지도 못한다.

그래서 별도의 `EffectContainer`에 붙인다. M2에서 정한 "종류별 컨테이너" 규약이 여기서도 그대로 적용됐다.

연결 방식도 M8a의 킬 카운트와 같다. `EnemyContainer`의 `child_entered_tree`로 새 적을 잡아 그 적의 `died` 시그널에 연결한다. `get_tree().node_added` 전역 훅은 쓰지 않는다 — 플레이어도 `died`를 갖고 있어서 무관한 노드까지 걸린다(M5a에서 겪음).

한 가지는 주석으로 명시해뒀다. 이펙트 생성은 물리 스텝 중에 발생하는 `died` 시그널 안에서 일어나지만, **이펙트는 충돌 도형이 없는 순수 `Sprite2D`라 `add_child`가 안전하다.** M5a에서 젬(Area2D)을 같은 자리에서 추가했다가 물리 서버에 거부당한 적이 있어서(D-015), 나중에 누군가 이걸 보고 불필요하게 `call_deferred`로 "고치는" 것을 막기 위해서다.

## 5. 화면 흔들림 — 반드시 정확히 복원해야 한다

흔들기는 대상의 `position`에 매 프레임 랜덤 오프셋을 더하는 것이다. 함정은 끝날 때다.

**흔들림이 끝나면 원래 위치로 정확히 되돌려야 한다.** 마지막 오프셋이 남으면 흔들 때마다 월드 전체가 조금씩 밀린다. 한 번에 몇 픽셀이라 즉시 눈치채기 어렵고, 한참 뒤 "화면이 왜 비뚤어졌지?"가 된다. 원인 추적이 매우 어려운 종류다.

테스트 케이스 5·6이 **최종 오차가 정확히 0인지**를 검사한다(`final_delta=0.0000`). 두 번 연속 호출해도 누적되지 않고 한 번의 지속시간 안에 끝나는지도 함께 본다.

수치는 **5px / 0.15초**로 잡았다. 이 게임은 화면에 적이 수십 마리 있고 플레이어가 그 사이를 빠져나가야 한다. 흔들림이 크면 적 위치를 놓쳐서 조작이 불가능해진다. **연출이 플레이를 방해하면 연출이 아니라 버그다.**

### 부수 작업 — 배경을 40px 넓혔다

흔들기 대상이 `Main`이라 배경 `ColorRect`도 같이 움직인다. 배경이 정확히 1280×720이면 흔들리는 순간 가장자리에 검은 띠가 보인다. 배경을 사방 40px 넓혀 해결했다.

## 6. 카메라를 넣지 않았다

흔들림은 보통 `Camera2D`로 구현한다. 하지만 이 프로젝트는 카메라가 없고, 넣는 순간 **화면 경계 계산이 전부 바뀐다**(D-007). 플레이어 이동 제한, 적 스폰 위치, 투사체 제거가 모두 화면 좌표를 쓰고 있다.

M9의 목적은 손맛이지 구조 변경이 아니다. `Main`의 위치를 직접 흔드는 것으로 같은 효과를 얻었다. **연출을 위해 구조를 바꾸는 것은 순서가 뒤바뀐 것이다.**

## 7. 하지 않은 것

| 항목 | 이유 |
|---|---|
| 사운드 | 이번 팩에 오디오가 없었다. 별도 다운로드가 필요한데, 시각 폴리시만으로 손맛의 대부분이 확보됐다고 판단해 미뤘다 |
| 비치명타 히트 스파크 | `projectile.gd` 수정이 필요하다. M9는 기존 스크립트 무수정 원칙으로 진행했고, 사망 이펙트만으로도 타격감이 충분했다. `spawn_hit()`은 이미 만들어져 있어 나중에 한 줄로 연결 가능 |
| 스프라이트 아트 교체 | 도형 플레이스홀더가 색·크기 대비로 충분히 읽힌다. 적 3종이 빨강/주황/자주로 구분되고 크기도 다르다 |

## 8. 검증 결과

```
TEST_CASE hit_effect_frees_itself        PASS frames_advanced=24 last_frame=23
TEST_CASE effect_advances_frames         PASS first_frame=0 last_frame=3
TEST_CASE enemy_death_spawns_in_container PASS container_effects=1 enemy_effects=0
TEST_CASE death_effect_scales_with_enemy PASS small_scale=0.55 large_scale=1.65
TEST_CASE shake_displaces_and_restores   PASS displacement=3.0000 final_delta=0.0000
TEST_CASE shake_does_not_stack           PASS elapsed_frames=3 final_delta=0.0000
```

전체 14스위트 80케이스 통과, 실제 게임 50초 실행 시 에러 0건. 캡처로 경험치 바가 이제 화면에서 보이는 것(HUD에 두 번째 바)과 피격으로 HP가 95/100으로 줄어든 것을 확인했다.

## 9. 다음 단계

M10(밸런싱) — **움직이는 플레이어 기준**으로 생존 시간을 실측하고 수치를 조정한다. 정지 상태 74초는 실제 난이도가 아니다.
