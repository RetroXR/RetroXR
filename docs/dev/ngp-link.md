# The SNK link cable (Neo Geo Pocket / Color)

Two Neo Geo Pockets (either model: one core, one wire) joined by a lead in their
EXT sockets, on `mednafen_ngp` from **RetroXR/beetle-ngp-libretro** (branch
`retroxr`, tag `retroxr-mednafen_ngp-libretro-vN`, Windows and Android built by
its `retroxr-release.yml`). `CoreSources` points the core download at that tag.
The working checkout is `~/libretro-cores-retroxr/beetle-ngp-libretro`.

## The core

Stock beetle-ngp (NeoPop) stubs `system_comms_read/poll/write`, so a game sees an
empty cable. `mednafen/ngp/link.c` puts SIO0 on the link bus through
`RETRO_ENVIRONMENT_GET_LINK_INTERFACE`. `link_interface.h` is the gambatte fork's,
byte-identical.

- **The wire:** `ngp-sio-1` at 6 144 000 Hz, the TLCS-900H clock that
  `TLCS900h_interpret()` counts in (515 a scanline). `ngp_link_ran()` runs after
  every instruction and rendezvouses once a grain, which is 2060 ticks (four
  scanlines).
- **A byte** is stamped at least a grain ahead and paced at 3200 ticks, one byte
  at 19200 8N1. The BIOS hands a game's whole buffer over in one call, and
  receivers are written for UART spacing.
- **Attach:** the core always attaches at load. Uncabled it runs free, so there
  is no core option.
- **Log:** the core logs `Link cable: N machine(s) on the wire` at WARN.

The cable is a null modem: TXD↔RXD and /RTS↔/CTS, active-low. The wiring is
documented at lude.rs/ngp-link. Four things had to be right, and each one was a
game that failed:

1. **Receive delivers each byte ONCE.** NeoPop's scanline hook peeks the next
   byte. Wired to a real queue, that re-raised the first byte on every line and
   the rest never came. Gals' Fighters then showed LINK FAILURE.
2. **The inbox IS the BIOS receive buffer.** BIOS-driven games (Gals' Fighters)
   never take the interrupt. They poll COMRECIVESTATUS (`FF2D4E`) and read with
   COMGETDATA (`FF2CB4`), so a byte stays queued until a BIOS read takes it.
   `ngp_link_waiting()` returns the real count (NeoPop returned a bool), and
   `ngp_link_arrived()` raises the interrupt once per byte for games with their
   own handler.
3. **INTRX0 is 11, INTTX0 is 12.** NeoPop had them swapped. The vectors are RAM
   slot 0x6FE4 (RX) and 0x6FE8 (TX), and INTES0 at 0x77 agrees. Only games that
   drive SIO0 from their own handlers notice: KOF R-1, KOF R-2 and SNK vs.
   Capcom stopped at their second screen until this was fixed. The same games
   write SC0BUF directly, which is a transmit (`ngp_link_tx_direct`) and raises
   INTTX0 when the byte has left. `reset_memory()` stores initial I/O values
   through `storeB`, which is not a send, so a flag keeps it off the wire.
4. **0xB2 is the handshake pair.** Writing bit 0 sets this end's /RTS: COMONRTS
   writes 0, which asserts it. Reading bit 0 returns the peer's /RTS as this
   end's /CTS, and 1 when nothing is cabled. Each change is sent as its own
   message, stamped like a byte. KOF R-1 spins on it between messages.

Two further details:
- The HLE BIOS's own receives use `ngp_sc0buf_received()` rather than
  `storeB(0x50)`, because a store now means "send".
- COMGETBUFDATA still reads one byte per call, a NeoPop bug that no tested game
  hits.

## The room

`neo_geo_pocket.tscn` carries a `LinkPort` on the top edge, left of the
cartridge slot, facing -Z. The spawn catalog offers `ngp` a "Link Cable": the
two-ended `gb_link_cable` lead. Nothing in that plug group is Game Boy specific,
and a third machine on the wire is not something the SNK cable does.

## Probes (`RetroXR/Tools/link/`)

```bash
"$godot" --headless --path RetroXR res://Tools/link/ngp_link_room_probe.tscn -- --roms=Z:/roms
"$godot" --headless --path RetroXR res://Tools/link/ngp_link_probe.tscn -- \
    --rom="Z:/roms/ngpc/SNK Gals' Fighters (USA, Europe).ngc" --out=gals \
    --seq="w400,0:A,w40,0:A,w77,1:A,w40,1:A,w200,b:D,w40,0:A,w30,1:A,w200,s:sel" [--nocable]
```

**The room probe** (12 checks) does this:
- seats the lead the way a hand does and powers both units on;
- presses through to Gals' Fighters' mode screen, then asks for at least ten
  messages each way (the handshake is `00 'SNKGFE1OK'`);
- pulls one end out and pushes it back in.

**The game probe** scripts both machines and writes side-by-side shots to
`probe_out/ngp/<out>/`. Its header gives the step syntax. `S:name` and
`--load=name` save and restore both machines, which is how a game with the link
deep inside it is reached in stages.

**Traps, all learned the hard way:**
- **Press the two machines apart.** Two units pressed on the same frame call on
  the same tick, each hears the other's call, and neither answers (the Tetris
  trap in `gb-link.md`). Use `0:X,w37,1:X`.
- **The two machines are not frame-locked.** `w`/`_frames` count machine 0's
  frames only, and machine 1 is held within a horizon, not in step. A long
  script therefore drifts between runs. Card Fighters' Clash, which also reads
  the RTC, never repeats.
- **Run the game probes one at a time.** Two in parallel wrote nothing, which is
  the same finding as in `ws-link.md`.
- **The room probe must still the unit's `HandheldInput` for a press.** It
  resends the idle pad every frame, which wipes out `SetJoypadState`.
- **Wait for teardown before quitting.** A probe that quits two frames after
  `StopContent` while cabled segfaults. The emulation threads are still
  detaching from the bus.
- **beetle-ngp's pad map:** RetroPad **B** is the NGP's A (confirm), RetroPad A
  is its B, and START is Option.

## Measured (2026-09-21, Windows, both machines headless in one process)

Every "works" below reached versus play on both units, with the same match on
both screens. For the fighting games, that means identical round timers and one
player's walk showing on the other's screen.

| Game | Path | Result |
|---|---|---|
| SNK Gals' Fighters | Mode Select → 2P VS | works; greyed out and CPU-only with no cable |
| Fatal Fury F-Contact | START → 2P PLAY MODE | works |
| Bust-A-Move Pocket | VS-PLAYER | works (1P/2P stage select, one shot seen on both screens) |
| King of Fighters R-1 | START → TEAM VS | works (needed fix 3) |
| King of Fighters R-2 | START → VS MODE | works (needed fix 3) |
| SNK vs. Capcom: Match of the Millennium | VS MODE → ONE VS | works (needed fix 3) |
| The Last Blade: Beyond the Destiny | VS PLAY | works |
| Magical Drop Pocket | FRIEND CHALLENGE | works; with no cable it stops at "WAIT..." |
| Sonic the Hedgehog Pocket Adventure | GO TO ROOM → DUEL ROOM → SONIC RUSH | works (one unit is Tails, the other Sonic) |
| Card Fighters' Clash (SNK/Capcom) | in-game menu → LINK → COM CABLE | **untested**: the link is past the opening tutorial battle, and the probe never finished it |
| Biomotor Unitron | in-game | **untested**: the link is deep in the RPG |

## Netplay and rollback (2026-09-22, fork commit on `retroxr`, NOT yet released)

Three things stood between the NGP and a rollback session, each measured:

1. **The RTC read the host's clock.** `rtc.c` called `localtime()` on every read,
   so two peers booted a second apart disagreed from FRAME 1 — cable or not.
   Core option **`ngp_rtc=deterministic`** starts it at 2000-01-01 00:00 UTC and
   runs it on emulated time (the link's `own_clock`, which the state carries).
   Three cold cabled runs of Gals' Fighters, 2400 frames: bit-identical, both
   machines, same bytes on the wire (3783/4504).
2. **The state lost things.** Upstream never saved the Z80's IRQ line (`iline`,
   section `Z80I`): a state taken while the TLCS-900 held it raised made the sound
   CPU take another path for ~20 frames — the RAM CRC caught it through the shared
   RAM at 0x7000. That was Bust-A-Move's anchor 500 (stock too) and KOF R-1's 852
   and 860. The fork also saves `SC0BUF`/`COMMStatus` (`SIO`) and the whole link
   (`LINK`: inbox, RTS queue, pacing, `tx_done_at`, `own_clock`). `rewind_probe`
   over 100..2500: 0 bad of 300 anchors on KOF R-1, Bust-A-Move and Gals' Fighters
   (were 2, 1, 0). **Find such a thing by diffing two states, not by reading code:**
   `sdiff`-style parsing of the Mednafen sections names the variable (MDFNSVST,
   32-byte section name + size, then len-prefixed var name + size + bytes).
3. **A cabled pair could not stop on one frame.** A stock frame ends at the
   instruction that crosses vblank, so two units' frame N ends on different bus
   ticks; gated and fed to N, one sits at N-1 blocked inside its frame on the bus
   and cannot take a state. Measured on Gals' Fighters' link screen: 124 of 143
   boundaries unreachable (gambatte: 139 of 139 — every link core has this).
   Core option **`ngp_fixed_frames=enabled`** runs every `retro_run` for exactly
   102485 ticks (515 × 199, a hardware constant, so vblank stays in the window),
   overshoot carried, anchored with a whole window, never asking the bus past the
   edge, promising a grain past it on the way out, and holding a message stamped
   past the edge for the next window — the Lynx fork's `lynx_fixed_frames`
   contract, which is what the session's group rollback barrier needs. Result:
   **0 of 143**. Under fixed frames a load restores the link clock ABSOLUTELY (the
   group restore puts the bus back to that instant); otherwise every bus tick is
   rebased relative to `now`, which never goes back.

**Measured with fixed frames on:** a cabled restore sweep of Gals' Fighters (pause
both, capture both cores + `LinkCaptureGroup`, run 12, `LinkRestoreGroup` then the
cores, replay, compare both CRCs and the wire) — **0 bad of 100 anchors, 92 of
them mid-conversation**. Mutation: dropping the inbox on load turns 26 of 40 red.
Skipping the ABSOLUTE restore stays green (the relative rebase is already
self-consistent), so that branch is belt-and-braces, not load-bearing.

The probe is `Tools/netplay/ngp_link_netplay_probe` (`--mode=pause|trace|sweep`,
`--nocable`, `--opt=`, `--root=`): gated exactly as the session gates, input
lead capped at 60 frames (posting hundreds at once overruns the gate's ring and
reads as a wedge at ~600).

**Owed:**
- a `NetplayCores` row (`link_rollback`, both options pinned) — it must wait for a
  fork RELEASE carrying the options, since `CoreSources` downloads by tag;
- a real two-peer session over the cable;
- the Card Fighters' Clash link battle and trade;
- Biomotor Unitron;
- Android and Quest (the release builds for arm64, but nobody has run it on a headset);
- two people playing it in a headset.
