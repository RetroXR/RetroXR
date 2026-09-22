# ComLynx

Two to eight Atari Lynxes on one ComLynx lead, on `mednafen_lynx` from
**RetroXR/beetle-lynx-libretro** (branch `retroxr`, tag
`retroxr-mednafen_lynx-libretro-vN`), wire `comlynx-1` at 16 MHz.

**The core.** Mikey's UART already had a transmit hook nothing was attached to,
and modelled the wire's loopback. `mednafen/lynx/link.cpp` puts the UART on the
link bus through `RETRO_ENVIRONMENT_GET_LINK_INTERFACE` (the block in
`link_interface.h` is a verbatim copy). Uncabled it behaves as stock; there is no
core option. Three things had to be true before a commercial game would start a
linked match, and each one was found by a game failing without it:

1. **A byte lands when its stop bit would.** It is sent the moment the guest
   writes SERDAT, stamped with the tick its last bit leaves the wire
   (`CMikie::ComLynxByteCycles()`: 11 Timer-4 borrows), and latched at that tick
   with no countdown (`ComLynxRxWire`). The first build sent at the END of the
   frame, stamped a 256 us grain on, and then queued it behind Mikey's 44-tick
   loopback gap -- about eight byte-times late. Title screens linked; every game
   start sent each unit off alone with its TX count frozen (Joust, Rampart,
   Slime World). The grain is 2048 cycles (128 us), under the fastest byte
   (62500 baud, 2816 cycles), so every stamp is inside the peers' horizon.
2. **It is one wire.** While cabled, a unit's own byte goes into the same inbox
   as its peers' (`ComLynxExternalLoopback` turns Mikey's instant loopback off),
   ordered by the tick it ends, and frames that overlap are merged by AND (a break
   wins), because the line is open-collector. With the loopback always first, no
   two units heard the wire in the same order and nothing ever collided: two or
   three units agreed by luck, four or more never did (Slime World had no banner
   at 4 or 8, Warbirds split "3 PLAYERS"/"2 PLAYERS"). A byte is latched at its
   stop bit with whatever overlaps it that has arrived; holding it a grain to be
   sure made each unit hear its own echo late, and games that check the echo do
   not forgive that.
3. **Units are not switched on in the same instant.** Identical code on identical
   clocks transmits at identical ticks; on a colliding wire every frame then
   collides and the ANDed byte settles nothing (the tell: each unit's received
   count EQUALS its sent count). Real units drift, and games' collision recovery
   assumes it. In the room players power machines on at different times; the
   probe staggers them (`--stagger`, default 7 frames).

NOEXP (IODAT bit 2) reads the lead: `ComLynxCable(peers >= 2)`. Inverting it
changed nothing in any game tried.

**The frontend bug this found.** `GET_OVERSCAN` wrote an `int32_t` into the
core's `bool` (libretro.h says `bool *`). In Beetle Lynx that bool sits right
before `input_state_cb`, so the write zeroed its low byte -- which turned it into
the POLL trampoline, and every button read 0. No Lynx game had ever taken input
in RetroXR. `VideoHandler::GetOverscan(bool*)` now.

**The room.** `atari_lynx.tscn` carries a `LinkPort` on the bottom edge; the spawn
catalog offers "ComLynx Cable" -- the GBA lead (`link_cable`), whose inline
junction is how a third to eighth unit chains in, as on the real cable.

**Room probe** (`RetroXR/Tools/link/lynx_link_room_probe.tscn`, `-- --roms=Z:/roms`):
the path a player uses -- three Lynxes from `system.tscn`, the catalog's ComLynx
Cable seated in two sockets, the units switched on one after another, Slime World
talking across the lead; then a second lead from the first one's junction to a
third unit (a bus of three), a plug pulled and pushed back. 19 checks. Windowed
with `--shot` it photographs the cabled pair to `probe_out/lynx/room/`: both screens
say "2 PLAYERS", the plugs seated in the bottom edge.

**Probe** (`RetroXR/Tools/link/lynx_link_probe.tscn`, one at a time -- two cabled
probes in parallel break each other):

```bash
"$godot" --headless --path RetroXR res://Tools/link/lynx_link_probe.tscn -- \
    --rom="Z:/roms/atarilynx/Warbirds (USA, Europe).lnx" --count=4 \
    --seq="h10,w1500,s:t,0:B,w200,1:B,w200,2:B,w200,3:B,w300,s:m,0:B,w300,1:B,w300,2:B,w300,3:B,w300,s:r3"
```

Needs the BIOS at `system/mednafen_lynx/lynxboot.img` (not `system/`). Always run
the same script with `--nocable` as the control leg. `hN` holds presses longer;
several games drop a 3-frame press in a linked menu.

**Games** (2026-09-21, core `7844198`):

| Game | Result | Units | Notes |
|---|---|---|---|
| Checkered Flag | PASS | 2 | both press P then A; SINGLE HEAT (not PRACTICE); one race, same clock on both |
| Joust | PASS | 2 | "2 PLAYERS" on the title; one arena, blue and yellow riders |
| Rampart | PASS | 2 | red and blue castles on one map (`h8,w1100,...`) |
| Todd's Adventures in Slime World | PASS | 2, 4, 8 | every unit presses P, then D, A on unit 0; "8 PLAYERS" and eight Todds in one cave |
| Warbirds | PASS | 2, 4 | "4 PLAYERS"; `h10`; the others' planes in formation and in flight |
| Xenophobe | PASS | 2 | the other's character crossed out on select; one room |
| BattleWheels | PASS | 2 | one arena, the other car and its explosions; shared scoreboard |
| Battlezone 2000 | LINKED SETUP | 2, 4 | "N PLAYERS", a tank colour per unit, the solo wave screen skipped; CPU enemies could not be switched off, so the other player's tank in the arena is not yet confirmed |
| Gauntlet: The Third Encounter | FAIL | 2, 3 | units sync the intro and title, but whoever starts goes to character select alone and stops transmitting; tried either unit, both, staggers 7/150, holds, during the intro |
| California Games | FAIL? | 2, 3 | the title streams bytes but never syncs; no linked start found |
| Robotron: 2084 | N/A | 2 | never touches the UART; single player |

Gauntlet and California Games are the open ones: both talk on the title and give
up at the start, the shape the first two fixes cured elsewhere, so the next
suspect is a timing detail neither game tolerates (parity, the TX-empty IRQ, or
a byte arriving in the grain it overlaps).
