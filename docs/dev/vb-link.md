# The Virtual Boy link cable

Two Virtual Boys joined by a lead in their EXT. sockets, on `mednafen_vb` from
**RetroXR/beetle-vb-libretro** (branch `retroxr`, tag
`retroxr-mednafen_vb-libretro-vN`, built by the fork's `retroxr-release.yml`).
The working checkout is `~/libretro-cores-retroxr/beetle-vb-libretro`.

Nintendo designed the cable and never sold it, and no retail game shipped with a
link mode. What uses it is homebrew, one unreleased prototype, and Mario's Tennis
with its two-player code patched back in.

## The core

Stock Beetle VB has no port: `CCR`, `CCSR`, `CDTR` and `CDRR` (0x02000000-0C) all
read 0 and a transfer never runs. `mednafen/vb/comm.c` implements them as the
Sacred Tech Scroll describes (it agrees with Red Viper's and Shrooms VB's code)
and puts them on the link bus through `RETRO_ENVIRONMENT_GET_LINK_INTERFACE`,
exactly as libretro/RetroArch#19454 adds it to `libretro.h`: the fork's
`libretro-common/include/libretro.h` carries the pull request's block line for
line and there is no private header (v2; v1 vendored the gambatte fork's
`link_interface.h`, an earlier draft that also probed a plain environment 94).

- **The port** is the Game Boy's with one more wire: a clocked 8-bit exchange,
  160 us (3200 CPU cycles) a byte, on whichever unit selected its own clock
  (`C-Clk-Sel` 0); the other waits with `C-Stat` set. Either end can raise the
  level-3 interrupt, and there are TWO requests behind it, acknowledged
  separately (`C-Int-Inh`, `CC-Int-Inh`).
- **COMCNT** is an open line either unit pulls low: `CC-Rd` is this unit's
  `CC-Wr` AND the other's, live; `CC-Smp` samples it when an exchange ends.
- **The wire:** `vb-comm-1` at 20 000 000 Hz, the V810's clock. Three messages:
  a COMCNT state, a clock (with the byte), and the answer to a clock (the byte
  back, and whether the unit was waiting at all). **The clocked unit decides
  whether the exchange happened**, so the two ends cannot disagree about a byte;
  the clocking unit holds `C-Stat` until it is told, and both finish on one tick.
- **The horizon** is 800 cycles while the port is in use and 8000 while idle
  (50 rendezvous a frame instead of 500). Two cabled units in a live match run
  at about 250 fps unthrottled.
- **A bus of more than two carries nothing.** Uncabled, or with no bus at all,
  the port is a Virtual Boy with an empty socket: an internal-clock transfer
  completes with `FF`, an external-clock one waits. There is no core option.
- **Log:** `[vb-comm] N unit(s) on the wire`, `N byte(s) exchanged`,
  `N clock(s) ... found this one not waiting`, at 1, 10, 100 … at WARN.
  `VB_COMM_TRACE=1` in the environment logs every register access (`R`/`W`),
  every byte landing (`D`) and every `CC-Smp` sample (`S`) with the unit and its
  link clock, runs folded — it is how every protocol below was read.

**What real software forced.** Each row was a game that failed without it:

| symptom | cause | fix |
|---|---|---|
| Mario's Tennis: the second unit took a whole frame to answer, and `inbox full` | the caller signals with COMCNT pulses **eight cycles wide** every 25, and the other unit polls the line for them; every edge inside one horizon was stamped on the same tick, so only the last survived | a message is stamped a FIXED 800 cycles ahead, so the waveform arrives as it left, 40 us late; the inbox is a ring of 512 |
| SPONG, Pong Ultimate: black screen on entering versus | VUEngine waits on `FCLK` in `DPSTTS` before starting a linked match; the VIP never set the bit | `FCLK` reads high through the first half of a display frame (`vip.c`) |
| Pong Ultimate: both units stop mid-handshake, silently | **`HALT` did not halt.** The op set a flag and the CPU ran on to the next timing event (≤ 259 cycles). VUEngine halts until the link interrupt marks the byte done; resumed a few instructions before the `HALT`, it ran the `HALT` once more, saw the byte done, returned into code that masks interrupts — and was put to sleep there for ever | `HALT` runs the clock to the next event at once (`v810_oploop.inc`) |
| Elevated Speed: "No linked player has been detected"; VUEngine titles never connect | both read COMCNT milliseconds after power-on to learn whether they are the SECOND unit switched on. The first rendezvous was the guest's first touch of a link register, and a COMCNT state said once into a bus the other unit had not joined yet is dropped | the port meets the bus on the first instruction after load, and repeats its COMCNT state every rendezvous until the other unit is heard from |
| 3-D BattleSnake, Hyper Fighting: a byte moves at boot | the SDK's startup code leaves the port waiting on the external clock, and the game then writes `CCR = 80` | switching a waiting transfer to the internal clock makes it run, as the hardware does |

The makefile does not track `.inc` files: after touching `v810_oploop.inc`,
delete `mednafen/hw_cpu/v810/v810_cpu.o` or the change is not in the build. That
cost an hour.

## The room

`virtual_boy_primitive.tscn` carries a `LinkPort` on the underside of the visor
beside the stand, facing straight down, where the real EXT. socket is. The spawn
catalog offers `virtualboy` a "Link Cable": `vb_link_cable`, the two-ended Game
Boy lead under its own plug family (`vb_link_plug`), so it seats in a Virtual Boy
and in nothing else. `link_tests` walks it through the lead x socket matrix.

## Probes (`RetroXR/Tools/link/`)

```bash
"$godot" --headless --path RetroXR res://Tools/link/vb_link_room_probe.tscn [-- --rom=<path>]
"$godot" --headless --path RetroXR res://Tools/link/vb_link_game_probe.tscn -- \
    --rom=<rom> --tag=<name> --script="<steps>" [--delay2=N] [--every] [--nocable]
```

The room probe (13 checks) seats the lead the way a hand does, powers both units
on, presses one unit's START on Mario's Tennis's title and asks for the call to
cross both ways, then pulls a plug and pushes it back. The game probe scripts
both units and saves side-by-side shots to `probe_out/vb/<tag>/`; its header has
the step syntax. **Run it once with `--nocable` as the control leg, one leg per
process.**

**Traps:**
- **Press the two units APART.** Units pressed on the same frame both call,
  neither is listening, and each opens its one-player menu.
- **Power them on apart for VUEngine and Elevated Speed** (`--delay2=40`). The
  first unit on becomes the waiting end, the second sees COMCNT held and calls;
  two switched on in the same instant both wait. Nobody does that in a room.
- **3-D BattleSnake and Tic Tac Toe: the second player starts.** Player 1
  starting sends its handshake before player 2 is listening and both hang —
  which is what the cable's builder reported on hardware.
- **A menu needs time to open.** A press 150 frames after the last START can
  land before the cursor exists; settle 150 frames more and hold for 12.
- **A savestate of a cabled pair does not resume.** What was in flight on the
  bus is gone; Mario's Tennis sat still for ever. Drive from boot.
- beetle-vb's pad: RetroPad A/B/L/R/START/SELECT are the unit's own, the right
  pad is L2 (up), R2 (left), L3 (down), R3 (right); **RetroPad X is its
  low-battery toggle.**
- `XENU_UNTHROTTLED=1` runs a leg in a fifth of the time.

## The list, tested 2026-10-06 (cabled leg, and a `--nocable` control)

| title | route | result |
|---|---|---|
| Mario's Tennis + M.K.'s multiplayer patch | START ×4 on both; START on unit 0's title; DOWN ×2, A ×2; A, RIGHT, A on unit 1; START | **1P vs 2P**: "MARIO VS LUIGI", each unit shows the court from its own end, unit 1 serves, both scoreboards read 00–15. Uncabled, unit 0 gets the one-player MODE menu and plays the computer |
| — doubles, `1P.COM vs 2P.COM` | DOWN on the title for DOUBLES, START, RIGHT on MODE | plays; scores agree |
| — doubles, `1P.2P vs COM.COM` | the MODE default | **ERROR on both scoreboards**. The patch's author calls this mode unfinished ("buggy… too time-consuming without an emulator with link cable support"); whether hardware shows the same is not established |
| Virtual Boy Link Cable Test (DogP) | A; unit 0 left-pad UP (Master); START on unit 1, then unit 0 | Tx 5A / Rx 5A, success counts climb together, 0 errors; COMCNT written on either reads low on both. Uncabled: the master counts errors with Rx FF, the remote waits |
| 3-D BattleSnake (DogP, 2008) | RIGHT then START on one unit | both screens draw the same two trails to the collision |
| Tic Tac Toe (DogP, 2008) | RIGHT then START on one unit; direction + A per move | moves alternate; identical boards |
| SPONG demo (2019) | START into the menu on each, apart; DOWN ×2 (Versus Mode), START on each | same ball, paddles and score on both, "Player 1" / "Player 2" |
| Pong Ultimate 1.44 DX | reach the title apart ("Connection Status: Connected"); A on each | same ball and paddles on both, 10 000+ bytes |
| Elevated Speed 22-03-04 | `--delay2=40`; Multiplayer on each | unit 0 hosts ("Begin Race"), unit 1 "Waiting for host…", then both race the same track with ranks |
| Hyper Fighting | VERSUS on each; START to confirm a fighter | RYU VS E. HONDA, ROUND 1, same picture on both; a pause on one pauses both |
| Virtual League Baseball 2 (prototype) | START to the title on both, then START apart | MODE SELECT reads "PLAYER 1 VS PLAYER 2" on both; uncabled it reads "PLAYER 1 VS COMPUTER" with Pennant Race and Team Edit. No game played |
| Formula V public demo (2021) | `--delay2=60` | the engine's handshake crosses (one byte, `34`), but **Versus is greyed out in this demo**, as Championship is |
| Faceball / NikoChan Battle | — | **no link code**: its Arena mode was never written (M.K. looked and found none) |
| 3D Pong, Bombenleger, Game Hero Legends, Virtual WarZone | — | never released, or sold only; not tried |

**Nothing else moved.** A headless libretro harness (one core, one ROM, a fixed
input script, a hash of picture and sound every 250 frames) ran the 31 retail and
prototype ROMs in the library on the stock core and on the fork: identical, frame
for frame, over 6000 frames. The four link titles tried the same way all differ
from stock, which is what says the harness can tell.

## Where the software comes from

- The patch: `multiplayer_v1.bspatch` (BSDIFF40) from M.K.'s thread on Planet
  Virtual Boy, <https://www.virtual-boy.com/forums/t/mario-s-tennis-multiplayer-patch/>.
  Applied to `Mario's Tennis (Japan, USA).vb` (SHA-1 `5162f7fa…`, 512 KB) it
  gives a 2 MB ROM, SHA-1 `6bf2484b981e0c134c22b00eb464b5c19d2121c8`.
- DogP's three, SPONG, Pong Ultimate, Elevated Speed and Formula V's demo are
  their authors' own free downloads (Planet VB's pages, or the author's site).
- **Hyper Fighting's full ROM is not an author release** — it is a cart dump
  Planet VB now hosts; the author's free release is the 2013 demo, which has no
  versus mode. Virtual League Baseball 2 is an unreleased Kemco prototype Planet
  VB published in 2025. Neither is in the repo or in the probes' defaults.

## Owed

- **Two people in headsets.** Nobody has reached under a Virtual Boy to seat this
  lead by hand; the socket is on the underside because the real one is.
- **Android and Quest**: the release builds for arm64, but nobody has run it there.
- **The cable's sync wire is not modelled.** On hardware it locks the two units'
  mirrors, and so their frame clocks, together; here each unit keeps its own
  phase. VUEngine's frame handshake tolerates that (every frame's exchange
  blocks until both are there). Nothing found needs more.
- **Netplay**: a cabled pair has no `NetplayCores` row and no group rollback.
- What an unanswered clock shifts in is `FF` here; the hardware reports differ
  (`FF`, `00`, the peer's stale byte). No title tried cares.
- Mario's Tennis's third mode, above.
