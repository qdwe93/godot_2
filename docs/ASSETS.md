# ASSETS — 아트 에셋 현황과 생성 기록

> 이 문서는 **이미지 생성 시도의 전 과정**을 남긴다. 성공한 것뿐 아니라 **못 한 것과 그 이유**까지 적는다.
> 사용자가 나중에 다른 도구로 직접 생성할 수 있도록 **프롬프트 원문**을 그대로 보존한다.

---

## 1. 결론 요약 (2026-08-13)

**codex CLI에는 이미지 생성 기능이 없다.** 따라서 이번 작업에서 AI 이미지 생성은 **한 건도 실행하지 못했다.**
그리고 A팀 디자이너 리뷰가 "지금은 아트를 교체하지 말 것"을 권고했으므로, 이번 마일스톤에서는 **에셋 없이 도형 상태에서 시각 위계만** 손봤다.

아래 2절이 조사 기록, 3절이 나중에 쓸 프롬프트, 4절이 대안이다.

---

## 2. 조사 기록 — codex 이미지 생성 가능 여부

### 2-1. 확인한 것

```powershell
codex --version          # codex-cli 0.144.6
codex exec --help
codex plugin list
Get-Content "$env:USERPROFILE\.codex\config.toml"
```

### 2-2. 결과

| 확인 대상 | 결과 |
|---|---|
| `codex exec` 옵션 | `-i, --image <FILE>...` 가 있지만 **"Optional image(s) to attach to the initial prompt"** — 이미지를 *입력으로 첨부*하는 기능이지 생성이 아니다 |
| 설치된 플러그인 | `documents`, `pdf`, `spreadsheets`, `presentations`, `template-creator`, `sites`, `browser`, `visualize` |
| `visualize` 플러그인 | 차트·다이어그램 렌더링용. 래스터 이미지(스프라이트) 생성기가 아니다 |
| 마켓플레이스 미설치 목록 | `chrome`, `computer-use`, `latex`, `linear`, `figma`, `canva`, `hugging-face` 등. **이미지 생성 플러그인 없음** |
| config.toml | 이미지 생성 관련 모델·엔드포인트 설정 없음 |

### 2-3. 부가 제약

설령 이미지 생성 플러그인이 있었어도 **이 PC의 codex는 셸 프로세스를 띄우지 못한다**(`CreateProcessAsUserW failed: 5`, CLAUDE.md 참고).
플러그인 대부분이 외부 실행 파일을 호출하므로 동작하지 않았을 가능성이 높다.

### 2-4. 그래서 프롬프트가 하나도 없는 이유

**이미지 생성을 시도조차 못 했으므로 "실행한 프롬프트"는 존재하지 않는다.**
대신 3절에 **실행했다면 썼을 프롬프트**를 그대로 작성해 남긴다. 사용자가 다른 도구(Midjourney, DALL·E, Stable Diffusion, Nano Banana 등)에 그대로 붙여 넣어 쓸 수 있다.

---

## 3. 에셋 사양과 생성 프롬프트 (미실행, 재사용 목적)

### 3-1. 공통 제약 — 어떤 도구를 쓰든 지켜야 하는 것

이 게임의 화면은 배경이 `#141419`(거의 검정)이고, 후반에는 적이 **160~240마리** 동시에 뜬다.
따라서 스프라이트는 다음을 만족해야 한다.

- **투명 배경 PNG**, 정사각 캔버스, 오브젝트가 중앙에 꽉 차게
- 탑다운(위에서 내려다본) 시점. 원근·그림자 없음
- 그림자·글로우·아웃라인 블러 금지 (겹쳤을 때 서로를 지운다)
- **밝은 외곽선 1~2px**은 권장 (어두운 배경에서 실루엣이 살아난다)
- 디테일 최소화. 20px로 축소했을 때 형태가 남아야 한다
- 텍스트·로고·워터마크 금지

### 3-2. 필요한 스프라이트 목록

| # | 이름 | 파일명(안) | 표시 크기 | 형태 문법 | 색 방향 |
|---|---|---|---|---|---|
| 1 | 플레이어 | `player.png` | 24×24 | 원형 코어 + 방향 표식 | 밝은 하늘색 `#4DD9FF` — **화면에서 가장 밝아야 함** |
| 2 | 기본 적 | `enemy_basic.png` | 20×20 | **사각형** | 빨강 `#E64040` |
| 3 | 빠른 적 | `enemy_fast.png` | 17×17 | **삼각형**(진행 방향을 가리킴) | 주황 `#FF9926` |
| 4 | 탱커 적 | `enemy_tank.png` | 28×28 | **두꺼운 테두리 육각형** | 자주 `#BF59F2` |
| 5 | 보스 | `enemy_boss.png` | 60×60 | 대형 + 고대비 외곽선 | 마젠타 `#F259F2` |
| 6 | 경험치 젬 | `xp_gem.png` | 10×10 | 마름모 | 초록 `#4DFF66` — 적보다 어둡게 |
| 7 | 투사체 | `projectile.png` | 8×8 | 짧은 캡슐 | 호박색 `#FFE633` — **가장 어둡게** |

> **형태를 색보다 우선한다.** 적록색각이상(남성 약 8%)에게 빨강·주황·자주는 비슷한 갈색으로 수렴한다.
> 지금 적 3종이 전부 같은 사각형이라 색이 유일한 단서인데, 그 단서가 작동하지 않는다.

### 3-3. 프롬프트 원문 (영문 — 대부분의 생성기가 영문에 안정적이다)

**공통 접미사** (모든 프롬프트 끝에 붙인다):

```
top-down view, flat vector style, single centered object, transparent background,
no drop shadow, no glow, no gradient background, no text, no watermark,
crisp 1-2px bright outline, high contrast against near-black background,
readable when scaled down to 20 pixels, game sprite asset
```

**1. 플레이어**

```
A small round sci-fi survivor drone seen from directly above, glowing light-cyan
(#4DD9FF) body with a clear pointed front indicating facing direction,
compact and instantly recognizable as the player character, brightest element on screen,
<공통 접미사>
```

**2. 기본 적**

```
A simple hostile blob enemy seen from directly above, solid square silhouette,
dull red (#E64040), aggressive but plain, the most common weak enemy,
<공통 접미사>
```

**3. 빠른 적**

```
A fast darting enemy seen from directly above, sharp triangular silhouette
pointing forward to convey speed and direction, orange (#FF9926), smaller than
the basic enemy, lightweight and agile,
<공통 접미사>
```

**4. 탱커 적**

```
A heavy armored enemy seen from directly above, thick-bordered hexagonal silhouette,
purple (#BF59F2) with a noticeably heavier outline than other enemies,
bulky and slow, clearly the most dangerous regular enemy,
<공통 접미사>
```

**5. 보스**

```
A large menacing boss enemy seen from directly above, magenta (#F259F2) core with
a bright high-contrast outline, imposing silhouette distinct from all regular enemies,
occupies three times the area of a normal enemy,
<공통 접미사>
```

**6. 경험치 젬**

```
A small experience gem pickup seen from directly above, diamond silhouette,
green (#4DFF66), simple faceted crystal, subtle not flashy — it must not outshine
the enemies or the player,
<공통 접미사>
```

**7. 투사체**

```
A tiny energy bullet seen from directly above, short capsule shape, amber (#FFE633),
minimal and unobtrusive, the least attention-grabbing element on screen,
<공통 접미사>
```

### 3-4. 생성 후 반드시 할 것

1. `assets/sprites/`에 넣고 **출처와 라이선스를 이 문서에 기록**한다 (생성 도구·모델·날짜)
2. `--import`를 돌린다. 건너뛰면 실행 시 리소스를 못 찾는다
3. `.tscn`의 `ColorRect`를 `Sprite2D`로 교체할 때 **`enemy_spawner.gd`가 `Sprite`를 `ColorRect`로 캐스팅해 색을 주입한다**(`enemy_spawner.gd:101-103`). 여기와 `boss_spawner.gd:79-82`를 같이 고쳐야 한다. 안 고치면 **에러 없이 색만 조용히 안 바뀐다**
4. 교체 전후로 160마리 화면을 캡처해 **가독성이 실제로 좋아졌는지** 눈으로 비교한다

---

## 4. 대안 — 프로그램 생성 (실행 가능함을 확인)

이 PC에 **Pillow 11.3.0 / Python 3.14.0**이 있다. AI 생성 없이 스크립트로 스프라이트를 만들 수 있다.

이 게임에는 오히려 이쪽이 나을 수 있다:

- 3-2의 형태 문법(사각형/삼각형/육각형/마름모)은 **도형이라 AI가 필요 없다**
- 색·크기·외곽선 두께를 **정확한 값으로** 지정할 수 있다 (AI 생성물은 색이 어긋난다)
- 위계를 바꾸고 싶으면 상수 하나만 고쳐 전부 다시 만든다
- 결정적이라 재현 가능하고, 라이선스 문제가 없다

**아직 실행하지 않았다.** A팀 디자이너 리뷰가 "도형 상태에서 위계를 먼저 세우고, 교체는 그 규칙을 그대로 옮기는 작업이어야 한다"고 했기 때문이다. 위계 작업(M11)이 끝난 뒤 판단한다.

---

## 5. 이번 마일스톤에서 실제로 한 시각 작업 (에셋 없이)

| 항목 | 내용 |
|---|---|
| 보스 색 | `Color(0.1, 0.1, 0.12)` → `Color(0.95, 0.35, 0.95)`. 배경 대비 **1.05:1 → 약 6.5:1** |
| 적 피격 번쩍 | `enemy.gd`가 피격 시 0.06초 흰색 |
| 명중 이펙트 | `projectile.gd`/`orbital.gd`가 `EffectSpawner.spawn_hit()` 호출 (이전에는 호출처가 0건) |
| 위험 상태 | HP 30% 이하에서 HP바 적색 + 화면 비네트 |
| 바 색 구분 | HP바 녹색 / 경험치바 청색 (이전에는 둘 다 기본 테마라 구분 불가) |

---

## 6. 기존 보유 에셋

| 에셋 | 출처 | 라이선스 | 비고 |
|---|---|---|---|
| `assets/vfx/impact_white_6x4.png` 외 | Brackeys VFX 번들 | CC0 | M9에서 도입. PC 보유분이라 다운로드 없음 (devlog 013) |

사운드는 **아직 없다.** 보유 팩에 오디오가 포함되지 않아 M9에서 미실시했다.
