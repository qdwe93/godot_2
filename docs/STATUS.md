# STATUS — 진행 상황 및 재개 가이드

> **이 파일만 읽으면 작업을 이어서 할 수 있어야 한다.** 컴퓨터가 꺼져도, 세션이 끊겨도 여기서부터 재개한다.

**최종 갱신**: 2026-08-12
**현재 마일스톤**: M1 완료 → **다음은 M2 (적 스폰 + 추적)**

---

## 한 줄 요약

플레이어가 WASD로 움직이고 화면 밖으로 못 나간다. 자동 테스트와 스크린샷 검증 수단까지 갖췄다. 적은 아직 없다.

## 완료된 것

### M0 — 프로젝트 셋업
- [x] codex 표준 호출 방식 확정 → `CLAUDE.md`
- [x] `project.godot` (1280×720, gl_compatibility), 폴더 구조, `.gitignore`
- [x] 헤드리스 임포트 + 실행 검증 파이프라인
- [x] 문서 골격 (PRD / GDD / DECISIONS / devlog / CLAUDE.md)

### M1 — 플레이어 이동
- [x] InputMap: `move_left/right/up/down` ← WASD **물리 키코드**
- [x] `scenes/player.tscn` (CharacterBody2D, 반지름 12 원형 충돌, 하늘색 24×24 플레이스홀더)
- [x] `scripts/player.gd` — 8방향 이동 200px/s, 화면 경계 제한
- [x] `scripts/capture_helper.gd` — 게임 화면 PNG 저장 도구 (시각 검증용)
- [x] `tests/test_player_movement.tscn` — 프로젝트 최초 자동 테스트 (3케이스 통과)
- [x] 부팅 자가진단 `M1_BOOT_OK actions_ok=true`

## 바로 다음에 할 일 (M2: 적 스폰 + 추적)

**목표**: 화면 밖에서 적이 주기적으로 생성되어 플레이어를 향해 이동한다.

1. `scenes/enemy.tscn` — `CharacterBody2D` 루트, 충돌 레이어 **2**, 마스크 **1**(플레이어 감지), 빨간 플레이스홀더
2. `scripts/enemy.gd` — 매 `_physics_process`마다 플레이어 방향으로 직진. **경로 탐색(NavigationAgent2D)은 쓰지 않는다** (개활지 맵이라 불필요하고 수백 마리에는 성능이 안 나옴)
3. `scripts/enemy_spawner.gd` — `Timer`로 주기적 스폰. 위치는 **화면 사각형 바깥의 원주 위 랜덤 지점** (시야 안에서 튀어나오지 않게)
4. `main.tscn`에 `EnemyContainer`(Node2D)와 `EnemySpawner` 추가. **적은 반드시 EnemyContainer 아래에만 붙인다** — 나중에 "가장 가까운 적 찾기"와 오브젝트 풀링 전환의 기준점이 된다
5. 적끼리 완전히 겹치는 문제는 이번 단계에서 해결하지 않는다. M2 목표는 스폰과 추적까지다
6. 테스트 추가: `tests/test_enemy_spawn.tscn` — ① 일정 시간 후 적이 N마리 이상 생성되는가 ② 스폰 위치가 화면 밖인가 ③ 적이 플레이어 쪽으로 실제로 가까워지는가

**M2 수용 기준(DoD)**: 헤드리스 테스트 통과 + 창 모드 캡처 스크린샷에 적이 여러 마리 보임 + 런타임 에러 없음

**참고 수치**: GDD 5절 (기본 적 HP 10 / 속도 60 / 접촉 피해 5, 스폰 간격 1.5초)

## 미해결 이슈 / 주의사항

| # | 내용 | 상태 |
|---|---|---|
| 1 | codex 샌드박스가 셸을 못 띄움 (`CreateProcessAsUserW failed: 5`) | **우회 완료** — codex는 파일 쓰기만, 실행·git은 Claude. 작업지시서에 셸 금지 문구 필수 |
| 2 | **헤드리스에서 뷰포트 높이가 틀리게 보고됨** (1280×720 → 1280×1280) | **우회 완료** — 화면 크기 의존 검증은 창 모드로만. 헤드리스에서는 SKIP 처리 (devlog 002) |
| 3 | 플레이어 크기 값(12)이 3곳에 중복 | 방치. M9 아트 교체 때 정리 |
| 4 | 화면 경계를 뷰포트 기준으로 계산 중 | 카메라 도입 시 월드 경계로 교체 (DECISIONS D-007, M7 재검토) |
| 5 | `test.md` — 저장소 초기 테스트 파일 | 사용자가 만든 파일이라 손대지 않음 |
| 6 | codex 토큰 한도 | 아직 여유 (M0+M1에서 약 15만 토큰 사용). 소진 시 즉시 사용자에게 보고하고 대기 |

## 재개 절차

```powershell
# 1. 부팅 확인 (M1_BOOT_OK actions_ok=true 가 나와야 정상)
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --quit-after 30
```

```powershell
# 2. 자동 테스트 (창 모드로 돌려야 경계 케이스까지 검증됨)
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --path "C:\Workspaces\game_make\test_godot_2" "res://tests/test_player_movement.tscn"
```

`TEST_RESULT PASS`가 나오면 정상. 그 후 위 "바로 다음에 할 일"을 진행한다.
자주 쓰는 명령어 전체는 [CLAUDE.md](../CLAUDE.md) 참고.
