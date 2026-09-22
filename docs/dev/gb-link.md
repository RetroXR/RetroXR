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

**In the room:** a Game Gear still wears the placeholder box, which now carries
an EXT socket (`SystemInfo.serial_port` + `default_model.gd`, the handheld
`LinkPort`), and the spawn menu offers a **Gear-to-Gear Cable** (the two-ended
GB lead). The socket stands 20 mm off the back panel on purpose: the lead's plug
collider reaches 20 mm behind its origin, and flush it was buried in the box's
own body and ejected every few frames. CoreSources fetches the linked build
(`RetroXR/Genesis-Plus-GX`, `retroxr-genesis_plus_gx-libretro-v1`, Windows +
Android). `gg_link_room_probe` seats the lead by hand and checks the bus (12/12):

```bash
"$godot" --headless --path RetroXR res://Tools/link/gg_link_room_probe.tscn -- --roms=Z:/roms
```
