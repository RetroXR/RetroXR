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

### 2g′. Rolling back a cabled group — 2026-09-22, the Atari Lynx first

A cabled machine used to drop to lockstep, because rollback rewinds ONE core
and a cabled core's state is half a conversation. It now rolls back as a GROUP
when every core on the lead can: `Wrapper::NetplayGroupIteration`, with the
shared state in `libretro-godot/src/NetplayGroup.hpp`.

- **Every member stops at every frame edge** (`NetplayRollbackGroup::Rendezvous`).
  Each hands in a proposal (its first mismatch, how far it has verified, whether
  it could run); the LAST to arrive decides for all of them, under the lock. The
  anchor is the EARLIEST mismatch on any member, and every member rewinds to it:
  a machine whose own inputs were right still heard the other end say things it
  will now not say. A frame is verified only when every member verified it, so
  no CRC leaves for a frame the cable could still undo. A frame runs only if
  every member can run it.
- **The bus is snapshotted at every edge and restored with the cores**
  (`LinkCoordinator::CaptureGroup` / `RestoreGroup`, the late join's primitives).
  A replay stops at every edge too and re-captures as it goes.
- **A cable moves only at an edge, once every frame BEFORE it is confirmed**
  (`frame <= watermark + 1`, not `<= watermark`: a player's own input for a
  frame only exists once the frame has run). The leader lands it
  (`ScheduleLinkOp` on the head core), then captures, so a rewind TO that frame
  finds the new cable. One that arrives after its frame breaks the group.
- **The cores must END their frames on the same bus tick.** Nothing in the
  frontend can make them; it is a core option (`lynx_fixed_frames`, see
  `lynx-link.md`). A core whose frames end on its display cannot: the edges land
  at unrelated instants on the wire, the barrier deadlocks or the snapshot is not
  one moment. `NetplayCores` marks the ones that can with `link_rollback`.

**Session.** `_group_link_rollback()` keeps ROLLBACK for a group that is
`link_rollback` on every core, on ONE bus, and whose installed build declares
every option its row pins (`_core_declares_pins`, a peek: an older build ignores
the pin and would desync). `power_on_stagger` (any strategy) switches unit i on
at `start + i*stagger` (`SetNetplayPowerOnFrame`: the frame counts, the core does
not run), takes the lead OFF the bus at cold start, and holds the room's lead off
too (`holds_cable`, asked by `CompositeCable.netplay_took_bus`, because a lead
re-joins at every power-on) until the scheduled join at
`start + MAX_AHEAD + 2 + stagger*(n-1)` -- through the C++ group under rollback,
the ordinary `_link_ops` boundary under lockstep. Identical handhelds switched on
together collide on every byte; lockstep needs this as much as rollback.
`handheld_rollback` exempts a handheld that feeds nothing but buttons from the
handheld-means-lockstep rule. Late join and desync resync are refused for a
rolling group (`_state_transfer_possible`) until measured.

Three bugs the real session found, none reachable from mocks: `_pump_local_records`
drained only the anchor core, so the far machine's player was never confirmed;
`net_start_core` read `merge_values() == false` ("already set") as failure, so the
second same-core machine of a pair never started; and `LinkCoordinator::RebuildBuses`
re-anchored every bus on ANY cable change (now it keeps a bus whose members did
not change) while leaving a LOOSE endpoint's stale origin (now re-anchored).

**Evidence** (Warbirds, two Lynxes, 2800 frames, windows x86_64):
`Tools/netplay/lynx_rollback_probe` (`--leg=rb|ref|solo|compare`, one per
process): group rollback with the far pad confirmed 67 ms late equals plain
lockstep at all 186 checkpoints, 8 group rewinds, in flight; a mutant that skips
the bus restore diverges at the first rewind. `Tools/netplay/lynx_session_probe`
(`--mode=rollback|lockstep`): two NetworkManagers over loopback ENet, each with
two `system.tscn` Lynxes and the catalog's ComLynx Cable seated -- 44 group
rewinds, no desync reported, both peers' CRCs of both machines equal at all 102
checkpoints, all four screens in flight; lockstep equal at 102/102. `netplay_tests`
`link/` covers the session's decisions with mocks.

### PlayStation (pcsx_rearmed) — rollback, and a cabled pair as one group, 2026-09-22

On RetroXR's fork past v3. The cable itself was never the problem; savestates
and thread timing were, and both broke rollback long before a second console
was involved.

**A load has to put the machine back exactly**, because rollback does one every
time it mispredicts. Found by diffing every internal global before a save
against after loading it back in the same process, where a correct load is an
identity (`netplay_spike --spike-selfload` is the cheap version of the same
question: green there and red in the ordinary leg means the load is sound and
something from LATER leaked through it).

- `LoadState` called `sio1Reset()`, which re-armed PSXINT_SIO1 from the cycle of
  the LOAD. The event scheduler after a load was not the one the state
  described, so interrupts came a few cycles off and the replay wandered within
  two frames -- with no cable in the socket. The port and the netlink driver
  (clock, horizon, stamps, lines, the queue of bytes not yet landed) are in the
  state now.
- The memory cards' FLAG byte was not saved and a load set its "new card" bit on
  purpose. WipEout polls its cards when the menu opens, re-read the directory,
  and went somewhere the first run never did -- 3000 frames in, which is why a
  save at 600 looked fine.
- gpulib: the load replayed GP1(02) (acknowledge IRQ), which left it in the
  register write cache, so the game's next acknowledge matched and was DROPPED.
  Its write cache, `last_flip_frame`, the dirty bits, a VRAM transfer in flight
  and the GPUREAD latch are saved; a read transfer flushes the renderer before
  latching its first word (it read pixels the original run had not drawn yet).
- Upstream, all reached by the same audit: root counters lost the part-tick when
  `cycleStart` was rebuilt, MDEC resumed a macroblock from its start, `FifoSize`
  was re-derived from Mode, `cdClearSamples` reset to 512 (writing silence into
  the CD capture buffers in SPU RAM), `subCycle` was zeroed, and the upper half
  of SPU `regArea` was never saved.

**The cable has to keep each frame's traffic inside the frame**
(`pcsx_rearmed_link_frame_edges`, on; netplay pins it, which also refuses an
older build, since it does not declare the option). The port never asks the bus
past the frame's VBlankStart, a byte stamped past the edge waits for the next
frame, and the two consoles meet at both edges. Two more, and they are the ones
worth remembering:

- **A byte may never land past the last GRANT.** The CPU overshoots its
  scheduled rendezvous by an instruction, or a whole block under a recompiler,
  and a register read in that overshoot used to release anything due by the
  current cycle -- but a byte due past the grant may not be on the bus yet.
  This is what made a group stopped at every edge disagree with plain lockstep
  with ZERO rollbacks, which is how it was found: run `--alllocal` (both pads
  local, nothing ever mispredicted) and the difference is still there, so it is
  not the rewind.
- **A promised horizon never goes back.** The poll assigned `now + horizon`
  where the frame edge had promised further.

**Everything that runs on a thread of its own is off**
(`pcsx_rearmed_netplay_deterministic`, pinned): the threaded GPU and SPU, the
dynarec's compile thread, CD read-ahead. On a Quest they default to ON and two
identical LOCKSTEP runs parted at frame 120. One switch rather than four pins,
because which of the four a build has varies (no dynarec thread in a Lightrec
build), and a frontend pinning a name would refuse a build for not declaring an
option it cannot have.

**Evidence** (WipEout (USA), `Tools/netplay/psx_rollback_probe`, the Lynx probe's
legs and oracle driving two PlayStations through `psx_link_probe`'s menu walk
into a two-player race, `--leg=rb|ref|solo|compare`, one per process):

- **windows x86_64**: group rollback equals lockstep at 262/262 checkpoints over
  80 group rewinds, ~152 KB across the cable; the solo control (each core
  rewinding alone) diverges at 120.
- **Quest 3, arm64, new_dynarec**: 262/262 over 80 rewinds, ~156 KB; solo
  diverges at 82. Run it there with the `Quest psx rollback probe` preset
  (`com.xenu.retroxr.psxrb`), arguments in `user://psxrb.cfg`, results pulled
  back with `run-as` and compared on a desktop.
- `netplay_spike --spike-rollback`: 165 single-core rewinds equal to lockstep.
  A state written by one process and loaded by a fresh one replays 20/20, which
  is what a late join does.

**Still open**: a state loaded ~1200 frames BACK into a core that has run on
past it drifts (both CPUs, so not the recompiler). Only a LOCKSTEP resync does
that, and the row does not offer LOCKSTEP. `cross_play` is false: never
measured across architectures.

### Sega Saturn (mednafen_saturn) — rollback, and a cabled pair as one group, 2026-09-22

On RetroXR's fork past v2. Exact loads (the SCI's clocks), a deterministic boot
(fixed SMPC clock and settings), and `beetle_saturn_link_frame_edges`: the link
CLOCK gives every frame one span, so edges line up whatever the video mode. The
details, the probes and the numbers are in `saturn-link.md` § Netplay. The same
work found that PlayStation, Saturn and Jaguar plugs were missing from
`LinkPlug.ANY_GROUP`, so a session never found a console lead's far machine.

### Atari 2600 (stella) — vetted 2026-09-21: lockstep yes, rollback NO

`netplay_spike` on `stella_libretro.dll` with Air Raid (USA), Windows x86_64,
control leg fceumm/3-D WorldRunner under the same flags (passes both modes):

- lockstep: two cold starts give identical CRCs; savestate (1041 bytes) @600
  reload → 0/20 mismatches. DETERMINISM + LOCKSTEP hold.
- `--spike-rollback --spike-lag=0` (serialize every frame, 0 rewinds) == lockstep,
  so per-frame serialization does not perturb the core.
- `--spike-lag=1` and `=3` DIVERGE from lockstep at the first input change
  (START at frame 180; CRC 180 matches, 240 does not). One rewind across a
  changed input corrupts the run: something input-dependent is not in stella's
  `retro_serialize` (suspect the libretro wrapper's own cached input / console-
  switch edge state — unconfirmed). A lag-1 run "passing" its own replay is
  self-consistency, not correctness — diff against lockstep.

So stella is NOT in `NetplayCores`. If added, it would be `strategies:
[Strategy.LOCKSTEP]` only; not done yet, and the cross-machine state leg
(x86_64 → arm64) has not been run for it.

### Neo Geo (fbneo) — rollback on RetroXR's fork, 2026-09-22

Stock fbneo (v1.0.0.03 GIT6bb3167) cannot roll back; our fork can. The fork is
`~/libretro-cores-retroxr/FBNeo`, branch `retroxr`, from libretro/FBNeo at 6bb3167
(**local only — not yet published**, so there is no `CoreSources` row and players
still download stock). `NetplayCores["fbneo"]` has `rollback_needs_pins`: a session
rolls back only when the installed build declares `fbneo-netplay-deterministic`
(the fork declares it at `retro_set_environment` so `CoreOptionsStore.peek` sees
it); a stock build gets lockstep.

**The oracle is the WHOLE savestate, hashed every frame** (`netplay_spike
--spike-crc-state --spike-crc-interval=1`). The RAM CRC hid all of this: the
68K RAM agreed while the sound chip had already split, and a rollback run's RAM
CRCs "healed" after diverging. `FBNEO_STATE_TRACE=<n>` (fork, env) logs a CRC of
every named state area on each serialize whose frame is a multiple of n — diff
two runs to name the area.

What was wrong, in the order it was found:
- **ROM path needs backslashes on Windows** (fbneo splits the directory on `\`;
  `Z:/…` searches `.\mslug.zip`). Not a fork change — worth checking the app's path.
- **Host-seeded state:** the MVS uPD4990A clock is seeded from the host's local
  time and `BurnRandomInit` from `time(NULL)`, so peers differed from frame 1;
  and `<set>.fs` (MVS NVRAM) from the last run changes the next boot. Fork option
  `fbneo-netplay-deterministic` sets `kNetGame` before the driver starts (fixed
  2018-06-01 clock, fixed seed, hiscores off) and `TweakScanFlags` no longer
  clears it. The NVRAM file still differs per player — UNSOLVED for a cold start;
  the session's state transfer carries NVRAM (it is in the savestate).
- **The option never arrived:** libretro-godot dropped a value for a key the core
  had not declared yet, and fbneo declares its options inside `retro_load_game`.
  `OptionsHandler` now keeps every frontend value and lays it back on after each
  declaration (`ReapplyFrontendValues`).
- **YM2610 savestate** (`burn/snd/fm.c`, `burn_ym2610.cpp`, `ymdeltat.c`):
  postload rebuilt ADPCM-A start/end from REGS and an unsaved `adpcmTL` (the fix
  dink made for the YM2608 in 2022, never applied to the 2610); Delta-T
  `now_data` re-read from ROM over its saved value; `eg_cnt`/`eg_timer`/`lfo_cnt`
  not saved (the YM2203 saves them); `nFractionalPosition` (resampler) not saved,
  so a frame after a load rendered a different number of chip samples.
- **`YM2610ResetChip` left REGS stale** — it writes zeros to the chip, not to
  REGS, and postload rebuilds every operator from REGS. KOF '98 resets its sound
  driver when a game starts; a rewind across that brought the old TLs back.

Measured with the final fork, Windows x86_64: Metal Slug, KOF '98 and Garou each
equal to lockstep **on the full state at all 1800 frames**, lag 3 and 6 (~163
rollbacks); two cold starts identical; reload 0/1200. The stock DLL under the
same oracle: reload 1200/1200 mismatched, rollback 1800/1800. The fceumm control
passes both. `netplay_tests` `rollback` group covers the pin gate (mutation-tested).

**Owed:** a real two-machine session; the Android build and a Quest run; the
x86_64 → arm64 state leg; publishing the fork (repo, release workflow, tag,
`CoreSources` row). The four fork fixes to the sound chip are upstreamable.

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
