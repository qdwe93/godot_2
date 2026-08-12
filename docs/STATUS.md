# STATUS — 진행 상황 및 재개 가이드

> **이 파일만 읽으면 작업을 이어서 할 수 있어야 한다.** 컴퓨터가 꺼져도, 세션이 끊겨도 여기서부터 재개한다.

**최종 갱신**: 2026-08-13
**현재 마일스톤**: M5 완료 (M5a+M5b) → **다음은 M6 (무기·패시브 효과 적용)**

---

## 한 줄 요약

**한 판의 루프가 처음부터 끝까지 이어졌다.** 이동 → 적 스폰 → 자동 사격 → 처치 → 젬 드랍 → 자석 수집 → 레벨업 → 화면 정지 → 3택 선택 → 재개. 다만 **선택한 업그레이드가 아직 아무 효과도 없다**(M6).

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

### M5a — 경험치 젬과 자석 수집
- [x] `xp_gem.tscn`/`xp_gem.gd` — 레이어 8(=4번), 자석에 끌려와 수집 시 경험치 지급
- [x] `pickup_spawner.gd` — 적 `died` 시그널로 드랍. **물리 스텝 회피 위해 `call_deferred`** (D-015)
- [x] 플레이어 `MagnetArea`(반경 60) — 시그널이 아니라 폴링 수집
- [x] `level_system.gd` — 곡선 `5+(레벨-1)*3`, 다중 레벨업 + 잔여 경험치 이월
- [x] `tests/test_experience.tscn` — 5케이스. **전체 5스위트 24케이스 통과, 런타임 에러 0**

### M5b — 레벨업 일시정지 UI
- [x] `level_up_ui.tscn`/`level_up_ui.gd` — CanvasLayer, **`process_mode = 3`(WHEN_PAUSED)**
- [x] 연속 레벨업 대기열 (젬 하나로 여러 레벨 → 한 번에 하나씩 선택)
- [x] `upgrade_chosen(id)` 시그널 — M6이 여기에 효과를 연결하면 UI는 수정 불필요
- [x] `tests/test_level_up_ui.tscn` — 5케이스. **전체 6스위트 29케이스 통과**
- [x] 실제 게임 캡처로 UI 표시 확인 (강제 레벨업 진단)

## 바로 다음에 할 일 (M6: 무기·패시브 효과 적용)

**목표**: 고른 업그레이드가 실제로 플레이 감각을 바꾼다. 무기 3종 이상, 패시브 3종 이상.

1. **업그레이드 데이터 분리**: 현재 풀은 `level_up_ui.gd` 안의 상수다. `scripts/upgrade_data.gd` 같은 곳으로 옮겨 id·이름·설명·최대 레벨·효과를 한 곳에서 관리
2. **효과 적용기**: `level_up_ui`의 `upgrade_chosen(id)` 시그널을 받는 `upgrade_manager.gd`를 만든다. **UI는 무엇이 선택됐는지만 알리고, 무엇이 바뀌는지는 모른다**
3. **패시브 4종** (GDD 7절): 신발(이속 +10%), 심장(최대 HP +20), 자석(수집 범위 +30%), 장갑(쿨다운 -8%). 현재 UI에 있는 왕관(경험치 +10%)도 유지
   - 스탯은 **기본값 × 배율** 방식으로 관리할 것. 현재값에 직접 곱하면 반올림 오차가 누적되고 되돌리기가 불가능하다
4. **무기 2종 추가** (GDD 6절): 산탄(전방 부채꼴 3발), 궤도구(플레이어 주위 공전, 접촉 피해)
   - 궤도구는 투사체가 아니라 **플레이어 자식으로 공전**시키는 편이 간단하다
5. **최대 레벨 상한**: 같은 업그레이드를 무한히 고르지 못하게. 상한에 도달한 항목은 선택지 풀에서 제외
6. 테스트 `tests/test_upgrades.tscn` — ① 신발 선택 시 이동 속도가 정확히 +10% ② 중복 선택 시 배율이 누적 ③ 상한 도달 항목이 풀에서 빠짐 ④ 산탄이 3발을 발사 ⑤ 궤도구가 플레이어를 따라다니며 적에게 피해

**M6 수용 기준(DoD)**: 테스트 통과 + 업그레이드 전/후 스탯 실측 로그 + 캡처로 신규 무기 확인

**참고 수치**: GDD 6절(무기 표), 7절(패시브 표)

## 미해결 이슈 / 주의사항

| # | 내용 | 상태 |
|---|---|---|
| 1 | codex 샌드박스가 셸을 못 띄움 (`CreateProcessAsUserW failed: 5`) | **우회 완료** — codex는 파일 쓰기만, 실행·git은 Claude. 작업지시서에 셸 금지 문구 필수 |
| 2 | **헤드리스에서 뷰포트 높이가 틀리게 보고됨** (1280×720 → 1280×1280) | **우회 완료** — 화면 크기 의존 검증은 창 모드로만. 헤드리스에서는 SKIP 처리 (devlog 002) |
| 3 | 플레이어 크기 값(12)이 3곳에 중복 | 방치. M9 아트 교체 때 정리 |
| 4 | 화면 경계를 뷰포트 기준으로 계산 중 | 카메라 도입 시 월드 경계로 교체 (DECISIONS D-007, M7 재검토) |
| 5 | `test.md` — 저장소 초기 테스트 파일 | 사용자가 만든 파일이라 손대지 않음 |
| 6 | codex 토큰 한도 | 아직 여유 (M0~M5a 누적 약 100만 토큰). 소진 시 즉시 사용자에게 보고하고 대기 |
| 12 | **codex는 이 PC에서 파일을 읽지 못한다** (읽기에도 셸을 씀) | **기존 파일 수정 위임 시 파일 전문을 지시서에 첨부** (D-014) |
| 13 | 안 주운 젬이 무한히 쌓임 (수명 없음) | M7 성능 측정에서 재검토 |
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
