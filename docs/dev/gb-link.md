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
answer `RETRO_ENVIRONMENT_GET_LINK_INTERFACE`, and both call the wire `gb-sio-1`
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

**Link port 1, protocol `gbc-ir-1`**, at the cable's 8388608 Hz. The cable stays
port 0, `gb-sio-1`. ONE message of eight bytes: `[0] = 1` (an LED level), `[1]` the
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
  `cores_data_tests`: the row must name a core that carries `gbc-ir-1` on every
  platform. The Game Boy's row keeps SameBoy -- it has no window. A clock file is
  per core (`saves.md`), so a Gold or Silver cartridge that ran on SameBoy asks
  for the time again under Gambatte; the battery is per system and carries over.

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
`gg-ext-1`, through the link API exactly as libretro/RetroArch#19454 adds it to
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
