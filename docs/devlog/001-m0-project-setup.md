# 개발일지 001 — M0: 프로젝트 셋업

**날짜**: 2026-08-12
**마일스톤**: M0 (프로젝트 셋업)
**결과**: 완료. Godot 4.7.1 프로젝트가 헤드리스로 부팅되는 것까지 검증.

---

## 1. 오늘 한 일

1. 개발 환경 실측 (Godot·codex·gh 설치 상태와 버전)
2. codex 표준 호출 방식 확정 (스모크 테스트 2회)
3. codex에 프로젝트 골격 생성 위임
4. Godot 헤드리스 임포트 + 실행 검증
5. 문서 골격 작성 (PRD / GDD / DECISIONS / STATUS / CLAUDE.md)

## 2. 환경 실측 결과

프롬프트를 쓰기 전에 추측 대신 전부 확인했다. 추측이 틀렸을 때 나중에 드는 비용이 훨씬 크기 때문이다.

| 항목 | 확인된 사실 |
|---|---|
| Godot | 4.7.1 stable, `C:\Program Files (x86)\Godot\` — **PATH에 없음** |
| codex | 0.144.6, 모델 `gpt-5.6-sol`, 기본 추론 강도 `xhigh` |
| Antigravity | IDE만 설치됨. 헤드리스 에이전트 모드 없음 → 자동화에서 제외 |
| gh | qdwe93 계정 인증 완료, `repo` 스코프 있음 → 푸시 가능 |

**Godot 실행 파일이 두 개**라는 점이 중요했다. `Godot_v4.7.1-stable_win64.exe`(GUI용)와 `..._win64_console.exe`(콘솔용)가 있는데, **자동화에는 반드시 console 버전을 써야 한다.** 일반 버전은 Windows에서 콘솔에 stdout을 연결하지 않아서, 게임이 `print()`로 뭘 출력해도 CLI에서 받을 수 없다. 즉 검증이 불가능하다.

## 3. 시행착오 ①: codex 샌드박스가 셸을 못 띄운다

### 문제

첫 스모크 테스트에서 codex에게 "현재 폴더의 파일 개수를 세라"고 시켰더니, 셸 호출이 전부 실패했다.

```
ERROR codex_core::exec: exec error: windows sandbox: runner failed during SpawnChild:
CreateProcessAsUserW failed: 5 (액세스가 거부되었습니다.)
```

codex는 세 번 재시도했고 전부 같은 오류였다. 그런데도 최종 답변은 `SMOKE_OK 4`였다 — **셸 없이 다른 경로로 얻은 값이거나 추정치다.** 실제 파일은 그때 2개였으므로 이 답은 신뢰할 수 없었다. 이게 오히려 더 위험한 신호였다: **도구가 실패해도 codex는 그럴듯한 답을 내놓는다.** 검증 없이 codex 말만 믿으면 안 된다는 뜻이다.

### 원인

Windows용 codex 샌드박스가 제한된 토큰으로 자식 프로세스를 생성하려다 권한 거부(에러 5)를 받는다. 이 PC의 정책·권한 설정 문제로 보이며, codex 쪽 이슈라 우리가 고칠 대상이 아니다.

### 시도한 것과 판단

`--dangerously-bypass-approvals-and-sandbox` 플래그로 샌드박스를 통째로 끄면 셸이 살아날 가능성이 있었다. **시도하지 않기로 했다.** 먼저 "셸 없이도 코드 작성이 되는가"를 확인하는 게 순서였기 때문이다.

그래서 두 번째 스모크 테스트로 파일 생성만 시켜봤다:

```
codex exec -C <프로젝트> -s workspace-write "Create codex_write_test.txt containing WRITE_OK. Do not run any shell commands."
```

→ **성공.** codex는 셸이 아니라 apply_patch(diff 적용) 방식으로 파일을 쓰기 때문에 샌드박스 안에서도 정상 동작한다.

### 결론

샌드박스를 끌 이유가 사라졌다. 애초에 정한 역할 분담(codex=코딩, Claude=검증·git)과 정확히 맞아떨어진다. 자세한 판단 근거는 [DECISIONS.md](../DECISIONS.md) D-003.

**다만 파급 효과가 있다: codex는 자기가 쓴 코드를 스스로 실행해 볼 수 없다.** 컴파일 에러조차 확인이 안 된다. 그래서 앞으로 작업지시서에는 ① 셸 금지 문구를 명시하고 ② 수용 기준을 구체적으로 적고 ③ 불확실한 부분을 스스로 밝히게 한다. 실제로 M0 지시서 마지막에 "확신이 덜한 Godot 4.7 문법 가정을 명시하라"고 요구했고, codex는 "불확실한 부분 없음"이라고 답했다 — 그리고 검증 결과 정말로 문제가 없었다.

## 4. codex 작업지시 방식

PowerShell에서 긴 프롬프트를 인자로 넘기면 따옴표·개행 이스케이프가 깨진다. 그래서 **작업지시서를 텍스트 파일로 쓴 뒤 파이프로 넘기는 방식**을 표준으로 정했다.

```powershell
Get-Content <지시서.txt> -Raw | codex exec -C "<프로젝트 경로>" -s workspace-write -c model_reasoning_effort="medium"
```

추론 강도는 작업 난이도에 맞춰 `-c model_reasoning_effort=`로 조절한다. M0 골격 생성은 `medium`으로 충분했다(토큰 23k 사용). 스모크 테스트는 `low`로 낮췄다.

## 5. Godot 검증 — 헤드리스로 게임을 확인하는 법

Godot은 GUI 에디터 없이 CLI만으로 검증할 수 있다. 두 단계로 확인했다.

### ① 임포트

```powershell
& "...\Godot_v4.7.1-stable_win64_console.exe" --headless --path "<프로젝트>" --import
```

Godot은 프로젝트의 모든 리소스를 스캔해 `.godot/` 폴더에 임포트 캐시를 만든다. **파일을 새로 추가한 뒤 이 단계를 건너뛰면, 실행 시 리소스를 못 찾아 실패한다.** 에디터를 열면 자동으로 되는 일이라 GUI 사용자는 존재조차 모르는 단계인데, CLI 자동화에서는 반드시 명시해야 한다.

결과: 종료 코드 0, 오류 없음.

### ② 실행

```powershell
& "...\Godot_v4.7.1-stable_win64_console.exe" --headless --path "<프로젝트>" --quit-after 30
```

`--quit-after N`은 **N 프레임 후 자동 종료**시킨다. 이게 없으면 게임이 무한 루프로 돌아 CLI가 영원히 멈춘다. 자동화 검증의 핵심 플래그다.

결과:
```
M0_BOOT_OK { "major": 4, "minor": 7, "patch": 1, ... "string": "4.7.1-stable (official)" }
EXITCODE=0
```

부팅 확인용 토큰(`M0_BOOT_OK`)을 스크립트가 출력하게 설계한 게 유효했다. 종료 코드만 보면 "게임이 실제로 내 씬을 로드했는지"는 알 수 없지만, 이 토큰이 찍혔다는 건 **메인 씬이 로드되고 `_ready()`까지 실행됐다**는 증거다. 앞으로도 마일스톤마다 이런 검증 토큰을 심는다.

## 6. 미해결: 시각 검증 수단이 없다

헤드리스 모드는 **렌더링을 하지 않는다.** 화면에 뭐가 그려지는지는 알 수 없다. M0은 배경과 라벨뿐이라 넘어갔지만, M1부터는 "플레이어가 실제로 움직이는가"를 눈으로 봐야 한다.

해결 방향은 게임 코드 안에서 뷰포트를 PNG로 저장하는 것이다(`get_viewport().get_texture().get_image().save_png()`). 데스크톱 스크린샷보다 신뢰도가 높고 완전히 자동화된다. 단 **실제 창을 띄워야 하므로 `--headless` 없이 실행**해야 한다. M1에서 함께 구현한다. 근거는 [DECISIONS.md](../DECISIONS.md) D-004.

## 7. 다음 단계

M1(플레이어 이동). 상세 계획은 [STATUS.md](../STATUS.md) 참고.
