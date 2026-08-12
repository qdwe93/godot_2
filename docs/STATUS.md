# STATUS — 진행 상황 및 재개 가이드

> **이 파일만 읽으면 작업을 이어서 할 수 있어야 한다.** 컴퓨터가 꺼져도, 세션이 끊겨도 여기서부터 재개한다.

**최종 갱신**: 2026-08-12
**현재 마일스톤**: M0 완료 → **다음은 M1 (플레이어 이동)**

---

## 한 줄 요약

Godot 4.7.1 프로젝트 골격을 만들고 헤드리스 실행까지 검증했다. 게임플레이 코드는 아직 하나도 없다.

## 완료된 것 (M0)

- [x] codex 표준 호출 방식 확정 및 스모크 테스트 → `CLAUDE.md` 참고
- [x] `project.godot` (1280×720, gl_compatibility, 메인 씬 지정)
- [x] 폴더 구조 `scenes/` `scripts/` `assets/` `docs/`
- [x] `.gitignore` (`.godot/` 캐시 제외)
- [x] `scenes/main.tscn` — 배경 ColorRect + 안내 Label만 있는 빈 씬
- [x] `scripts/main.gd` — 부팅 확인용 `M0_BOOT_OK` 출력
- [x] 헤드리스 임포트 + 실행 검증 통과 (종료 코드 0)
- [x] 문서 골격 (PRD / GDD / DECISIONS / devlog / CLAUDE.md)

## 바로 다음에 할 일 (M1: 플레이어 이동)

**목표**: WASD로 움직이는 플레이어. 화면 밖으로 나가지 않음.

1. `project.godot`에 InputMap 추가 — `move_left` / `move_right` / `move_up` / `move_down` 액션에 WASD **물리 키코드**로 바인딩
   - 물리 키코드를 쓰는 이유: 사용자의 키보드 레이아웃(예: AZERTY)이 달라도 같은 위치의 키가 작동하게 하려고
2. `scenes/player.tscn` — `CharacterBody2D` 루트 + `CollisionShape2D` + 플레이스홀더 스프라이트(ColorRect 또는 도형)
3. `scripts/player.gd` — `_physics_process`에서 입력 벡터 정규화 후 `velocity` 설정, `move_and_slide()` 호출
4. `main.tscn`에 플레이어 인스턴스 배치, 화면 경계 제한(clamp)
5. **시각 검증 수단 확보**: 헤드리스로는 화면을 볼 수 없으므로, 커맨드라인 인자를 받아 게임 내에서 스크린샷을 PNG로 저장하는 방식을 M1에서 함께 도입한다 (DECISIONS.md D-004 참고)

**M1 수용 기준(DoD)**: 창 모드로 실행 → WASD로 플레이어가 8방향 이동 → 대각선 이동 속도가 직선과 같음(정규화 확인) → 화면 밖으로 나가지 않음 → 헤드리스 실행 시 에러 없음

## 미해결 이슈 / 주의사항

| # | 내용 | 상태 |
|---|---|---|
| 1 | codex 샌드박스가 셸 프로세스를 못 띄움 (`CreateProcessAsUserW failed: 5`) | **우회 완료** — codex는 파일 쓰기만, 실행·git은 Claude가 담당. 작업지시서에 셸 금지 문구 필수 |
| 2 | 시각적 검증 수단이 아직 없음 | M1에서 인게임 스크린샷 저장 방식으로 해결 예정 |
| 3 | `test.md` — 저장소 초기 테스트 파일 | 사용자가 만든 파일이라 손대지 않음. 정리 원하면 알려줄 것 |
| 4 | codex 토큰 한도 | 아직 여유. 소진 시 즉시 사용자에게 보고하고 대기 (PROMPT.md 8절) |

## 재개 절차

```powershell
# 1. 마지막 커밋이 정상 실행되는지 확인
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --quit-after 30
```

종료 코드 0이면 정상. 그 후 위 "바로 다음에 할 일"을 진행한다.
