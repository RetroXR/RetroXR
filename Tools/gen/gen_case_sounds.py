"""Generate close-up game case Foley as 48 kHz mono PCM.

    python Tools/gen/gen_case_sounds.py [--out <dir>]

Latch sounds are separate takes cut from these CC0 field recordings:
    mewpudding101, Plastic CD case opening and closing
    https://freesound.org/people/mewpudding101/sounds/265634/
    ewellis, Plastic Disc Case Open and Close (PlayStation 2 case)
    https://freesound.org/people/ewellis/sounds/792907/
case_recordings/ contains mono 48 kHz PCM decodes of the public HQ previews.
The hinge textures and the jewel lid hitting its stop are synthesized.
"""
import argparse
import pathlib
import wave

import numpy as np
from scipy import signal

SR = 48000
OUT = pathlib.Path(__file__).resolve().parents[2] / "RetroXR" / "Audio" / "cases"

# In/out points in seconds and playback peak for each successive take.
# Leave the soft neighboring contacts in the cut, especially on the release.
LATCH_TAKES = {
    "jewel_open": [(.130, .300, .48), (2.890, 2.990, .44),
                   (5.400, 5.550, .38), (7.485, 7.710, .46)],
    "jewel_close": [(1.735, 1.848, .81), (4.202, 4.365, .75),
                    (6.721, 6.922, .77), (8.745, 8.855, .87)],
    "keep_open": [(.946, 1.159, .69), (4.462, 4.674, .63),
                  (8.380, 8.556, .54), (12.425, 12.606, .60)],
    "keep_close": [(2.810, 2.981, .86), (6.645, 6.809, .82),
                   (23.490, 23.650, .71), (15.584, 15.748, .78)],
}

# (Hz, decay in ms, amplitude) of the rigid jewel lid at its hinge.
JEWEL = [(410, 9, .26), (760, 13, .46), (1310, 10, .68), (2230, 7, .68),
         (3510, 5, .48), (5190, 3, .34), (7240, 2, .17)]


def put(mix, at, clip, gain=1.0):
    start = int(at * SR)
    length = min(len(clip), len(mix) - start)
    if length > 0:
        mix[start:start + length] += gain * clip[:length]


def unit(samples):
    return samples / max(np.max(np.abs(samples)), 1e-12)


def band_noise(rng, length, low, high):
    sos = signal.butter(2, [low, high], btype="bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, rng.standard_normal(length))


def body(rng, modes):
    # Make one impulse response per take. A slightly different grip damps
    # the whole shell and shifts which parts of the lid radiate most.
    t = np.arange(int(.085 * SR)) / SR
    tuning = rng.uniform(.96, 1.04)
    damping = rng.uniform(.83, 1.14)
    response = np.zeros_like(t)
    for hz, decay, level in modes:
        f = hz * tuning * rng.uniform(.98, 1.02)
        envelope = np.exp(-1000 * t / (decay * damping))
        response += level * rng.uniform(.72, 1.15) * envelope * np.sin(2 * np.pi * f * t)
    return response


def knock(rng, response, width_ms, edge_band):
    # A wider contact (panel landing flat) excites less treble than a tab
    # releasing. Mix the radiated shell with a brief, unpitched contact sound.
    width = max(3, round(width_ms * .001 * SR))
    force = np.hanning(width + 2)[1:-1]
    shell = signal.fftconvolve(response, force / force.sum())
    t = np.arange(int(.015 * SR)) / SR
    edge = band_noise(rng, len(t), *edge_band)
    edge *= -np.expm1(-t / .00016) * np.exp(-t / (.0008 + width_ms * .0006))
    shell = .8 * unit(shell)
    shell[:len(edge)] += .55 * unit(edge)
    return unit(shell)


def rub(rng, duration, band, grain_ms):
    # The pressure wanders as two surfaces slide. A second, slow envelope
    # lifts the stroke on and off the surface without a hard cut.
    length = int(duration * SR)
    t = np.arange(length)
    stride = max(2, int(grain_ms * .001 * SR))
    knots = np.arange(0, length + stride, stride)
    pressure = np.interp(t, knots, rng.uniform(.08, 1, len(knots)) ** 2)
    return unit(band_noise(rng, length, *band) * pressure * np.hanning(length).clip(0) ** .75)


def finish(mix, peak):
    mix[-int(.005 * SR):] *= np.linspace(1, 0, int(.005 * SR))
    return peak * unit(mix)


def jewel_stop(rng):
    mix = np.zeros(int(.18 * SR))
    lid = body(rng, JEWEL)
    put(mix, .002, knock(rng, lid, rng.uniform(.26, .48), (1000, 6500)))
    rebound = rng.uniform(.018, .032)
    put(mix, rebound, knock(rng, lid, .40, (1000, 5300)), rng.uniform(.26, .38))
    put(mix, rebound + rng.uniform(.011, .019), knock(rng, lid, .48, (800, 4500)), .10)
    return finish(mix, rng.uniform(.70, .85))


def jewel_creak(rng):
    # Short catches in the pin travel. Leave gaps between patches of friction.
    mix = np.zeros(int(.16 * SR))
    lid = body(rng, JEWEL)
    at = .002
    for _ in range(rng.integers(2, 4)):
        length = rng.uniform(.013, .028)
        put(mix, at, rub(rng, length, (850, 3700), 1.7), rng.uniform(.36, .65))
        put(mix, at + .72 * length, knock(rng, lid, .52, (1000, 4200)), rng.uniform(.12, .35))
        at += length + rng.uniform(.006, .022)
    return finish(mix, rng.uniform(.13, .20))


def keep_hinge(rng):
    duration = rng.uniform(.10, .17)
    mix = .58 * rub(rng, duration, (420, 2700), 9)
    # The clear sleeve buckles locally while the living hinge bends.
    for _ in range(rng.integers(2, 5)):
        put(mix, rng.uniform(.012, duration - .025),
            rub(rng, rng.uniform(.006, .018), (1600, 5600), 2), rng.uniform(.15, .43))
    return finish(mix, rng.uniform(.12, .18))


def case_sounds():
    for family in ("jewel", "keep"):
        path = pathlib.Path(__file__).with_name("case_recordings") / (family + ".wav")
        with wave.open(str(path), "rb") as source:
            if (source.getframerate(), source.getsampwidth(), source.getnchannels()) != (SR, 2, 1):
                raise ValueError(f"Expected 48 kHz 16-bit mono PCM at {path}")
            recording = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2") / 32768.
        # Remove mic rumble before cutting to preserve the attack at the edit.
        recording = signal.sosfilt(signal.butter(2, 70, "highpass", fs=SR, output="sos"), recording)
        for action in ("open", "close"):
            name = f"{family}_{action}"
            for take, (start, end, peak) in enumerate(LATCH_TAKES[name], 1):
                clip = recording[round(start * SR):round(end * SR)].copy()
                fade = round(.003 * SR)
                clip[:fade] *= np.linspace(0, 1, fade)
                yield f"{name}_{take:02}", finish(clip, peak)

    for name, make, count, seed in (("jewel_creak", jewel_creak, 4, 2000),
                                    ("keep_hinge", keep_hinge, 3, 5000),
                                    ("jewel_stop", jewel_stop, 4, 6000)):
        for i in range(count):
            yield f"{name}_{i + 1:02}", make(np.random.default_rng(seed + i))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUT))
    out = pathlib.Path(ap.parse_args().out)
    out.mkdir(parents=True, exist_ok=True)
    for name, samples in case_sounds():
        with wave.open(str(out / f"{name}.wav"), "wb") as wav:
            wav.setparams((1, 2, SR, 0, "NONE", "not compressed"))
            wav.writeframes(np.rint(samples * 32767).astype("<i2").tobytes())
        print(f"{name}  {1000 * len(samples) / SR:.0f} ms  peak {max(abs(samples)):.2f}")


if __name__ == "__main__":
    main()
