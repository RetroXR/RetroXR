# Four-player adapters: the NES Four Score and the Famicom 4 Players Adaptor

Added 2026-11-02. Two objects, one base class:

| object | spawn token / save type | where it plugs in | sockets |
|---|---|---|---|
| `NesFourScore` (`nes_four_score.tscn`) | `nes_four_score`, on the NES card | BOTH NES controller ports, with one block | four NES pads, on the sloped top |
| `FamicomFourPlayersAdaptor` (`famicom_four_players_adaptor.tscn`) | `famicom_four_players_adaptor`, on the Famicom card | the Famicom's front 15-pin expansion port | four 15-pin expansion pads, round the curve |

Both extend `FourPlayerAdapter` (`Scripts/Objects/controllers/four_player_adapter.gd`). It holds the captive
lead, the four sockets, the 2/4 switch, the save hooks, and the rule that the ADAPTER decides what its ports are
to the core. The generic `RetroMultitap` is a separate thing (one plug, the Super Multitap's arrangement) and is
untouched; nothing offers it on an NES.

## The hardware (looked up, not invented)

Sources: NESdev "Four Score" and "Four player adapters"; Wikipedia "NES Four Score and Satellite"; MAME
`bus/nes_ctrl/4score.cpp` and `hori.cpp`; Wikimedia Commons photographs of the unit and its PCB (Hori FPA-NES-02);
Nintendo Power vol. 19; shop photographs and the box back of the Hori adaptor (beep-shop, otakaraou, retorotoro);
NESdev forum t=18747.

**Four Score (NES-034, 1990, a Hori board).**
- A light grey wedge, thicker at the back. Its top slopes toward the player.
- Four NES sockets in one row on that top, numbered 1-4 left to right in red.
- **One** cord leaves the rear edge, right of centre. It ends in **one moulded block carrying two NES plugs side
  by side** at the console's port pitch. So the block fills both ports at once, its left plug in port 1.
- The 2/4 slide is at the left end, an oval cap in a front-to-back slot: "2" at the rear, "4" at the front.
- Two TURBO **push buttons** sit at the right end, B then A, oval caps flush in a panel (Commons photographs). They
  LATCH: the board under them carries two square six-pin push switches marked C V G on both sides, the
  self-locking DPDT kind, so one press holds turbo on and the next lets it off (the cap sits lower while on). Each
  works for every pad in both modes, masking its button to 0 on a clock of about two frames. An earlier build drew
  them as slides from a written description; the photographs, and the player who remembered "a switch and two
  buttons", corrected it.
- The sockets stand portrait (an NES plug is 16 x 25 mm) in black bezels, in a band of controls toward the back
  of the top; the front strip carries only the name.
- On the wire: at 4, $4016 D0 carries player 1, then player 3, then the signature `0,0,0,1,0,0,0,0`; $4017 D0
  carries player 2, player 4, then `0,0,1,0,0,0,0,0`. At 2 the unit is two extension cords, and sockets 3 and 4
  are dead.

**4 Players Adaptor (Hori HJ-17, Famicom).**
- A light grey half-disc: a straight back, and a curved front with a notch per socket.
- Four DA-15 sockets: 1 on the left flank, 2 front-left, 3 front-right, 4 on the right flank. Sockets 2 and 3 face
  forward; 1 and 4 face out at a slant.
- One cord runs to a 15-pin plug for the Famicom's front expansion port.
- A sideways 2/4 slide on top near the back: "2" on the left, "4" on the right.
- At 2, sockets 1 and 2 are the "simple" Famicom expansion pads: players 3 and 4, on bit 1 of $4016 and $4017. The
  console's two hardwired pads stay players 1 and 2.
- At 4 it speaks its own protocol on bit 1: two pads a line and a signature, with the signatures swapped against the
  Four Score's. Sockets 1 and 2 still read as simple players 3 and 4, because their eight bits come first.

**What is NOT known and is a choice:**
- Every size. No measurement of either unit was found. The Four Score is drawn 205 x 105 mm, 45 mm at the back and
  22 at the front, about eight socket pitches wide from photographs. The Hori is a 170 mm half-disc, 30 mm high.
- Both cords' lengths (1 m).
- That the TURBO switches latch is read off the board (six-pin square push switches), not off a manual.

The bodies print the numbers and switch legends only. No Nintendo or Hori wordmark, per the project's debranding,
though the Hori's "4 PLAYERS ADAPTOR" is drawn.

## What the cores do (read from their sources)

| core | NES Four Score | Famicom four players |
|---|---|---|
| fceumm (RetroXR's fork, the default for nes and famicom) | ON when port 2 or 3 is its **"Gamepad"** (513). Its plain joypad id 1 is its **"Auto"**, which turns the Four Score on only for games in its own `fourscore_db_list`. NONE on both turns it off. | port 4 **"4-Player Adapter"** (769), SIMPLE mode only (`FAMI4C`: players 3/4 = libretro ports 2/3 on D1, then 1s). Selecting it turns the NES Four Score off. Players 3/4 are read only off ports announced as Gamepad. |
| Mesen | ON when port 2 or 3 is not None and the console is not a Famicom; "Standard Controller" (257) | port 4 **"Four Player Adapter"** (768), simple mode (`StandardController::ReadRAM` shifts P3/P4 to bit 1 on a Famicom) |
| Nestopia | ports 2/3 "Gamepad" (257); which adapter reads them is its `nestopia_select_adapter` option (auto from its database / ntsc / famicom). **Not pinned** by RetroXR. | the same option, `famicom`. It has no port 4. |
| QuickNES | two players only | — |

**No core here emulates Hori's own 4P protocol.** So the adaptor's sockets 3 and 4 reach no player in either
position of its switch. Sockets 1 and 2 are players 3 and 4 in both, which is also true of the hardware. Adding the
protocol would mean six inputs in the fceumm fork (`FAMI4C` reads two); it has not been done.

## How the room routes them

`SystemPorts` gained five things, each usable by more than these two objects:

- **Port owners** (`own_port_device` / `disown_port_device`, `port_owners`). An adapter decides what a libretro
  port IS to the core, whatever pad feeds it. Its `port_device(machine, port)` answers `{type, names}`. Every
  announcement path asks the owner first: `announce_cabinet_port`, `announce_port`, `bind`, `unbind`, and
  `reannounce_all` at a core start. Pads in its sockets bind with `announce=false`. Without this, a core start
  re-announced the pad in socket 3 as itself (plain joypad = fceumm "Auto") and players 3 and 4 went dead for every
  game outside fceumm's list. The pad's own `device_names` cannot fix that: the right name depends on the port,
  not on the pad.
- **A plug that fills more than one socket** (`ControllerPlug.socket_span`, `accepts_plug_at`, `_take_spanned`,
  `_free_spanned`, `cabinet_ports_of_plug`). Each port's snap filter is bound to its index. A span-2 plug is
  refused where its neighbour is missing, shut or taken; seated, the neighbour is disabled and bound to the same
  plug, so the owner is told twice (`on_plugged_in` once per port). `build_zones` keeps a spanned socket shut.
- **The accessory connector** (`build_accessory_port`, `Connectors.ACCESSORY_PORTS`, `RetroSystem.ACCESSORY_SLOT`
  = 24 in saves and on the wire). One per console that has one; only `famicom` so far, connector
  `famicom_expansion`, libretro port 4. What seats there is announced on that port by its own device type and
  names, as a USB device is. `RetroSystemModel.configure_accessory_port` places it; the Famicom primitive's is
  `Front/AccessorySeat` on the 15-pin recess. This is the socket a Famicom Zapper, Arkanoid paddle or keyboard
  would use too.
- **Input filters** (`set_input_filter` / `filter_port_input`). Something between a port's pad and the core.
  `RetroController._deliver_joypad` and `PadReceiver._send_joypad` pass every frame through it BEFORE
  `netplay_route`, so netplay carries what the core will see. The Four Score's TURBO is the one user: it counts
  the core's own frames while a core runs (physics ticks otherwise), on and off two frames each way.
- **Unwired ports** (`UNWIRED_PORTS`: nes 2-3, famicom 2-4). At every core start a port the room has nothing on
  is announced EMPTY. Left unannounced it stays at the core's own default, "Auto", and fceumm then plugs in a
  Four Score by itself for every game in its `fourscore_db_list` (and a Famicom 4-player adapter on port 4 for its
  `famicom_4p_db_list`, at load). Measured with Bomberman II (USA): with no Four Score in the room its BATTLE MODE
  showed three players; told the ports are empty, it refuses BATTLE MODE as the real console without one does.

The adapter re-reads where its lead is from the console on every lead event (`_resync`: tear everything down,
then build again). A socket seating or leaving is incremental (`_attach_socket` / `_on_sub_released`), so other
pads are not re-plugged.

Routing:

| | port 0 / 1 (the block's plugs) | port 2 / 3 | port 4 |
|---|---|---|---|
| Four Score at 4 | the pad in socket 1 / 2 as itself, NONE when empty | socket 3 / 4; the core's named Gamepad ALWAYS (the game finds the unit with the socket empty) | — |
| Four Score at 2 | the same | NONE; sockets 3 and 4 dead | — |
| Hori, either position | the Famicom's own hardwired pads, untouched | adaptor socket 1 / 2; Gamepad ALWAYS | the lead's plug: "4-player adapter" / "four player adapter" |

Swapping the block's plugs is impossible, but the rule is general: socket i rides plug i % 2, and its port is
that plug's port plus 2 for the back row.

## Saves

The entries (`_serialize_four_player` / `_load_four_player` / `_restore_four_player` in `ScenePersistence`) hold:
`system`, `port_index` (the block's first socket, or `ACCESSORY_SLOT`), `tap_mode` (2 or 4), `sockets` (one
reference per socket), and the Four Score's `turbo_a` / `turbo_b`. A pad in a socket saves no port of its own
(`_adapter_holding`). As with the multitap, the pads restore first and the lead after; both wait for cords made
a frame after spawning.

## Checks

- `four_player_tests` (headless, no core): see testing.md. Mutation-tested: switching the owner path off turns 8
  cases red, taking the span away 8, putting the second plug on the wrong side 1, ignoring the switch 1.
- `Tools/input/four_score_core_probe` (headless, a REAL fceumm, one leg per process, `--root=` a scratch root
  holding `cores/fceumm_libretro.dll`). The probe writes an NROM test ROM (44 bytes of code) that strobes the pads, reads both
  ports 24 times and leaves bits 0-1 of each read at $0300 / $0320. Every pad goes through its OWN
  `_deliver_joypad`. Measured 2026-11-02, all four legs PASS:
  - `4p`: $4016 D0 = `1,0,0,0,0,0,0,0 | 0,0,1,0,0,0,0,0 | 0,0,0,1,0,0,0,0` (P1 A, P3 SELECT, signature);
    $4017 = P2 B, P4 START, `0,0,1,0,…`.
  - `2p` and `none`, the controls: all 1s after the first eight reads.
  - `famicom`: $4016 D1 = P3 SELECT, $4017 D1 = P4 START, then 1s, beside the hardwired Controller I on D0.
- `Tools/input/four_score_game_probe` (headless, a REAL fceumm, a real ROM, one leg per process, `--leg=4p|2p|none`,
  `--steps=from-to:player:buttons,...`, `--shots=frames`, `--out=`). Each pad goes through its own delivery path;
  the game's screen is saved where asked. **Bomberman II (USA), 2026-11-02**, with the script
  `400-406:1:start,900-906:1:start,1000-1004:1:down,1030-1034:1:down,1070-1076:1:start,1320-1326:1:start` (skip the
  intro, title, down twice to BATTLE MODE, START, 1 WIN MATCH):
  - `4p`: frame 1500 is "1 WIN MATCH READY" with **P1 P2 P3**; adding `1800-2100:3:right`, the blue P3 walks two
    tiles right in the arena (frames 1790 / 1950 / 2100) while P1 and P2 stand.
  - `2p` (the unit at 2) and `none` (no unit): BATTLE MODE refuses START; still the menu at 1500. Before
    `UNWIRED_PORTS`, `none` showed P1 P2 P3: fceumm's own guess.
- `Tools/models/four_player_render_probe` (WINDOWED, `-- --out=<dir>`): both units plugged in with pads. It
  prints the block's plugs against the NES's port zones, which are equal to the millimetre, and each switch
  knob's and TURBO cap's travel when thrown.

## Traps met building it

- Procedural meshes: Godot's front face is **clockwise** seen from outside. The Hori's first body was wound
  counter-clockwise and rendered dark from the inside.
- `-> Array[int]` functions must build typed arrays. `return [2, 3] if x else []` is an untyped Array at run time
  and fails the assignment (a SCRIPT ERROR that silently skipped the rest of `_build_routes`).
- The block's pitch is the NES model's (`nes_model.gd` `_PORT_X`, 17.9 mm). `four_player_tests` measures it
  against the console, and the second plug's world offset from port 2 against the first's from port 1. A plug on
  the wrong side is 35.8 mm out.
- Half-plane cuts make a convex outline but remove the curve between notches. The Hori's outline walks the arc
  and steps in to a short flat at each socket; it is star-shaped, so the fan triangulation holds, and the
  collision is the hull.

## OWED

- Four players in a game: Bomberman II's battle is three. A four-player game (Gauntlet II, Super Spike V'Ball) on
  fceumm, and anything on Mesen and Nestopia, which were read, not run.
- Nestopia's adapter option is left to its database.
- Headset feel: the sockets on the Four Score's slope, the slides, the block going in.
- Quest.
- A netplay session with four players. Port devices are not yet put on an agreed frame in a session; see
  netplay.md, the multitap's same note.
- Hori's 4P protocol in the fceumm fork.
- A Famicom expansion-port pad model. Today the generic pad and a real pad's receiver go in the adaptor's sockets.
- Real sizes, if a unit or its manual turns up.
