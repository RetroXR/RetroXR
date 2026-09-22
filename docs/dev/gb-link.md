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

genesis_plus_gx carries it (RetroXR fork, `libretro/gg_link.c`, core commit
`3d726c2`) on wire `gg-ext-1`, through the link API exactly as
libretro/RetroArch#19454 adds it to `libretro.h` -- no private header. The UART
is what games use: `$03` lands in the peer's `$04` with RX-full and an NMI, and
reading it empties the sender's TX-full. With nothing cabled, bit 2 of `$05` and
an NMI every frame, which is how Columns greys out VERSUS. Parallel pins are
carried too (crossed 0<->2, 1<->3, 4<->5, 6<->6); nobody has tested a game on them.

```bash
python Tools/gen_gglink_rom.py
"$godot" --headless --path RetroXR res://Tools/link/gg_link_probe.tscn
"$godot" --headless --path RetroXR res://Tools/link/gg_link_probe.tscn -- "--rom=Z:/roms/gamegear/Columns (USA, Europe).gg" --seconds=30 "--press=DOWN@11.5,START@12.5,START@16,START@18" "--press2=DOWN@11.5,START@14,START@21,START@23"
```

**Wait on the screen, never on a frame count.** Headless, the probe spins frames
far faster than the core emulates, so 240 frames was ~23 emulated ones and the
master had not sent its first byte yet -- a "failure" that was only impatience.

**Stagger the two machines' presses** (`--press2`), as with Tetris: Columns makes
whoever picks VERSUS first the host (SELECT GAME) and the other shows WAIT; both
then reach READY. Measured 2026-09-21. There is no Game Gear MODEL in the room
yet (it spawns the placeholder box, no socket), so no player can seat a lead.
