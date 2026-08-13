"""한 판을 초 단위로 시뮬레이션한다 — 게임을 돌리지 않고 생존 시간을 예측한다.

왜 필요한가
-----------
예측이 빗나간 이유 (M12b에서 배운 것)
------------------------------------
이 시뮬레이터는 **0차원**이다. 적과 플레이어의 위치를 모른다. 그래서 실제로 일어나는
다음 일을 못 본다.

    플레이어가 도망치면, 적은 뒤에서 쫓아오며 무기 사거리(350px) 밖에 머문다.

즉 화면 위에 있지만 **맞지 않는 적**이 계속 쌓인다. 시뮬레이터는 "화면에 들어온 적은
곧 죽는다"고 보므로 처치율을 과대평가하고, 그만큼 생존 시간을 길게 예측한다.
실제로 M12b 1차안에서 시뮬 718초 대 실측 392초로 1.8배 어긋났다.

**그러므로 이 도구로 절대 시간을 예측하지 마라.** 쓸 곳은 두 가지다.
  - 곡선에 절벽이 있는지 (스폰율이 한 페이즈에서 몇 배 뛰는지)
  - 후보 A와 B 중 어느 쪽이 더 오래 가는지의 **순서**

최종 수치는 반드시 `tests/diag_balance.tscn` 실측으로 정한다.

`tools/balance_model.py`는 페이즈별 **정적** 수지(처치율 대 스폰율)만 본다. 그것만으로는
"그래서 몇 초에 죽는가"를 답할 수 없다. 플레이어의 화력은 시간에 따라 자라고, 적은
쌓이고, 경험치는 처치 수에 비례하기 때문에 이 셋이 서로를 물고 돈다.

실측(`tests/diag_balance.tscn`)은 정확하지만 한 조건당 30초~2분이 걸리고, 3택 운 때문에
조건당 3회는 돌려야 한다. 후보안이 10개면 한 시간이다.

이 시뮬레이터는 1초 안에 끝난다. **후보를 거르는 데 쓰고, 살아남은 것만 실측한다.**

모델의 한계 (반드시 알고 쓸 것)
-------------------------------
- 명중률 100%. 투사체 비행 시간, 사거리, 화면 밖 적을 무시한다
- 적을 "평균 체력을 가진 균질한 덩어리"로 본다. 탱커 한 마리가 앞을 막는 상황을 못 본다
- **피해 모델이 경험식이다.** 아래 `FREE_ENEMIES` / `DAMAGE_SPREAD` 주석 참고

보정 상수는 실측에 맞춰 적합한 값이다. 즉 이 시뮬레이터는 **현재 수치에서 실측을
재현하도록 맞춰져 있고**(생존 94초/실측 94.4초, 처치 85회/실측 81회, 레벨 6/실측 6),
거기서 수치를 바꿨을 때의 방향과 크기를 예측한다.
절대값을 믿지 말고 **후보 A와 B의 비교**에 쓸 것. 최종 판단은 항상 실측이다.

쓰는 법
-------
    python tools/balance_sim.py                 # 현재 수치
    python tools/balance_sim.py --plan m12b     # 후보안
    python tools/balance_sim.py --plan m12b --verbose
"""

from __future__ import annotations

import argparse

DT = 0.25
MAX_TIME = 900.0

ENEMY_HP = {"basic": 10.0, "fast": 6.0, "tank": 40.0}
ENEMY_CONTACT = {"basic": 5.0, "fast": 4.0, "tank": 12.0}
ENEMY_SPEED = {"basic": 60.0, "fast": 115.0, "tank": 40.0}

# 적은 화면 밖 반지름 794px에서 생성되고, 무기 사거리는 350px이다. 즉 생성된 적은
# 한동안 **맞지 않는 상태로 걸어 들어온다.**
#
# 이걸 빼먹었더니 시뮬레이터가 "적이 생기는 즉시 죽는다"고 답해서 화면에 적이 0마리인
# 그림이 나왔다. 실측에서는 같은 시점에 8~15마리가 있다. 차이는 전부 이동 시간이다.
SPAWN_RADIUS = 794.0
WEAPON_RANGE = 350.0

PLAYER_BASE_HP = 100.0
INVINCIBILITY = 0.5
BASE_REGEN = 0.6          # scripts/player.gd health_regen
HEART_REGEN_PER_LEVEL = 0.4

# 무기 기본값 — scripts/weapon.gd / shotgun.gd / orbital.gd
WEAPON_DAMAGE, WEAPON_COOLDOWN = 5.0, 0.5
SHOTGUN_DAMAGE, SHOTGUN_COOLDOWN, SHOTGUN_PELLETS = 3.0, 1.0, 3
ORBITAL_DAMAGE, ORBITAL_INTERVAL = 4.0, 0.5

# 젬 1개당 경험치와 봇 실측 수집률 (devlog 017)
PICKUP_RATE = 0.65

# --- 실측 보정 상수 (devlog 017의 실측 로그에 맞췄다) ---
#
# ACCURACY: 이론 dps 중 실제로 적에게 꽂히는 비율. 투사체 비행 시간, 사거리 밖 적,
#   빗나감, 과잉 피해를 한 숫자로 뭉뚱그린 값이다.
#
# FREE_ENEMIES / DAMAGE_SPREAD: 회피 실패율 모델.
#   피격 확률 = clamp((적 수 - FREE_ENEMIES) / DAMAGE_SPREAD, 0, 1)
#
#   처음에는 확률을 적 수에 **선형 비례**시켰는데, 그러면 적이 5마리일 때도 계속
#   피가 깎여 "초반부터 서서히 죽는" 엉뚱한 그림이 나왔다. 실측 로그(DIAG_SAMPLE)는
#   정반대를 말한다 — 적이 21마리일 때까지 **HP가 만피로 유지**되다가, 57마리를
#   넘는 순간 15초 만에 120에서 16으로 무너진다.
#
#   즉 회피에는 문턱이 있다. 일정 수까지는 다 피하고, 그 위로는 급격히 무너진다.
#
#   처음에는 94초짜리 짧은 판 2건에만 맞춰 FREE=35 / SPREAD=62 로 잡았다. 그런데
#   M12b 곡선으로 판이 392초까지 늘어나자 이 값이 크게 어긋났다 — 적 30마리 언저리를
#   오래 유지하는 구간에서 모델은 "피해 0"이라고 했지만 실제로는 초당 1.75씩 깎였다.
#   **짧은 판만 보고 맞춘 상수는 긴 판에서 안 맞는다.** 지금 값은 392초 판의
#   (적 수, HP) 시계열 4점으로 다시 맞춘 것이다.
#
# 이 상수들은 **현재 수치 기준으로 맞춘 것**이다. 수치를 바꾼 뒤의 예측은 방향과
# 크기의 근사이지 절대값이 아니다. 최종 판단은 항상 실측이다.
ACCURACY = 0.46
FREE_ENEMIES = 20.0
DAMAGE_SPREAD = 79.0


# --------------------------------------------------------------------------
# 후보안 정의 — 하나의 plan이 "웨이브 곡선 + 경험치 + 업그레이드"를 모두 담는다
# --------------------------------------------------------------------------

CURRENT = {
    "label": "현재 (M12a 측정 시점)",
    "phases": [
        # start, interval, max_enemies, per_spawn, hp_mult, weights
        (0.0, 1.20, 40, 1, 1.0, {"basic": 1}),
        (30.0, 0.80, 60, 1, 1.2, {"basic": 1}),
        (60.0, 0.60, 80, 2, 1.5, {"basic": 3, "fast": 1}),
        (120.0, 0.45, 110, 2, 2.0, {"basic": 3, "fast": 2}),
        (180.0, 0.35, 140, 3, 2.8, {"basic": 3, "fast": 2, "tank": 1}),
        (240.0, 0.30, 160, 3, 3.5, {"basic": 2, "fast": 2, "tank": 2}),
        (330.0, 0.26, 180, 4, 5.0, {"basic": 2, "fast": 3, "tank": 2}),
        (450.0, 0.22, 200, 4, 7.5, {"basic": 1, "fast": 3, "tank": 3}),
        (600.0, 0.18, 220, 5, 11.0, {"basic": 1, "fast": 3, "tank": 4}),
        (780.0, 0.15, 240, 5, 16.0, {"fast": 3, "tank": 5}),
    ],
    "xp_base": 5.0,
    "xp_step": 3.0,
    "gem_value": {"basic": 1.0, "fast": 1.0, "tank": 1.0},
    # id: (최대 레벨, 종류)
    "upgrades": {
        "shotgun": (1, "shotgun"),
        "orbital": (1, "orbital"),
        "gloves": (5, "cooldown"),
        "heart": (5, "hp"),
        "shoes": (5, "speed"),
        "magnet": (3, "magnet"),
        "crown": (5, "xp"),
    },
    "gloves_mult": 0.92,
    "heart_flat": 20.0,
    "blade_mult": 1.0,
    "crown_mult": 1.10,
}


def make_plan(**overrides) -> dict:
    plan = {key: value for key, value in CURRENT.items()}
    plan.update(overrides)
    return plan


PLANS: dict[str, dict] = {"current": CURRENT}




# --------------------------------------------------------------------------



def build_phases(
    count: int,
    total_time: float,
    start_rate: float,
    end_rate: float,
    end_hp_mult: float,
    start_max: int = 40,
    end_max: int = 240,
    rate_shape: float = 0.7,
) -> list:
    """스폰율과 체력 배율을 기하급수로 잇는 페이즈 표를 만든다.

    손으로 13줄을 적으면 어디가 절벽인지 눈에 안 보인다. 두 끝점만 주고 사이를
    기하급수로 채우면 **절벽이 생길 수 없다** — 연속한 두 페이즈의 비가 항상 같다.

    `enemies_per_spawn`은 1로 고정한다. 이걸 1 -> 2로 올리는 순간 스폰율이 2배가
    되는데, `spawn_interval`은 되돌릴 수 없어서(테스트 불변식이자 설계 의도) 그
    절벽을 흡수할 방법이 없다. 60초 절벽이 정확히 이 문제였다.

    `rate_shape < 1`이면 스폰율이 앞쪽에서 더 빨리 오른다. 1.0으로 두면 초중반
    화면에 적이 7~10마리밖에 안 남아 심심하다 — 플레이어의 처치 속도가 스폰을
    한참 앞서기 때문이다. 0.7이면 중반 밀도가 15~25마리로 올라간다.
    """
    phases = []
    for index in range(count):
        t = index / float(count - 1)
        start_time = round(total_time * (index / float(count - 1)) ** 1.05, 0)
        rate = start_rate * (end_rate / start_rate) ** (t ** rate_shape)
        hp_mult = 1.0 * (end_hp_mult / 1.0) ** t
        interval = round(1.0 / rate, 2)
        max_enemies = int(round(start_max + (end_max - start_max) * t, -1))
        phases.append((start_time, interval, max_enemies, 1, round(hp_mult, 2), _weights_for(t)))
    return phases


def _weights_for(t: float) -> dict:
    """시간이 흐를수록 기본형에서 빠름·탱커로 옮겨 간다."""
    if t < 0.15:
        return {"basic": 1}
    if t < 0.30:
        return {"basic": 4, "fast": 1}
    if t < 0.45:
        return {"basic": 4, "fast": 2}
    if t < 0.60:
        return {"basic": 3, "fast": 2, "tank": 1}
    if t < 0.75:
        return {"basic": 3, "fast": 3, "tank": 2}
    if t < 0.90:
        return {"basic": 2, "fast": 3, "tank": 3}
    return {"basic": 1, "fast": 3, "tank": 4}


def phase_at(phases: list, elapsed: float):
    chosen = phases[0]
    for phase in phases:
        if elapsed >= phase[0]:
            chosen = phase
        else:
            break
    return chosen


def weighted(values: dict[str, float], weights: dict[str, int]) -> float:
    total = sum(weights.values())
    return sum(values[name] * weight for name, weight in weights.items()) / total


class Player:
    def __init__(self, plan: dict, priority: list[str]) -> None:
        self.plan = plan
        self.priority = priority
        self.levels: dict[str, int] = {}
        self.level = 1
        self.xp = 0.0
        self.max_hp = PLAYER_BASE_HP
        self.hp = PLAYER_BASE_HP
        self.picks = 0

    def level_of(self, upgrade_id: str) -> int:
        return self.levels.get(upgrade_id, 0)

    def dps(self) -> float:
        plan = self.plan
        cooldown_factor = plan["gloves_mult"] ** self.level_of("gloves")
        damage_factor = plan["blade_mult"] ** self.level_of("blade")

        total = WEAPON_DAMAGE * damage_factor / (WEAPON_COOLDOWN * cooldown_factor)

        shotgun_level = self.level_of("shotgun")
        if shotgun_level > 0:
            pellets = SHOTGUN_PELLETS + (shotgun_level - 1)
            total += pellets * SHOTGUN_DAMAGE * damage_factor / (SHOTGUN_COOLDOWN * cooldown_factor)

        orbital_level = self.level_of("orbital")
        if orbital_level > 0:
            total += orbital_level * ORBITAL_DAMAGE * damage_factor / ORBITAL_INTERVAL
        return total

    def regen(self) -> float:
        return BASE_REGEN + HEART_REGEN_PER_LEVEL * self.level_of("heart")

    def xp_needed(self) -> float:
        return self.plan["xp_base"] + self.plan["xp_step"] * (self.level - 1)

    def xp_multiplier(self) -> float:
        return self.plan["crown_mult"] ** self.level_of("crown")

    def gain_xp(self, amount: float) -> None:
        self.xp += amount * self.xp_multiplier()
        while self.xp >= self.xp_needed():
            self.xp -= self.xp_needed()
            self.level += 1
            self._pick_upgrade()

    def _pick_upgrade(self) -> None:
        upgrades = self.plan["upgrades"]
        for upgrade_id in self.priority:
            if upgrade_id not in upgrades:
                continue
            if self.level_of(upgrade_id) < upgrades[upgrade_id][0]:
                self.levels[upgrade_id] = self.level_of(upgrade_id) + 1
                self.picks += 1
                if upgrade_id == "heart":
                    self.max_hp += self.plan["heart_flat"]
                    self.hp = min(self.hp + self.plan["heart_flat"], self.max_hp)
                return


def simulate(plan: dict, priority: list[str], verbose: bool = False) -> dict:
    player = Player(plan, priority)
    phases = plan["phases"]
    alive = 0.0
    total_kills = 0.0
    elapsed = 0.0
    samples: list[tuple] = []
    next_sample = 0.0

    # 아직 사거리 밖에서 걸어 들어오는 적들. (남은 이동 시간, 마리 수)
    transit: list[list[float]] = []
    engaged = 0.0

    while elapsed < MAX_TIME and player.hp > 0.0:
        phase = phase_at(phases, elapsed)
        _, interval, max_enemies, per_spawn, hp_mult, weights = phase
        enemy_hp = weighted(ENEMY_HP, weights) * hp_mult
        contact_damage = weighted(ENEMY_CONTACT, weights)
        gem_value = weighted(plan["gem_value"], weights)
        travel_time = (SPAWN_RADIUS - WEAPON_RANGE) / weighted(ENEMY_SPEED, weights)

        spawn_rate = per_spawn / interval
        if alive < float(max_enemies):
            transit.append([travel_time, spawn_rate * DT])

        arrived = 0.0
        for entry in transit:
            entry[0] -= DT
            if entry[0] <= 0.0:
                arrived += entry[1]
        transit = [entry for entry in transit if entry[0] > 0.0]
        engaged += arrived

        kill_rate = player.dps() * ACCURACY / enemy_hp
        kill_rate = min(kill_rate, engaged / DT) if engaged > 0.0 else 0.0
        engaged = max(engaged - kill_rate * DT, 0.0)
        alive = engaged + sum(entry[1] for entry in transit)

        killed = kill_rate * DT
        total_kills += killed
        player.gain_xp(killed * gem_value * PICKUP_RATE)

        # 피해 — 회피 실패율이 적 밀도에 비례한다고 본다.
        # 무적 시간 때문에 초당 피격은 1/INVINCIBILITY 회가 상한이다.
        # 상수를 화면 전체 적 수(진단이 찍는 값)에 맞춰 적합했으므로 여기서도 alive를 쓴다.
        contact_chance = min(max((alive - FREE_ENEMIES) / DAMAGE_SPREAD, 0.0), 1.0)
        player.hp -= contact_chance * contact_damage / INVINCIBILITY * DT
        player.hp = min(player.hp + player.regen() * DT, player.max_hp)

        if elapsed >= next_sample:
            samples.append((elapsed, alive, player.level, player.dps(), player.hp, total_kills))
            next_sample += 30.0
        elapsed += DT

    if verbose:
        print(f"{'t':>6}{'적':>7}{'레벨':>6}{'dps':>8}{'HP':>8}{'누적처치':>10}")
        print("-" * 45)
        for sample_time, sample_alive, level, dps, hp, kills in samples:
            print(f"{sample_time:>5.0f}s{sample_alive:>7.0f}{level:>6}{dps:>8.0f}{hp:>8.0f}{kills:>10.0f}")
        print()

    return {
        "survived": elapsed,
        "level": player.level,
        "picks": player.picks,
        "dps": player.dps(),
        "kills": total_kills,
        "alive": alive,
    }


# --------------------------------------------------------------------------
# M12b 후보 — devlog 017의 진단 세 가지를 동시에 고친다
#
# 1) 스폰 절벽 제거: enemies_per_spawn을 늘리지 않고 spawn_interval만 줄인다.
#    per_spawn을 1 -> 2로 올리면 그 순간 스폰율이 2배가 되는데, spawn_interval은
#    (테스트 불변식과 설계 양쪽에서) 되돌릴 수 없으므로 절벽을 흡수할 방법이 없다.
#    간격만 쓰면 곡선이 매끄럽다.
# 2) 경험치 수입: 젬 값을 적 종류별로 다르게 준다 (탱커가 더 값지다).
# 3) 화력 성장: 칼날(공격력 +25% x5) 신설, 산탄/궤도구를 3레벨까지 성장시킨다.
# --------------------------------------------------------------------------

M12B = make_plan(
    label="M12b 출고 수치",
    # 14페이즈 / 900초 램프 / 스폰율 0.83 -> 4.0 per second / 체력 배율 1 -> 5
    #
    # 처음에는 끝스폰 8.0 / 끝HP 9.0 으로 잡았다. 시뮬레이션은 718초를 예측했지만
    # 실측은 392초였다. 시뮬레이터가 못 보는 것이 있다 — 아래 "예측이 빗나간 이유" 참고.
    # 실측을 보고 곡선을 완만하게 낮춘 값이 이것이다 (실측 572~886초).
    phases=build_phases(14, 900.0, 0.83, 4.0, 5.0),
    gem_value={"basic": 1.0, "fast": 1.0, "tank": 3.0},
    upgrades={
        "shotgun": (5, "shotgun"),
        "orbital": (5, "orbital"),
        "blade": (8, "damage"),
        "gloves": (5, "cooldown"),
        "heart": (5, "hp"),
        "shoes": (5, "speed"),
        "magnet": (3, "magnet"),
        "crown": (5, "xp"),
    },
    blade_mult=1.30,
)

PLANS["m12b"] = M12B


GREEDY = ["shotgun", "orbital", "blade", "gloves", "heart", "shoes", "magnet", "crown"]


def main() -> int:
    parser = argparse.ArgumentParser(description="한 판 시뮬레이션")
    parser.add_argument("--plan", default="current", choices=sorted(PLANS))
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    plan = PLANS[args.plan]
    print(f"[{plan['label']}]")
    result = simulate(plan, GREEDY, args.verbose)
    minutes, seconds = divmod(result["survived"], 60.0)
    print(
        f"생존 {result['survived']:.0f}초 ({minutes:.0f}분 {seconds:.0f}초) | "
        f"레벨 {result['level']} | 업그레이드 {result['picks']}개 | "
        f"최종 {result['dps']:.0f} dps | 누적 처치 {result['kills']:.0f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
