"""The sounds of a game case, synthesized: RetroXR/Audio/cases/*.wav (48 kHz mono 16-bit).

A jewel case is polystyrene: stiff and barely damped, so a knock rings bright (2-9 kHz) for several ms. Its lid
unlatches as two side detents pop a few ms apart, latches with the lid's slap on the tray under them, and its pins
creak by stick-slip. A keep case is polypropylene: soft and lossy, a hollow shell, so its clasp gives a dull pop
(400-3500 Hz) that dies in a few ms, with the air's thump under the cover and the sleeve's crackle.

Each sound is modes (decaying sines) struck by a short noise burst, plus shaped noise. No recording was used.
    python Tools/gen/gen_case_sounds.py [--out <dir>]
"""
import argparse
import pathlib
import wave

import numpy as np
from scipy import signal

SR = 48000
OUT = pathlib.Path(__file__).resolve().parents[2] / "RetroXR" / "Audio" / "cases"


def strike(rng, dur, bands, burst_ms, loss):
    """One knock: modes in `bands` [(lo Hz, hi Hz, count, gain)], each dying as 1 / (pi f loss), struck by a
    `burst_ms` noise burst (the contact's length: it sets how bright the knock is)."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    ring = np.zeros(n)
    for lo, hi, count, gain in bands:
        for f in np.exp(rng.uniform(np.log(lo), np.log(hi), count)):
            tau = 1.0 / (np.pi * f * loss * rng.uniform(0.7, 1.4))
            ring += gain * rng.uniform(0.4, 1.0) * np.exp(-t / tau) * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28))
    m = max(int(burst_ms * 0.001 * SR), 2)
    burst = rng.standard_normal(m) * np.hanning(m)
    out = signal.fftconvolve(burst, ring)[:n]
    return out / np.max(np.abs(out))


def noise(rng, dur, lo, hi, env):
    n = int(dur * SR)
    sos = signal.butter(2, [lo, hi], btype="band", fs=SR, output="sos")
    out = signal.sosfilt(sos, rng.standard_normal(n)) * env(np.arange(n) / n)
    return out / np.max(np.abs(out))


def put(mix, at_s, clip, gain=1.0):
    a = int(at_s * SR)
    b = min(a + len(clip), len(mix))
    mix[a:b] += gain * clip[: b - a]


def norm(x, peak):
    fade = int(0.004 * SR)
    x[-fade:] *= np.linspace(1.0, 0.0, fade)
    return x * (peak / np.max(np.abs(x)))


PS = [(1800, 9000, 9, 1.0), (500, 1300, 2, 0.35)]          # a polystyrene lid, struck
PS_SLAP = [(1500, 7000, 9, 1.0), (450, 1400, 4, 0.8)]      # the lid landing flat on its tray
PP = [(400, 1400, 4, 1.0), (1400, 3500, 4, 0.6)]             # a polypropylene clasp tab
PP_BOX = [(220, 600, 3, 1.0)]                              # the hollow shell


def jewel_open(rng):
    mix = np.zeros(int(0.16 * SR))
    put(mix, 0.002, strike(rng, 0.06, PS, 0.35, 0.02))
    put(mix, 0.002 + rng.uniform(0.004, 0.012), strike(rng, 0.06, PS, 0.35, 0.02), rng.uniform(0.6, 1.0))
    for _ in range(int(rng.integers(1, 4))):               # the freed lid rattling on its pins
        put(mix, rng.uniform(0.03, 0.09), strike(rng, 0.03, PS, 0.25, 0.03), rng.uniform(0.06, 0.16))
    return norm(mix, 0.8)


def jewel_close(rng):
    mix = np.zeros(int(0.16 * SR))
    put(mix, 0.002, strike(rng, 0.07, PS_SLAP, 0.8, 0.025))
    at = 0.002 + rng.uniform(0.001, 0.004)
    put(mix, at, strike(rng, 0.05, PS, 0.35, 0.02), 0.8)
    put(mix, at + rng.uniform(0.002, 0.007), strike(rng, 0.05, PS, 0.35, 0.02), rng.uniform(0.5, 0.8))
    return norm(mix, 0.85)


def jewel_stop(rng):
    # The lid thrown open against its stop: its ears on the tray's back edge, the lid's slap, a bounce, a rattle.
    mix = np.zeros(int(0.2 * SR))
    put(mix, 0.002, strike(rng, 0.08, PS_SLAP, 1.0, 0.025))
    put(mix, 0.002 + rng.uniform(0.0005, 0.002), strike(rng, 0.05, PS, 0.4, 0.02), 0.6)
    bounce = rng.uniform(0.025, 0.045)
    put(mix, bounce, strike(rng, 0.06, PS_SLAP, 0.8, 0.025), rng.uniform(0.2, 0.35))
    for _ in range(int(rng.integers(1, 4))):
        put(mix, bounce + rng.uniform(0.015, 0.07), strike(rng, 0.03, PS, 0.25, 0.03), rng.uniform(0.05, 0.12))
    return norm(mix, 0.9)


def jewel_creak(rng):
    dur = rng.uniform(0.2, 0.34)
    mix = np.zeros(int(dur * SR))
    pins = [(rng.uniform(1900, 2600), rng.uniform(2, 4)), (rng.uniform(3300, 4400), rng.uniform(1.5, 3))]
    n = int(0.02 * SR)
    t = np.arange(n) / SR
    tick = sum(np.exp(-t / (ms * 0.001)) * np.sin(2 * np.pi * f * t) for f, ms in pins)
    at = 0.004
    rate0, rate1 = rng.uniform(70, 110), rng.uniform(160, 260)   # the slips come faster as the lid gets going
    while at < dur - 0.03:
        u = at / dur
        put(mix, at, tick, np.sin(np.pi * u) ** 0.7 * rng.uniform(0.5, 1.0))
        at += rng.uniform(0.7, 1.4) / (rate0 + (rate1 - rate0) * u)
    mix += 0.12 * np.max(np.abs(mix)) * noise(rng, dur, 3000, 8000, lambda u: np.sin(np.pi * u))[: len(mix)]
    return norm(mix, 0.4)


def keep_open(rng):
    mix = np.zeros(int(0.26 * SR))
    put(mix, 0.002, strike(rng, 0.05, PP, 1.8, 0.08))
    put(mix, 0.002 + rng.uniform(0.012, 0.03), strike(rng, 0.05, PP, 1.8, 0.08), rng.uniform(0.5, 0.9))
    put(mix, 0.002, strike(rng, 0.08, PP_BOX, 4.0, 0.07), 0.35)
    put(mix, 0.01, noise(rng, 0.09, 150, 700, lambda u: np.sin(np.pi * u) ** 2), 0.25)   # air under the cover
    for _ in range(int(rng.integers(3, 7))):               # the sleeve and the hinge letting go
        put(mix, rng.uniform(0.04, 0.2), strike(rng, 0.01, [(2500, 6000, 3, 1.0)], 0.3, 0.06), rng.uniform(0.05, 0.15))
    return norm(mix, 0.7)


def keep_close(rng):
    mix = np.zeros(int(0.2 * SR))
    put(mix, 0.002, strike(rng, 0.09, PP_BOX, 5.0, 0.07), 0.6)
    put(mix, 0.002, noise(rng, 0.05, 120, 600, lambda u: np.exp(-5 * u)), 0.3)
    at = 0.004 + rng.uniform(0.002, 0.008)
    put(mix, at, strike(rng, 0.05, PP, 1.4, 0.08), 0.9)
    put(mix, at + rng.uniform(0.008, 0.024), strike(rng, 0.05, PP, 1.4, 0.08), rng.uniform(0.5, 0.9))
    return norm(mix, 0.75)


def keep_hinge(rng):
    dur = rng.uniform(0.22, 0.32)
    mix = 0.3 * noise(rng, dur, 1500, 5000, lambda u: np.sin(np.pi * u) ** 1.5)
    for _ in range(int(rng.integers(5, 11))):
        put(mix, rng.uniform(0.01, dur - 0.03), strike(rng, 0.012, [(1800, 5000, 3, 1.0)], 0.4, 0.07), rng.uniform(0.3, 1.0))
    return norm(mix, 0.3)


SOUNDS = [("jewel_open", jewel_open, 4), ("jewel_close", jewel_close, 4), ("jewel_creak", jewel_creak, 4),
    ("keep_open", keep_open, 4), ("keep_close", keep_close, 4), ("keep_hinge", keep_hinge, 3),
    ("jewel_stop", jewel_stop, 4)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUT))
    out = pathlib.Path(ap.parse_args().out)
    out.mkdir(parents=True, exist_ok=True)
    for k, (name, make, count) in enumerate(SOUNDS):
        for i in range(count):
            x = make(np.random.default_rng(1000 * k + i))
            with wave.open(str(out / ("%s_%02d.wav" % (name, i + 1))), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(SR)
                w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
            f, p = signal.welch(x, SR, nperseg=1024)
            print("%s_%02d  %.0f ms  peak %.2f  centroid %.0f Hz" % (name, i + 1, 1000 * len(x) / SR,
                np.max(np.abs(x)), np.sum(f * p) / np.sum(p)))


if __name__ == "__main__":
    main()
