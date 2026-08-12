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

### 문법만 검사

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --check-only -s "res://scripts/main.gd"
```

### 창 모드 실행 (눈으로 확인할 때)

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --path "C:\Workspaces\game_make\test_godot_2" --quit-after 300
```

`--headless`를 빼면 실제 창이 뜬다. `--quit-after`로 반드시 자동 종료를 걸어 좀비 프로세스를 막는다.

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
