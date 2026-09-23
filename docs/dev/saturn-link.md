# The Sega Saturn Link Cable

Two Saturns joined through their rear **Communication Connectors**, on
`mednafen_saturn` (Beetle Saturn) from **RetroXR/beetle-saturn-libretro** (branch
`retroxr`, tag `retroxr-beetle-saturn-libretro-vN`, built by the fork's
`.github/workflows/retroxr-release.yml`). The working clone is
`~/libretro-cores-retroxr/beetle-saturn-libretro`.

Official Japan-only cable (the "Taisen cable"). Exactly six games use it:
Gebockers, Hyper Reverthion, Steeldom, **Daytona USA Circuit Edition (the
Japanese disc — the Western "Championship Circuit Edition" dropped it)**, Doom,
GunGriffon II. Hyper Duel and Virtual On are NOT link games: both switch the SCI
off after the boot library and never touch it again (traced), and their
two-player modes are split-screen on one console.

Desktop only in practice: CoreRecommendations puts Android on YabaSanshiro,
which has no SCI. Beetle's Android build carries the same code if chosen.

## The core

Stock Mednafen never emulated the SH-2 serial port (SCI): its six registers
(FFFFFE00–05) read zero and writes vanished. `mednafen/ss/sh7095_sci.inc`
implements it; `link_sci.c` puts it on the link bus through
`RETRO_ENVIRONMENT_GET_LINK_INTERFACE` (the RetroArch#19454 API — the same one
libretro-godot's `LinkInterface.hpp` hosts; `libretro_link.h` carries the PR's
block verbatim until libretro-common has it).

- A byte at a time: TSR/RSR take a frame's worth of cycles from the manual's BRR
  formulas (async `32·4ⁿ·(N+1)` cycles a bit, clocked `4·4ⁿ·(N+1)`), flags with
  FTCSR-style read-before-clear (`SSRM`), ERI/RXI/TXI/TEI at IPRB[15:12] via
  VCRA/VCRB. Timing rides `FRT_WDT_NextTS`, which the JIT honours too — no new
  scheduler event, so the savestate layout is unchanged.
- Wire `saturn-sci-1`, clocked in **master cycles** (`timestamp × cur_clock_div`,
  61 or 65 by resolution, accumulated per frame) — CPU cycles change with the
  video mode.
- Only the **slave SH-2** is wired (`SL_WIRED`). See the table.
- Core option `beetle_saturn_link_cable`, default on, not restart-time; off is
  the stock core. Uncabled, every game still boots (checked for all five).

**The fixes real games forced** (each was measured, then fixed):

| symptom | cause | fix |
|---|---|---|
| Two cabled consoles hang at boot, black | every disc's boot library probes the MASTER SH-2's port in clocked mode (sends `80 11 3B 74`, listens); crossed master lines answer each other and both wait for a dev host | wire the slave SH-2 only. Every link game measured talks on the slave, async |
| GunGriffon II battle: 通信エラー (communication error) | bytes announced at the END of a frame were floored to the sender's horizon: up to a horizon of added delay, and the game waits ~2 byte-times for a reply | announce at shift START, stamped for landing — the wire's own lookahead; horizon ≤ fastest enabled port's frame |
| same, still | two queued bytes released on one cycle → overrun | the master SH-2 also wakes at the next queued byte's tick |
| same, still | game clears SSR (incl. TDRE) with TE off, enables TE later; a stale `0xFF` went out and the partner read it as its reply | TDRE is held at 1 while TE=0 |
| Daytona: hello `01`/`02` exchanged, then silence; both "Wait for a Challenger" | channel 0 set `DRCR0=TXI`: packets go out by DMA paced by the SCI. Mednafen ran every channel as auto-request and masked DMA addresses onto the external bus | DRCR RXI/TXI gate the channel on the request (RIE∧RDRF / TIE∧TE∧TDRE); DMA to FFFFFE0x reaches the SCI; a claimed source does not also interrupt the CPU |
| first byte after a quiet spell 4 byte-times late | a horizon once published cannot be retracted; the idle rendezvous (2000 Hz) had promised 0.5 ms | cap the horizon at 1/20000 s whenever cabled |

Rates seen: Steeldom slave async `SMR=21` (parity) `BRR=2`; GunGriffon II slave
async `SMR=20` `BRR=1` handshake then `BRR=0` in battle (~12 µs a byte), polled
with RXI waking the task; Daytona slave async 8N1 `BRR=5`, RXI + TXI-paced DMA.

Diagnostics, all environment variables read by the core:
`SS_SCI_TRACE=1` (all SCI accesses, folded), `=2` (slave only), `=3` (slave,
unfolded); `SS_SCI_ERRLOG=1` (overruns, framing errors, bytes at a disabled
receiver — a `cpu0 receiver-off` flood is the boot probe clocking itself and is
harmless); `SS_LINK_WIRED=<mask>` (which SH-2s the cable joins, bit 0 master).
**Keep traces short: a flood of WARN lines stalls the emulation thread** — a
20 000-line trace froze both consoles mid-frame, which looked like a deadlock.

## The room

`SaturnLinkCable` / `SaturnLinkPort` / `SaturnLinkPlug` subclass the PlayStation
lead (`psx_link_*`): two consoles, peers, no junction. The ONLY difference is the
plug group `saturn_link_plug`, so neither lead seats in the other's console —
`link_tests` asserts both directions, and forgetting the port's `plug_group`
override (it extends `PsxLinkPort`) turns five cases red. `SystemInfo/saturn.tres`
has `serial_port = true`; `default_model.build_serial_port` picks
`saturn_link_port.tscn` for `saturn`. Spawn catalog, spawn view and
`ScenePersistence.LEAD_SCENES` know `saturn_link_cable`. Geometry is the PS1
placeholder with a COMMUNICATION legend.

## Shipping

`CoreSources` names `mednafen_saturn` → `RetroXR/beetle-saturn-libretro`, tag
`retroxr-beetle-saturn-libretro-v1` (Windows + Android, CI-built from the tag),
replacing the buildbot's build in place, so `system/mednafen_saturn` and every
save stay where they were. Android still defaults to YabaSanshiro.

## The room probe

`RetroXR/Tools/link/saturn_link_room_probe.tscn` is the player's path: two
Saturns from `system.tscn` (`core_directory` = the probe root), a spawned
`saturn_link_cable`, each plug pushed in through `XRToolsSnapZone.pick_up_object`
BEFORE power, no `LinkConnect`. Steeldom: both reach LINK MODE, then only B
presses right and player 2's half of the screen must be IDENTICAL on both.
`--nocable` is the control leg and must fail 4 checks. Measured 2026-09-22 on
the CI-built v1 core fetched through the `/releases/latest/` URL: all pass
cabled, 4 fail uncabled. ("A's screen changed" alone is NOT a check — the
select screen animates, so it passes unplugged.)

## The probe

`RetroXR/Tools/link/saturn_link_probe.tscn` — two Saturns in one process, the
real bus, one button script per console in **emulated** seconds (frames/60;
wall-clock presses drift the moment the machine is loaded), a press is
`t:button[:hold_ms]`:

```bash
"$godot" --headless --path RetroXR res://Tools/link/saturn_link_probe.tscn -- \
  --root=<root with system/mednafen_saturn and cores/mednafen_saturn_libretro.dll> \
  --rom="Z:/roms/saturn/<disc>.chd" [--nolink] --at=60,70 --shot=<dir>/s.png \
  --press=... --press2=...
```

It writes `save/<core>/satlink_{a,b}.bkr` in the root: **a hung boot flushes a
garbage System Memory there** and the next run says 本体RAMの準備ができていません —
delete them between experiments.

Scripts that reached link play (2026-09-21), each with a `--nolink` control leg
that fails:

- **Steeldom** — `--press=38.6:start,46.3:start,49.2:down,50.2:start
  --press2=38.6:start,46.3:start,52.1:down,53.1:start,57.9:right,59.8:right`. The
  title menu reads LINK MODE with a cable, 2P GAME without; B's right presses
  change Player 2's pilot on BOTH screens.
- **GunGriffon II** — Double Seater → VS.Battle → mission → briefing → A 先攻,
  B 後攻 (the script is in the session log: 13/14 presses, emulated ×0.965 of the
  wall-clock originals). Linked: "Now connecting", SATELLITE NETWORK: CONNECT,
  the battle with one round timer on both and OFFENSE/DEFENSE swapped. Unlinked:
  "Now connecting…" for ever.
- **Daytona USA Circuit Edition (Japan)** — `30:start,36:start,42:start` then
  three `down:80` (a 200 ms press auto-repeats two rows) and `start`, B three
  seconds later. Linked: Player 1/Player 2, Link battle course select, B's
  presses move the course on both. Unlinked: Wait for a Challenger counts down.

Two linked Saturns run at about 0.87× realtime headless on the dev desktop.

Owed: a race or battle driven to its end; Doom, Gebockers, Hyper Reverthion;
the headset.

## Netplay: rollback, and a cabled pair rolled back together (2026-09-22)

`NetplayCores["mednafen_saturn"]` is ROLLBACK + LOCKSTEP with `link_rollback`
and `rollback_needs_pins`. It needs the fork past v2 (`d7ed3e9`, `ee78092`,
`183d53b`); an installed build that does not declare the pinned options gets
lockstep. Pinned: `netplay_deterministic`, `link_cable`, `link_frame_edges` on;
`autortc`, `sh2_jit`, `mpeg_card`, `opposite_directions` off; `sh2_interleave`
exact; `midsync` on. NOT pinned: `cart`, `shared_ext`, `save_method` --
`SaturnStorage` forces those from the machine (a seated backup cartridge), after
the pins, so a pin there would only fight it.

What the core needed, each found by a measurement:

- **A load was not an identity** (`netplay_spike --spike-selfload
  --spike-crc-state --spike-crc-interval=1`, then the two states at 602 diffed by
  named variable -- a Mednafen state is 32-byte section names, then
  `len,name,u32 size,data` entries, ten lines of Python). Only the fork's own SCI
  differed: an idle `tx_end` sank a frame's cycles every frame until it wrapped,
  and a load clamped it; `poll_ts` was not saved at all, so a load moved
  `FRT_WDT_NextTS`. Everything upstream Mednafen saves was exact.
- **Cold boots differ between players** even with `autortc` off: the SMPC clock
  and its four settings bytes come from the player's own `.smpc`.
  `beetle_saturn_netplay_deterministic` (restart-time) boots a fixed, VALID clock
  (Thu 1 Jan 1998 00:00, built by hand, not `localtime`) and factory settings
  with the configured language. Invalid would stop at the BIOS clock screen.
- **Frame edges** (`beetle_saturn_link_frame_edges`). Group rollback stops both
  consoles at every frame edge and needs frame N to end on one bus tick. A
  Saturn frame does not: interlaced fields are a line short, PAL is longer, and
  the SH-2 overshoots by a block. Rather than cut `retro_run` to fixed windows
  (the Lynx way, and VDP2's frame is wired through `Emulate`), the LINK CLOCK
  gives every frame the same span, `MasterClock/40` ticks: 1:1 through the frame,
  then a jump to the next edge. Timing between the consoles is exact inside a
  frame; only the gap has no length. The port meets the peer at both edges,
  never asks past the edge, never lands a byte past the last grant, and loops
  on an early wake instead of acting on it. The savestate's optional `LINK`
  section carries the clock and the driver (queue, horizon, holds, grant),
  restored verbatim only in this mode. **Outside a frame the port does not
  meet the bus**: the attach kick inside `retro_load_game` used to wait for the
  other console, which a session has not started yet (it waits for every core
  to load) -- the second Saturn never finished loading.

**The room had a hole too:** `RetroSystem._link_cables` finds a machine's bus by
sweeping `LinkPlug.ANY_GROUP`, and the PlayStation, Saturn and Jaguar plugs are
`RcaPlug`s of their own that never joined it. A session on a cabled Saturn (or
PlayStation) therefore never saw the far machine: it was not in the group, its
core never started, and the session wedged at frame 0. They join it now.

Evidence, windows x86_64:

- `netplay_spike`, Virtua Fighter 2 (USA), whole savestate hashed: self-load
  equals the plain run at all 1200 frames (was: parted at 602); rollback lag 3 and
  6 (310 rewinds) equals lockstep at 300/300; the v2 build under the same
  rollback parts at 190. Deterministic boot: host clock vs none equal 20/20; with
  the option off they differ from frame 60.
- `Tools/netplay/saturn_rollback_probe` (`--leg=rb|ref|solo|compare`, one per
  process, `--root=` for a fork build, `--option=k=v` for a mutant): Steeldom,
  both consoles in LINK MODE, rb == ref at 150/150 over 40 group rewinds,
  ~28000 messages each way; solo diverges at 70. **With `link_frame_edges` off
  the group WEDGES** at 2317, the first mispredicted press.
- `Tools/netplay/saturn_session_probe` (`--mode=rollback|lockstep`): two
  NetworkManagers over loopback ENet, two cabled `system.tscn` Saturns each (a
  TV stand-in in channel 0: a console refuses a netplay start with no display).
  Rollback: 72 group rewinds, no desync, both peers' CRCs of both machines equal
  at 150/150. Lockstep: the same, 150/150. It loads from the PLAYER'S core root:
  swap the fork build in and put the original back. Give it a LOCAL disc
  (`--rom=`): `Z:` is a network share, and two cores opening a 337 MB CHD over it
  miss the session's 10 s readiness deadline.

The crash at EXIT that two Saturn cores used to hit about half the time was not
the core. It was metaxr-audio's mixer being released through freed class records
after the last frame, and is fixed there (`extensions.md`, metaxr-audio). Owed: two real
machines over a real network, the published release (`CoreSources` still names
v1), Linux/macOS builds of the new options, and the games with a battle to the
end (GunGriffon II, Daytona CE).
