# STATUS — 진행 상황 및 재개 가이드

> **이 파일만 읽으면 작업을 이어서 할 수 있어야 한다.** 컴퓨터가 꺼져도, 세션이 끊겨도 여기서부터 재개한다.

**최종 갱신**: 2026-08-13
**현재 마일스톤**: M4 완료 → **다음은 M5 (경험치와 레벨업)**

---

## 한 줄 요약

이동 → 적 스폰 → 자동 공격 → 피격/사망까지 한 판의 뼈대가 돌아간다. 성장 요소(경험치·레벨업)가 아직 없어서 게임이라기보다 데모에 가깝다.

⚠️ **현재 밸런스로는 플레이어가 죽지 않는다.** 무기 처치 속도(1마리/초)가 스폰 속도(0.67마리/초)를 앞서 적이 접근하지 못한다. 버그가 아니라 밸런스 문제이며 M7/M10에서 다룬다 (GDD 8절 실측표).

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

### M4 — 접촉 피해와 체력
- [x] `player.gd` — HP 100, 무적 0.5초, `take_damage()`, `health_changed`/`died` 시그널
- [x] `player.tscn`에 `Hurtbox`(Area2D) — **시그널이 아니라 매 프레임 겹침 폴링** (D-012)
- [x] `main.gd` — `PLAYER_HEALTH`/`PLAYER_DIED` 로그, 사망 시 스포너 정지 + 게임오버 라벨
- [x] `tests/test_player_damage.tscn` — 5케이스 통과
- [x] **테스트 하네스 무결성 강화** (D-013) — 거짓 통과 차단, 고장 주입으로 검증
- [x] M1 경계 테스트의 헤드리스 SKIP 해제 (구현이 ProjectSettings 기반으로 바뀌어 검증 가능해짐)

## 바로 다음에 할 일 (M5: 경험치와 레벨업)

**목표**: 적을 죽이면 경험치 젬이 떨어지고, 모으면 레벨업하며 업그레이드를 3개 중 하나 고른다.

1. `scenes/xp_gem.tscn` — `Area2D`, 레이어 **4**, 마스크 **5**. 작은 초록 플레이스홀더
2. **드랍 연결**: `enemy.gd`는 이미 `died(enemy_position)` 시그널을 쏘고 있다. 스포너나 별도 매니저가 이 시그널을 받아 젬을 생성한다. 적 스크립트가 직접 젬을 만들지 않게 할 것 — 적은 자기가 죽는 것만 알면 된다
3. **자석 수집**: 플레이어에 `MagnetArea`(Area2D, 레이어 5 / 마스크 4, 반경 60) 추가. 범위에 들어온 젬이 플레이어를 향해 가속하며 날아오고, 닿으면 경험치 획득
4. `scripts/experience.gd` 또는 플레이어 내부에 레벨·경험치 상태. 곡선은 `5 + (레벨-1) * 3` (GDD 7절)
5. **레벨업 UI**: `get_tree().paused = true`로 멈추고 3택 제시
   - ⚠️ **Godot 함정**: 일시정지 중에는 노드의 `process_mode`가 기본값이면 입력을 못 받는다. UI 루트를 `PROCESS_MODE_WHEN_PAUSED`로 설정해야 버튼이 눌린다. 놓치면 게임이 영원히 멈춘 것처럼 보인다
   - ⚠️ D-011 관련: `create_timer()`는 일시정지 중에도 진행되므로 캡처 도구 타이밍에 영향이 있는지 확인할 것
6. M5의 업그레이드는 **효과가 실제로 적용되지 않아도 된다**. 선택 UI와 흐름까지가 M5, 실제 무기·패시브 효과는 M6
7. 테스트 `tests/test_experience.tscn` — ① 적 사망 시 젬 생성 ② 자석 범위 밖 젬은 안 움직임 ③ 범위 안 젬이 플레이어에게 도달해 경험치 증가 ④ 곡선대로 레벨업 ⑤ 레벨업 시 트리가 일시정지되고 선택 후 재개

**M5 수용 기준(DoD)**: 테스트 통과 + 캡처 스크린샷에 젬이 보임 + 레벨업 UI가 실제로 클릭 가능(일시정지 중 입력 확인)

**참고 수치**: GDD 4절(자석 반경 60), 7절(경험치 곡선·패시브 목록)

## 미해결 이슈 / 주의사항

| # | 내용 | 상태 |
|---|---|---|
| 1 | codex 샌드박스가 셸을 못 띄움 (`CreateProcessAsUserW failed: 5`) | **우회 완료** — codex는 파일 쓰기만, 실행·git은 Claude. 작업지시서에 셸 금지 문구 필수 |
| 2 | **헤드리스에서 뷰포트 높이가 틀리게 보고됨** (1280×720 → 1280×1280) | **우회 완료** — 화면 크기 의존 검증은 창 모드로만. 헤드리스에서는 SKIP 처리 (devlog 002) |
| 3 | 플레이어 크기 값(12)이 3곳에 중복 | 방치. M9 아트 교체 때 정리 |
| 4 | 화면 경계를 뷰포트 기준으로 계산 중 | 카메라 도입 시 월드 경계로 교체 (DECISIONS D-007, M7 재검토) |
| 5 | `test.md` — 저장소 초기 테스트 파일 | 사용자가 만든 파일이라 손대지 않음 |
| 6 | codex 토큰 한도 | 아직 여유 (M0~M4 누적 약 60만 토큰). 소진 시 즉시 사용자에게 보고하고 대기 |
| 7 | 적들이 서로 겹쳐 한 덩어리로 뭉침 (분리 로직 없음) | M7에서 밀도 실측 후 도입 |
| 8 | **유닛 테스트 전부 통과 ≠ 게임이 정상.** M3·M4에서 겪었다 | 마일스톤마다 창 모드 캡처 + 실제 씬 로그 확인 병행 (devlog 004·005) |
| 9 | `create_timer()`는 일시정지 중에도 진행됨 | M5 레벨업 일시정지 도입 시 캡처 타이밍 영향 확인 필요 (D-011) |
| 10 | **현재 밸런스로는 죽지 않는다** (처치 1.0/초 > 스폰 0.67/초) | M7 난이도 상승 / M10 밸런싱 (GDD 8절 실측표) |
| 11 | 사망 후 재시작 불가 (라벨만 표시) | M8 |

## 작업 규칙 (사고 후 추가)

- **스크립트를 고쳤으면 `--check-only` 문법 검사를 먼저 돌린다.** Godot 4.7은 Variant 추론(`var x := <Variant>`)을 **에러**로 취급해 스크립트 전체가 로드되지 않는다. 게임은 조용히 빈 노드로 실행된다
- **고장 주입 실험 전에 반드시 커밋한다.** 미커밋 상태에서 `git checkout -- <파일>`을 쓰면 마지막 커밋으로 돌아가 작업이 사라진다 (M4에서 실제로 발생)
- 테스트를 수정했으면 **일부러 고장을 내서 FAIL하는지 확인**한다. 통과 확인만으로는 절반이다

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
