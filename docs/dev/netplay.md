# §2f, §2g — netplay, and netplay over a link cable

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### 2f. Netplay — a suite, and the one thing it cannot cover

`RetroXR/Tests/netplay_tests.tscn` is 685 cases over the whole lockstep stack,
headless, ~32 s, exits non-zero. Groups: `cores/` (the determinism allowlist),
`identity/` (which core builds may play each other), `wire/` (every packed
block's round trip, including per-port accelerometer, gyro, IR/touch and
lightgun state), `owners/` (who supplies which port on which frame),
`assemble/` (frame completion and pruning), `start/` (the asynchronous cold
start), `lockstep/`, `desync/`, `join/`, `leave/`, `rollback/`, `link/` (a
cabled pair as one session).

```bash
"$godot" --headless --path RetroXR res://Tests/netplay_tests.tscn
"$godot" --headless --path RetroXR res://Tests/netplay_tests.tscn -- --only=start
```

**It runs two — for the join cases, three — complete NetworkManagers in ONE
process**, each under its own `SceneMultiplayer`, over real loopback ENet. Do
not reach for two OS processes instead: the RPCs, channels, serialization and
handshake are already the real ones, and one process keeps the run deterministic
and headless. It replaced `Tools/netplay_session_probe.tscn`, which was the same
idea at a quarter of the coverage.

Godot 4.7 currently prints a fixed `ObjectDB` shutdown warning after these
in-process branch-ENet suites (`18 RefCounted` objects in the ordinary netplay
run). It is the engine's RPC cache interaction with the project's NetworkManager
autoload, not an accumulating session leak: one pair and many sequential pairs
leave the same fixed count, a raw ENet pair in this project reproduces it, and
the same raw pair in a minimal project without the autoload is clean. Removing
the autoload before connecting suppresses the warning but leaves Godot with a
dangling autoload singleton and eventually crashes the full suite, so do not
hide it that way. The passing case count and exit status remain the gate.

What no suite here can cover is a real core's arithmetic. That is
`Tools/netplay/netplay_spike.gd`, and it now has a **cross-machine leg**, which is the
only thing that tests the one payload lockstep actually puts on the wire — a
savestate, shipped for a late join or a desync resync:

```bash
machine 1:  ... res://Tools/netplay/netplay_spike.tscn -- --spike-state-out=Z:/np.bin
machine 2:  ... res://Tools/netplay/netplay_spike.tscn -- --spike-state-in=Z:/np.bin
```

Machine 1 writes its state, the frame, its core identity and its whole phase-A
CRC table; machine 2 loads that state into ITS core and replays the same input
timeline against machine 1's CRCs. Run it x86_64 → arm64 and back. Cold-start
CRC determinism was verified across those two in 2026-07-06; a foreign savestate
crossing between them was not, and a libretro state is a struct dump for most
cores.

**ROM/device validation still owed:** the automated suite proves that lightgun,
accelerometer, gyroscope and multi-point IR/touch values survive the network,
reach the native input handler and keep their sub-device index. It does not prove
that a real content core consumes those values correctly. In particular, Wii
Remote accel/gyro/IR through Dolphin and a real lightgun title still need a ROM,
the matching core and preferably the real controller. The user does not plan to
obtain a ROM, so leave this as an explicit unverified hardware/content check; do
not represent the mock/no-ROM suite as that proof.

**Cross-platform play is a build-identity problem before it is a determinism
problem.** `core_download_manager.gd` points every platform at
`nightly/<platform>/latest/`, so five separate builds are in play (win-x64,
linux-x64, android-arm64, osx-arm64, osx-x64) cut at five different times from
five different commits. Two Windows players who downloaded the same day are
byte-identical; a Windows player and a Quest player essentially never are. The
core FILE can therefore never be compared — what is compared is
`Libretro.GetCoreIdentity()`, which the C++ publishes from the emulation thread
once `retro_load_game` succeeds: `library_name`, `library_version`,
`api_version`, `serialize_size`. fceumm puts its git hash in the version
(`FCEUmm (SVN) 5cd4a43`), so nightly skew really is visible there.

That dictionary is **empty until content has loaded and empty again after it
stops**, which makes it the readiness test as well as the identity. That matters
more than it sounds: `StartContent` spins the emulation thread and returns, so a
core that is missing, refused or wedged fails ASYNCHRONOUSLY — a real fceumm
took **34 frames** to come up in a probe here. Reporting a peer ready before
then is reporting a peer with no core.

**The identity is published in two halves, at the two moments each half is safe
at, and both constraints are load-bearing:**

- `library_name`/`library_version`/`api_version` land **at load**. They were
  read from `retro_get_system_info` during `Core::Load` and cost no call into
  the core, so they are safe everywhere.
- `serialize_size` lands **after the first `retro_run`**, and is 0 until then.
  Dolphin answers `retro_serialize_size` by marshalling onto its CPU thread and
  walking every subsystem, so asking at load segfaults it on a machine that does
  not exist yet — and because the publish sat on the unconditional load path,
  that broke every Dolphin boot, not just netplay.

It cannot simply move to after the first frame either: **the netplay gate does
not run frame 0 until every peer reports ready, and readiness is this dictionary
being non-empty.** Requiring a frame deadlocks every cold start — measured, the
identity never arrived in 2888 ticks — and the symptom is a 10 s timeout saying
"core did not come up". So a reader comparing sizes across peers must treat 0 as
"not measured yet" rather than as a difference; at cold start both peers are
usually 0 and the version comparison carries the weight.

`RetroXR/Tools/netplay/core_identity_probe.tscn` is the guard for all of that, and it
needs a real core so it stays a probe. It runs the same core twice, gated (a
netplay cold start: identity must arrive with ZERO frames run) and ungated (the
size must really get measured), and exits non-zero.

```bash
"$godot" --headless --path RetroXR res://Tools/netplay/core_identity_probe.tscn -- \
  --ident-core=fceumm "--ident-rom=$HOME/retroxr/roms/nes/rom.nes"
```

**Run it against dolphin, not just a quick NES core** — fceumm cannot fail the
half that matters. And give Dolphin `--ident-leg=gated` and `--ident-leg=ungated`
in separate processes: both legs in one run means a restart, Dolphin is one of
the cores that will not unwind, and the abandoned thread segfaults on the way
out looking exactly like an identity crash.

### 2g. Netplay over a link cable — one session, two machines

**A link cable never crosses the network.** `LinkCoordinator` is a process-wide
singleton joining two cores in the SAME process, so under netplay every peer
replicates BOTH machines and it is determinism, not a wire, that keeps the two
buses agreeing. A cabled pair is therefore ONE session over TWO machines, which
is why `NetplaySession` holds a `_group` rather than a system.

Ports are named `machine * PORTS_PER_MACHINE + port`, so both machines' pads fit
in one assembled frame; each core is handed only its own 20-int block plus that
machine's aux and key blocks. Aux (tilt, touch) and keyboard ride with each
machine's own port-0 owner — copying the anchor's tilt into every linked handheld
is just as wrong as dropping the far handheld's input. A linked late join pauses
every local core at one boundary and transfers both core savestates plus
`LinkCoordinator`'s clock horizons and queued messages. The joiner restores the
physical bus first, then its external bus snapshot, then the core states, so it
cannot resume half of an in-flight serial conversation.

The per-machine launch spec also records `rom`, `empty_media`, or `no_content`.
That last mode is the cartridge-less GBA in single-pak play: it cold-boots mGBA
with the BIOS only, then an ordinary core savestate carries the downloaded
program, RAM, registers and link state just like a cartridge-backed machine.
Empty-disc BIOS menus use `empty_media` instead and regenerate the zero-byte
image locally; BIOS files themselves are never transferred. Every peer must
already have matching firmware. The no-ROM tests cover this launch/state
plumbing with mock cores. mGBA IS now in `NetplayCores` (verified, with
ROLLBACK/LOCKSTEP/DETERMINISM), so the core is no longer the blocker it once
was — but a real single-pak netplay run still needs a payload-carrying game ROM,
which the user does not plan to obtain. Leave THAT validation noted as
outstanding; do not read mGBA's presence in the table as proof single-pak play
was exercised end to end.

Late-join state is a bounded stream, not one RPC: 64 KiB reliable chunks, eight
in flight, cumulative acknowledgements, SHA-256 per payload, and a 256 MiB total
cap. The metadata is a chunked payload too, because it contains SRAM and the
external link-bus queues. Capture, transfer, core startup and state load all have
progress deadlines; a timeout tears the newcomer down, makes it a spectator and
releases the existing players. Firmware matching hashes every path declared by
the core (including directory contents), not only the files used to draw a BIOS
screen.

Two things this had to get right, and both are the same rule:

- **Every machine on every connected wire is in the session.** When it held one, the far end
  was ungated on the host and not running at all on a client, so the client's
  gated core sat on a bus whose other end never published — and the coordinator
  waits for a peer that is behind rather than guessing, with deliberately no
  timeout. Host fine, client wedged. A console can have several independent
  leads (four GameCube-to-GBA cables are the obvious case), so the group is the
  transitive merge of every cable bus touching the anchor, not the first match.
- **All THREE leads, not just the handheld one.** Every lead that can put two
  cores on a wire answers `linked_machines()` / `held_machines()`, and a machine
  finds its bus by asking the leads rather than searching its own sockets. That
  is not tidiness: a GameCube-to-GBA lead puts its wide end in a **controller**
  socket, so there is no `LinkPort` on the console side to walk out of, and a
  search from the machine would have decided a cabled GameCube was on no bus at
  all. `net_link_bus` therefore sweeps both the `link_plug` and `controller_plug`
  groups. (That the GC end is in `controller_plug` and not `link_plug` is pinned
  by `link_tests`; the same suite seats both ends through their real socket APIs
  and verifies that `net_link_bus` discovers the console through
  `controller_plug`.)
- **A plug seated mid-game lands on ONE agreed frame.** `LinkCoordinator.hpp`
  says so itself: the thing it cannot enforce is that Connect and Disconnect
  happen on the same emulated frame on every peer, and that is the caller's job.
  Nothing was doing it. The host now waits for every peer to acknowledge the
  reliable topology command, then holds the boundary until every local core has
  finished the preceding frame; only then does it change the bus and release
  that frame to any core. `link_cable._resolve` hands the decision to the host
  instead of joining on the spot whenever a hand moves.

`RetroXR/Tools/netplay/netplay_link_probe.tscn` is the real-core half — two gambatte
Game Boys, the real bus, ROMs from `Tools/gen_gblink_rom.py`:

```bash
python Tools/gen_gblink_rom.py     # once, into RetroXR/Tools/gblink/
"$godot" --headless --path RetroXR res://Tools/netplay/netplay_link_probe.tscn
```

Its two legs pull opposite ways and both must hold. Fed on both machines, the
pair runs and trades bytes (240 frames, 293/431 messages). Fed on only the near
one — a client before the group existed — **the near core reaches frame 2 and
stops dead.** That second leg is the reproduction, and a green there would mean
the bus had stopped waiting, which is worse than the hang: a cabled netplay pair
would desync instead of stalling.

`RetroXR/Tools/link/gc_gba_link_probe.tscn` is the same thing for the ASYMMETRIC
lead, which had been reasoned about and unit-tested and never once run with the
cores that actually speak the JOY bus. It wants Dolphin, mGBA and two commercial
ROMs, so it is a probe. It reproduces what `GcGbaCable` does on seating, in
order: `SetControllerPortDevice(port, (7 << 8) | 0)` then
`LinkConnect(gba, console_port, GBA_JOY_PORT)`.

```bash
"$godot" --headless --path RetroXR res://Tools/link/gc_gba_link_probe.tscn
"$godot" --headless --path RetroXR res://Tools/link/gc_gba_link_probe.tscn -- --gba-empty
```

First run, 2026-08-21, Four Swords Adventures against Super Mario Advance:
Dolphin attaches `gba-joy-1` at 486 MHz, mGBA at 16777216 Hz, `bus 0 [P1 on,
P2 on]`, peers 2/2, and **6247/6248 messages** over 1574 frames with both cores
in step. So the console-port end of the lead works with real cores.

**`--gba-empty` is the pairing the game actually wants**, and the difference is
stark: with no cartridge in the handheld the same run trades **82407/82408**
messages, thirteen times as many. Four Swords Adventures uses the GBA as a
screen and pad and uploads its own program over the wire, so a handheld holding
its own commercial cartridge is a legitimate cabling but not a conversation
either title was written for. Do not read a low byte count in the cartridge case
as a fault.

**The bus is cheap, and the teardown cost report does not say otherwise.**
Measured with `--no-cable`, which boots both cores side by side and never joins
them: uncabled **57.1 / 57.3 fps**, cabled **54.8 / 54.6 fps** over the same
28.4 s. About 4%. The report's "22368 ms blocked" over a 28.4 s run looks
alarming and is not lost time — the two cores are on separate threads, so one
blocking IS the other one working. Read the fps, not the blocked total.

What the report is good for is STALLS, and there is one real artifact: a single
~1 s hitch early on (967 ms on the console at 1034 ms in, 1197 ms on the
handheld at 2394 ms in), with only 1 and 6 further events over 20 ms in the
whole run. It lands during the program upload and does not recur. On a desktop
that is a hitch; in a headset it would be felt once, and it is the one number
worth watching if this ever reaches a Quest.

Both cores are now in `NetplayCores` (they were not when this section was first
written): `mgba` is `verified` with ROLLBACK/LOCKSTEP/DETERMINISM, `dolphin` is
`verified: false`, `state_transfer: false`, DETERMINISM only. So a session over
this pair can now be started — but note what the probes above do and do not
prove: they exercise the BUS with real cores, not a netplay session over it.
Dolphin having no transferable state is why it is DETERMINISM-only, which in
turn means no late join and no desync repair.

### e-Reader cards under netplay (mGBA) — 2026-09-22: rollback and late join both measured

A swipe during a session is a **disc op, kind 2** (`NetplaySession.DISK_OP_CARD`):
`system.gd._on_expansion_card_swiped` sends the strip's md5 to the host (clients
use `EV_DISK_OP` intent), the host schedules it, and every peer resolves the strip
in its OWN card folder with `net_resolve_card` — never `net_resolve_rom`, which
would re-point the machine's cartridge at the strip. The core sees an ordinary
eject/replace-image-0/insert on the agreed frame (`ScheduleDiscOp`).

- **Why rollback is allowed for this op and not for a disc:** RetroXR's mGBA fork
  now serializes the whole scanner — registers, serial state, scan position, the
  card under the head and the one waiting (`GBA_SUBSYSTEM_EREADER` extdata, a
  FIXED-size block so `retro_serialize_size` does not change on a swipe). Before
  that it was upstream's `// TODO: Serialize these`.
- **Under rollback the op is scheduled `MAX_AHEAD` further out**: a rollback core
  speculates up to MAX_AHEAD past the confirmed frame, so `DISK_LEAD` alone can
  name a frame it has already run.
- **libretro-godot race, fixed:** the solo runner's boundary stall let a disc/reset
  frame run as soon as it was CONFIRMED; confirmations arriving during the 4 ms
  wait could leave the frames just before it unverified, and the later rewind
  went behind the op, which a replay never re-applies. The card vanished. It now
  also requires `m_np_verified + 1 >= frame`. The group runner never had it.
- **Proof:** `Tools/netplay/ereader_rollback_probe` (legs `ref`, `rb`, `join`,
  `compare`; windowed for the final screen). Real e-Reader (USA) + Air Hockey-e
  strip 1, `--crc=ram`: rb == ref at 42/42 checkpoints (23 after the card) with 42
  rollbacks, join (fresh core, mid-scan snapshot) == ref 21/21, all three reach
  "Scan AIR HOCKEY 2/2". **Control:** the same fork without the scanner block —
  rb diverges from frame 630, join from 660, both drop back to "Scan Dot Code".
  Use `--crc=ram`: the whole-state CRC differs between identical runs on this
  core, so it cannot be the oracle.
- Not yet exercised: two real peers over a real network, and a multi-strip card
  (strip 2) inside a session.

### The standalone VMU (vemulator) — 2026-09-22: rollback yes, measured end to end

A VMU running a minigame out of a controller is its OWN netplay machine: `VmuCard`
answers the same duck-typed seam as `RetroSystem` (`get_libretro_node`,
`net_boot_spec`, `net_prepare_boot`, `net_start_core`, `net_stop_core`,
`port_holders`, `net_sram_file_bytes`/`net_set_sram`). One port, and the card is
its own pad, so `_requires_lockstep_input` skips a machine whose holder is
itself (it has no aux feed) and ObjectSync hands port 0 over on a grab
(`_maybe_handoff_port`'s `VmuCard` branch). A host in a session who powers a card
on gets `_net_offer`: the session boots the game on every peer instead.

- **What a peer boots from.** A library minigame (`roms/vmu`) goes by md5 and is
  never sent, like any ROM. A game lifted off a CARD is the player's save, so its
  128 KB image travels in the spec's SRAM field, flagged `vmu_card` in a `rom`
  spec (the session knows three modes); the client checks it against the md5.
  Progress goes back to the HOST's card only.
- **It needs the RetroXR fork past `retroxr-vemulator-libretro-v2`.** v2 has no
  savestates (`serialize_size 0`; rollback stalls at frame 0 waiting for its first
  state). The fork added them on 2026-09-21, and on 2026-09-22 a `clock` option
  (`system|fixed`) and an initialised `VE_VMS_CPU::instructionCount`.
- **Cold start had two separate sources of divergence, and fixing one hid behind
  the other.** (1) `VMU::setDate` seeds the clock from the host's wall clock.
  `clock=fixed` seeds Sat 1 Jan 2000 00:00, built by hand rather than through
  `localtime`, because peers in different time zones would otherwise disagree.
  (2) `instructionCount` was never initialised and is serialized, so the STATE
  CRC differed from frame 60 even with identical emulation. Measured by diffing
  two cold states at frame 4: 22 bytes, PC, ACC/C and that counter.
- **`--spike-option` does NOT reach vemulator at load.** It goes through
  `SetCoreOption`, which is ignored before `StartContent`, and the core writes its
  whole option set back at shutdown, so a spike "with clock=fixed" was running
  whatever the `.opt` file said. Write `core_options/vemulator.opt` directly
  before each run. `NetplaySession` pins through the file, which is the right path.
- **The CRC is a savestate's** (`crc_from_state`): the core publishes neither
  SYSTEM_RAM nor a memory map, so the RAM oracle never fires. `netplay_spike`
  takes `--spike-crc-from-state` for the same reason.
- Pinned in the row: `clock=fixed`, `bios=disabled` (one peer having the BIOS
  file and another not is two machines; HLE is the same everywhere),
  `enable_flash_write=enabled` (the scratch-.bin crash, see `VmuCard._boot`),
  `serial_link=disabled`.

`Tools/netplay/vmu_netplay_probe` (two processes, real `NetworkManager`, real
`vmu_card.tscn`, loopback). Alien Shooter, Windows x86_64:

- library game: rollback, 82 rollbacks, port 0 handed host → client at frame 710,
  **29/29 checkpoints agreed** by both peers through frame 1740.
- `--card`: the same, the image shipped as SRAM: 29/29 agreed.
- mutation: the fork WITHOUT the `instructionCount` initialiser → DESYNC @60.
- the clock mutation (`clock=system` in the row) still PASSED the probe: the two
  cold starts land within the same second. The clock's proof is the spike pair:
  `system` 61 s apart differ, `fixed` match.
- The probe counts AGREED checkpoints off the session's table, because matches
  are silent. A client that never reports is never compared, and an earlier
  version "passed" that way. The client's own "finished at frame 6" is read after
  its core stopped, and does not mean anything.

Owed: arm64 (Quest) and cross-play (`cross_play: false` until measured), a
headset run, and a published fork release. `CoreSources` still names v2 until then.
