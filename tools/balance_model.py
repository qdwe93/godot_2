"""화력과 적 체력을 같은 축에 놓고 본다 — 게임을 돌리지 않고 계산만 한다.

왜 필요한가
-----------
봇 진단(`tests/diag_balance.gd`)은 한 판을 실제로 돌려 생존 시간을 잰다. 정확하지만
**한 번에 게임 시간만큼 걸린다.** 15분짜리 판은 15분이 든다.

밸런싱은 "바꾸고 → 재고 → 또 바꾸는" 반복이라, 매 후보안마다 실측을 돌리면 사이클이
성립하지 않는다. 이 스크립트는 수치만으로 **처치율 대 스폰율**을 뽑아 후보를 걸러낸다.
살아남은 후보만 실측으로 확인하면 된다.

모델의 한계 (반드시 알고 쓸 것)
-------------------------------
- 명중률 100%, 투사체가 항상 표적에 닿는다고 본다. 실제는 이보다 낮다.
- 궤도구는 항상 적 하나에 닿아 있다고 본다. 실제는 밀도에 따라 오르내린다.
- 회피·젬 수집 실패·화면 밖 스폰 지연을 무시한다.

즉 이 모델은 **플레이어에게 후하다.** 여기서도 처치율이 스폰율에 못 미치면
실제로는 확실히 못 미친다.

쓰는 법
-------
    python tools/balance_model.py
    python tools/balance_model.py --power 1.0   # 업그레이드 0개 상태
"""

from __future__ import annotations

import argparse

# 곡선은 **한 곳에서만** 정의한다.
#
# 예전에는 이 표를 wave_data.gd 와 balance_sim.py 양쪽에서 손으로 옮겨 적었다.
# 세 벌이 있으면 언젠가 갈라지고, 갈라진 순간부터 이 도구의 계산은 게임과 무관한
# 숫자가 된다. balance_sim 의 플랜에서 직접 가져온다.
import importlib.util as _importlib_util
from pathlib import Path as _Path

_spec = _importlib_util.spec_from_file_location(
    "balance_sim", _Path(__file__).resolve().parent / "balance_sim.py"
)
_balance_sim = _importlib_util.module_from_spec(_spec)
_spec.loader.exec_module(_balance_sim)

# 게임에 실제로 들어가 있는 곡선의 플랜 이름. wave_data.gd 를 바꿨으면 여기도 바꾼다.
ACTIVE_PLAN = "m16"
PHASES = _balance_sim.PLANS[ACTIVE_PLAN]["phases"]


ENEMY_HP = {"basic": 10.0, "fast": 6.0, "tank": 40.0}

# 무기 기본값 — scripts/weapon.gd / shotgun.gd / orbital.gd
WEAPON_DAMAGE, WEAPON_COOLDOWN = 5.0, 0.5
SHOTGUN_DAMAGE, SHOTGUN_COOLDOWN, SHOTGUN_PELLETS = 3.0, 1.0, 3
ORBITAL_DAMAGE, ORBITAL_INTERVAL = 4.0, 0.5

# scripts/upgrade_data.gd
GLOVES_MULTIPLIER, GLOVES_MAX_LEVEL = 0.92, 5
BLADE_MULTIPLIER, BLADE_MAX_LEVEL = 1.30, 8
SHOTGUN_MAX_LEVEL, ORBITAL_MAX_LEVEL = 5, 5

# 업그레이드 선택 횟수의 총합 = 최대 레벨의 합
# shoes5 heart5 magnet3 gloves5 crown5 blade8 shotgun5 orbital5
TOTAL_UPGRADE_PICKS = 5 + 5 + 3 + 5 + 5 + 8 + 5 + 5

# scripts/level_system.gd — 다음 레벨까지 필요한 경험치
XP_BASE, XP_STEP = 5.0, 3.0

# 젬 1개당 경험치 (scripts/xp_gem.gd) 와 봇 실측 수집률.
# 수집률은 devlog 017의 9회 측정에서 60~68% 범위였다. 중간값을 쓴다.
GEM_VALUE = 1.0
MEASURED_PICKUP_RATE = 0.65


def dps(gloves_level: int, shotgun_level: int, orbital_level: int, blade_level: int = 0) -> float:
    cooldown_factor = GLOVES_MULTIPLIER ** gloves_level
    damage_factor = BLADE_MULTIPLIER ** blade_level
    total = WEAPON_DAMAGE * damage_factor / (WEAPON_COOLDOWN * cooldown_factor)
    if shotgun_level > 0:
        pellets = SHOTGUN_PELLETS + (shotgun_level - 1)
        total += pellets * SHOTGUN_DAMAGE * damage_factor / (SHOTGUN_COOLDOWN * cooldown_factor)
    if orbital_level > 0:
        total += orbital_level * ORBITAL_DAMAGE * damage_factor / ORBITAL_INTERVAL
    return total


def average_enemy_hp(weights: dict[str, int], hp_multiplier: float) -> float:
    total_weight = sum(weights.values())
    weighted = sum(ENEMY_HP[name] * weight for name, weight in weights.items())
    return weighted / total_weight * hp_multiplier


def cumulative_xp(level: int) -> float:
    """레벨 `level`에 도달하기까지 필요한 누적 경험치."""
    return sum(XP_BASE + XP_STEP * (i - 1) for i in range(1, level))


def print_xp_table() -> None:
    """성장 속도의 상한 — 화력을 올려도 경험치가 안 들어오면 못 찍는다."""
    print()
    print(f"성장 비용 (젬 1개 = {GEM_VALUE:.0f} XP, 봇 실측 수집률 {MEASURED_PICKUP_RATE:.0%})")
    print(f"{'레벨':>5}{'누적 XP':>10}{'필요 처치':>11}{'1킬/초 기준':>14}")
    print("-" * 40)
    for level in (5, 6, 7, 10, 15, 20, 26):
        xp = cumulative_xp(level)
        kills = xp / GEM_VALUE / MEASURED_PICKUP_RATE
        print(f"{level:>5}{xp:>10.0f}{kills:>11.0f}{kills / 60.0:>12.1f}분")
    print(f"업그레이드를 전부 최대로 찍으려면 레벨 {TOTAL_UPGRADE_PICKS + 1}이 필요하다.")


def main() -> int:
    parser = argparse.ArgumentParser(description="처치율 대 스폰율 계산")
    parser.add_argument(
        "--power",
        type=float,
        default=None,
        help="화력 배율을 직접 지정한다 (기본: 시간대별로 도달 가능한 화력을 추정)",
    )
    args = parser.parse_args()

    floor_dps = dps(0, 0, 0, 0)
    ceiling_dps = dps(GLOVES_MAX_LEVEL, SHOTGUN_MAX_LEVEL, ORBITAL_MAX_LEVEL, BLADE_MAX_LEVEL)
    print(f"화력 하한 (업그레이드 0개)  {floor_dps:7.2f} dps")
    print(f"화력 상한 (전부 최대)       {ceiling_dps:7.2f} dps  = 하한의 {ceiling_dps / floor_dps:.1f}배")
    print()
    print(f"{'시작':>6} {'적HP평균':>9} {'스폰/초':>8} {'처치/초(상한)':>14} {'수지':>9}  판정")
    print("-" * 66)

    for start, interval, max_enemies, per_spawn, hp_multiplier, weights in PHASES:
        enemy_hp = average_enemy_hp(weights, hp_multiplier)
        spawn_rate = per_spawn / interval
        power = ceiling_dps if args.power is None else floor_dps * args.power
        kill_rate = power / enemy_hp
        balance = kill_rate - spawn_rate
        verdict = "처치 우세" if balance >= 0 else f"적자 {-balance:.2f}/초"
        print(
            f"{start:>5.0f}초 {enemy_hp:>9.1f} {spawn_rate:>8.2f} {kill_rate:>14.2f} "
            f"{balance:>9.2f}  {verdict}"
        )

    print()
    print("주의: 처치율은 명중률 100% 가정의 **상한**이다. 실제는 이보다 낮다.")
    print("     상한조차 스폰율에 못 미치는 구간은 실제로도 확실히 무너진다.")
    print_xp_table()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
