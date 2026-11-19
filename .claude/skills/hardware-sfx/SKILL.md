---
name: hardware-sfx
description: Record a real console's switches, buttons, carts and connectors, cut the takes into game-ready one-shots, and wire them into RetroXR. Use when adding recorded hardware sounds for any machine — the NES-001 pass is the worked example, and every trap here cost a take, a silent build or a wrong-sounding room.
---

# Recording a machine and putting it in the room

The NES-001 pass produced 119 clips across 16 families. Everything below is what
that cost. Work in this order — each stage assumes the one before it is right,
and the expensive mistakes were all "carry on and find out at the end".

## 1. The chain

Two mics at once, and they are not interchangeable:

- **Contact mic** (Korg CM-300 piezo) taped to the shell. This is the *mechanism*
  — the click, the detent, the spring. It has **no bass and no air**; a plastic
  clack recorded through it alone sounds thin and a semitone high.
- **Phone** (iPhone, Voice Memos) a foot away, as the air mic. This is the *body*.

Blend them. Neither alone sounds like the machine.

**Traps that cost takes:**

- **A piezo into a PC line/mic input is an impedance mismatch.** The high end
  survives, the low end does not, and everything comes back brighter and higher
  than life. If a take sounds high-pitched, this is why — it is not the room.
- **The phone applies AGC and it drifts, about 2 dB/s.** A minute-long take gets
  audibly louder toward the end, so a level-based split finds different
  thresholds at the two ends of the same file. Measure the drift and correct it
  before slicing, or slice on the contact mic and use the phone only for body.
- **PC fans are in every take.** Kill them at the source if you can. If not,
  spectral subtraction (STFT, profile from a silent head) removes them cleanly —
  it did here — but the profile must come from the *same* take.
- **Clap between groups.** One sharp clap before each new button. It is the only
  reliable sync between the two recordings and the only reliable marker for
  where one group ends.

**Capture press and release separately for anything sprung.** RESET on a NES is
a spring button: it clicks going in and clicks coming out, ~250 ms apart. Recorded
as one event it can never be played back correctly, because the game fires those
on different frames.

## 2. Cutting the takes

Detect bursts on an envelope, align the two mics by cross-correlation, score each
one-shot by peak-to-tail ratio, and **write each hit to its own numbered file** so
bad ones can be culled by ear without recutting.

**The labelling trap, in full, because it shipped wrong once.** Clips were split
into "tray down" and "tray up" by *duration alone* — 284 ms against a 460 ms
median, comfortably past the cut — and the two families came out **inverted**: the
sync clap was labelled as a tray movement. Duration does not identify a sound.

The test that works is **airborne energy**: a clap is loud on the phone and quiet
on the contact mic; a mechanism is the reverse. Here the clap read **+15.1 dB**
louder on the air mic, which no tray movement came close to. Add a discriminator
that measures the thing you actually mean, then re-check the spread of both
families (2.7 dB and 2.5 dB here) before believing the split.

Listen to at least one clip from every family before shipping it.

## 3. Into the repo

Ship **16-bit / 48 kHz mono**. `PcmClip.load_frames()` handles 8- and 16-bit only
— **24-bit silently yields nothing**.

Name them `<prefix>_NN.wav` from `01` with no gaps; the loader counts up and stops
at the first miss, so a gap truncates the bank.

**`compress/mode=0` is mandatory and is not the default.** The project imports new
`.wav` as QOA (`mode=2`), `PcmClip` refuses a compressed sample, and the result is
a bank that loads as **zero frames — silent, with no error**. Every new file:

```bash
sed -i 's|^compress/mode=2$|compress/mode=0|' RetroXR/Audio/<sys>/*.wav.import
rm -f .godot/imported/*.sample
"$godot" --headless --path RetroXR --editor --quit
```

Add a provenance entry to `RetroXR/Audio/LICENSE-audio.txt`. Recorded in-house
carries no licence, but say so explicitly and note the chain — future-you will
want to know why some families start at their peak and others do not.

## 4. Wiring it up

**`SpatialAudioEmitter` is PCM-push only.** There is no "play this AudioStream"
entry point, so a one-shot cannot be an `AudioStreamPlayer3D`. Use `PcmOneShot`,
which wraps the push loop. Retriggering **restarts rather than layers** — right
for a switch, since the mechanism cannot be in two states at once and two copies
of one transient comb-filter into something metallic.

**Pool banks by moulding, not by button.** A and B are the same piece of plastic
and sound identical; so do SELECT and START; so do the four arms of a rocker.
Three banks beat eight, and every take in a bank becomes variation for all of it.

**Never play the variant you played last** for that bank. A mashed button doubles
often enough that a plain random pick reads as a glitch.

**Voices:** enough that a real gesture cannot cut itself off. Two for a console
(a spring button's press and release are ~250 ms apart); three for a pad (a
direction and a face button can change in the same frame).

**Distances**, as shipped and still unverified in a headset: console panel
`unit_size 0.6 / max_distance 3.0 / volume 0.6`; pad `0.4 / 2.5 / 0.45`.

### Where the sound comes from

A sound belongs at its **source**, not at the node that owns the clip. A pad's
plug goes into a socket on the console, so it plays at the socket — left alone it
came from wherever the pad was lying, which is how it ended up "always in my left
ear". Use `play_from(frames, at)`. `play()` clears any previous emit position, so
a reused voice cannot inherit a stale point.

Look the socket up **by identity** (`_port_plugs`), falling back to the index —
the index is the *libretro* port, which equals the cabinet socket for a joypad but
not for everything.

### Hang them off the gesture, not the state change

Sounds go on the **widgets**, never on `power_on()` / `power_off()` or the plug
callbacks alone. Those are also called by code: tearing a room down powers every
machine off, and a restore seats every saved cart and plug through the same snap
zones a hand uses. A rack of consoles all clicking at once during a room change
is not what a power switch means.

Guard both directions:

- A restore sets `_restoring_media` on the system; media sounds check it.
- A teardown frees the zones, and an emptied zone reports a drop — so on unplug,
  read `_connected_system` **before** `super()` clears it, and check the system is
  still valid and not queued for deletion. That is the only way to tell a pulled
  cable from a console being deleted out from under one.

For buttons read as **input state** rather than pressed as widgets, drive off
edges of the merged button mask. When input is lost (`not _got_input`), reset the
previous mask to 0 rather than comparing against it — otherwise a dropped pad
clicks every button it happened to be holding on the way to the floor.

### `bool(null)` throws

`Object.get()` returns `null` for a property the host does not have, and
`bool(null)` is not a valid constructor call — it raises, so the guard bails and
the sound can *never* play. This shipped and was caught by a probe:

```gdscript
return host.get("_restoring_media") != true     # not bool(host.get(...))
```

## 5. Proving it

Write a throwaway probe under `RetroXR/DevTools/`, print `[probe]` lines, delete it
after. Two ways a probe here lies:

- **Calling an override directly can silently resolve to the parent class**, so
  the probe passes after the override is deleted. Drive the *real* path —
  `zone.pick_up_object()` / `zone.drop_object()`, not `pad.on_plugged_in()`.
- **Ask the right voice.** A round-robin means the voice you sample may still be
  running the previous sound. Wait for all voices idle before asserting anything
  about position or content.

`render_offline` is not an audio oracle. Assert a positive control — something
that must be audible — or the test cannot fail.

Break the code and watch the check go red before believing it.

## Worked example

`RetroXR/Scripts/Objects/system_models/nes_model.gd` (console panel: power,
reset press/release, channel switch, cart insert/eject) and
`RetroXR/Scripts/Objects/controllers/nes_controller.gd` (three button banks,
plug in/out at the socket). Clips in `RetroXR/Audio/nes/`.

Note the tray banks are recorded and shipped but were deliberately left unwired
in that pass — a bank existing is not a bank being played, and it is worth saying
which is which in the code.
