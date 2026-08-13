# CLAUDE.md — AI 작업 규칙 (요약본)

전체 지침은 [PROMPT.md](PROMPT.md)에 있다. 이 파일은 매 세션 반복해서 쓰는 **명령어와 규약**만 모아둔 치트시트다.

## 세션 시작 절차

1. `docs/STATUS.md` 읽기 (현재 마일스톤 / 다음 할 일)
2. 최신 `docs/devlog/` 파일 읽기
3. `git log --oneline -10`
4. 아래 "헤드리스 실행 검증"으로 마지막 커밋이 실행되는지 확인 후 이어서 작업

## 역할 분담

- **codex CLI = 메인 코더** (GDScript, .tscn 작성)
- **Claude = 지휘** (설계, 작업지시, 검증, git, 문서). 자명한 1~2줄 수정만 직접 처리
- **git 커밋/푸시는 항상 Claude가 한다**

## 검증된 명령어 (경로 그대로 복사해 쓸 것)

### codex 위임 — 표준 호출

```powershell
Get-Content <작업지시서.txt> -Raw | codex exec -C "C:\Workspaces\game_make\test_godot_2" -s workspace-write -c model_reasoning_effort="medium" 2>&1 | Select-Object -Last 40
```

- 긴 작업지시는 스크래치패드에 `.txt`로 쓴 뒤 파이프로 넘긴다 (PowerShell 이스케이프 문제 회피)
- `model_reasoning_effort`: 단순 구현 `low`~`medium`, 까다로운 설계·디버깅 `high`~`xhigh` (config.toml 기본값은 `xhigh`)
- 모델 기본값은 `gpt-5.6-sol`. 바꾸려면 `-m <모델명>`
- **`-s workspace-write` 유지.** 아래 제약 참고

### ⚠️ codex 제약 — 셸 실행 불가 (M0에서 확인)

이 PC의 codex는 샌드박스에서 프로세스를 띄우지 못한다 (`CreateProcessAsUserW failed: 5 액세스 거부`).
따라서 **codex 작업지시서에는 반드시 다음 문장을 넣는다**:

> Do NOT run any shell commands. The Windows sandbox cannot spawn processes on this machine; every shell call will fail. Use file read/write (apply_patch) only. Do NOT run git.

파일 읽기/쓰기(apply_patch)는 정상 동작하므로 코드 작성에는 지장이 없다. 실행·검증·git은 전부 Claude가 한다.

### Godot — 실행 파일 경로

PATH에 없으므로 항상 전체 경로로 호출한다.

- 에디터(GUI): `C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64.exe`
- CLI/헤드리스: `C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe` ← **자동화는 이걸 쓴다** (일반 exe는 콘솔에 stdout을 안 준다)

### 임포트 (에셋·씬 추가 후 필수)

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --import
```

새 파일을 추가하고 이걸 건너뛰면 실행 시 리소스를 못 찾고 실패한다.

### 헤드리스 실행 검증

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --quit-after 30
```

- `--quit-after N`은 **N 프레임 후 자동 종료**한다. 무한 대기를 막아주므로 자동화 검증의 핵심
- 종료 코드 0 + 스크립트가 출력하는 부팅 토큰(`M0_BOOT_OK` 등) 확인
- 런타임 에러는 stderr에 찍히므로 `2>&1`로 합쳐서 본다

### M1 플레이어 이동 자동 테스트

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path <project> res://tests/test_player_movement.tscn
```

- `TEST_CASE <이름> <PASS|FAIL|SKIP> <상세>`는 개별 케이스 결과, `TEST_RESULT <PASS|FAIL> passed=<n> failed=<n> skipped=<n>`은 최종 결과다. `SKIP`은 통과 수에 포함하지 않는다.
- 전체 통과 시 종료 코드 0, 실패 시 1을 반환한다.
- 이동 bounds 테스트는 헤드리스에서도 실행한다. 창 모드는 시각·캡처 검증에만 필요하다.

### M2 적 생성·추적 자동 테스트

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path <project> res://tests/test_enemy_spawn.tscn
```

- 주기 생성, 화면 밖 생성 위치, 플레이어 추적, 최대 적 수 제한을 헤드리스에서 검증한다.

### M3 자동 조준·발사 자동 테스트

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path <project> res://tests/test_weapon.tscn
```

- 무표적 미발사, 최근접 조준, 피해·사망, 발사체 수명, 개수 상한을 헤드리스에서 검증한다.

### M4 접촉 피해·체력·사망 자동 테스트

```powershell
Godot_v4.7.1-stable_win64_console.exe --headless --path <project> res://tests/test_player_damage.tscn
```

- 접촉 피해, 무적 시간, 지속 접촉 재피격, 사망, 사망 후 적 생존을 헤드리스에서 검증한다.

### 문법만 검사

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --check-only -s "res://scripts/main.gd"
```

#### 스크립트 변경 후 필수

스크립트를 변경하면 검증자는 위 명령의 `-s` 경로를 바꿔 변경된 각 스크립트를 검사한다.

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --check-only -s "res://scripts/player.gd"
```

Godot 4.7에서는 `Variant` 값으로부터 `:=` 타입을 추론하는 선언이 경고가 아니라 파싱 오류다. `get()`, `get_setting()`, 타입 없는 딕셔너리 접근 등에는 명시적 타입을 쓴다.

### 창 모드 실행 (눈으로 확인할 때)

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --path "C:\Workspaces\game_make\test_godot_2" --quit-after 300
```

`--headless`를 빼면 실제 창이 뜬다. `--quit-after`로 반드시 자동 종료를 걸어 좀비 프로세스를 막는다.

스크린샷 캡처는 `--capture=<저장 경로> --capture-after=<초>`를 추가한다 (기본 3.0초). 캡처에는 창 모드 실행이 필요하므로 `--headless`를 쓰지 않는다.

**렌더 프레임 수는 경과 시간의 척도가 아니다.** 화면이 단순하면 수천 fps로 돌아가므로 프레임 수로 기다리면 실제로는 몇 초밖에 지나지 않는다.

## 프로젝트 규약

| 폴더 | 용도 |
|---|---|
| `scenes/` | `.tscn` 씬 파일 |
| `scripts/` | `.gd` 스크립트 |
| `assets/` | 아트·오디오 |
| `docs/` | 모든 문서 (한글 내용, 영문 파일명) |

- 엔진: Godot **4.7.1 stable**, 렌더러 `gl_compatibility`, 해상도 1280×720
- 언어: GDScript만 사용
- 문서 내용은 한글, 파일명은 영문 (인코딩 문제 회피)
- 커밋 메시지는 한글. 예: `M1: 플레이어 WASD 이동 구현`
- `.godot/` 는 커밋하지 않는다 (.gitignore 처리 완료)
- **`process_mode` 값은 기억으로 쓰지 말 것.** 실제 값은 `INHERIT=0, PAUSABLE=1, WHEN_PAUSED=2, ALWAYS=3, DISABLED=4`. 2와 3을 바꿔 쓰면 **평소에 멈춰 있는 노드**가 되는데 에러는 안 난다. 확신이 없으면 `print(Node.PROCESS_MODE_ALWAYS)`로 한 줄 확인한다
  - 일시정지 중에도 눌려야 하는 UI(레벨업 3택) → `3`(ALWAYS) 또는 `2`(WHEN_PAUSED)
  - 항상 갱신돼야 하는 HUD → 반드시 `3`(ALWAYS)
- GDScript 람다는 지역 변수를 **값으로 캡처**한다. 람다 안에서 지역 변수를 증가시켜도 바깥 값은 그대로다. 시그널 발생 횟수 같은 카운터는 멤버 변수나 Array 같은 참조형에 담아야 한다

### `.tscn` 편집

- 섹션 순서는 `[gd_scene]` → 모든 `[ext_resource]` → 모든 `[sub_resource]` → 모든 `[node]`. 어기면 씬 전체가 로드 실패한다.
- `load_steps` = ext_resource 개수 + sub_resource 개수 + 1. 리소스를 추가하면 반드시 같이 갱신한다.
- 노드 블록 사이에는 빈 줄을 넣는다.
- 기존 파일에 추가할 때는 **끝에 덧붙이지 말고 해당 섹션 안에 병합**한다. 스크립트도 마찬가지다 (함수 중복 선언은 파싱 에러).
- 노드 블록에서 `script = ExtResource(...)`는 **스크립트가 선언한 속성보다 먼저** 와야 한다. 순서가 뒤집히면 그 속성값은 조용히 버려진다 — 게임은 정상 실행되고 기능만 동작하지 않는다.
- 시그널 연결은 **객체를 만드는 쪽에서 그 자리에서** 한다. `get_tree().node_added` 같은 전역 훅으로 대신하지 않는다. 전역 훅은 모든 노드에 반응하고, 이름이 같은 시그널을 가진 무관한 노드까지 걸린다.

## 밸런스 측정 (M12a에서 상설화)

**진단 스크립트를 매번 새로 쓰지 말 것.** M10에서 그러다 같은 함정(일시정지 중 `physics_frame` 미발생, 출력 버퍼링)에 반복해서 걸렸다.

### 0단계 — 곡선은 손으로 적지 말 것

`wave_data.gd`의 `PHASES` 14줄은 `tools/balance_sim.py`의 `build_phases()`가 생성한 값이다. 두 끝점(시작·끝 스폰율, 끝 체력 배율)만 주면 사이를 기하급수로 채우므로 **절벽이 생길 수 없다**. 손으로 한 줄만 고쳐도 그 보장이 깨진다.

**`enemies_per_spawn`은 1로 고정한다.** 1에서 2로 올리는 순간 스폰율이 정확히 2배가 되는데 `spawn_interval`은 되돌릴 수 없어 흡수할 방법이 없다. 예전 곡선의 60초 절벽이 이 문제였다. 밀도는 오직 `spawn_interval`로만 올린다.

### 1단계 — 계산으로 후보 거르기 (게임을 안 돌린다)

```bash
python tools/balance_model.py
```

```bash
python tools/balance_sim.py --plan m12b --verbose
```

`balance_model.py`는 페이즈별 **처치율 대 스폰율**과 성장 비용을, `balance_sim.py`는 한 판을 초 단위로 시뮬레이션한다. `wave_data.gd`를 고쳤으면 두 파일의 수치도 같이 고친다.

> ⚠️ **시뮬레이터로 절대 시간을 예측하지 마라.** 0차원 모델이라 "도망치는 플레이어를 사거리 밖에서 쫓아오는 적"을 못 본다. M12b에서 시뮬 718초 대 실측 392초로 1.8배 어긋났다. 쓸 곳은 ① 곡선에 절벽이 있는지 ② 후보 A와 B의 **순서** 두 가지뿐이고, 최종 수치는 반드시 실측으로 정한다.

### 2단계 — 실측

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --quit-after 20000000 "res://tests/diag_balance.tscn" -- "--mode=bot" "--pick=greedy" "--max=900" "--speed=3" > <출력파일> 2>&1
```

| 인자 | 뜻 |
|---|---|
| `--mode=bot\|idle` | 봇 조작 / 무입력(하한값) |
| `--pick=random\|greedy` | 3택 선택 전략. `greedy`는 산탄→궤도구→장갑→심장→신발→자석→왕관 고정 |
| `--max=<초>` | 게임 시간 상한 |
| `--sample=<초>` | 샘플 간격 (기본 15) |
| `--speed=<배>` | `Engine.time_scale` 배속 |

- **`--pick=greedy`를 빼면** 무작위 선택이라 "게임이 약한 것"과 "선택이 나쁜 것"이 섞여 해석이 안 된다. greedy 우선순위는 `tools/balance_sim.py`의 `GREEDY`와 같은 순서로 맞춰 둔다
- **`--speed=3`이면 소요 시간이 정확히 1/3**이 된다. 배속 왜곡은 검출되지 않았다 (devlog 017 4절)
- **한 조건당 최소 3회.** 3택 운에 따른 편차가 20초를 넘는다
- 출력은 **파일로 직접 리다이렉트**한다. 파이프로 받으면 버퍼링되어 진행이 안 보인다
- `DIAG_RESULT`가 최종 결과, `DIAG_SAMPLE`이 시계열, `DIAG_UPGRADE`가 선택 시점이다

## 전체 테스트 스위트 (한 번에 돌리기)

```powershell
foreach ($t in @("test_player_movement","test_enemy_spawn","test_weapon","test_player_damage","test_experience","test_level_up_ui","test_upgrades","test_upgrade_limits","test_new_weapons","test_waves","test_boss_and_separation","test_hud","test_game_flow","test_effects","test_scene_wiring","test_feedback","test_visual_hierarchy","test_power_growth")) { $r = & "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --quit-after 3600 "res://tests/$t.tscn" 2>&1 | Select-String -Pattern "TEST_RESULT|TEST_ERROR"; "$t => $r (exit=$LASTEXITCODE)" }
```

| 스위트 | 케이스 | 검증 내용 |
|---|---|---|
| `test_player_movement` | 3 | 이동량, 대각선 정규화, 화면 경계 |
| `test_enemy_spawn` | 4 | 주기 스폰, 화면 밖 위치, 추적, 개수 상한 |
| `test_weapon` | 7 | 조준·사거리·경계값, 명중/사망, 수명, 무한증식 방지 |
| `test_player_damage` | 5 | 접촉 피해, 무적, 지속 접촉 재피격, 사망, 사망 후 적 생존 |
| `test_experience` | 5 | 젬 드랍, 자석 범위, 수집, 곡선, 다중 레벨업 |
| `test_level_up_ui` | 5 | 일시정지, 3택 중복 없음, 일시정지 중 처리, 재개, 연속 레벨업 대기열 |
| `test_upgrades` | 5 | 배율 정확도, 기본값 기준 복리, HP 증가+회복, 라이브 타이머 반영, 공유 리소스 미오염 |
| `test_upgrade_limits` | 5 | 왕관 경험치 배율, 매니저 부재 시 안전, 상한 도달 제외, 선택지 2개, 0개 시 화면 생략 |
| `test_new_weapons` | 5 | 잠금 상태 무동작, 산탄 3발, 부채꼴 각도, 궤도구 추종, 적별 피해 제한 |
| `test_waves` | 8 | **불변식 기반** — 시작 시각 엄격 증가, 전 페이즈 도달 가능, 경계 배타성, 곡선 단조성, 변종 id 실재, HP 배율, 변종 스탯, 레거시 모드 |
| `test_boss_and_separation` | 6 | 보스 1회 스폰, 보스 스탯, 화면 밖, 적 분리, 추적 유지, 분리 비활성화 |
| `test_hud` | 6 | 초기 표시값, HP 반영, 경험치·레벨, 킬 카운트, 타이머 서식, 사망 시 정지 |
| `test_game_flow` | 6 | 타이틀 정지, 시작 해제, 사망 요약, 재시작 전 정지 해제, auto-play 2건 |
| `test_effects` | 6 | 이펙트 자동 해제, 프레임 진행, 컨테이너 배치, 크기 비례, 흔들림 복원 2건 |
| `test_scene_wiring` | 6 | **배선 스모크** — 전 업그레이드 노출, 그룹 실재, 교차 메서드 실재, 플레이어 자식 노드, 시그널, 보스 드랍 연결 |
| `test_feedback` | 5 | 명중 이펙트 생성, 피격 번쩍, 번쩍 복원, 위험 상태 진입·해제 |
| `test_visual_hierarchy` | 4 | **시각 규칙** — 밝기 순서, 전 요소 3:1 대비, 플레이어 최상위, 적 형태 구분 |
| `test_power_growth` | 8 | **성장 경로** — 칼날이 세 무기 전부에 적용, 기본값 기준 복리, 산탄 탄수·궤도구 피해 레벨링, `max_level=1` 회귀 방지, 체력 재생, 젬 값 전달 |

> ⚠️ `test_enemy_spawn`은 **간헐적으로 1케이스가 실패**한다 (12회 중 1회 관측, 재현 8회 실패). 스폰 개수·추적 거리가 타이머 위상에 민감한 것으로 추정. 한 번 실패하면 재실행해 보고, 반복되면 허용 오차를 넓힐 것.

### ⚠️ 테스트에 목록을 하드코딩하지 말 것

`test_waves`가 밸런스 수치를, `test_upgrade_limits`가 업그레이드 id 목록을 하드코딩해서 **튜닝과 콘텐츠 추가를 두 번 막았다**.
값이 아니라 **불변식**을 검사하고, 목록은 `WaveData.PHASES` / `UpgradeData.get_all_ids()`처럼 **정의에서 읽어 온다**.

### ⚠️ 유닛 통과 ≠ 배선 연결

이 프로젝트에서 "정의는 있는데 게임에서 실행되지 않는" 버그가 3건 나왔다 (산탄·궤도구 미노출, `spawn_hit()` 호출처 0건, 보스 드랍 메서드 이름 불일치).
전부 유닛 테스트를 통과했다. **그룹 이름·문자열 메서드·선택지 노출을 바꿨으면 `test_scene_wiring`을 돌린다.**

### 스프라이트를 바꿨으면 축소해서 재라

원본 크기로 보면 절대 못 잡는다. AI 생성물 8장 중 6장이 이 검사에서 걸렸다.

```bash
python tools/check_sprite_luminance.py assets/sprites
```

휘도(어두운 디테일)·충전율(슬롯 대비 크기)·밝기 순서 세 가지를 본다.
`.tscn`의 `Polygon2D`를 `Sprite2D`로 바꾸면 `enemy_spawner.gd`·`boss_spawner.gd`·`enemy.gd`의
`color` 주입이 **에러 없이 조용히 죽는다** (`Sprite2D`에는 `color`가 없다).

## 빌드 (Windows / 웹 / Android)

절차와 함정은 [docs/BUILD.md](docs/BUILD.md)에 있다. 프리셋은 `export_presets.cfg`.
Android는 `--export-debug`를 쓴다 (릴리스 키스토어 없음). `build/.gdignore`를 지우지 말 것 — 지우면 웹 산출물이 프로젝트 에셋으로 재임포트된다.

## 게임 실행 — 타이틀 화면과 자동 진행

M8b부터 게임은 **타이틀 화면에서 일시정지한 채 시작**한다. 자동화 실행(캡처·진단·장시간 측정)은 반드시 `--auto-play`를 넘겨야 한다.

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --path "C:\Workspaces\game_make\test_godot_2" -- "--auto-play" "--capture=<경로>.png" "--capture-after=<초>"
```

`--auto-play`는 두 가지를 한다: ① 타이틀을 건너뛰고 즉시 시작 ② **레벨업 UI가 뜨면 자동으로 첫 선택지를 고른다.** 이게 없으면 무인 실행은 타이틀에서, 혹은 첫 레벨업에서 영원히 멈춘다.

> **테스트 실행에 `--quit-after 3600`을 반드시 붙인다.** 테스트 스크립트가 파싱 실패하면 `quit()`이 호출되지 않아 **프로세스가 무한 대기**한다. `TEST_ERROR` 보호 장치는 스크립트가 로드된 뒤에야 작동하므로 이 경우를 못 막는다.

> **무인 실행은 첫 레벨업에서 멈춘다.** 3택 UI가 일시정지한 채 입력을 기다리기 때문이다. 장시간 밸런스 측정을 하려면 진단 스크립트가 `level_ui.choose(0)`으로 자동 선택해야 한다.

전부 `TEST_RESULT PASS`와 종료 코드 0이어야 한다. `TEST_ERROR`가 보이면 케이스가 실행조차 안 된 것이다.
