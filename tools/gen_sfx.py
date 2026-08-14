"""효과음 6종을 생성한다 (16bit mono 44.1kHz WAV).

**왜 직접 만드는가.** CC0 팩을 받아 쓰면 출처·라이선스를 계속 따라다녀야 하고,
받은 음원의 길이·음량이 제각각이라 게임 안에서 다시 맞춰야 한다. 여기서 만든
소리는 전부 이 파일이 근거이므로 라이선스 문제가 없고, 수치를 고쳐 다시 돌리면
그대로 재현된다.

    python tools/gen_sfx.py

주의: 음량은 여기서 이미 맞춰 둔다. 게임 쪽에서 dB로 다시 깎기 시작하면
"어느 쪽이 진짜 음량인지" 알 수 없어진다.
"""

import math
import os
import random
import struct
import wave

RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio", "sfx")


def _write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    print("%-14s %5.0f ms  peak=%.2f" % (name, len(samples) / RATE * 1000.0, peak))


def _env(index, total, attack, release):
    """어택-릴리스 포락선. 딸깍 소리(클릭 노이즈)를 막는 게 목적이다."""
    attack_samples = max(1, int(attack * RATE))
    release_samples = max(1, int(release * RATE))
    if index < attack_samples:
        return index / attack_samples
    remaining = total - index
    if remaining < release_samples:
        return remaining / release_samples
    return 1.0


def _square(phase):
    return 1.0 if math.sin(phase) >= 0.0 else -1.0


def _tone(duration, start_hz, end_hz, volume, wave_fn, attack=0.004, release=0.02):
    total = int(duration * RATE)
    out = []
    phase = 0.0
    for i in range(total):
        t = i / total
        hz = start_hz * pow(end_hz / start_hz, t)
        phase += 2.0 * math.pi * hz / RATE
        out.append(wave_fn(phase) * volume * _env(i, total, attack, release) * (1.0 - t * 0.35))
    return out


def _mix(*layers):
    length = max(len(layer) for layer in layers)
    out = [0.0] * length
    for layer in layers:
        for i, value in enumerate(layer):
            out[i] += value
    return out


def shoot():
    """발사 — 초당 10발 넘게 겹치므로 짧고 작아야 한다. 길면 소음이 된다."""
    return _tone(0.07, 900.0, 320.0, 0.30, _square, attack=0.002, release=0.03)


def hit():
    """적 명중 — 짧은 노이즈 '틱'. 발사보다도 작다 (산탄 7발이면 7번 난다)."""
    total = int(0.055 * RATE)
    rng = random.Random(20260814)
    out = []
    for i in range(total):
        noise = rng.uniform(-1.0, 1.0)
        out.append(noise * 0.22 * pow(1.0 - i / total, 2.4) * _env(i, total, 0.001, 0.01))
    return _mix(out, _tone(0.05, 620.0, 380.0, 0.12, math.sin, attack=0.001, release=0.02))


def pickup():
    """젬 획득 — 한꺼번에 수십 번 불려도 소음이 되지 않도록 아주 짧고 작게 만든다."""
    return _mix(
        _tone(0.05, 880.0, 1400.0, 0.16, math.sin, attack=0.001, release=0.018),
        _tone(0.05, 1760.0, 2800.0, 0.035, math.sin, attack=0.001, release=0.018),
    )


def hurt():
    """주인공 피격 — 낮고 거칠게. 무적 시간이 있어 자주 나지 않는다."""
    total = int(0.22 * RATE)
    rng = random.Random(4041)
    noise = [rng.uniform(-1.0, 1.0) * 0.16 * pow(1.0 - i / total, 1.6) * _env(i, total, 0.002, 0.03) for i in range(total)]
    return _mix(noise, _tone(0.22, 300.0, 90.0, 0.42, _square, attack=0.002, release=0.05))


def level_up():
    """레벨업 — 화면이 멈추므로 유일하게 '음악'이어도 되는 자리다. 4음 상행."""
    notes = [523.25, 659.25, 783.99, 1046.50]
    out = [0.0] * int(0.62 * RATE)
    step = int(0.085 * RATE)
    for index, hz in enumerate(notes):
        length = 0.30 if index == len(notes) - 1 else 0.18
        layer = _mix(
            _tone(length, hz, hz, 0.26, math.sin, attack=0.004, release=0.06),
            _tone(length, hz * 2.0, hz * 2.0, 0.07, math.sin, attack=0.004, release=0.06),
        )
        offset = index * step
        for i, value in enumerate(layer):
            if offset + i < len(out):
                out[offset + i] += value
    return out


def death():
    """사망 — 길고 아래로. 한 판에 한 번뿐이라 마음껏 길어도 된다."""
    return _mix(
        _tone(0.95, 420.0, 55.0, 0.38, _square, attack=0.006, release=0.25),
        _tone(0.95, 210.0, 27.5, 0.20, math.sin, attack=0.006, release=0.25),
    )


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, maker in (
        ("shoot.wav", shoot),
        ("hit.wav", hit),
        ("pickup.wav", pickup),
        ("hurt.wav", hurt),
        ("level_up.wav", level_up),
        ("death.wav", death),
    ):
        _write(name, maker())


if __name__ == "__main__":
    main()
