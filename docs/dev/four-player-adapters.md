# Four-player adapters: the NES Four Score, the NES Satellite, the Famicom 4 Players Adaptor and the PlayStation and PlayStation 2 Multitaps

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


## The NES Satellite (NES-032 transmitter, NES-033 receiver)

Added 2026-11-02 after the Four Score. Two objects, both on the NES card, plus a "C Battery" row there:

| object | spawn token / save type | what it is |
|---|---|---|
| `NesSatellite` (`nes_satellite.tscn`) | `nes_satellite` | the transmitter: four sockets, TURBO B/A, CTLR/GUN slide, power button and red LED, the black IR lens at its -Z end, six C cells under a door in its bottom |
| `NesSatelliteReceiver` (`nes_satellite_receiver.tscn`) | `nes_satellite_receiver` | the receiver: two NES plugs on its back (it IS its own plug, socket_span 2, so it seats like the Four Score's block), an IR lens on its upper front angled up, a signal LED |

**From Nintendo's booklet** (archive.org NESManuals "NES Satellite_text.pdf", read page by page) and the Commons
photograph:
- The receiver goes "straight into the sockets in the Control Deck", gripped by ribs on its sides. Its LED flashes
  as information is received, and every few seconds besides.
- The transmitter takes **six "C" cells**, behind a battery door on its **bottom**.
- **Power switch:** "depress the Power Switch, the red LED will light ... pressing the switch again will turn the
  power off". Left on and unused for **seven minutes, it turns itself off**. That is electronic, so the button is
  momentary and the unit holds the state (`press_power`).
- **Mode switch:** "CTLR" or "GUN". GUN is for any game using the Zapper, which must be in **socket 2**.
- **TURBO buttons:** A and B, for all sockets at once.
- **No 2/4 switch.** It "operates differently in the three or four-player mode", so a controller in socket 3 or 4
  makes it a four-player adapter (`_four_player`). One- and two-player games want 3 and 4 empty.
- **Range** 1 to 15 feet. The beam is "approximately 60 degrees from side to side and 30 degrees up and down".
  Nothing may block the signal, and the lenses face each other.

**Not known, and chosen:**
- Every size (175 x 56 x 240 mm transmitter, 62 x 56 x 56 mm receiver, from the photograph).
- The receiver's acceptance angle (80 degrees off its lens face).
- Whether TURBO survives a power cycle. Here it latches like the Four Score's.
- The mass with cells (0.7 kg).

**How it works in the room:**
- **Pairing.** The transmitter pairs with the nearest seated receiver that no other transmitter has (`_repair`).
  This runs whenever a receiver seats or leaves, and once a second. It then routes exactly as the Four Score
  through its block (NesFourScore: `_lead()` is the receiver).
- **The infrared is a GATE on input, not on routing.** `filter_port_input` passes a pad's frame only while
  `link_up()`: powered, receiver seated, within 0.30-4.57 m, inside the 60 x 30 degree beam, the transmitter
  inside the receiver's face, and a clear ray between the lenses (`IrBus.SIGHT_MASK`: the room and loose
  objects block, held things do not). Otherwise the console hears a released pad. The routing stays put, so a
  hand between the lenses never re-plugs four pads.
- The link is looked at every 6 physics ticks.
- Any press resets the 7-minute timer and blinks the receiver.
- **CTLR with a gun in socket 2:** announced as a plain pad, since the light lines are not carried. At GUN it is
  the Zapper, and sockets 3 and 4 are dead.
- **Battery bay:** `BatteryBay` (six C, along z) and `PowerInput`. The switch does nothing without a live supply,
  and pulling the cells switches it off. As everywhere, a room with power simulation off, or with no wall outlet,
  powers it anyway.
- **Saves:** the transmitter's entry holds `gun_mode`, `turbo_a`/`turbo_b` and `sockets`, and saves no seat. The
  receiver's own entry (`nes_satellite_receiver`) holds its `system` and `port_index`. Power is not saved: it
  comes back off, as after an auto-off.

**Checked:**
- `four_player_tests` `satellite/` (39 cases): pairing, two/four-player by sockets 3-4, power, the beam,
  range, a wall, TURBO, GUN, the auto-off, the six C seats, and both halves saved. Mutation-tested: gate off (2
  red), no sight ray (1), always four-player (1).
- `four_score_game_probe --leg=sat`: Bomberman II through the Satellite, as `4p` (READY with P1 P2 P3, P3
  moving). `--leg=satoff`, never switched on, is the control: START never gets through and the game stays on
  its title.
- `four_player_render_probe` (windowed) draws the set on a second NES, and a second transmitter turned over with
  its door off and six C cells in.


## The PlayStation Multitap (SCPH-1070)

Added 2026-11-02. `PsMultitap` (`Scenes/Objects/controllers/playstation/ps_multitap.tscn`, spawn token and save
type `ps_multitap`), on the PlayStation card.

**From the Commons photograph:**
- A light grey V of two arms, its rounded vertex toward the players. The cord leaves the inner corner toward the
  console.
- Ports A and B on the left arm's outer face, C and D on the right's. Each is a controller socket with a memory
  card slot over it, lettered on top, with a card mark beside A.
- **One** connector on the cord goes into a controller port **and** the memory card slot above it.
- No switch.

**Not known, and chosen:**
- Every size (arms 130 mm along their outer faces, 34 mm deep, 36 mm tall, at 90 degrees).
- The connector's shape past "a PS1 plug with a card tongue over it". Here: the PlayStation pad's own plug, a
  26 mm tongue, and a block joining their backs. The tongue's height is read off the console it seats in
  (`_place_tongue`), since the slot's place over the port is that model's (13.6 mm on the shipped PlayStation).

**What the cores do (pcsx_rearmed read; nothing else run or pinned):**
- The multitap is an **option**, `pcsx_rearmed_multitap`: disabled / port 1 / port 2 / ports 1 and 2. It is read
  live (`update_multitap` -> `padChanged`).
- Its layout is in `pad.c`:
  - A tap in port 1 is players 1-4 on libretro ports 0-3, and the console's **port 2 then reads libretro port 4**
    (`PAD2_startPoll`: `pad_index = portMultitap ? 4 : 1`).
  - A tap in port 2 is ports 1-4, or 4-7 beside a tap in port 1.
- It emulates no cards on a tap: `sio.c` knows two cards.
- Beetle PSX has its own per-port options (`..._enable_multitap_port1/2`); its layout was not read, so it is not
  pinned.

**How the room does it:**
- `ForcedCoreOptions.ps_multitap(core, systemid, taps)` pins the option from which ports hold a tap
  (`SystemPorts.ps_multitap_sockets`, by the group `ps_multitap`). It applies both ways, so a console with none
  says disabled. The tap calls `RetroSystem.refresh_multitap_option` on every seat and pull, so a running core
  hears it at once.
- **Port 2 moves.** `SystemPorts.set_socket_port(1, 4)` while a tap is in port 1 (`socket_port_overrides`):
  - `libretro_port_for` answers the moved port.
  - The controllers table files that socket's holder at the moved port (rumble finds it there).
  - `cabinet_port_of` looks by PLUG first, so a save still names socket 2.
  - The move is quiet: it re-tables and re-announces, tells the plug's owner, and reports no plug or unplug to
    netplay. No hand did anything, and every peer makes the same move from its own tap's seat.
  - A second tap in port 2 is moved with it, so its players are 5-8.
- **The card slot.** `ControllerPlug.covers_card_slot`:
  - `accepts_plug_at` refuses the connector while a card is in that port's slot.
  - Seated, the slot is shut (`_cover_card_slot`, `RetroSystem.is_card_slot_covered`), and opens again when it
    leaves.
- **Slot A is the console's slot** for the port the tap is in: `MemoryCardController.on_memcard_inserted` /
  `on_memcard_removed` with that slot, as the console's own zone would call them. B, C and D take a PlayStation
  card that no core reads, and say so in the log.
- **Ports.** Each port is the pad in its socket as itself (a DualShock picks its port's pad type as in the
  console), or NOTHING: the tap answers "no pad" for an empty socket. The tap owns all four ports
  (`own_port_device`).
- **Saves.** The tap's entry adds `tap_cards` (a card reference per slot, validated and dropped-mod-cleaned as
  `sockets`). The console's own entry names only cards its OWN zones hold (`_console_held_card`), or slot A's card
  came back in the console's slot where the tap's connector then could not go.

**Checked:**
- `four_player_tests` `psmultitap/` (31 cases): a card keeps the connector out; seated it shuts card slot 1; A-D
  are players 1-4; the console's port 2 moves to libretro 4 and still saves as port 2; the option says port 1 for
  pcsx_rearmed and nothing for another core; an empty socket is no pad; a core start agrees; slot A's card is the
  console's card 1 and slot B's is not its card 2; the entries validate; a second tap in port 2 is 5-8 with "ports
  1 and 2"; the first pulled, the second is 2-5 with "port 2", slot 1 open, its card no longer the console's; no
  tap, "disabled".
- Mutation-tested: no port-2 move (5 red), no slot-A pass-through (1), no card gate (1).
- `four_player_render_probe` (windowed) draws it in a PlayStation's port 1 with four pads and a card in slot A.

- **Crash Team Racing (USA) on pcsx_rearmed, 2026-11-03** (`Tools/input/ps_multitap_game_probe`, headless, scratch root, HLE
  BIOS). The option is the room's own (`port 1`), not set by the probe. Script, in core frames:
  `3300-3306:1:start,3500-3506:1:down,3530-3536:1:down,3560-3566:1:down,3620-3626:1:cross,3800-3806:1:cross,`
  `3950-3956:1:down,3990-3996:1:down,4050-4056:1:cross,4400-4406:3:right,4480-4486:4:down,4481-4487:2:right`
  (VS. > SINGLE > PLAYERS > 4P, then players 2-4 move), shots 4100, 4300, 4390, 4560.
  - Leg `tap`: 3P and 4P are lit, 4P opens SELECT CHARACTER with four cursors and four kart panels, and players
    2, 3 and 4 each change their own panel (Cortex to Tiny, Tiny to Pura, Coco to Polar).
  - Leg `none` (the control: two pads in the console's ports, option `disabled`): 3P and 4P are drawn dark,
    and 4P flashes red and stays on PLAYERS.
  - Not run: a race with four players, or the pad on the console's port 2 beside a tap (libretro 4).

**OWED:** Beetle and SwanStation; a headset; the Quest; a session.

## The PlayStation 2 Multitap (SCPH-10090)

Added 2026-11-03. `Ps2Multitap` (`Scenes/Objects/controllers/playstation/ps2_multitap.tscn`, spawn token and save
type `ps2_multitap`), on the PS2 card. A subclass of `PsMultitap`: everything but the body is the PlayStation's.

**From Evan-Amos's photograph** (Wikimedia Commons, `Sony-PlayStation-2-Multitap.jpg`, public domain):
- A black, flat, rectangular box, its sides ribbed with the PlayStation 2's horizontal grooves.
- **Ports A and B on one long face, C and D on the other**, each a controller socket under a memory card slot,
  lettered on top over the port, with a card mark beside A. Going round from the cord's end: A, B along the
  front, then C, D back along the far face (D at the cord's end, as A is).
- The cord leaves one short end, and its connector fills a controller port and the card slot over it.
- No switch. "MULTITAP" across the top; the maker's marks are left off.

**Not known, and chosen:**
- Every size (140 x 78 x 31 mm, the ports 64 mm apart on a face, the card slot in the second rib from the top and
  the socket in the fourth).
- **What either tap does in the other console.** The connectors are the same shape, so a SCPH-1070 goes into a PS2
  and a SCPH-10090 into a PlayStation. Here, in the other console, socket A is that controller port's pad, B-D
  reach nothing, port 2 is not moved and no option is set (`PsMultitap._active`, by the console's systemid). What
  the real hardware does there was not found.

**What the cores do:**
- **pcee2** (WizzardSK/pcee2-libretro, `pcee2-libretro/Libretro.cpp`, read 2026-11-03):
  - The option is `pcsx2_multitap`: disabled / port1 / port2 / both. It sets PCSX2's `MultitapPort1/2`, and
    `retro_run` re-reads it and calls `VMManager::ApplySettings()`, so a change applies mid-game.
  - Its port map: 1A, then 1B-1D with a tap in port 1, then 2A, then 2B-2D with a tap in port 2. That is
    pcsx_rearmed's layout, so the console's port 2 is libretro port 4 beside a tap in port 1.
  - Every mapped pad is a DualShock 2. Its `retro_set_controller_port_device` is empty.
- **RetroXR's LRPS2 build** (`RetroXR/ps2`, fork v7, `pcsx2/PAD/PAD.cpp`):
  - The same key, values and port map (`build_pad_map`), so one `ForcedCoreOptions.ps_multitap` row serves both
    cores.
  - It declares 8 ports: 0-1 keep the USB devices, 2-7 are a DualShock 2 alone.
  - Each pad reads its libretro port's latched input through a pad -> port map that is latched with it
    (`pad_lr_live`), so the EE never reads one frame's map with another frame's input.
  - A tap's pads share their console port's analog settings. Rumble goes to the pad's own libretro port.
  - Before v7 the fork forced both taps off in `PAD::LoadConfig`, and only polled ports 0-1.
- Neither core emulates a card on a tap: slot A is the console's slot for that port, B-D are no core's.
- An LRPS2 without the key (the buildbot's, our v6 and older) drops it.
  `RetroSystem.refresh_multitap_option` warns once the core has said its options and the key is not among them.
  **But the tap still moves port 2 to libretro 4 there.** An old build reads libretro ports 0 and 1 only, so with
  a tap in port 1, sockets A and B play as the console's ports 1 and 2, and the pad in the console's own port 2 is
  lost.

**How the room does it:** as the PlayStation's (above), plus:
- `ForcedCoreOptions.multitap_group(systemid)` picks which taps a console counts, `ps2_multitap` for a PS2 and
  `ps_multitap` otherwise, through `SystemPorts.ps_multitap_sockets(group)`.
- Its slots take PS2 cards only (`playstation2`).
- The connector is the PlayStation pad's plug moulded black.

**Checked:**
- `four_player_tests` `ps2multitap/` (32 cases):
  - The connector fills a port and a card slot. The tap is in its own group.
  - A faces along Z and C the other way, A and B share a face, and the cord leaves the -X end (by sign).
  - A-D are players 1-4, and port 2 moves to 4 and still saves as port 2.
  - LRPS2 and pcee2 are told `port1`, then `both` and `port2` with a second tap, then `disabled`; Play! is told
    nothing. An empty socket is no pad.
  - A PlayStation card is refused and a PS2 card in slot A is the console's card 1.
  - The entry validates and builds a `Ps2Multitap` again.
  - Either tap in the other console is socket A alone, with no option set.
- Mutation-tested:
  - Every tap active in any console: 2 red.
  - The PS2 option row dropped: 6 red.
- `four_player_render_probe -- --only=ps2` (windowed) draws it in a PS2's port 1 with four pads and a card in slot A.
- The fork's change builds on Windows (MSVC, `ninja -C build pcsx2_libretro`).
- The new DLL declares `pcsx2_multitap` with the four values (`core_options_probe --match=multitap`: 80 options).
  The installed v6 declares 79 and no such key.
- `Tools/input/ps2_multitap_core_probe` ran the new DLL from a scratch data root on Gran Turismo 4, 2026-11-03.
  - Leg `tap` sets the option on the running core three times. The core's own WARN lines were "multitap in
    port 1: 5 libretro ports, the console's port 2 is libretro port 4", then "in ports 1 and 2: 8 ... port 4",
    then "off: 2 ... port 1".
  - Leg `none` (the control) printed no layout line.
  - This is the option path and the port map only. No game that reads a tap was run.

**OWED:**
- A real four-player PS2 game on either core. TimeSplitters 2 and Gauntlet: Dark Legacy read a tap.
- The fork's Android build, a published v7 and `CoreSources` moved to it.
- pcee2 installed in this room.
- A headset, the Quest and a session.

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
- The Satellite: a Zapper through it at GUN with a real core; its LED's every-few-seconds blink with no input;
  interference between two Satellites (here a receiver serves one transmitter).
