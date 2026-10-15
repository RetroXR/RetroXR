# The PlayStation 2's i.LINK — a cable and a six-port hub

## The core half

Our PS2 fork (`github.com/RetroXR/ps2`, branch `retroxr`, release
`retroxr-pcsx2-libretro-v2`, `pcsx2/FW.cpp`) models the
console's i.LINK controller. Each console attaches ONE link port, index 0, protocol
`ps2-ilink-1394`, at the IOP's 36.864 MHz, behind the core option `pcsx2_ilink`
(default on, restart to change). It is a real IEEE 1394 bus, not a pair: every console
on the wire is a node, bus index is the PHY id, the highest is root, up to 64 nodes.

Verified by the fork: two consoles on Time Crisis II and Gran Turismo 3, and **six** on
GT3's i.LINK Battle (all six get Console IDs, two race, four show trackside views).
Consoles sharing one NVRAM get distinct EUI-64s because each salts its i.LINK ID with
the handle the frontend gave it. Savestates carry the controller (`iLink` block); the
cable itself is not saved. `LRPS2_ILINK_LOG=1` logs bus resets, self-IDs and every
packet; `LRPS2_FW_LOG=1` every register access.

## The room half

| class | what it is |
|---|---|
| `ILinkPlug` | an `RcaPlug` in group `ilink_plug`, **and** in `LinkPlug.ANY_GROUP` |
| `ILinkPort` | a `PsxLinkPort` taking `ilink_plug`; `get_hub()` beside `get_machine()` |
| `ILinkCable` | a `PsxLinkCable` (`ilink_cable.tscn`, 1.8 m, black 4-pin ends) |
| `ILinkHub` | a pickable box with six `ILinkPort`s (`ilink_hub.tscn`) |
| `ILinkBus` | the static resolver every lead defers to |

A PS2 wears the socket because `SystemInfo/ps2.tres` sets `serial_port`, and
`RetroSystemModelDefault.build_serial_port` picks `ilink_port.tscn` for `ps2` — on the
back panel beside the A/V row, where every stand-in console puts its link socket. The
spawn menu offers both the lead and the hub under the PlayStation 2 (and in the
generic list). Saves: the lead is a `LEAD_SCENES` row, the hub a pose-only
`PLAIN_SCENES` row; a lead records its own seat as the hub plus `Port1`..`Port6`,
which works because the hub answers `on_av_topology_changed` (a no-op, `RfSwitch`'s
trick) so `RcaPort.get_device()` finds it.

**No lead decides its own bus.** `ILinkBus.settle` walks every lead in the
`ilink_cable` group, unions each lead's two ends (console or hub), and calls
`LinkConnectGroup` once per connected set with two or more consoles, ordered by
`LinkCable.stable_key` so every netplay peer names the same bus head. Two hubs joined
by a lead are one bus. Stale buses are parted FIRST and only their orphans are
disconnected: `ConnectGroup` takes a listed port off its old bus by itself, so parting
a console that is moving would be a second reset for nothing, and parting it after the
join would undo it.

A lead's `linked_machines()` is the WHOLE bus, not its two ends, and its plugs are in
`any_link_plug`, so `RetroSystem.net_link_bus()` sees a hub's far consoles. The PS1,
Saturn and Jaguar plugs are NOT in that group; their sweep only finds a machine's own
lead. (pcsx2 is not in `NetplayCores` today, so no session covers a PS2 yet; the lead
still routes every join and part through `netplay_took_bus`.)

A seated plug's nose sits inside the hub's shell and a seated plug is kinematic, so the
hub adds a collision exception for whatever a socket picks up — exactly what
`RetroSystem` does for its own sockets — or plugging in shoves the hub off the table.

## The one behaviour a hub makes easy to hit

GT3's driver (Polyphony's PDI1394.IRX over Sony's ILINK.IRX) only learns who is on the
bus from a bus reset that arrives AFTER it has started. Every join and part is a reset
for everyone on the wire, and a console switching back on re-states its whole bus after
`ILinkBus.RESTATE_COOLDOWN` physics frames (the same as the PlayStation lead's re-state).
What is left is a console cabled before it booted that then never sees another plug
move: it sits on its Console ID screen. Replugging any lead on that bus fixes it.

The hub is unpowered, which a real one is not (the PS2's 4-pin port carries no bus
power). Deliberately: a hub that stays dark until a player finds its brick looks broken.

## Tests

`link_tests` covers the plug gating both ways, the spawn and save rows, the PS2's socket
(and that a PlayStation has none), the hub's six sockets, their facing (measured in the
hub's frame: authored inside out, the step is negative), a seated shell standing
outside the box with its collision exception made and undone, a three-console bus
through one hub found from every lead and from `net_link_bus()`, a pulled spoke, a hub
left with one console, two chained hubs and a plain console-to-console pair beside them.
All with real `system.tscn` consoles and real socket seating; no core, so the bus is
checked through `ILinkBus`'s bookkeeping rather than peer counts.

## Three screens, verified through the room (2026-09-22)

`Tools/link/gt3_ilink_hub_probe.tscn` + `gt3_three_screen.txt` run three real pcsx2
consoles on Gran Turismo 3 A-spec (USA) v1.10, cabled through a real `ILinkHub` with
real `ILinkCable`s, and drive the jamesfmackenzie.com three-screen set-up
(Arcade → i.LINK Battle → **Broadcast** on every console). Windowed, ~6 min a run.

What it showed, every run:

- All three report 3 peers from boot, and their frame counters lock together (the
  180-frame stagger collapses to ~30) once GT3's i.LINK driver is up.
- Entering i.LINK Battle, one or two consoles get bounced back to the Arcade menu —
  which one varies run to run. Pressing CROSS again and then **replugging that
  console's lead at the hub** gets it in. After that all three hold Console IDs
  (L 3, C 2, R 1 here) on the "Compete | Broadcast" screen. The probe does this
  reactively (`reenter`: a blue Arcade frame means bounced).
- **Broadcast is the default choice**, highlighted brighter; RIGHT moves to Compete.
  (All three on Compete also works: one race, three players.)
- With all three on Broadcast, IDs 2 and 3 go to "Waiting..." and **Console ID 1 is
  the control unit**: it picks the track, car and settings and drives with the full
  HUD. IDs 2 and 3 show the same race, in step, without a HUD, as its left and right
  views: ordered **ID 2 | ID 1 | ID 3** the three frames form one continuous
  panorama.
- Which physical console gets ID 1 is decided by the bus, not by where it stands —
  the right-hand one here. The article hit the same thing and swapped monitor cables;
  in the room, move the televisions (or the consoles' leads).

Things the run needed that a player will also meet:

- **The BIOS first-run wizard.** RetroXR pins `pcsx2_fastboot = disabled` (boot through
  the BIOS) unless the BIOS-boot override is on, so a PS2 with blank NVRAM stops on
  User Preferences (language, time zone ...). Once walked, the `.nvm` beside the BIOS
  remembers it for every console.
- **A post-driver bus reset**, as above: replug a lead once everyone is in i.LINK
  Battle.

## The sound of three consoles (2026-10-03)

Three cabled consoles crackled in Broadcast. Three UNCABLED consoles racing a full
six-car field each did not, so it was never the load of three PS2s. Two faults, one
in the core and one in the frontend, and they needed different measurements to see.

**The core ran one console at a time.** A console is granted its next stretch once
every other console's promise ("I originate nothing before this tick") reaches the end
of it. v1 asked for a stretch as long as the promise, half a millisecond, which only
holds for a console standing at or behind every other, and no two stand on the same
tick. So they took strict turns. `FW_GRAIN_LINKED` is now half of `FW_AHEAD_LINKED`:
the stretch is 0.25 ms, the promise still 0.5 ms, and the slack lets them run
together. Nothing crosses the wire later than it did. Cabled, GT3 three-screen, same
script, `XENU_UNTHROTTLED=1`:

| core | mean fps | worst second | not parked on the bus (L/C/R, racing) |
|---|---|---|---|
| v1 release | 100 | **42** | 57% / 20% / 20% (adds up to one console) |
| step = promise / 2 | 162 | 126 | 84% / 33% / 34% |

42 fps is the crackle: under 60 nothing the frontend does can keep three sinks fed,
and v1 went under in the menus, not the race. Released as
`retroxr-pcsx2-libretro-v2` (fork commit `2b1bd7fa0`), which `CoreSources` names; the
published Windows binary measured 163 mean and 108 worst on the same run. (A local
build is `cmake -S . -B build -G Ninja` in an MSVC shell, three minutes.)

**The frontend braked each console on its own sink.** The audio brake holds a core
while its sink is over target. Cabled consoles advance together, and each one's EE
stops at its own vsync until its frontend calls `retro_run`, so a console asleep on a
full sink held the other two still while THEIR sinks drained, three times a frame.
A `retro_run` that should take a few ms took 25-35, and every sink sat 10 ms lower
than an uncabled console's. A machine on a bus now brakes on the neediest sink on the
wire (`AudioHandler::MsUntilBusWantsFrames`, `SinkClock`, `LinkCoordinator::BusSinkClocks`),
giving way only while it holds less than twice its target. This is every link bus,
not just this one; only i.LINK has been measured.

Paced, cabled, 9000 frames, mixer underruns after boot / sink floor..ceiling:

| | underruns | sink, ms |
|---|---|---|
| v1 core, own-sink brake (two runs) | 416, 550 | 17-24 .. 47-56 |
| three uncabled consoles (the control, before and after) | 18, 0 | 25-35 .. 62-70 |
| new core, bus brake | 28 | 29-37 .. 61-71 |

The 28 are one second of track loading where a `retro_run` took 40 ms. That hitch is
the core's and an uncabled console has it too; cabled, all three share it.

How to measure it again, and what misled:

- `gt3_ilink_hub_probe --audio` prints each console's fps, sink floor..ceiling, the
  mixer's underruns, and where its second went: in `retro_run`, asleep on the brake,
  parked on the bus (`Libretro.GetPacingStats`, `Libretro.LinkCost`). `--nocable` with
  `gt3_three_solo.txt` is the control leg.
- **A paced run cannot show a throughput fault.** It reads 60 fps with twice the host
  to spare and 60 with nothing. `XENU_UNTHROTTLED=1` drops the brake and the ceiling;
  the fps is then what the group can do. The paced runs with the new core looked no
  better than v1's, second for second, and the core change was nearly written off.
- `parked` needs `XENU_LINK_WAIT_DIAGNOSTICS=1`. The timing used to be compiled in only
  without `NDEBUG`, and godot-cpp defines `NDEBUG` for `template_debug` too, so no
  build anyone loaded had it.
- A probe's consoles are SILENT unless it calls `SetAudioPlaying(true)`: nothing there
  is wired to a set. The first `--audio` run measured empty sinks and 1128 underruns a
  second, all of them the silence the rule intends.
- Three PS2s commit a lot of memory. One run hit the host's commit limit mid-race
  (`Parameter "mem" is null` in the log), a console stalled for 6.3 s, and the run
  read as the fix making things worse. Check for that line before believing a run.

Not re-verified with the shorter stretch: six consoles, and Time Crisis II (no image
here). The promise is unchanged, which is what both were verified against.

One fix came out of the first run: `RetroSystem.net_refresh_link_cables()` rejoins every lead
touching a console after its core starts or stops, and on a hub that is every spoke
of one bus — three part/join pairs, six resets, per power switch. `ILinkBus.rejoin`
now rejoins a bus once per frame however many leads ask (`link_tests` counts it).

## Switched on one after the other (2026-10-15)

Two consoles on one lead, one switched on while the other was off: when the second
came on, the FIRST froze -- at 10 fps for about 19 s on Time Crisis II, and for good
whenever the second never starts an i.LINK driver (BIOS browser, a game without one).
Every core release had it; the old v3 froze identically.

`LinkCoordinator` holds every member of a wire at the instant a newcomer joined until
the newcomer first calls `advance` (`CeilingLocked`: an attached peer that has not
published bounds the others at their origin). The core attaches at load, but met the
cable only from its IOP event, which the boot's `psxReset` wiped and nothing re-armed
until the game's driver touched the controller. Fork commit `3093f618f`: `psxHwReset`
ends in `FWiopReset`, so a console on a cable meets it from power-on. The frontend's
rule is unchanged and right; any other core that attaches before its guest drives the
port has to publish from attach for the same reason.

`Tools/link/ilink_power_on_probe` (windowed, scratch home with `probe_home.txt`,
`--rom=`, `--rom2=` for B, `--delay=`, `--out=` for a line-flushed log, a watchdog
for a stuck main thread) is the check: unfixed core with B on Ace Combat 04, A parks
at 10 fps for the whole run; fixed, both 60. It flags FROZEN only for a console with
no frames for 5 s, which a parked one is not (it keeps ~10): read the fps.

## The heavy scenes took turns (2026-10-15)

Time Crisis II linked fell from 60 to 36 fps where the second area starts and stayed
there, the sound broken up. Even after v2, the consoles took turns in heavy scenes. A
PS2 does a frame's work in a burst after vsync and spins out the rest almost for free;
two consoles switched on apart have their vsyncs anywhere against each other
(measured 50% and 91% of a frame in), so one's burst runs while the other spins to the
edge of its 0.25 ms stretch and waits. With ~15 ms of work a frame each that is 30 ms
a frame. MTVU (`pcsx2_mtvu`, off by default on x86) trimmed the work ~10% and changed
nothing else.

Fork commit `a04020112`: after every anchor a console measures where its next frame
starts on the cable (`FWvsync`, from `VSyncStart`) and skips its controller's clock on
by the rest of a frame (`fw_skip`), carrying its own timers with it. The skip is asked
for and granted like any stretch. Same spot, two consoles, MTVU on, worst ten seconds:

| | fps | parked | own work a frame | packet latency |
|---|---|---|---|---|
| promise 0.5 ms, unaligned | 36-38 | ~43% | 15 ms | 0.5 ms |
| `LRPS2_ILINK_AHEAD_US=8000` | 51-53 | ~27% | 13-15 ms | 8 ms |
| promise 0.5 ms, aligned | 48, then 58-60 within ~40 s | <10% | 19 ms | 0.5 ms |

Aligned, nothing waits and nothing crosses later; what is left is the host doing two
heavy frames at once (own work rising 14 -> 19 ms on a laptop Ryzen AI 9 465 that also
draws the room uncapped). `LRPS2_ILINK_ALIGN=0` is the control leg (logs the phase,
moves nothing), `LRPS2_ILINK_PHASE=1` logs it every 600 frames -- its readings drift by
a few thousand ticks because it divides by the last frame interval, so only the first
few hundred frames after a skip say much.

How it was measured, and what to reach for next time:
- `XENU_PACE_TRACE=1` (`performance.md`) with `XENU_LINK_WAIT_DIAGNOSTICS=1` in the
  room, played by a person: per console and second, fps, `retro_run`, brake sleep and
  parked time. Own work a frame is (run - parked) / fps; when fps follows
  1000 / (sum of the consoles' own work), they are taking turns.
- A game launched from the editor inherits the EDITOR's environment, so the switches go
  on a game started from a shell. Claude Code's background-shell memory sweep killed
  one such session; `cmd /c start` detaches it.
- Released as `retroxr-pcsx2-libretro-v4` (fork merge `bb21ba39e`: libretro/ps2 master
  to 3660a1fe8 with both commits on top), which `CoreSources` names. The merge took
  upstream's Vulkan heap ceiling in place of v3's budget, moved the i.LINK save block
  onto upstream's C savestate (`SaveStateFreeze.c`, `SaveState_PeekTag`), and kept the
  fork's `PlaceMainAndCode` over upstream's `AllocateNearModule`, which wants main memory
  AND the code cache near each image -- more than six images side by side can all
  have. `ilink_power_on_probe --state=<s>` saves and reloads A on a live cable. Upstream
  also changed pacing (one frame per `retro_run`, input of the presenting `retro_run`),
  so the heavy spot is OWED a re-measure on v4. GT3, three or more consoles and the
  other platforms are unmeasured with alignment; two early probe runs of it died
  silently as B started and every run since has not.
