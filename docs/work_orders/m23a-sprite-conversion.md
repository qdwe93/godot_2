# M23-A 작업지시서 — 젬·투사체·궤도구를 그림으로

> **쓰는 법** (CLAUDE.md "codex 위임 — 표준 호출"):
>
> ```powershell
> Get-Content docs\work_orders\m23a-sprite-conversion.md -Raw | codex exec -C "C:\Workspaces\game_make\test_godot_2" -s workspace-write -m gpt-5.6-sol -c model_reasoning_effort="high" 2>&1 | Select-Object -Last 40
> ```
>
> 배경은 [STATUS.md](../STATUS.md) 의 "M23 후보 A", 경위는
> [devlog 023](../devlog/023-m22-bright-floor.md).

---

## 지켜야 할 실행 제약

**Do NOT run any shell commands. The Windows sandbox cannot spawn processes on this
machine; every shell call will fail. Use file read/write (apply_patch) only.
Do NOT run git. Do NOT run python. Do NOT run Godot.**

파일 읽기는 된다. **고치기 전에 반드시 해당 파일을 읽어라.**

실행·임포트·테스트·측정·git 은 전부 사람이 한다. 마지막 절의 명령 목록을
출력으로 남겨라.

## 먼저 읽을 파일

- `scenes/xp_gem.tscn`, `scenes/projectile.tscn`, `scenes/orbital.tscn`
- `scripts/projectile.gd`, `scripts/xp_gem.gd`, `scripts/orbital.gd`
- `tools/sprite_outline.py`, `tools/check_sprite_luminance.py`
- `tests/test_visual_hierarchy.gd`
- `CLAUDE.md` 의 ".tscn 편집" 절

주석과 문서는 **한글**로 쓴다. 기존 파일의 어조를 따른다 (무엇이 아니라 **왜**를 적는다).

---

## 배경

M22 에서 바닥이 밝은 회보라 포석 타일이 됐고, 스프라이트 5종
(player / enemy_basic / enemy_fast / enemy_tank / enemy_boss)에는
`tools/sprite_outline.py` 가 어두운 외곽선을 구웠다.

**젬·투사체·궤도구는 그 처리를 못 받았다.** 씬이 텍스처가 아니라 `ColorRect`
단색 사각형을 그리기 때문이다. M22 는 임시로 `Sprite` 뒤에 2px 큰 `Outline`
ColorRect 를 깔아 대비만 맞춰 뒀다.

그런데 **쓸 그림이 이미 디스크에 있고 한 번도 안 쓰였다.**

| 파일 | 캔버스 | 실제 모양 | 지금 화면 |
|---|---|---|---|
| `assets/sprites/xp_gem.png` | 1024 | 초록 **마름모** | 초록 정사각형 |
| `assets/sprites/projectile.png` | 1254 | 주황 **짧은 캡슐** | 주황 정사각형 |
| `assets/sprites/orbital.png` | 1024 | 청록 **원형 코어** | 청록 정사각형 |

`docs/ASSETS.md` 3-0절의 형태 규칙(마름모 / 짧은 캡슐 / 원형)과도, 레퍼런스
("젬이 초록 다이아몬드")와도 맞는다.

이 작업은 셋을 **실제로 그리게** 만들고, 그 결과 검사 도구가 다시
"그려지는 것만 검사한다"로 합쳐지게 하는 것이다.

**밸런스 수치는 하나도 건드리지 않는다.**

---

## TASK 1 — `tools/sprite_outline.py` 에 세 개 추가

`DISPLAY_SIZES` 표에 넣는다.

| 이름 | 표시 크기 |
|---|---:|
| `xp_gem` | **20** |
| `projectile` | **16** |
| `orbital` | **28** |

⚠️ **`.tscn` 의 `offset_*` 는 반지름이라 두 배가 표시 크기다.**
젬은 `-10..10` 이므로 20px 이지 10px 이 아니다. 예전 `check_sprite_luminance.py`
의 `SPEC` 이 10/8/14 를 쓰고 있었는데 그건 **절반값이라 틀린 값이다.**
한글 주석으로 이 사실을 적어 둘 것.

기존 두께 규칙 `t_display = clamp(0.05 * 표시크기, 2.0, 5.0)` 은 그대로 둔다.
셋 다 하한 2.0px 에 걸린다 (M22 에서 임시 `Outline` 을 2px 로 깐 것과 같은 값이다).

`--revert` 와 `assets/sprites_src/` 시딩 동작은 건드리지 않는다. 다만 **시딩은
디렉터리가 없을 때만 일어나므로**, 이미 존재하는 지금은 세 원본이 보관되지 않는다.
`_seed_sources()` 를 고쳐 **`sprites_src` 에 없는 이름만 개별적으로 채우도록**
바꿔라. 이미 있는 파일은 절대 덮어쓰지 마라 — 외곽선이 구워진 결과를 원본
자리에 되돌려 넣으면 다음 실행에서 외곽선이 두 번 구워진다.

## TASK 2 — 세 씬을 `Sprite2D` 로 바꾼다

각 씬에서:

1. M22 에서 넣은 **`Outline` ColorRect 노드를 지운다.** 구운 외곽선이 대체한다
2. `Sprite` 노드의 타입을 `ColorRect` → **`Sprite2D`** 로 바꾼다
3. `offset_*` / `color` / `mouse_filter` 속성을 지우고 `texture` 와 `scale` 을 준다

`scale` = 표시 크기 ÷ 텍스처 캔버스 크기. **정확한 값을 쓸 것**:

| 씬 | 텍스처 | 표시 | `scale` |
|---|---:|---:|---|
| `xp_gem.tscn` | 1024 | 20 | `Vector2(0.01953125, 0.01953125)` |
| `projectile.tscn` | 1254 | 16 | `Vector2(0.012759171, 0.012759171)` |
| `orbital.tscn` | 1024 | 28 | `Vector2(0.02734375, 0.02734375)` |

`ColorRect` 는 좌상단 기준이고 `Sprite2D` 는 **중심 기준**이라 `offset` 없이
그 자리에 온다. 한글 주석으로 남길 것.

`.tscn` 규칙을 지켜라 (CLAUDE.md):
- 섹션 순서 `[gd_scene]` → `[ext_resource]` → `[sub_resource]` → `[node]`
- **`load_steps` = ext_resource 수 + sub_resource 수 + 1.** 텍스처를 `ext_resource`
  로 추가하므로 **반드시 1씩 늘어난다**
- 노드 블록 사이 빈 줄
- `script = ExtResource(...)` 는 그 스크립트가 선언한 속성보다 **먼저**

## TASK 3 — 투사체를 진행 방향으로 회전시킨다

**이게 이번 작업에서 놓치기 제일 쉬운 것이다.**

`scripts/projectile.gd` 는 `direction` 을 갖고 있지만 **`rotation` 을 한 번도
쓰지 않는다.** 지금까지는 정사각형이라 회전이 무의미했다. 캡슐로 바뀌면
**모든 투사체가 항상 오른쪽을 가리킨다** — 위로 쏘든 아래로 쏘든.
에러는 안 난다.

`launch()` 에서 방향을 정한 뒤 스프라이트를 그 각도로 돌려라.
`rotation = direction.angle()` 이다. 캡슐 그림이 **가로로 누워 있으므로**
(알파 경계 1254x721) 추가 보정각은 필요 없다.

노드 전체를 돌릴지 `Sprite` 만 돌릴지는 **`Sprite` 만** 돌린다 — 노드를 돌리면
`CollisionShape2D` 도 같이 도는데 원형이라 무의미하고, 나중에 충돌 모양을 바꿀 때
혼란만 남는다. 한글 주석으로 이유를 적어라.

`scripts/orbital.gd` 와 `scripts/xp_gem.gd` 는 회전이 필요 없다 (원형·마름모).

## TASK 4 — `tools/check_sprite_luminance.py` 의 `SPEC` 에 셋을 되돌린다

M22 에서 "게임이 안 그리니까 검사에서 뺀다"며 제거했고, 그 자리에 한글 주석이
붙어 있다. **이제 그리므로 되돌린다.** 주석도 그 사실에 맞게 고쳐라.

`SPEC` 은 지금 `이름 -> (표시 크기, 목표색)` 형식이다 (순위는 M22 에서 없앴다).

| 이름 | 표시 크기 | 목표색 |
|---|---:|---|
| `xp_gem` | 20 | `(0.15, 0.50, 0.22)` |
| `projectile` | 16 | `(0.62, 0.36, 0.10)` |
| `orbital` | 28 | `(0.28, 0.48, 0.55)` |

**판정 규칙은 바꾸지 마라.** 양쪽 톤에서 외곽 대비 3:1, 본체 dE 25, 충전율 35%
그대로다. 적 변종 dE 검사도 그대로다 (이 셋은 적이 아니므로 그 검사에 안 들어간다).

⚠️ 충전율이 걱정되면 **숫자를 낮추지 말고 보고만 해라.** 마름모는 외접 정사각형의
50%, 캡슐은 더 낮을 수 있다. 기준을 손대는 것은 사람이 측정을 보고 결정한다.

## TASK 5 — `tests/test_visual_hierarchy.gd` 를 고친다

M22 에서 넣은 두 케이스가 `Outline` ColorRect 를 전제한다. 그 노드가 사라지므로
**지금 그대로 두면 조용히 실패한다.**

- `_test_outlined_elements_clear_minimum_contrast` — **삭제.** 외곽선이 그림에
  구워졌으므로 이제 `tools/check_sprite_luminance.py` 가 잰다 (씬에서 읽을 색이
  더는 없다)
- `_test_colorrect_elements_are_outlined` — **교체.** 아래 새 케이스로

**새 케이스: `sprite_elements_use_textures`**

세 씬(`xp_gem` / `projectile` / `orbital`)에 대해 전부 검사한다.

1. `Sprite` 노드가 **`Sprite2D`** 이고 `texture` 가 `null` 이 아니다
2. `Outline` 이라는 이름의 노드가 **없다** (구운 외곽선으로 대체됐는데 남아 있으면
   그림 뒤에 검은 사각형이 깔린다)
3. `scale × 텍스처 크기` 가 의도한 표시 크기와 **0.5px 안에서** 일치한다
   (젬 20 / 투사체 16 / 궤도구 28)

3번이 핵심이다. `scale` 은 숫자 하나만 틀려도 **에러 없이 크기만 달라진다.**
한글 주석으로 적어라.

**새 케이스: `projectile_faces_its_direction`**

투사체를 인스턴스화하고 `launch()` 로 **위쪽**(`Vector2.UP`) 같은 비자명한 방향을
준 뒤, `Sprite` 의 `rotation` 이 그 각도와 맞는지 본다.
`Vector2.RIGHT` 로 검사하면 **안 된다** — 기본값이 이미 오른쪽이라 회전을 아예
구현하지 않아도 통과한다. 한글 주석으로 그 이유를 적어라.

`EXPECTED_CASE_COUNT` 를 맞춰 고쳐라 (지금 6 → 케이스를 하나 지우고 둘 추가하면 **7**).

⚠️ **SKIP 도피로를 만들지 마라.** 잴 수 없으면 FAIL 이다. M21 에서 가장 중요한
케이스가 정확히 그 상황에서만 SKIP 으로 내려앉아 스위트가 초록불을 준 적이 있다.

`_read_visual_colours()` 가 젬·투사체의 `Sprite.color` 를 읽고 있다면 그 부분도
정리해라 — **`Sprite2D` 에는 `color` 가 없어 `get("color")` 가 조용히 `null` 을
돌려준다.** 남겨 두면 셋업이 조용히 실패한다.

## TASK 6 — 문서

- `docs/ASSETS.md`: 젬·투사체·궤도구가 이제 `ColorRect` 가 아니라 텍스처라는 사실을
  적는다. M22 상자에 "이 셋은 ColorRect 라 도구가 안 닿는다"는 취지의 문장이 있으면
  고쳐라
- `docs/STATUS.md` 의 "M23 후보 A" 절은 **손대지 마라.** 결과 기록은 사람이 한다

---

## 하지 말 것

- 셸·git·python·Godot 실행
- 밸런스 수치 (`wave_data.gd`, `upgrade_data.gd`, 속도·피해·쿨다운) 변경
- 표시 크기 변경 (젬 20 / 투사체 16 / 궤도구 28 고정)
- `assets/sprites_src/` 의 기존 5장을 덮어쓰기
- 검사 기준(3:1, dE 25, 충전율 35%) 완화
- `tools/make_ground_tile.py` 나 바닥 관련 파일 변경

## 마지막에 출력할 것

사람이 그대로 복사해 돌릴 수 있게, **아래 순서대로** 명령을 나열해라.
결과를 예측하지 마라 — 무엇을 확인해야 하는지만 적어라.

1. `python tools/sprite_outline.py xp_gem projectile orbital`
2. Godot `--import`
3. `python tools/check_sprite_luminance.py assets/sprites` (8종 전부 나와야 한다)
4. 각 변경 스크립트에 `--check-only -s`
5. `test_visual_hierarchy` 단독 실행
6. 전체 24스위트 (CLAUDE.md 의 foreach 한 줄)
7. `--auto-play` 캡처 — **마름모·캡슐·원이 실제로 그 모양으로 보이는지,
   투사체가 쏘는 방향을 향하는지 눈으로 볼 것**

7번을 건너뛰지 말라고 적어라. 이 프로젝트에서 색·그리기 결함은 **여섯 번 다
캡처로만** 발견됐다.
