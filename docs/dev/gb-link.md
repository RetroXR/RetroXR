# §2e — the Game Boy link probes

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### 2e. The Game Boy link probes — three layers, two cores, two clocks

`RetroXR/Tools/link/gb_link_probe.tscn` drives the bus directly, `gb_link_room_probe.tscn`
drives the path a player uses (pick a lead up, push a plug into a socket), and
`gb_tetris_link_probe.tscn` runs a commercial two-player game over the result.
Probes rather than tests: they want a real core and, for Tetris, a real ROM.

```bash
"$godot" --headless --path RetroXR res://Tools/link/gb_link_probe.tscn -- --core=mgba
"$godot" --headless --path RetroXR res://Tools/link/gb_link_room_probe.tscn
"$godot" --headless --path RetroXR res://Tools/link/gb_tetris_link_probe.tscn -- --roms=Z:/roms --core=gambatte --core2=mgba
```

**Both cores, and between them.** gambatte and mGBA each carry a Game Boy, both
answer `RETRO_ENVIRONMENT_GET_LINK_INTERFACE`, and both call the wire `gb-sio`
with the same message layout -- so a gambatte Game Boy and an mGBA one join the
same cable, which `--core2` is there to prove. mGBA needs its GB driver as well
as its GBA one: they are separate cores with separate serial ports, and before
`gb_sio_netlink.c` a lead between two mGBA Game Boys carried nothing, silently.

The ROMs the first two run come from `Tools/gen_gblink_rom.py` and swap a known
byte for ever, painting the screen white while the byte coming back is right. No
assertion is made against an absolute shade -- a core picks a palette per game --
only that a cabled screen is neither of the two an uncabled pair shows. The
`_fast` pair is the same exchange at the Game Boy Color's 262144 Hz clock, a
transfer of 128 cycles against 4096, which is the one path a Game Boy cannot
reach: SC bit 1 reads back as one on a DMG whatever is written.

**Drive the two machines one at a time.** Tetris settles which unit owns the
clock by having both send 0x29 until one is listening when the other calls, so
two machines driven on the same emulated frame both call and neither listens --
the trace reads as two masters clocking the same tick for ever, each getting the
0xFF of a cable nobody is holding. Real hardware cannot stay there because two
people are never frame-perfect; a script can, and will. The same probe also
presses START and then LOOKS, because in Tetris that button picks a game type,
confirms a level, starts the match AND pauses it, and the pause travels down the
wire.

**Tetris DX is not a usable target.** Its 1PLAYER and 2PLAYER entries are greyed
out until a profile exists, so each machine needs a scripted name entry through
an on-screen keyboard first, and the two routes drift apart. The Game Boy Color
path is covered by the `_fast` ROMs instead.

### The Game Boy Color's infrared port — 2026-10-13

Both Game Boy cores carry it: gambatte (`libgambatte/libretro/link_infrared.cpp`,
hooked through `src/infrared_io.h`) and mGBA (`src/platform/libretro/gb_ir_netlink.c`,
a `GBInfraredDriver` beside the serial one). Neither emulated the port before --
gambatte kept the byte written to `FF56` and nothing else, mGBA called it an
unknown register and read `FF` -- so Mystery Gift flashed into the dark.

**Link port 1, protocol `gbc-ir`**, at the cable's 8388608 Hz. The cable stays
port 0, `gb-sio`. ONE message of eight bytes: `[0] = 1` (an LED level), `[1]` the
sender's bus index, `[2]` 0 or 1, stamped with the tick the edge LANDS on. The two
cores share the id and the layout, so a unit of each see each other, and nothing
limits the bus to a pair: the receiver reads lit while ANY other unit's LED is.
Every machine that has the port attaches it (not an original Game Boy, and not a
Game Boy Advance, which runs these games and leaves the window out), behind no
option, and it is inert until the frontend joins port 1 to something.

**What crosses is WHEN the LED changed, and nothing else.** RP is a lamp and an
eye: no clock, no byte, no interrupt. Pokemon tells a 0 from a 1 by whether two
flashes are 183 or 366 microseconds apart, so the one thing the wire must not do
is move two edges by different amounts. Every edge is stamped the same distance
ahead -- `IR_LATENCY`, 1024 ticks, 122 us, which is also the commit horizon -- and
a promise made while the port was idle (16384 ticks) makes the delay GROW to meet
it and stay grown for that burst, rather than shorten one flash. A port is "in
use", and its horizon short, while its receiver is on, its LED is lit, or it
flashed in the last eighth of a second; two units left facing each other with
neither using the port rendezvous 512 times a second, not 8192.

**`GBC_IR_STATS=1` in the environment makes each core say, as its port leaves the
bus, how many edges came in and how many arrived after the tick they were stamped
for** (WARN: `Infrared: 42344 edges in, 0 of them late, the worst by 0 ticks`).
None may be late on mGBA, which wakes on the tick it was granted; gambatte may be
a few ticks late now and then, by as much as a chunk overshoots its grant. It is
the thing to read first when a pair will not talk -- on a Quest, in logcat -- and
it is what separated the faults below from the game's own bad luck.

**A machine waits on ONE bus.** A port whose link cable is carrying a peer goes
DEAF: it still says where it is and still flashes, and stops seeing. Each bus
lines its machines up on its own, so with both live the cable can hold this
machine for the other while the light holds the other for this one -- for ever,
there being no timeout on either. So Mystery Gift does nothing between two units
that are each cabled to a running machine; pull the lead. `--cabled` is that leg:
nothing trades and nothing freezes.

**Not modelled:** the receiver warming up and losing sight of a steady light
(SameBoy does both), a unit seeing its own LED, anything that is not another Game
Boy Color (a television remote, a Pocket Pikachu), and the port a HuC1 or HuC3
cartridge carries.

**Three things in mGBA rode with it and are not the port**, all of them found by
loading a state on the Mystery Gift screen:

- `FF56` is a register on a Game Boy Color now: bits 0, 6 and 7 are kept, bits
  1-5 read high.
- **A loaded state could wreck the timer.** `timaPeriod` is ONE byte in the
  savestate with the flags in the byte after it, and was read back as a word. A
  state saved in the few cycles between TIMA overflowing and its interrupt -- the
  only time that flag is set -- loaded a period of 260 where it saved 4, and TIMA
  then counted on a mask that is not a power of two until the game rewrote TAC.
  Upstream, and there since 2017. Mystery Gift's timer overflows every 30 us, so
  for it that window is one save in twenty-five: the listener's `halt` came back
  4096 or 8192 ticks late and no greeting was ever answered. `src/gb/timer.c`
  reads the byte.
- **A loaded state took both link drivers off the schedule** (`mTimingClear`, and
  nothing put them back), which does not stop the machine that loaded -- it stops
  the one at the OTHER end of the wire, waiting on a tick that is never published
  again. `retro_unserialize` re-arms them, on the beat they were on, counted off
  the clock the state carries: a step from the load would leave a machine that
  loaded and one that never did waking on different ticks, and those two are
  exactly what rollback compares. With somebody in view the port's driver comes
  back no further than it had been granted before the load -- a whole horizon on
  from wherever the state put it runs past the end of the peer's promise.

**The game misses by itself, about one call in six.** The listener polls the
port from a loop a few hundred cycles long and, once it sees the caller's first
flash, halts until its next timer tick before it looks again; that flash lasts
640 cycles. Caught late it is over by the second look, the listener takes the
second flash for the first, and waits out its timeout for one that is never sent.
The caller waits a random while before it flashes, so which call misses is luck.
Not the link: no edge arrived late in any of those runs. A player presses A
again, and `gbc_ir_probe` does too (up to five times, and says how many).
`--stress=20` makes twenty calls and counts the greetings answered, with
`--reload` loading a state on each machine before every one.

```bash
python Tools/gs_save.py <a Gold or Silver save>                  # what is in it
python Tools/gs_save.py <save> --unlock a.srm
python Tools/gs_save.py <save> --unlock b.srm --id 12345 --name PROBE
"$godot" --headless --path RetroXR res://Tools/link/gbc_ir_probe.tscn -- \
    "--rom=<Pokemon Gold or Silver>" --save=a.srm --save2=b.srm
... -- ... --core=mgba --core2=gambatte   # a unit of each
... -- ... --nolink                       # the control: must NOT trade
... -- ... --reload                       # each loads a state first
... -- ... --cabled                       # and a link cable between them too
... -- ... --stress=20 [--reload]         # twenty calls: how many are answered
```

**The saves are scratch copies and are WRITTEN** (the game stores the gift), made
afresh for every run: a pair that has already traded is told "one gift a day per
person". The main menu offers MYSTERY GIFT when a save exists and
`sNumDailyMysteryGiftPartnerIDs` (file offset `0x0BE5`) is not `FF`; no checksum
covers it, so `gs_save.py --unlock` writes what the girl in the Goldenrod
Department Store does. The two copies are given different trainers because the
oracle is the cartridge: each machine writes its partner's trainer id and name
into its own save when the exchange completes, and is read for the OTHER one's.

Measured 2026-10-13, windows x86_64, both cores built from the working trees, each
leg its own process:

| Leg | Result |
|---|---|
| gambatte / gambatte, mGBA / mGBA, gambatte / mGBA, mGBA / gambatte | 20/20 each, on the first press: both cartridges hold the other's trainer, 2352 + 2240 edges and none late, 70 emulated frames at 1.00x real time |
| `--nolink`, either core | 14/14: five presses, nothing written, nothing frozen |
| `--cabled`, either core | 16/16: nothing trades, nothing freezes (the port is deaf) |
| Gold (gambatte) facing Silver (mGBA) | 20/20 |
| `--reload`, gambatte and mGBA | 24/24 each. mGBA before the timer fix: 2 runs of 6 never traded and one took four presses |
| `--cabled --reload`, mGBA | 20/20: the cable's own re-arm, nothing frozen |
| mGBA with the re-arm taken out (`--reload`) | stops dead at the first load and times out: the machine that did NOT load is the one parked |
| `--stress=20` | gambatte 15, and 17 with `--reload`; mGBA 18, and 16 with `--reload`. No edge late in any: 0 of 78076 in the last |

About 8900 rendezvous a second for each machine while both ports are in use, nearly
all of them waited on -- twice a cabled pair's idle cost, for the second or so an
exchange lasts and for as long as two units sit on the "Press A" screen.

Building the two cores here: gambatte with MSYS2's mingw64 (`make -f
Makefile.libretro platform=win` from a MINGW64 shell), mGBA with CMake and the
VS 2022 build tools, with the flags `retroxr-release.yml` gives. **gambatte's
makefile does not track headers: `make ... clean` after touching one.**
`libretro.o` holds the driver objects whose layout `link_infrared.h` and
`link_serial.h` define, and is not rebuilt when they change -- the core then runs,
links and mostly works with two files disagreeing about how big an object is. It
showed here as a counter reading "0 edges in, 3 of them late".

**Under netplay:** `netplay.md`, "The Game Boy Color's infrared port under
netplay".

**Released** as `retroxr-gambatte-libretro-v4` and `retroxr-mgba-libretro-v8`,
which `CoreSources` names; every platform's build comes off the tag.

#### In the room: two windows in sight of each other — 2026-10-13

A link cable is decided by which sockets its plugs are in. Infrared has no lead,
so the room decides it from where two machines are and which way they look.

| Piece | What it is |
|---|---|
| `IrPort` (`Scripts/Objects/cables/ir_port.gd`) | a node on the stand-in's `IrWindow`: link port 1, family `gbc_ir`, beam along its own **-Z** |
| `IrBus` (`ir_bus.gd`) | one static resolver for the whole room, as `ILinkBus` is: which windows are a pair, and `LinkConnectGroup` / `LinkDisconnect` on port 1 to match |
| `NetplayLinkGate` (`netplay_link_gate.gd`) | the "has a session taken this join" rule, lifted out of `CompositeCable` so a link with no lead answers to the same one |

**Two machines are linked while each one's window is inside the other's beam.**
Both ways round, because a unit that can be seen by one it cannot see is half a
conversation. It is NOT "the two beams overlap": two units side by side looking
the same way throw beams that overlap for ever and see nothing of each other
(`ir_tests` `view/` has that case, and a one-sided rule fails it).

| | to link | to stay linked |
|---|---|---|
| distance between the windows | 60 cm | 80 cm |
| off each window's axis | 60° (a cone 120° across) | 70° |
| held for | 0.3 s (3 looks) | lost for 0.3 s |

Those are the room's numbers, not the hardware's: a real Game Boy Color wants its
partner a hand's width away and nearly dead ahead, which in a headset is a fiddle
nobody could see the reason for. The room looks ten times a second
(`LOOK_TICKS` = 9 of its 90 physics ticks). The dwell is there because every
change is a bus rebuild in the cores, and in a session an operation the host
schedules: a window swept past another must not make one, nor a hand through the
beam.

- **Line of sight is required.** One ray, window to window, against the room
  (layer 1) and loose objects (layer 3), with both machines' own bodies excluded
  by RID -- a window is set into its own shell. **Nothing that is HELD blocks**:
  picking a thing up moves it to layer 17, which covers what a hand is carrying,
  seated plugs, and the unit's own cartridge, 18 mm out of the same edge as its
  window. With a partner off toward the back of the shell the line really does
  pass through that cartridge (`ir_tests` asks the held layer and gets a
  `RetroCartridge` back), so adding layer 17 to `SIGHT_MASK` means dealing with
  the cartridge first. Hands and the player's body do not block either.
- **A window has ONE partner, the nearest.** Three units in a row pair the two
  closest; the third is left alone until one of them is switched off or turned.
- **Only machines that are switched on, and not cabled.** A machine whose link
  cable has a peer on it (`LinkPeerCount(0) >= 2`) is left out of the pairing --
  its core would be deaf on port 1 anyway (above), and joining it would also fold
  the cable's machines and the beam's into one netplay group for nothing. A cable
  seated between a linked pair parts the infrared link on the next look.
- **It answers as a lead does.** An `IrPort` is in `LinkPlug.ANY_GROUP` and has a
  `cable` (the HEAD window of its pair, from both windows, so a sweep that keeps
  each lead once keeps the bus once) answering `linked_machines()`,
  `held_machines()` and `rejoin()`. So `RetroSystem._link_cables`, the re-state
  after a core restart (`net_refresh_link_cables`) and focus mode's "keep what is
  wired to this machine" all reach it with no sweep learning that infrared exists.
- **A restart is a fresh look.** A pair holding at 70 cm, past where it could
  link, does not come back by itself after either core restarts: it has to be
  brought within 60 cm again.
- **The window glows, faintly, while the link is LIVE** -- both cores on the bus
  (`LinkPeerCount(1) >= 2` at each end), not merely a partner in view. A unit
  facing one whose core has no infrared port (SameBoy; a Game Boy game running as
  a DMG) is in view of it, linked to nothing, and stays dark, and the `[IrBus]
  linked:` line prints each end's peer count for the same reason. The glow is
  `RetroSystemModelGameBoyColor._light_ir`, emission energy 0.12: at 0.55 the
  photograph showed a bright red panel beside the power lamp.
- **Gambatte is the Game Boy Color's recommended core on desktop now** (it was
  SameBoy; Quest was already Gambatte). `CoreRecommendations` `gbc`, pinned by
  `cores_data_tests`: the row must name a core that carries `gbc-ir` on every
  platform. The Game Boy's row kept SameBoy -- it has no window -- until
  2026-10-20, when it moved to Gambatte too, for the cable: a lead into a SameBoy
  unit joins nothing. A clock file is per core (`saves.md`), so a Gold or Silver
  cartridge that ran on SameBoy asks for the time again under Gambatte; the
  battery is per system and carries over.

`Tests/ir_tests` (119 cases, no core) is the geometry, the pairing, the dwell
and hysteresis, sight against real colliders, the netplay hand-off against a
stub session, and the scene: a real `gbc` machine's port looks OUT of the edge
its window is on (by sign), the Game Boy has none, two real machines link and
are found by `net_link_bus`. Mutation-tested 2026-10-13, 38 breaks, every one
caught -- after two rounds: the dwell cases counted looks in terms of the
constant they were meant to check (a dwell of 1 passed), and a 25 mm standoff
on the sight line turned out to protect nothing (see "held", above) and was
removed.

`Tools/link/gbc_ir_room_probe` is the room path with real cores: two
`system.tscn` machines with a cartridge each, switched on a metre and a half
apart, and only THEN brought face to face -- so the gift crosses a link the room
made under running cores. It writes saves, so it refuses to run unless the data
root holds `probe_home.txt`; give it a scratch `USERPROFILE` (and `APPDATA`).

```bash
USERPROFILE=<scratch home> APPDATA=<scratch> "$godot" --headless --path RetroXR \
    res://Tools/link/gbc_ir_room_probe.tscn -- "--rom=<Gold or Silver>" --save=a.srm --save2=b.srm
... -- ... --apart | --away | --wall | --cabled     # the controls: none may trade
... -- ... --core=mgba [--core2=gambatte]
# windowed, for the photographs of the window lit and dark:
"$godot" --path RetroXR --resolution 640x480 --position 20,20 res://Tools/link/gbc_ir_room_probe.tscn -- ...
```

Measured 2026-10-13, windows x86_64, the RELEASED cores (gambatte v4, mGBA v8),
each leg its own process:

| Leg | Result |
|---|---|
| gambatte / gambatte | 31/31: apart and dark, then linked with 2 peers each and both windows lit, the gift on the first press, each cartridge holding the other's trainer; carried apart, parted and dark |
| mGBA / mGBA, mGBA / gambatte | 31/31 each (second press and first) |
| `--apart`, `--away`, `--wall` (gambatte), `--apart` (mGBA) | 24/24 each: no partner, 0 peers, dark windows, five presses, nothing written, nothing frozen |
| `--cabled` | 27/27: the pair links, the cable goes in and carries both machines, the infrared link parts, nothing trades |

**OWED:** a headset -- nobody has held two of these up to each other, so the
60 cm / 60° numbers are untried by a hand. A Quest run: the Android cores are
published and have never been started. A real two-peer session (`netplay.md`).
Any game but Gold and Silver.

### The Game Gear's Gear-to-Gear cable

genesis_plus_gx carries it (RetroXR fork, `libretro/gg_link.c`, branch `retroxr` at `b41f14e`) on wire
`gg-ext`, through the link API exactly as libretro/RetroArch#19454 adds it to
`libretro.h` -- no private header. Both halves of the EXT port cross:

- **UART** (`$03`-`$05`), what most games use. A byte lands in the peer's `$04`
  with RX-full and an NMI **ten bit times** after it was written, at the rate
  `$05` bits 6-7 pick; reading it acks and empties the sender's TX-full. The byte
  time is load-bearing: Faceball answers every byte from its NMI, and at the old
  one-horizon delivery the rally ran 8x fast and starved the first machine.
- **Parallel pins** (`$01`/`$02`), crossed 0<->2, 1<->3, 4<->5, 6<->6.
  Mortal Kombat 1/II and Pete Sampras bit-bang them. While a machine drives any
  pin the rendezvous is every LINE (the floor: the core only syncs between lines,
  and a horizon under the grain deadlocks); otherwise every four. **Bit 7 of `$01`
  reads 1 while cabled** -- Sampras waits for exactly `CF`/`F0`, and the stock
  latch left it 0, so the two could never match.
- **No cable = no framing error.** `$05` bit 2 is a lead into a switched-OFF Game
  Gear; with no lead the line idles. Raising it with nothing cabled (BizHawk's
  reading) hung Streets of Rage at boot. The bus cannot tell the two apart.

**Three games race for the lead at boot and deadlock if both machines start on
the same frame** -- Faceball 2000, Mortal Kombat, Mortal Kombat II -- as real
hardware would. Probe them with `--delay2=2` (power the second machine on later).
In a room nobody powers two Game Gears on in the same instant.

```bash
python Tools/gen_gglink_rom.py
"$godot" --headless --path RetroXR res://Tools/link/gg_link_probe.tscn          # 10 cases
"$godot" --headless --path RetroXR res://Tools/link/gg_link_probe.tscn -- "--rom=Z:/roms/gamegear/Columns (USA, Europe).gg" --tag=col --seconds=30 "--press=DOWN@11.5,START@12.5,START@16,START@18" "--press2=DOWN@11.5,START@14,START@21,START@23"
python Tools/gglink_sheet.py col     # contact sheet, top row machine A
```

`--press`/`--press2` tap buttons at wall-clock seconds (GG button 1 = `B`, 2 = `A`;
Sonic Drift confirms only with `A`), `--nolink` is the control leg, `--core=`
loads another build (e.g. the stock one) beside the installed core. **Wait on the
screen, never on a frame count**: headless spins frames faster than the core
emulates. **Stagger the two machines' confirms**: most games make whoever picks
the link mode first the host and show WAIT on the other.

Measured 2026-09-21, every game on the list, each against a `--nolink` control:

| Game | Result |
|---|---|
| Columns, Super Columns | VERSUS -> both play (Super Columns: B must confirm first) |
| Puyo Puyo, Puyo Puyo 2 (Tsuu) | versus field on both |
| Bust-A-Move | 1P VS 2P -> handicap -> versus field |
| Dr. Robotnik's Mean Bean Machine | GEAR TO GEAR MODE -> matched wells |
| Sonic Drift, Sonic Drift 2 | VERSUS -> same race, same course |
| Streets of Rage, Streets of Rage 2 | 2 PLAYERS -> stage 1 together |
| Fatal Fury Special | LINK GAME -> player select -> same map select (no fight filmed) |
| Crystal Warriors | VERSUS -> round select / WAIT -> member select (no battle filmed) |
| World Series Baseball '95 | VS MODE -> PL1/PL2 -> line-up -> PLAY BALL on both |
| Faceball 2000 | `--delay2`; host picks 2 Players, the other follows into the maze |
| Mortal Kombat, Mortal Kombat II | `--delay2`; Kontestant 1/2 -> same fight frame, same timer |
| Pete Sampras Tennis (Europe) | LINKED on the title; the other machine mirrors every menu to the venue |
| Mortal Kombat 3 (Europe) | never touches the EXT port -- no link code in this dump |
| World Series Baseball (USA) | no VS mode -- the '95 edition is the linked one |

**In the room:** a Game Gear is its own primitive handheld (`game_gear.tscn`,
model id `game_gear`): pad left, buttons 1/2 right (1 = RETRO B = `FaceButton2`,
2 = RETRO A = `FaceButton1`), blue START, all animated by the shared stand-in
pass; the EXT `LinkPort` is on the top edge left of the cart slot, 1 mm proud,
and the spawn menu offers a **Gear-to-Gear Cable** (`gg_link_cable`: the
two-ended GB lead under its own plug family, `gg_link_plug`, so it fits a Game
Gear and nothing else -- the socket on the placeholder body is keyed too). The
placeholder box keeps its socket too, as the fallback when the model is
missing; there it stands 20 mm off the back panel on purpose (the plug collider
reaches 20 mm behind its origin, and flush it was buried in the solid box and
ejected every few frames). CoreSources fetches the linked build
(`RetroXR/Genesis-Plus-GX`, `retroxr-genesis_plus_gx-libretro-v1`, Windows +
Android). `gg_link_room_probe` seats the lead by hand and checks the bus (12/12):

```bash
"$godot" --headless --path RetroXR res://Tools/link/gg_link_room_probe.tscn -- --roms=Z:/roms
```

**Under netplay (measured 2026-09-21).** A Game Gear never plays ROLLBACK in a
session: it is a handheld (`_requires_lockstep_input`), and a cabled one is
demoted as well (§2g), so a Gear-to-Gear pair is always LOCKSTEP. The core would
support rollback: `rewind_probe` on genesis_plus_gx passed 275 anchors with
0 mismatches on Columns, Sonic Drift 2 and Faceball 2000. The cabled pair holds
the netplay gate: `netplay_link_probe` with `--link-core=genesis_plus_gx
--roms=res://Tools/gglink/link_master.gg,res://Tools/gglink/link_slave.gg` ran
241/241 frames on one bus (traffic 29/26), and the unfed leg stopped at frame 3.
Neither demotion is pinned by a suite. A real two-headset GG session is OWED.

**The Master System plays ROLLBACK on the same core** (it is not a handheld).
Stock genesis_plus_gx kept the PAUSE edge latch (`pause_b`, `core/system.c`) out
of the savestate, so a rewind across a Start press raised or skipped the NMI by
timeline: `rewind_probe` failed 3/275 anchors on every SMS game, all at the
probe's START edges, while Game Gear (Start is a port bit) passed. The fork
saves it as a tagged `PSE!` block from `retroxr-genesis_plus_gx-libretro-v2`;
Sonic, Alex Kidd and Wonder Boy then passed 275/275 (BIOS on and off). An
older core with `mastersystem` listed desyncs only on PAUSE. A real
two-headset SMS session is OWED.

### Plug families

Each of these leads used to BE the Game Boy's or the GBA's scene under another
name, so every one of them seated in every one of those handhelds and the wire
caught the mismatch only as a log line. Each now has its own plug family
(the plug's `connector`, matched by the `LinkPort`'s `connector`), so a lead fits its
own machines and nothing else; `link_tests` walks the whole lead x socket matrix.

#### The original Game Boy's connector is the large one -- 2026-10-22

The Game Boy family had ONE family too, `link_plug`, so a Color's lead seated in an
original Game Boy. The Pocket and the Color kept the pins and shrank the shell, so on
the hardware it does not:

| Lead / socket | Spawn id / scene | Connector |
|---|---|---|
| Original Game Boy's EXT. | `dmg_link_port.tscn` (on `game_boy_primitive`) | `dmg_link_plug` |
| Color and the Printer's EXT.IN | `link_port.tscn` | `link_plug` |
| Advance, SP, the AGB-005's junction | `link_port.tscn`, `connector` set | `agb_link_plug` (a `link_plug` also fits: `Connectors.ALSO_FITS`) |
| AGB-005, and the GameCube lead's handheld end | `link_cable`, `gc_gba_cable` | `agb_link_plug` |
| DMG-04, large at both ends | `dmg_link_cable` (inherits `gb_link_cable`, large shell) | `dmg_link_plug` |
| CGB-003, small at both ends | `gb_link_cable` (the id stays, so saved Color pairs still load), on both cards | `link_plug` |
| DMG-14 Universal Game Link Adapter | `gb_link_adapter` | plug `dmg_link_plug`, back socket `link_plug` |

The DMG-14 is a dongle, not a cable: a small lead goes into its back and it goes
into a large socket. It is a `LinkAdapter` (`link_adapter.gd`), a `LinkCable` with a
CAPTIVE end A, no rope, and its back socket as the junction (`junction_port()`), so
the junction walk, the bus head (the adapter, which hangs off nothing), saves and
netplay all hold unchanged. Its collider stops 8 mm behind the mating face: the
small plug's nose enters the block, and a loose adapter and the frozen plug in it
would otherwise shove each other. The `gb` card offers the DMG-04, the `gbc` card
the CGB-003, and both the adapter; the `gb` card offers the CGB-003 as well, for its
printer. **The Printer's EXT.IN is the SMALL socket** (it is a Pocket-era part:
Nintendo's support page, the Japanese box, `RetroXR-models` nintendo/gb/printer
notes section 5), so an original Game Boy prints through the adapter, as the
Universal Game Link Cable it came with in the US and Europe did; it was the large
one for an afternoon, which was wrong. `gb_printer_room_probe` cables it that way. **The Advance keyed its own plug**: a
Color's lead goes into a GBA (Game Boy mode), the GBA's lead (and the GameCube lead's
handheld end) does not go into a Color, a Pocket or the Printer, so the Advance's
sockets and plugs are `agb_link_plug` and `link_plug` is listed in `Connectors.ALSO_FITS`
as fitting it; `link_tests` spells that one cross-fit out in its matrix. Sizes are RetroXR-models' (`nintendo/gb/link-plug`,
`nintendo/gbc/universal-link-adapter` MEASUREMENTS.md): the DMG-04 nose 12.0 x 5.6 in
the Game Boy's 12.4 x 5.9 mouth, the DMG-14 an 18 x 10 x 22 mm black block. `link_tests` `adapter/` cases: a Color, its lead,
the adapter and an original make a bus of two, joined once, saved against the
adapter, and nothing once it is pulled. Headset feel and a real two-core link
through the adapter are OWED.

### The DMG-07 4 Player Adapter -- 2026-11-03, core only

**A core, as the printer is** (`dmg07`, RetroXR/dmg07-libretro, MIT, local checkout
`~/libretro-cores-retroxr/dmg07-libretro`, branch `retroxr`).
- No CPU and no game.
- It attaches FOUR `gb-sio` link ports, one per player. Port k is player k+1, and
  Game Boy k's port 0 is cabled to it, so each Game Boy is on a cable of two.
- Both Game Boy drivers refuse a wire of more than two ("a Game Boy link cable
  carries 2"), so one five-machine bus was never an option. The star has no cycle,
  so not the infrared deadlock above.
- The adapter drives the clock for all four. At each byte slot it reads each Game
  Boy's published register and sends each a CLOCK with its byte, stamped a horizon
  out, as a Game Boy clocking its own transfer does (`LinkSerial::send`).
- **FAST clocks.** The real clock is 62.66 kHz (128 us a byte, then 0.9 ms before
  the next). A normally clocked gambatte takes 976 us a byte and would leave the game
  39 us. FAST takes 30 us.
- Player 1's cable powers it: with nothing on port 0 it sends nothing.

**Released and downloadable (2026-11-04).**
- `retroxr-dmg07-libretro-v1` publishes Windows, Android arm64, Linux and macOS
  (the printer's workflow, `.github/workflows/retroxr-release.yml`).
- `CoreSources` row `dmg07` and the overlay `libretro-core-info-retroxr/dmg07_libretro.info`
  (no systemid, as the printer's).
- It is a download row on the `gb` and `gbc` pages of OPTIONS > Cores > BIOS / Extras,
  beside the printer's (`cores_view._FOUR_PLAYER_EXTRA`).
- `gb_printer_tests` `_test_four_player_adapter_core` pins all three. Dropping the `gbc`
  row turns it red.
- The app's own `CoreDownloadManager` fetched v1 into the real cores folder, and the
  installed DLL started as "DMG-07 4 Player Adapter 1.0.0".

**The room object (2026-11-04): `Dmg07Adapter`** (`Scenes/Objects/peripherals/dmg07_adapter.tscn`,
spawn token and save type `dmg07_adapter`, on the Game Boy and Game Boy Color cards).
- A light grey rounded square with a round label on top, player 1's lead captive out of
  the middle of the back, and a socket in the MIDDLE of each other face, under the
  parting line: player 2 on the left, player 3 on the front, player 4 on the right. The
  first stand-in had them toward a corner, misread off Evan-Amos's photograph; a listing
  photograph square-on to an edge and RetroXR-models' `nintendo/gb/four-player-adapter`
  agree on the middle. Sizes are estimates (85 x 25 x 85 mm; the model's 72.5 x 21.65).
- **Its mod is `xenu.dmg07`** (RetroXR-models): the model's shell, the sockets moved onto
  its `PlayerNAnchor`s 1 mm proud, `Player1Port` 30 mm inside the cable's boot with the
  cord leaving the boot's end, and the lead's free end in the DMG-07's own light grey
  plug. The lead is a scene of its own (`dmg07_lead.tscn`, inheriting the DMG-04's) so
  that `xenu.gblink`, which dresses leads by scene path, leaves it alone; `lead_made`
  tells a mod when it exists (a frame after `_ready`). `mods/probes/dmg07_probe`.
- **A machine**, as the printer is: a kept `Libretro` running `dmg07`. Its sockets are
  `dmg_link_port`s (the DMG-04's large plug) with `link_port` 1-3, so a lead from a Game
  Boy to the socket for player k+1 is a wire of two: that Game Boy's port 0 and the
  adapter's port k. The walk stops at a machine, so nothing else is needed.
- **Player 1's lead is the DMG-04's** (`LinkCable`, `dmg07_lead.tscn`). One end is seated for good in
  a hidden `Player1Port` (`link_port` 0) in the back, its plug not grabbable and drawn
  as the cord's boot. It is the ADAPTER's: taken out of `spawned` (every lead files
  itself there as it enters the tree), freed with it, and its free end's seat is the
  adapter's entry (`lead`: device and socket). A lead in one of the three sockets is
  saved by that lead, naming the adapter and `PlayerNPort`.
- **Power is player 1's plug in a Game Boy** (`wants_power`, checked on the lead's
  `topology_changed` and twice a second): the core starts then and stops when it comes
  out, and every lead on the adapter is re-stated (`_rejoin_leads`). No core installed
  says so once in a toast. `auto_power` is a test seam: a suite asks `wants_power()`
  and starts nothing.
- No netplay: `net_prepare_boot` refuses ("not supported in netplay yet").
- `dmg07_tests` (36 cases): `scene/` the three sockets on ports 1-3 facing out of their
  own faces (by sign) and in the middle of each, port 0 in the middle of the back holding
  the lead's end, the plug not takeable, the lead not `spawned`, its own scene, announced
  by `lead_made` and freed with the adapter; `bus/` four Game Boys make four wires of two (Game Boy k's port 0 and the
  adapter's port k-1), and an unpowered adapter joins none; `save/` the entry names
  where player 1's lead is, validates, and a new adapter puts it back; `spawn/` both
  cards. Mutation-tested: a socket on the wrong port, the lead left in `spawned`, a
  socket off the middle, the DMG-04's scene and no `lead_made` all go red.
- `Tools/models/dmg07_render_probe` (windowed): four Game Boys round it.
- `Tools/link/dmg07_room_probe` (real cores, real data root; `--nolink` the control):
  Wave Race through the ROOM, the four Game Boys' `HandheldInput` held still so the
  presses land (as `vb_link_room_probe`). Every port on both sides sees 2 machines, the
  adapter's core pings as player 1's lead goes in, and each Game Boy picking MULTI is
  heard in turn: `players 1234 answer`, `begin`, `transmission`, and RIDER ENTRY on
  each with its own row "YOU".
- Headset, Quest and netplay OWED.

**The protocol** (`src/dmg07.c`) is Pan Docs' "4-Player Adapter" chapter.
- Ping: `FE` then three STAT bytes, `connected << 4 | id`. The replies are read as a
  SEQUENCE (`88 88 RATE SIZE`), because Pan Docs' two charts disagree on which slot
  each reply lands in.
- Three `AA` at a packet's end switch to transmission: a `CC` packet, then data
  packets of SIZE x 4 bytes, relayed a packet late, zeros for an absent player.
- Three `FF` from a packet's start restart the ping.
- `tests/dmg07_test.c` plays four simulated Game Boys through all of it (19 checks).

**Run with four real Game Boys** (`Tools/link/dmg07_probe`: N gambatte or (`--core=mgba`) mGBA cores and the
adapter on the bus directly, a scratch root holding `cores/dmg07_libretro.dll` and
`cores/gambatte_libretro.dll`, `--nolink` the control):
- All four cables come up (`LinkPeerCount` 2 on every port), and five cores run
  together without a wait.
- **Wave Race (USA, Europe), 2026-11-03** (gambatte, four Game Boys):
- Each player picks MULTI, and the adapter logs players 1 to 4 answering one by
  one. The game replies `88 88 FF 01` (RATE $FF, SIZE 1), then `AA` x3, then `CC`,
  then transmission.
- RIDER ENTRY shows each Game Boy its OWN row as "YOU" (the ping's player ids
  reach the game). Names typed on each machine reach the other three.
- GAME SELECT and the course menu move in step on all four. The STARTING GRID
  (1 YOU3, 2 YOU1, 3 YOU4, 4 YOU2) is the same on every screen.
- On the start line each player's input byte goes out in its own turn, in grid
  order, one packet in five.
- **Data is slots 1 to SIZE, not 0.** A Game Boy loads each byte after receiving
  the one before, so its first byte of a packet goes out one slot in. Pan Docs'
  prose says the first transfers; GBE+ (`src/dmg/dmg07.cpp`) and the game say
  slot 1. With slot 0 every relayed byte read zero and nobody saw anyone's name.
- **The race runs (2026-11-04).** Player 1 takes GAME SELECT and the course, the
  others confirm on the grid, and player 1's Start begins it: the countdown, GO,
  every Game Boy's race clock counting, each rider moving, and each seen on the
  others' screens (rider "1" on Game Boy 3's). An mp4 of four screens was the
  proof. A script that reaches it reliably (`--steps`, player 1's frames):
  `300-305:1:down,330-335:1:a,340-345:2:down,370-375:2:a,380-385:3:down,410-415:3:a,`
  `420-425:4:down,450-455:4:a,800-805:1:start,1000-1005:2:start,1150-1155:3:start,`
  `1300-1305:4:start,1500-1800:1:a/60,1900-2100:2:a/50,1900-2100:3:a/50,`
  `1900-2100:4:a/50,2200-2500:1:start/60,2700-4600:1:a,...` (`a/60` taps A for 8
  of every 60 frames).
- **What read for a day as "the race stalls on its countdown" was the PROBE.**
  `GetVideoImage()` hands back the video handler's own image, which it updates in
  place every frame. `dmg07_probe` converted and resized that image for its sheet,
  which changed the image's format and size; the handler's next update no longer
  fitted, and every later screenshot was the first one again. So a countdown that
  read 3 in the first shot read 3 for ever, and a blinking cursor caught in two
  phases read as four menus out of step. Copy it first (`img.duplicate()`), as the
  probes do now: one image per screenshot is the tell (hash them).
- `DMG07_WAIT=1` (hold a slot until every Game Boy taking part is armed, which
  GBE+ and DoubleCherryGB effectively do) never waited once: every Game Boy was
  armed at every slot.
- **Two more probe traps met on the way.** A press window of 6 frames can be
  jumped entirely when the loop's passes are far apart (two runs at once): a step
  now starts when its frame is first seen and lasts its full span. And one scratch
  root, used for many runs and an mGBA attempt, stopped taking any press while a
  fresh root with the same cores did: give every run a fresh root.
- **mGBA crashed on Wave Race itself** (2026-11-04), with no adapter, no lead and
  the link option off: a segfault in `_GBMBC2Read` at the first frame (gdb on a
  bare libretro harness). Wave Race is MBC2, whose 512-nibble save RAM is smaller
  than a bank, and `GBMBCSwitchSramBank` RETURNED without setting `sramBank`,
  which went on pointing at the mapping the libretro save remap had freed. Every
  other Game Boy ROM here ran. Upstream fixed it (mgba-emu 543a19758, #3859); the
  fork carries the `mbc.c` half (`0bf7a9ba3`, released as mGBA v10). Any
  MBC2 game crashed the same way.
- **mGBA races only under GBE+'s pacing, now the adapter's default** (dmg07 v2).
  Under Pan Docs' (`DMG07_TIMING=pandocs`) the four reach the grid and count down
  together, then a few frames after GO player 1's rider sits on the line with A
  held, while gambatte races under the same script. The bytes on the wire were the
  SAME on both cores (the same slots, every Game Boy armed at every slot,
  `DMG07_TRACE`), so the fault is how mGBA's Game Boy meets Pan Docs' timing, not
  the data; not looked into further. Under GBE+'s (8 x (6 x RATE + 512) cycles a
  byte, packets back to back: 3.9 ms a byte at Wave Race's RATE $FF), with every
  player holding A from the start line, every screen scrolls, the riders show on
  each other's screens and the clocks run on both cores; gambatte runs on to TIME
  OVER. An mp4 of the four mGBA screens was the proof. `DMG07_CLOCK=normal` left
  player 1 out ("OTHER PLAYERS ARE PLAYING THE GAME").
- GBE+'s pacing reaches the race sooner, so the script's last Start taps must stop
  by frame 2400 (`2200-2400:1:start/60`) or one lands after GO and pauses a
  machine. Wave Race's race HUD BLINKS: a still without it is not a stall.
- The probe pins `mgba_gb_model` "Game Boy" and `mgba_sgb_borders` OFF, as the
  room does (`ForcedCoreOptions.game_boy_model`).

**Three games, both cores (2026-11-04), under `mixed` pacing (dmg07 v3):** Pan
Docs' ping, then GBE+'s transmission. Each half is what one game needs on mGBA:
- **Yoshi's Cookie** answers the ping on mGBA only at Pan Docs' spacing. Under
  GBE+'s ping (bytes 1 ms apart, back to back) no Game Boy ever sent `88`: every one
  took the adapter for a cable partner and played TWO-player, each seeing itself as
  player 1 of 2 on the VS setup. With Pan Docs' (or `dcgb`, which keeps that ping)
  all four answer, RATE $F3, SIZE 1. gambatte answered under either.
- Script (`--steps`): VS is SELECT on the title, then START; NAME ENTRY takes START
  then A; player 1 starts the round. `420-425:N:select,480-485:N:start,`
  `700-705:N:start,760-765:N:start,820-825:N:a` for each N, `900-1300:1:start/60`,
  then A taps. The VS setup shows players 1-4 with each machine's own number lit,
  "1 SET READY / GO", and the boards' attacks cross between players (BLIND, PANIC!,
  SLAVE, -3).
- **F-1 Race** (MBC2 too, so it needs mGBA v10): MULTI GAME is DOWN, DOWN, START;
  RACER ENTRY says RACERS LINKED 4; NAME ENTRY wants three letters (A x3) and then
  START; player 1 takes START POSITION, GROUP SELECT and the course (START or A);
  each player then MACHINE SELECT (A) and "MACHINE TYPE A OK?" (A), then START. The
  game sets RATE $28, SIZE 4. Raced: the 3-2-1 lights, four numbered cars, 280
  km/h on the straight, the lap clocks in step and RANK swapping between machines,
  the same on both cores.
- Wave Race races under `mixed` on both, as above.

**Four more, both cores (2026-11-05):** each reaches the adapter's transmission
with all four Game Boys, and plays.
- **Faceball 2000** (RATE $FF, SIZE 1): START at the title (frame 1250); the
  INTER-FACE lobby says "4 Players Ready"; in the maze each player sees the others'
  faces and names (Player_02...). Later START taps pause it.
- **Super R.C. Pro-Am** (RATE $F4, SIZE 1): START taps; "READY TO RACE ... PLEASE
  WAIT FOR PLAYER 1", then four cars on the grid.
- **Top Rank Tennis** (MBC2, RATE $85, SIZE 3): START taps alone; GROUP PLAY!! with
  PLAYER 1-4 ON, DOUBLES with the four placed, then "Play!!".
- **Trax** (RATE $FF, SIZE 1): any press skips its intro to the menu, so START at
  300, DOWN at 450 (MULTI GAME), START at 500; "YOUR NUMBER IS 1-4", MAP 01, four
  tanks each on its own screen.
- **gambatte needed a fix for two of them** (v6, released, `link_serial.cpp`). The core calls
  `LinkSerial::check()` on EVERY instruction while the guest is armed, and it
  pumped the bus inbox (a locked `recv`) every time. Wave Race waits armed in HALT
  and never noticed; Super R.C. Pro-Am and Micro Machines busy-loop armed, so a
  Game Boy on the adapter ran at a sixth of real time (Micro Machines' first 600
  frames took seven minutes, 53 million bus calls a machine) or, with four, Super
  R.C. Pro-Am never drew a frame. advance() already pumps, and a peer stamps every
  message at least its horizon ahead, so nothing due before the grant arrives
  later: the pump in check() was pure cost. publish() also sent every SC flip to a
  wire with nobody on it (alone, no cable, Super R.C. Pro-Am ran at 28.8 fps); it
  now waits for a peer. mGBA had neither (53 fps alone and cabled). The fix kept
  `gb_link_probe` at 28/28 and Wave Race and Yoshi's Cookie four-player unchanged.
- **Micro Machines does NOT answer the ping.** Its manual: three or four players
  need the 4-Player adapter, and linked "the game starts directly" in the
  head-to-head mode. On the adapter its pad is ignored and it shows car and course
  screens (alone, START gives CHOOSE GAME: One Player / Two Player). On the wire
  every Game Boy sends $C0 at every slot (now and then $63) and never $88, so the
  adapter never counts it in. Its own handshake is not Pan Docs' and is not known:
  OWED, from its code.

**Frame rate, four Game Boys and the adapter, one Windows PC:**
- Paced: 59.0-59.9 fps in every 600-frame window after power-on (the first,
  through four staggered start-ups, is about 42-48). That is full speed: a Game Boy
  runs at 59.73 fps (4194304 / 70224), not 60. A probe's "frame rate over the run"
  (55-58) includes the start-up window and is not the steady rate.
- Unthrottled (`XENU_UNTHROTTLED=1`): 104-114 fps linked, about 1.8 x real time.
  The same four with `--nolink` run at thousands, so the lockstep is the cost:
  each Game Boy made 4.9 million advance calls in a minute.

**Earlier ROMs that are not DMG-07 games:**
- Wario Blast featuring Bomberman!: its four players are the Super Game Boy's,
  on a Super NES with a multitap. Lists (and a fandom wiki) put it under the
  adapter, with the note "4 players only with the use of Super Game Boy". On a
  plain Game Boy its menu is START and PASSWORD alone (START is PLAYER SELECT then
  ROUND 1-1 VS ENEMY 1), and with four on the adapter no Game Boy ever armed its
  serial port (re-checked 2026-11-04, after the probe's screenshot fix).
- Bomberman GB (USA): Story, Lesson and Password only.

OWED:
- Micro Machines (its handshake, above).
- The frame rate on a Quest.
- A netplay row (`NetplayCores`): no session has been run with it.
