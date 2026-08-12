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
- GDScript 람다는 지역 변수를 **값으로 캡처**한다. 람다 안에서 지역 변수를 증가시켜도 바깥 값은 그대로다. 시그널 발생 횟수 같은 카운터는 멤버 변수나 Array 같은 참조형에 담아야 한다

### `.tscn` 편집

- 섹션 순서는 `[gd_scene]` → 모든 `[ext_resource]` → 모든 `[sub_resource]` → 모든 `[node]`. 어기면 씬 전체가 로드 실패한다.
- `load_steps` = ext_resource 개수 + sub_resource 개수 + 1. 리소스를 추가하면 반드시 같이 갱신한다.
- 노드 블록 사이에는 빈 줄을 넣는다.
- 기존 파일에 추가할 때는 **끝에 덧붙이지 말고 해당 섹션 안에 병합**한다. 스크립트도 마찬가지다 (함수 중복 선언은 파싱 에러).
- 노드 블록에서 `script = ExtResource(...)`는 **스크립트가 선언한 속성보다 먼저** 와야 한다. 순서가 뒤집히면 그 속성값은 조용히 버려진다 — 게임은 정상 실행되고 기능만 동작하지 않는다.
- 시그널 연결은 **객체를 만드는 쪽에서 그 자리에서** 한다. `get_tree().node_added` 같은 전역 훅으로 대신하지 않는다. 전역 훅은 모든 노드에 반응하고, 이름이 같은 시그널을 가진 무관한 노드까지 걸린다.

- 경험치 수집 테스트: `godot --headless --path . res://tests/test_experience.tscn`
