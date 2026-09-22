# The WonderSwan Communication Cable

Two WonderSwans (or WonderSwan Colors: same core, same wire) joined by a lead in
their EXT sockets, on `mednafen_wswan` from **RetroXR/beetle-wswan-libretro**
(branch `retroxr`, tag `retroxr-mednafen_wswan-libretro-vN`, built by the fork's
`.github/workflows/retroxr-release.yml`).

## The core

Stock Beetle WonderSwan's `comm.c` completes every byte into thin air and never
receives one. The fork puts the UART on the link bus through
`RETRO_ENVIRONMENT_GET_LINK_INTERFACE`, the interface proposed upstream in
libretro/RetroArch#19454, whose block `mednafen/wswan/link_interface.h` copies
verbatim.

- Protocol `ws-sio-1` at 3 072 000 Hz. A message is one byte, stamped with the
  tick its stop bit leaves the wire: 3200 cycles at 9600 baud, 800 at 38400.
  The far unit latches it when its own clock gets there.
- The link clock counts 256 cycles a scanline, because the port is serviced once
  a line and `v30mz_timestamp` restarts every frame. Horizon and grain are both
  800 (the shortest byte), so the promise delays nothing.
- A bus of more than two carries nothing: no real cable joins three units.
- Uncabled, the port behaves exactly as stock, so there is no core option to
  turn it on.
- B3: bit 7 enable, bit 6 38400 baud; a write with bit 5 set clears the overrun
  flag. Reads: bit 0 rx full, bit 1 overrun, bit 2 tx empty.

**The fixes real games forced** (each was a hang with the naive UART):

| symptom | cause | fix |
|---|---|---|
| Digimon Tamers BS Ver. 1.5: NETWORK ERROR after the handshake | the game resets the port (B3 = 00) to flush it, and a byte from before the reset was read as the answer to the next one | switching the port off empties the receive buffer and the overrun flag |
| Guilty Gear Petit 1 & 2: 「つうしんたいきちゅう」 for ever, zero bytes | they enable the serial-SEND interrupt while idle and wait for it; Mednafen raised it only as an edge on completion | send is a level interrupt, asserted while the port is on and the buffer is empty |
| One Piece GBSC: both screens black after LUFFY VS LUFFY | battle init resets both fighters through pointers kept in SRAM (1000:003C/003E) before creating them; on a blank save they are 0 and the reset ORs into the task-list head, which then loops for ever | `op_gbsc_sram_fix` in `libretro.c`: a blank save gets the pointers the game itself assigns (09B0/0AC0), once, on the first `retro_run` |

The core logs `[ws-sio] cabled/uncabled`, `N bytes sent/received` and
`N bytes lost to overrun` at 1, 10, 100 … at WARN.

## The room

`wonderswan.tscn` carries a `LinkPort` on the top edge, and the spawn catalog
offers the platform a "Communication Cable": the two-ended `gb_link_cable` lead
(nothing in the plug group is Game Boy specific).

## Probes (`RetroXR/Tools/link/`)

```bash
"$godot" --headless --path RetroXR res://Tools/link/ws_link_room_probe.tscn -- --roms=Z:/roms
"$godot" --headless --path RetroXR res://Tools/link/ws_link_game_probe.tscn -- \
    --rom=<rom> --tag=<name> --script="<steps>" [--every] [--nocable]
```

The room probe seats the lead the way a hand does. It checks the bus count, then
Puyo Puyo Tsuu's boot handshake crossing both ways, then a pull and a reseat.
The game probe scripts both units and saves side-by-side shots to
`probe_out/ws/<tag>/`. **Run it once with `--nocable` as the control leg, one
leg per process.**

**Driving the games.** Presses land a few emulated frames differently from run
to run, so title screens that only listen in a window need slack. `s` (wait
until stable) and `c:WHO:BTN` (press until the screen changes) exist for that.
**Confirm one unit at a time:** units confirming on the same frame run the same
handshake in lockstep and can both pick the same role. Vertical games use the
rotated map: Tane o Maku Tori's A is libretro DOWN, and its menu cursor is
Y-left/Y-right.

## The list, tested 2026-09-22 (cabled leg, and a `--nocable` control leg)

| game | route (`--script`) | result |
|---|---|---|
| Puyo Puyo Tsuu | `w:400 b:start:6:120 b:right:6:30 0:a:6:120 1:a:6:240 b:a:6:240 b:a:6:240 b:start:6:400` | versus match on both; uncabled the mode screen never advances |
| Digimon Tamers: Battle Spirit | `w:300 b:start:6:150 b:a:6:150 b:start:10:150 b:down:10:60` then A on each unit in turn ×3, `w:600` | 2P BATTLE fight, timers agree |
| Digimon Tamers: Battle Spirit Ver. 1.5 | as above, ともだちとバトル → Ver1.5とバトル | fight, timers agree (needed the flush fix) |
| Guilty Gear Petit | `w:300 b:start:6:150 b:a:6:150 b:down:12:60` (VS), then YES and characters one unit at a time | LET'S ROCK, same frame on both (needed the level send fix) |
| Guilty Gear Petit 2 | same route | HEAVEN OR HELL, same frame on both |
| One Piece: Grand Battle Swan Colosseum | 4× START, UP, RIGHT (グランドバトル), A, DOWN (1P VS 2P), A per unit | 1P VS 2P fight, timers agree (needed the SRAM fix) |
| Pocket Fighter | 2× START, LEFT (カードバトル), A, DOWN (通信対戦), A per unit | card link battle: VS screen and board on both |
| Tane o Maku Tori | DOWN (skip intro), DOWN (menu), Y-left ×2 (たいせん), DOWN per unit | versus field on both, こっち/そっち cursors |
| Buffers Evolution | — | **no cable feature**: the manual (p.4–30) lists only ENDURO, S.S. and RECORD |
| Rockman EXE WS | — | **no cable code**: the ROM never reads B1 or B3 (N1 Battle does, but its link battle is behind story progress) |
| Swan Colosseum | — | not in the library |
