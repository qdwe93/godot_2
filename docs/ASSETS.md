# ASSETS — 아트 에셋 현황과 생성 기록

> 이 문서는 **이미지 생성의 전 과정**을 남긴다. 성공한 것뿐 아니라 **못 한 것, 잘못 판단한 것과 그 이유**까지 적는다.
> 나중에 다시 생성할 수 있도록 **프롬프트 원문**을 그대로 보존한다.

---

## 1. 결론 요약

**codex에는 이미지 생성 기능이 있다.** 2026-08-13 최초 조사에서 "없다"고 잘못 판정했다가 정정했다.
2절에 오판 경위와 실제 확인 방법을 남긴다. 3절이 이 게임에 쓸 프롬프트, 4절이 다른 프로젝트에서 검증된 운영 규칙이다.

이번 M11a 마일스톤에서는 **에셋을 생성하지 않았다.** 기능이 없어서가 아니라, A팀 디자이너 리뷰가
"도형 상태에서 시각 위계를 먼저 세우고, 교체는 그 규칙을 그대로 옮기는 작업이어야 한다"고 권고했기 때문이다.

---

## 2. codex 이미지 생성 — 오판과 정정 (2026-08-13)

### 2-1. 처음에 "없다"고 판단한 근거 (틀린 방법)

```powershell
codex --version          # codex-cli 0.144.6
codex exec --help        # -i/--image 는 이미지를 "입력으로 첨부"하는 옵션
codex plugin list        # documents/pdf/spreadsheets/presentations/sites/browser/visualize
```

`--help`의 옵션 목록과 플러그인 목록 어디에도 이미지 생성이 없어서 "기능 없음"으로 결론지었다.

### 2-2. 왜 틀렸나

**`imagegen`은 CLI 옵션도 플러그인도 아니라 모델이 직접 호출하는 내장 도구다.**
따라서 `--help`에도 `plugin list`에도 나타나지 않는다. **CLI 표면만 보고 모델의 도구 목록을 판단한 것이 오류였다.**

### 2-3. 실제로 확인하는 방법

```powershell
codex features list
```

```
image_generation                     stable             true
```

부가 증거:

- 생성 원본이 `~/.codex/generated_images/<uuid>/ig_*.png`로 남는다. 2026-06-09부터 쌓인 폴더가 실재한다
- 같은 PC의 다른 프로젝트(`voca_video_plan`)가 이 기능으로 이미지 20장을 실제 제작했고, 그 `handover.md`에 **"생성 방식: Codex 내장 `imagegen`"**이라고 기록돼 있다

### 2-4. 교훈

**도구의 존재 여부를 CLI 헬프로 단정하지 않는다.** 기능 플래그(`codex features list`)와 실제 산출물 흔적을 함께 본다.
이 프로젝트에서 "선언은 있는데 배선이 끊긴" 버그를 세 건 잡아놓고, 정작 조사 방법에서 같은 종류의 실수를 했다.

---

## 3. 에셋 사양과 생성 프롬프트 (아직 미실행)

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

## 4. 생성 운영 규칙 (같은 PC의 `voca_video_plan` 프로젝트에서 검증된 것)

그 프로젝트는 이미지 20장을 codex `imagegen`으로 제작하며 시행착오를 문서로 남겼다. 읽어서 옮겨 온 규칙이다.
(해당 폴더는 읽기만 했고 아무것도 수정하지 않았다.)

### 4-1. 비용 — 유료 호출이다

- **자산 하나당 호출 하나**가 기본이다. 여러 장면을 한 호출에 합치면 품질과 파일 대응이 떨어진다
- 오류가 나면 전체를 다시 만들지 말고 **불합격 파일만 표적 재생성**한다
- 호출 전에 값싼 결정적 검사(preflight)를 먼저 끝낸다 — 파일명 중복, 프롬프트 개수, 공통 스타일 접두사 누락. 그 프로젝트는 이걸 늦게 해서 잘못된 접두사로 생성할 뻔했다

### 4-2. 실패 사례와 회피법

| 겪은 문제 | 대응 |
|---|---|
| 해부학적 표현이 **안전 필터에 막힘** | 장면을 바꿔 우회 (해부도 → 교실용 모형) |
| 동작이 약하게 표현됨 (손이 닿기만 하고 잡지 않음) | 동작을 명시적으로 강하게 서술해 재생성 |
| 의도치 않은 **로고·상표형 표식**이 생김 | 금지 문구 추가: `plain unbranded surfaces, no badges, no emblems, no decorative glyphs, no logo-like markings` |
| 피사체가 화면 하단에 걸려 잘림 | 구도를 수치로 지정 (예: 하단 1/4에는 단순한 바닥만) |

### 4-3. 검수

- **contact sheet만 보지 말고 최종 파일을 원본 크기로 하나씩 연다**
- 확인 항목: 의미 / 텍스트·숫자 / 로고·워터마크 / 안전성 / 가장자리 크롭 / 화면비
- **실제 사용 화면에서 다시 본다.** 원본에서 괜찮아 보여도 게임 화면에 얹으면 다른 요소와 겹친다

### 4-4. 병렬화

서브에이전트를 최대 2개로 나눠 자산을 반씩 맡기고, 각자 **격리된 출력 위치**에 저장하게 한다.
공유 파일(최종 `assets/`, 씬, 문서)은 **메인만 수정**한다. 취합·검수도 메인이 한다.

### 4-5. 이 게임에 적용할 때 추가로 주의할 것

- **`.tscn`의 `ColorRect`를 `Sprite2D`로 바꾸면 `enemy_spawner.gd:101-103`과 `boss_spawner.gd:79-82`가 깨진다.** 두 곳 모두 `Sprite`를 `ColorRect`로 캐스팅해 변종별 색을 주입한다. 캐스팅이 실패하면 **에러 없이 색만 조용히 안 바뀐다**
- 스프라이트는 20px 안팎으로 축소돼 표시된다. 디테일을 넣어도 안 보인다
- 교체 전후로 적 160마리 화면을 캡처해 비교한다

### 4-6. 프로그램 생성이라는 선택지도 있다

Pillow 11.3.0 / Python 3.14.0이 설치돼 있다. 3-2의 형태 문법(사각형/삼각형/육각형/마름모)은 **도형이라 AI가 필요 없고**, 색·크기·외곽선 두께를 정확한 값으로 지정할 수 있다. 위계를 바꾸려면 상수 하나만 고쳐 전부 다시 만든다.
AI 생성은 캐릭터성이 필요한 플레이어·보스에, 프로그램 생성은 규칙적인 적·젬·투사체에 어울린다.

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
