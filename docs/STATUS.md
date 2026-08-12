# STATUS — 진행 상황 및 재개 가이드

> **이 파일만 읽으면 작업을 이어서 할 수 있어야 한다.** 컴퓨터가 꺼져도, 세션이 끊겨도 여기서부터 재개한다.

**최종 갱신**: 2026-08-12
**현재 마일스톤**: M3 완료 → **다음은 M4 (충돌 피해와 HP)**

---

## 한 줄 요약

플레이어가 WASD로 움직이고, 적이 몰려오고, 사거리 350 안에 들어온 적을 자동으로 쏴서 처치한다. 아직 플레이어는 죽지 않는다(피해 없음).

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

### M3 — 자동 공격
- [x] `scenes/projectile.tscn` / `scripts/projectile.gd` — Area2D 투사체, 속도 400, 수명 3초
- [x] `scripts/weapon.gd` — 쿨다운 0.5초, 가장 가까운 적 조준, **사거리 350**
- [x] `enemy.gd` — `take_damage()`, HP 0에 `queue_free()`, `died` 시그널(M5에서 사용)
- [x] `tests/test_weapon.tscn` — 7케이스 통과
- [x] 캡처 도구를 **시간 기준**(`--capture-after=<초>`)으로 전면 교체

## 바로 다음에 할 일 (M4: 충돌 피해와 HP)

**목표**: 적에 닿으면 플레이어가 피해를 입고, HP가 0이 되면 게임오버.

1. `scripts/player.gd`에 HP 추가 — 최대 100, `take_damage(amount)`, `health_changed`·`died` 시그널
2. **접촉 피해 판정**: 플레이어의 `move_and_slide()` 후 `get_slide_collision_count()`로 닿은 적을 확인하는 방식과, 플레이어에 `Area2D`(hurtbox)를 붙여 겹침을 감지하는 방식 중 후자를 권장
   - 이유: `CharacterBody2D`끼리는 서로 밀어내며 미끄러져서 접촉이 프레임마다 끊길 수 있다. Area2D 겹침 판정이 안정적이고, 히트박스 크기를 시각 크기와 독립적으로 조절할 수 있다
3. **무적 시간 0.5초** — 없으면 매 프레임 피해를 입어 즉사한다. 반드시 함께 구현할 것
4. HP 0이면 플레이어를 제거하고 게임 정지. 정식 게임오버 화면은 M8이므로 지금은 라벨 표시 정도로 최소 구현
5. 적이 죽을 때 이미 `died` 시그널을 쏘고 있으니 M4에서는 건드리지 않는다
6. 테스트 `tests/test_player_damage.tscn` — ① 적 접촉 시 HP 감소 ② 무적 시간 중에는 추가 피해 없음 ③ 무적 해제 후 다시 피해 ④ HP 0에서 사망 처리 ⑤ 플레이어 사망 후 적들이 에러 없이 동작(`is_instance_valid` 가드 확인)

**M4 수용 기준(DoD)**: 테스트 통과 + 캡처로 피격 확인 + 플레이어 사망 후에도 런타임 에러 없음

**참고 수치**: GDD 4절 (최대 HP 100 / 무적 0.5초 / 히트박스 반지름 12), 기본 적 접촉 피해 5

## 미해결 이슈 / 주의사항

| # | 내용 | 상태 |
|---|---|---|
| 1 | codex 샌드박스가 셸을 못 띄움 (`CreateProcessAsUserW failed: 5`) | **우회 완료** — codex는 파일 쓰기만, 실행·git은 Claude. 작업지시서에 셸 금지 문구 필수 |
| 2 | **헤드리스에서 뷰포트 높이가 틀리게 보고됨** (1280×720 → 1280×1280) | **우회 완료** — 화면 크기 의존 검증은 창 모드로만. 헤드리스에서는 SKIP 처리 (devlog 002) |
| 3 | 플레이어 크기 값(12)이 3곳에 중복 | 방치. M9 아트 교체 때 정리 |
| 4 | 화면 경계를 뷰포트 기준으로 계산 중 | 카메라 도입 시 월드 경계로 교체 (DECISIONS D-007, M7 재검토) |
| 5 | `test.md` — 저장소 초기 테스트 파일 | 사용자가 만든 파일이라 손대지 않음 |
| 6 | codex 토큰 한도 | 아직 여유 (M0~M3 누적 약 32만 토큰). 소진 시 즉시 사용자에게 보고하고 대기 |
| 7 | 적들이 서로 겹쳐 한 덩어리로 뭉침 (분리 로직 없음) | M7에서 밀도 실측 후 도입 |
| 8 | **유닛 테스트 전부 통과 ≠ 게임이 정상.** M3에서 두 번 겪었다 | 마일스톤마다 반드시 창 모드 캡처로 눈 검증 병행 (devlog 004) |
| 9 | `create_timer()`는 일시정지 중에도 진행됨 | M5 레벨업 일시정지 도입 시 캡처 타이밍 영향 확인 필요 (D-011) |

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
