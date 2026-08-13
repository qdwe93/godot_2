# BUILD — 내보내기(Export) 절차

> Godot 에디터를 열지 않고 실행 가능한 빌드를 만드는 방법. 전부 헤드리스 CLI로 처리한다.
> 프리셋 정의는 저장소 루트의 `export_presets.cfg`에 있다. 산출물은 `build/` 아래에 생기며 `.gitignore` 처리되어 있다.

## 대상 플랫폼

| 플랫폼 | 프리셋 이름 | 산출물 | 비고 |
|---|---|---|---|
| Windows | `Windows Desktop` | `build/windows/TangtangSurvivors.exe` | pck 내장(단일 파일), x86_64 |
| 웹 | `Web` | `build/web/index.html` 외 8개 | 싱글 스레드(nothreads) 템플릿 |
| Android | `Android` | `build/android/TangtangSurvivors-debug.apk` | arm64-v8a + armeabi-v7a, **디버그 서명** |

iOS는 대상에서 제외한다.

## 명령어

먼저 임포트를 한 번 돌린다 (에셋이나 씬을 추가했다면 필수).

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --import
```

### Windows

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --export-release "Windows Desktop" "C:\Workspaces\game_make\test_godot_2\build\windows\TangtangSurvivors.exe"
```

### 웹

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --export-release "Web" "C:\Workspaces\game_make\test_godot_2\build\web\index.html"
```

### Android (디버그 서명)

```powershell
& "C:\Program Files (x86)\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "C:\Workspaces\game_make\test_godot_2" --export-debug "Android" "C:\Workspaces\game_make\test_godot_2\build\android\TangtangSurvivors-debug.apk"
```

## 실행 방법

### Windows

`build/windows/TangtangSurvivors.exe`를 더블클릭하면 된다. 타이틀 화면에서 **시작**을 누른다.

무인 실행(캡처·측정)에는 `--auto-play`가 필요하다. 게임 인자는 `--` 뒤에 넘긴다.

```powershell
Start-Process -FilePath "C:\Workspaces\game_make\test_godot_2\build\windows\TangtangSurvivors.exe" -ArgumentList '--','--auto-play','--capture=C:\temp\shot.png','--capture-after=25' -Wait
```

### 웹

**로컬 파일(`file://`)로 열면 동작하지 않는다.** HTTP로 서빙해야 한다.

```bash
python -m http.server 8123 --directory build/web --bind 127.0.0.1
```

브라우저에서 `http://127.0.0.1:8123/index.html`을 연다. 캔버스를 한 번 클릭해 포커스를 준 뒤 조작한다.

### Android

```bash
adb install -r build/android/TangtangSurvivors-debug.apk
```

## 알아둘 것

### Android는 현재 조작이 불가능하다

입력이 **WASD 키보드 전용**이다(`project.godot`의 InputMap이 물리 키코드로만 바인딩됨). APK는 설치·실행되지만 터치 조작이 없어서 **물리 키보드나 게임패드를 붙이지 않으면 플레이할 수 없다.** PRD도 모바일·터치를 범위 밖으로 명시하고 있다. 터치를 지원하려면 가상 조이스틱이 별도 작업으로 필요하다.

### Android 릴리스 서명은 아직 없다

`--export-release "Android"`는 릴리스 키스토어가 없어 서명 단계에서 실패한다. 지금은 Godot 기본 디버그 키스토어로 서명한 `--export-debug`를 쓴다. 배포가 필요해지면 `keytool`로 릴리스 키스토어를 만들고 프리셋에 연결해야 한다. **키스토어 비밀번호를 `export_presets.cfg`에 넣어 커밋하지 말 것.**

### 빌드에 필요했던 프로젝트 설정 두 가지

- `rendering/textures/vram_compression/import_etc2_astc=true` — 없으면 Android 내보내기가 설정 오류로 거부된다
- `display/window/handheld/orientation="landscape"` — 1280×720 가로 화면 기준이므로 세로로 뜨지 않게 고정

### `build/`는 Godot 스캔에서 제외한다

`build/.gdignore`가 있어야 한다. 없으면 웹 산출물의 PNG들이 **프로젝트 에셋으로 다시 임포트되어** 다음 빌드의 pck에 섞여 들어간다.

### 테스트는 빌드에 포함되지 않는다

세 프리셋 모두 `exclude_filter="tests/*"`다. 자동 테스트 씬은 산출물에 들어가지 않는다.

## 검증 기록 (2026-08-13)

| 플랫폼 | 결과 |
|---|---|
| Windows | 실행 후 25초 캡처 성공. HUD·적·투사체·사망 이펙트 정상 렌더 |
| 웹 | 브라우저 콘솔에 `BOOT_OK milestone=M9 actions_ok=true`, `FLOW_TITLE_SHOWN` 출력. WebGL2 컨텍스트 확보 |
| Android | APK 서명·검증 통과. `lib/arm64-v8a`, `lib/armeabi-v7a` 양쪽 네이티브 라이브러리 포함 (실기기 설치는 미검증) |
