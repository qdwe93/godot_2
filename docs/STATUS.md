# STATUS — 진행 상황 및 재개 가이드

> **이 파일만 읽으면 작업을 이어서 할 수 있어야 한다.** 컴퓨터가 꺼져도, 세션이 끊겨도 여기서부터 재개한다.

**최종 갱신**: 2026-08-13
**현재 마일스톤**: **M7 완료** (M7a + M7b) → **다음은 M8 (HUD와 화면 흐름)**

---

## 한 줄 요약

**한 판의 루프가 완성되고 성장까지 실제로 작동한다.** 이동 → 적 스폰 → 자동 사격 → 처치 → 젬 드랍 → 자석 수집 → 레벨업 → 3택 선택 → **스탯이 실제로 변함** → 재개.

남은 큰 구멍 두 개: **무기가 기본 총 1종뿐**이고, **현재 밸런스로는 플레이어가 죽지 않는다**(M7).

**M7a에서 난이도 곡선이 들어가 이제 실제로 죽는다** (정지 상태 74초). 남은 것: 보스, 적 분리, HUD/화면 흐름, 폴리시, 밸런싱.

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

### M6a — 업그레이드 효과 적용
- [x] `upgrade_data.gd` — 정의 단일 출처 (id / 라벨 / 최대레벨 / 수치)
- [x] `upgrade_manager.gd` — **기본값 캡처 후 `base × f(level)` 재계산** (현재값 곱하기 금지)
- [x] 쿨다운 변경 시 **실행 중인 Timer.wait_time도 갱신** (안 하면 체감 안 됨)
- [x] 자석 반경은 `CircleShape2D.duplicate()` 후 변경 (공유 리소스 오염 방지)
- [x] **기존 스크립트 무수정**, 노드 추가만으로 구현
- [x] `tests/test_upgrades.tscn` — 5케이스. **전체 7스위트 34케이스 통과**

### M6b — 신규 무기와 레벨 상한
- [x] 왕관 경험치 배율을 실제 젬 경로에 연결 (`upgrade_manager` **그룹**으로 지연 조회, 매니저 없으면 원본 그대로)
- [x] `max_level` 상한 적용 — 남은 선택지 1~2개면 그만큼만, **0개면 화면 생략**(안 그러면 영구 정지)
- [x] 산탄 — 전방 부채꼴 3발 (-15°/0°/+15°), 초기 잠금
- [x] 궤도구 — **플레이어의 자식 노드로 공전**, 적별 피해 쿨다운, 초기 잠금
- [x] `tests/test_new_weapons.tscn` — 5케이스. **전체 9스위트 44케이스 통과**

### M7a — 난이도 곡선과 적 변종
- [x] `wave_data.gd` — 6페이즈 (간격 1.2→0.3초, 상한 40→160, 다중 스폰 1→3, **HP 배율 1.0→3.5**)
- [x] 적 3종(기본/빠른/탱커)을 **씬 복제 없이** 스탯 주입으로 구현
- [x] HP 배율은 **`add_child()` 이전에** 적용 (`_ready()`에서 `health = max_health`이므로)
- [x] `use_wave_data = false`로 기존 수동 설정 동작 보존
- [x] `tests/test_waves.tscn` — 6케이스. **전체 10스위트 50케이스 통과**
- [x] **실측: 정지 상태 플레이어가 74초에 사망** (이전에는 무한 생존). 적 63마리에서 145fps

### M7b — 보스와 적 분리
- [x] `boss_spawner.gd` — 300초에 **정확히 1마리**, 웨이브 가중치와 분리된 1회성 이벤트
- [x] `enemy.gd` 분리 로직 — 4프레임마다 재계산 + 인스턴스ID 분산 + 이웃 12개 상한 (O(n²) 회피)
- [x] `tests/test_boss_and_separation.tscn` — 6케이스. **전체 11스위트 62케이스 통과**
- [x] **실측: 최대 161마리에서 최저 144fps** → **오브젝트 풀링 도입 불필요 확정** (D-006 종결)
- [x] 테스트 실행에 `--quit-after 3600` 추가 (파싱 실패 시 무한 대기 방지)

## 바로 다음에 할 일 (M8: HUD와 화면 흐름)

**목표**: 플레이어가 자기 상태를 보고, 죽으면 다시 시작할 수 있다.

1. **HUD** (`CanvasLayer`) — HP바, 경험치바, 현재 레벨, 경과 시간, 처치 수
   - `CanvasLayer`여야 카메라·월드와 무관하게 화면에 고정된다
   - 데이터 출처는 이미 다 있다: `player.health_changed`, `LevelSystem.experience_changed`, `main.gd`의 생존 시간. **킬 수만 새로 세면 된다** (적 `died` 시그널을 카운트)
2. **화면 흐름**: 타이틀 → (시작) → 플레이 → (사망) → 게임오버(생존 시간·킬수·레벨) → (재시작) → 플레이
   - 재시작은 `get_tree().reload_current_scene()`이 가장 간단하다. 단 **일시정지 상태가 남아 있으면 새 씬도 멈춘 채 시작**하므로 반드시 `get_tree().paused = false`를 먼저 호출할 것
3. 현재 `GameOverLabel` 최소 구현을 정식 화면으로 교체
4. **캡처 도구와의 충돌 정리** — 무인 실행이 첫 레벨업에서 멈춰 캡처가 UI에 가린다. 캡처 헬퍼에 "레벨업 UI가 떠 있으면 자동 선택" 옵션(`--auto-upgrade`)을 넣으면 이후 모든 시각 검증이 편해진다
5. 테스트 — ① HP 변화가 바에 반영 ② 경험치·레벨 표시 갱신 ③ 킬 수 증가 ④ 사망 시 게임오버 화면 전환 ⑤ **재시작 후 일시정지가 풀린 상태로 시작** ⑥ 재시작 시 점수·레벨이 초기화

**M8 수용 기준(DoD)**: 전체 스위트 통과 + 캡처로 HUD 확인 + 재시작이 실제로 새 판을 시작하는지 확인

## 미해결 이슈 / 주의사항

| # | 내용 | 상태 |
|---|---|---|
| 1 | codex 샌드박스가 셸을 못 띄움 (`CreateProcessAsUserW failed: 5`) | **우회 완료** — codex는 파일 쓰기만, 실행·git은 Claude. 작업지시서에 셸 금지 문구 필수 |
| 2 | **헤드리스에서 뷰포트 높이가 틀리게 보고됨** (1280×720 → 1280×1280) | **우회 완료** — 화면 크기 의존 검증은 창 모드로만. 헤드리스에서는 SKIP 처리 (devlog 002) |
| 3 | 플레이어 크기 값(12)이 3곳에 중복 | 방치. M9 아트 교체 때 정리 |
| 4 | 화면 경계를 뷰포트 기준으로 계산 중 | 카메라 도입 시 월드 경계로 교체 (DECISIONS D-007, M7 재검토) |
| 5 | `test.md` — 저장소 초기 테스트 파일 | 사용자가 만든 파일이라 손대지 않음 |
| 6 | codex 토큰 한도 | **한도 도달 없음** (M0~M6a 누적 약 120만 토큰). 소진 시 즉시 사용자에게 보고하고 대기 |
| 14 | **실패 원인이 3연속으로 구현이 아니라 측정 쪽이었다** (M3 캡처 도구 / M5a 람다 캡처 / M6b 테스트 격리) | 테스트가 실패하면 **구현을 고치기 전에 측정 방법부터 의심**할 것 |
| 15 | 산탄·궤도구에 레벨 개념 없음 (한 번 얻으면 끝) | M10 |
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
