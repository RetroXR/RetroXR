# JagLink — two Atari Jaguars on one cable

The Jaguar's JagLink / CatBox cable is JERRY's UART (`$F10030`–`$F10034`) out
of the DSP port. RetroXR's `virtualjaguar` fork carries it over the
frontend's link bus (env 94, the API of libretro/RetroArch#19454) as protocol
**`jag-uart-1`**, one message per character.

- Core: `~/libretro-cores-retroxr/virtualjaguar-libretro`, branch `retroxr`
  (upstream libretro/virtualjaguar-libretro v3.6.1). `src/jerry/jlink_linkbus.c`
  is the transport; `uart.c` `UARTOnWire()` routes the plain cable to it.
  No GitHub fork / release exists yet, so `CoreSources` has no row: the
  build is installed by hand into `~/retroxr/libretro/cores/` (stock kept as
  `virtualjaguar_libretro.dll.stock`). Windows: `mingw32-make platform=win CC=gcc`.
- The core's `virtualjaguar_netlink` option: `auto` (default) resolves to the
  bus whenever the frontend offers one; TCP modes still work and win.

## How a byte crosses

A character is posted when it STARTS shifting out and stamped at its stop
bit (one character later), and lands straight in the partner's RBF at that
tick — the wire exactly. The first version sent a byte after it had shifted
out and then clocked it in again on the far side (two character times plus
the horizon); Doom and AirCars did not mind, BattleSphere did.
The horizon is 3/4 of a character at the current ASICLK (clamped 20–500 µs),
request == safe, so the machines step in lockstep; bytes are drained only
right after `advance()` returns, so landing is a function of emulated time.
The slice hook is in `JaguarExecuteNew` (`JLinkLBSlice`). Pending bytes and
the link clock are not in savestates.

Measured baud: BattleSphere ASICLK 22 (152 µs/char), AirCars 42 (285 µs),
Doom 13.

## Probe

```bash
"$godot" --headless --path RetroXR res://Tools/link/jag_link_probe.tscn -- \
    "--rom=Z:/roms/atarijaguar/Doom (World).j64" --game=doom [--no-cable | --tcp]
```
`--game=doom|aircars|battlesphere`, or `--steps=` (see the script header).
`--tcp` runs the core's own TCP link as a comparison leg. The probe writes
the REAL `core_options/virtualjaguar.opt` and restores it byte-for-byte — a
TCP leg once left `tcp_client` in it and every later "bus" run was TCP.

Results (2026-09-21, Windows):
- **Doom** — Deathmatch, YOUR/HIS FRAGS, separate spawns, ~2600 bytes each
  way. Uncabled: both sit on "ATTEMPTING TO CONNECT", 0 bytes.
- **AirCars** — Two Player Direct Serial: both reach the same briefing and fly
  one mission clock, ~1760 bytes each way.
- **BattleSphere Gold** — lobby, Free-For-All options and ship select linked
  (~50 KB); past launch one console flies and the other goes black, and TCP
  does the same, so it is the emulator. Upstream never validated a dogfight.

**Drive the machines one at a time.** On the bus the two Jaguars are
bit-identical; pressed on the same frame, BattleSphere picks the same player
id on both and says "Network Failure — unable to locate any other players".

## In the room

`atarijaguar.tres` has `serial_port`, so the primitive body wears a
`JagLinkPort` (the DSP port, legend "DSP"). The lead is `JagLinkCable`
(`jag_link_cable.tscn`, spawnable under the Jaguar and from the peripherals
list, saved as `jag_link_cable`). Port, plug and cable extend the
PlayStation's, under their own plug group `jag_link_plug`, so neither the
PlayStation nor the Saturn lead fits a Jaguar and a JagLink lead fits
neither of them. `link_tests` covers the gating both ways.

`Tools/link/jag_link_room_probe` builds two `RetroSystem`s, seats each end by
hand and checks nobody -> one end (still nobody) -> both (a pair) -> AirCars'
Two Player Direct Serial flying one mission clock -> pull a plug (parted).
It uses AirCars, not Doom: Doom's title is an attract loop that takes A only
in some phases, and the room's boot lands at a different point in it than a
bare Libretro does, so the Doom walk misses its presses there.

## Owed

- A published core build (Windows + Android) and its `CoreSources` row;
  until then only a machine with the fork installed by hand links.
- The BattleSphere dogfight; Voice Modem (Ultra Vortek) stays on the byte
  seam and is not carried by the bus.
- A headset check of the socket and lead on the Jaguar body.
