# 개발일지 008 — M6a: 업그레이드 효과 적용

**날짜**: 2026-08-13
**마일스톤**: M6a (패시브 5종의 실제 효과)
**결과**: 완료. 7스위트 34케이스 통과, 시행착오 0건.

---

## 1. 오늘 한 일

1. `upgrade_data.gd` — 업그레이드 정의를 한 곳에 모음
2. `upgrade_manager.gd` — 선택된 업그레이드를 실제 스탯에 반영
3. `tests/test_upgrades` — 5케이스
4. **기존 스크립트를 한 줄도 수정하지 않고** 노드 추가만으로 구현

## 2. 핵심 설계 — "현재값에 곱하기"를 금지한 이유

이동 속도 +10% 업그레이드를 구현하는 방법은 두 가지다.

```gdscript
# 방법 A — 현재값에 곱한다
player.speed *= 1.10

# 방법 B — 기본값에서 매번 다시 계산한다
player.speed = base_speed * pow(1.10, shoes_level)
```

**B를 택했다.** A는 짧지만 세 가지가 무너진다.

1. **부동소수점 오차가 누적된다.** 곱셈을 반복할수록 실제 값이 이론값에서 조금씩 멀어진다. 10레벨쯤 되면 밸런싱 수치를 계산해도 실제와 안 맞는다.
2. **되돌릴 수 없다.** 나중에 "저주 아이템으로 이속 감소" 같은 게 생기면, A는 나눗셈으로 되돌려야 하는데 순서에 따라 결과가 달라진다. B는 레벨만 빼고 다시 계산하면 끝이다.
3. **버그가 조용히 번진다.** A에서 어딘가 한 번 더 곱해지면 그 뒤로 모든 값이 계속 틀린 채 굴러간다. B는 항상 `기본값 × f(레벨)`이므로 어긋나는 순간 바로 드러난다.

테스트 케이스 2가 이걸 못박는다. 신발을 3번 고르면 기대값은 `200 × 1.1³ = 266.2`이고 실측도 정확히 266.2다. `200 × 1.1 × 3 = 660`이나 미세하게 어긋난 값이 나오면 실패한다.

## 3. 놓치기 쉬운 두 가지

### ① 이미 돌아가는 타이머는 export 값을 안 본다

무기 쿨다운은 코드에서 만든 `Timer` 노드가 관리한다. `weapon.cooldown` 값만 바꾸면 **이미 시작된 타이머는 예전 간격 그대로 계속 돈다.** 다음 프레임에도, 그 다음에도.

```gdscript
weapon.cooldown = new_value
timer.wait_time = new_value   # 이 줄이 없으면 업그레이드가 체감되지 않는다
```

에러는 안 난다. 그냥 "장갑을 골랐는데 공격이 안 빨라지네"가 된다. 테스트 케이스 4가 `cooldown`과 `Timer.wait_time`을 **둘 다** 검사한다.

### ② 리소스는 공유된다

자석 반경은 `CircleShape2D`라는 **리소스**의 속성이다. Godot에서 리소스는 여러 노드가 같은 인스턴스를 공유할 수 있다. 씬에서 만든 도형을 그대로 수정하면, 같은 도형을 쓰는 다른 노드까지 함께 바뀐다.

```gdscript
collision_shape.shape = collision_shape.shape.duplicate()   # 내 것으로 복제한 뒤
collision_shape.shape.radius = base_radius * pow(1.30, level)
```

테스트 케이스 5가 플레이어를 두 개 만들어 한쪽만 강화하고, **다른 쪽 반경이 60 그대로인지** 확인한다. 지금은 플레이어가 하나뿐이라 문제가 안 되지만, 적에게 같은 도형을 쓰거나 멀티플레이를 붙이는 순간 터질 종류의 버그다.

## 4. 기존 스크립트를 건드리지 않은 이유

`upgrade_manager`는 바깥에서 다른 노드의 속성을 읽고 쓴다. `player.gd`, `weapon.gd`, `level_up_ui.gd` 중 어느 것도 수정하지 않았다.

- 이 프로젝트에서 기존 파일 병합 실수로 **세 번** 빌드가 깨졌다(중복 `_process`, `.tscn` 섹션 순서, `script` 선언 위치). 추가만 하는 변경은 그 위험이 0이다.
- codex가 이 PC에서 파일을 못 읽으므로(D-014), 수정 대상이 없으면 지시서에 파일 전문을 붙일 필요도 없다. 토큰과 왕복이 함께 줄었다.
- 대가로 `upgrade_manager`가 다른 노드의 내부 구조(`Player/Weapon`의 `CooldownTimer` 이름 등)를 알아야 한다. 결합도가 올라간 것은 사실이고, M6b에서 무기를 추가할 때 이 지점을 다시 볼 것이다.

## 5. 미완 — 왕관(경험치 +10%)

경험치 획득 배율만 실제 경로에 연결되지 않았다. 젬이 경험치를 주는 흐름은 `젬 → player.add_experience() → LevelSystem`인데, 여기에 배율을 끼우려면 `player.gd` 또는 `xp_gem.gd`를 수정해야 한다. 이번 마일스톤의 "기존 파일 무수정" 원칙과 충돌해서 M6b로 미뤘다.

배율 자체는 `upgrade_manager.get_experience_multiplier()`로 계산되고 있으며, 코드 주석과 이 문서에 미연결 상태임을 명시했다. **동작하는 척하지 않는 것**이 중요하다 — 반쯤 된 기능을 완료로 적으면 나중에 "왜 경험치가 안 늘지"를 처음부터 다시 조사하게 된다.

## 6. 검증 결과

```
TEST_CASE shoes_multiplies_speed_exactly       PASS base=200.0000 expected=220.0000 actual=220.0000
TEST_CASE repeated_picks_compound_from_base    PASS base=200.0000 expected=266.2000 actual=266.2000
TEST_CASE heart_raises_max_hp_and_heals        PASS base_max=100 actual_max=140 base_health=100 actual_health=140
TEST_CASE gloves_updates_cooldown_and_live_timer PASS base=0.5000 expected=0.4232 cooldown=0.4232 timer_wait=0.4232
TEST_CASE magnet_scales_private_radius_only    PASS base=60.0000 first=78.0000 second=60.0000
TEST_RESULT PASS passed=5 failed=0 skipped=0
```

전체 7스위트 34케이스 통과, 실제 게임 30초 실행 시 런타임 에러 0건.

## 7. 다음 단계

M6b(신규 무기 2종 + 최대 레벨 상한 + 왕관 연결). 상세는 [STATUS.md](../STATUS.md).
