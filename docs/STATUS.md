# STATUS — 진행 상황 및 재개 가이드

> **이 파일만 읽으면 작업을 이어서 할 수 있어야 한다.** 컴퓨터가 꺼져도, 세션이 끊겨도 여기서부터 재개한다.

**최종 갱신**: 2026-08-12
**현재 마일스톤**: M2 완료 → **다음은 M3 (자동 공격)**

---

## 한 줄 요약

플레이어가 WASD로 움직이고, 화면 밖에서 적이 몰려와 플레이어를 추적한다. 아직 서로 아무 영향도 주지 못한다(공격·피해 없음).

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
- [x] 부팅 자가진단 `BOOT_OK actions_ok=true`

### M2 — 적 스폰 + 추적
- [x] `scenes/enemy.tscn` / `scripts/enemy.gd` — 직진 추적, 속도 60, 레이어 2 / 마스크 1
- [x] `scripts/enemy_spawner.gd` — 화면 밖 원주(반지름 794.3) 스폰, 간격 1.5초, 상한 30
- [x] `main.tscn`에 `EnemyContainer` 도입 — **모든 적은 이 아래에만 붙인다**
- [x] `tests/test_enemy_spawn.tscn` — 4케이스 통과 (주기 스폰 / 화면 밖 / 추적 / 상한)
- [x] 부팅 토큰 규약 변경: `BOOT_OK milestone=M2 ...`

## 바로 다음에 할 일 (M3: 자동 공격)

**목표**: 가장 가까운 적을 향해 일정 주기로 투사체를 발사하고, 맞은 적이 사라진다.

1. `scenes/projectile.tscn` — `Area2D` 루트 권장. 충돌 레이어 **3**, 마스크 **2**(적만 감지). 노란 작은 플레이스홀더
   - `CharacterBody2D`가 아니라 `Area2D`인 이유: 투사체는 물리적으로 밀 필요 없이 "겹쳤는가"만 알면 된다. Area2D가 가볍고 관통·다중 히트 처리도 쉽다
2. `scripts/projectile.gd` — 생성 시 방향을 받아 직진, 수명(3초) 또는 사거리 초과 시 `queue_free()`
   - **제거를 잊으면 화면 밖에 무한히 쌓여 메모리 누수가 된다**
3. `scripts/weapon.gd` (플레이어 자식 노드) — 쿨다운 0.5초마다 발사
   - 조준: `EnemyContainer`의 자식을 순회해 **가장 가까운 적**을 고른다. 적이 없으면 발사하지 않는다
4. 적 피격 처리: `enemy.gd`에 `take_damage(amount)` 추가. HP 0 이하면 `queue_free()`
   - 경험치 드랍은 M5. 지금은 사라지기만 한다
5. 테스트 `tests/test_weapon.tscn` — ① 적이 있을 때만 발사 ② 가장 가까운 적을 고르는가 ③ 투사체가 적에 맞으면 적과 투사체가 모두 사라지는가 ④ 빗나간 투사체가 수명 후 사라지는가

**M3 수용 기준(DoD)**: 테스트 통과 + 캡처 스크린샷에 투사체가 보임 + 일정 시간 방치해도 노드 수가 무한 증가하지 않음

**참고 수치**: GDD 6절 (기본 총 데미지 5 / 쿨다운 0.5초 / 투사체 속도 400), 적 HP 10 → 2발에 처치

## 미해결 이슈 / 주의사항

| # | 내용 | 상태 |
|---|---|---|
| 1 | codex 샌드박스가 셸을 못 띄움 (`CreateProcessAsUserW failed: 5`) | **우회 완료** — codex는 파일 쓰기만, 실행·git은 Claude. 작업지시서에 셸 금지 문구 필수 |
| 2 | **헤드리스에서 뷰포트 높이가 틀리게 보고됨** (1280×720 → 1280×1280) | **우회 완료** — 화면 크기 의존 검증은 창 모드로만. 헤드리스에서는 SKIP 처리 (devlog 002) |
| 3 | 플레이어 크기 값(12)이 3곳에 중복 | 방치. M9 아트 교체 때 정리 |
| 4 | 화면 경계를 뷰포트 기준으로 계산 중 | 카메라 도입 시 월드 경계로 교체 (DECISIONS D-007, M7 재검토) |
| 5 | `test.md` — 저장소 초기 테스트 파일 | 사용자가 만든 파일이라 손대지 않음 |
| 6 | codex 토큰 한도 | 아직 여유 (M0~M2 누적 약 20만 토큰). 소진 시 즉시 사용자에게 보고하고 대기 |
| 7 | 적들이 서로 겹쳐 한 덩어리로 뭉침 (분리 로직 없음) | M7에서 밀도 실측 후 도입 |

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
