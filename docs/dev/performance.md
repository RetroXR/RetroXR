# Screen rendering and frame-transfer profiling

The fast CRT tier now covers ordinary TVs, packed/stereo screen windows, VHS
and analog static. QualityManager.crt_fast selects it (the mobile default);
desktop retains the full tier. Source signal code is shared by both variants,
including VHS effects, packed regions, stereo selection and OSD. The fast tier
uses unshaded glass, an opaque alpha-scissor corner and the existing mobile
mask/beam stage. Packed windows use four clamped minification taps rather than
nine; no tap may sample an adjacent packed screen.

## A tube is drawn from its front only

All eight shaders a set can wear on its glass (crt_effect, screen_window,
vcr_effect, tv_static and their _mobile twins) are cull_back. They were
cull_disabled until 2026-10-14, and a deep tube showed its picture from behind:
standing at the side of the Panasonic CT-20D10B (xenu.panasonic, a 24.9 mm
tube; the stock one bulges 9 mm), the far part of the picture lay over the near
part.

The full tier blends its rounded glass edge (ALPHA), which puts the screen in
the transparent pass. Nothing there writes depth, and one mesh's triangles are
drawn in index order. Past the angle at which the far edge of the tube turns
away (about 76 degrees off axis on that tube) its back faces were painted
straight over the near half's front faces. It shows from ONE side only, the
side whose far triangles come later in the index buffer, and over part of the
height only. The fast tier is opaque, so depth hid it there except through a
scissored corner.

A tube bulges toward the viewer, so its front faces never overlap one another:
with the back ones culled there is nothing left to sort, and no depth prepass
is needed. A new stage shader has to cull back too. av_tests "display/a tube is
drawn from its front only" holds the eight to it. A cabinet's own tube mesh has
to be wound facing out, or it is now not drawn at all.

Tools/av/tv_side_view_probe (windowed) is how it looks and the check that can
fail: --picture=quarters photographs four colour bands from steep angles on
both sides and fails when a row meets them out of order or skips one. Restoring
cull_disabled fails it at -88, +86 and +88 with 11 to 95 rows out of order, on
crt_effect, screen_window and vcr_effect alike. Four things it had to learn:

- Two bands cannot show the fault. The far half lands beside what can be seen
  of itself and reads as one run. It takes the far QUARTER over the middle.
- A skipped band is the fault too: the blue left after the yellow is one pixel
  wide at 86 degrees.
- The tape's tracking line drags one row sideways, a different row each frame.
  The VCR leg runs with effect_amount 0.
- The stock cabinet's bezel caps are green, blue and yellow and stand in front
  of the bottom of the tube from the side. The checking leg hides them. A deep
  bezel (crt_plain) hides the whole tube at 88 degrees, which is no fault.

screen_window is shared with the DS/3DS panels, the Virtual Boy's lens quads
and the VMU's LCD. Those are flat quads placed by code with +Z facing out; the
DS and 3DS were photographed with the culled shader and both panels still draw.

## Compare shaders

Stage the isolated project as described in Tools/crt_bench/README.md. Run
with --visual for appearance comparisons, --visual --pair=reference,current
for the strict identity check, or --contracts for packed-screen isolation and
OSD assertions. The mobile/full comparison differs by design and is not a
pass/fail appearance test. Inspect the saved images.

Pass --wrapper=screen_window, --wrapper=vcr_effect or --wrapper=tv_static
for the repeated GPU timing experiment. Results are timings_<wrapper>.json.
Metadata identifies mono desktop versus stereo OpenXR; desktop results do not
predict Quest timings. Run GPU experiments sequentially without another game
or GPU capture running.

## Native transfer counters

Rebuild libretro-godot. SetVideoTransferProfiling(true) enables per-instance
counters; GetVideoTransferStats() returns cumulative calls, total_ms and
max_ms per stage. SetVideoTransferProfiling(false) stops collection. No clocks
or log formatting run on the normal disabled path. Snapshots are approximate
while an emulation-thread sample is finishing; use multi-second windows.

| Stage | Meaning | Thread |
|---|---|---|
| readback_total | Vulkan ReadbackToPixels CPU wall time, including synchronization and early returns | Emulation |
| readback_wait | Fence waits inside readback_total, including the previous submission | Emulation |
| readback_copy | Mapping, allocating/copying/swizzling and unmapping inside readback_total | Emulation |
| texture_update | CPU Image update/flip and ImageTexture.update call for queued frame updates | Main |

Wait and copy are subsets of total; do not add them to total. Readback attempts
can include deliberately blank fields or failures; copy and texture-update
counts can be lower. texture_update is CPU API time, not GPU upload completion,
and excludes initial texture creation. These counters do not time retro_run or
the room renderer. They accumulate over the VideoHandler lifetime.

For a room capture, place this one-shot JSON in user://vrsprobe.cfg (or the
Quest external files path documented in quality_manager.gd):

~~~json
{"after": 400, "profile_transfers": true, "report": 72}
~~~

[VRSProbe] transfer lines report interval averages per readback attempt and
per main-thread texture update, alongside viewport GPU/CPU measurements. New
Libretro nodes join automatically. The first interval establishes a baseline.
The config is consumed and no graphics preference is saved.

Tools/perf/video_transfer_probe.tscn measures a single real core with
--root=<isolated core root> --core=<name> --rom=<path> [--warmup=5] [--seconds=15].
The supplied root must contain cores/ and any required system/ firmware. Copy
core options and firmware into scratch storage first: cores write settings
and saves into this root. The probe prints a JSON result and fails if content
fails to load or no texture updates occur. It requires a GPU and real content
and therefore belongs in Tools, not Tests.

## Desktop measurements, 2026-10-12

Godot 4.7.2, NVIDIA RTX 5070 Laptop GPU, Mobile renderer, mono 512x512,
nine screens at one metre, 2x MSAA. Each result is the median of three run
medians (AB, BA, AB), with 30 warmup and 120 sampled frames per run.

| Stage | Full GPU ms | Fast GPU ms | Reduction |
|---|---:|---:|---:|
| Packed window | 0.034 | 0.024 | 29% |
| VHS | 0.031 | 0.025 | 19% |
| Static | 0.029 | 0.023 | 21% |

These are tiny isolated desktop workloads, not whole-room FPS gains or
Quest results. The full 600-sample/multiple-distance run exceeded its time
limit; only completed --quick runs are reported here. Raw samples and GPU
metadata: [desktop-fast-stages.json](../../Tools/crt_bench/results/2026-10-12-desktop-fast-stages.json).

A sequential PCSX2 Vulkan capture (Ace Combat 04, five-second warmup,
15 seconds measured) recorded 899 readback attempts and 472 copied/uploaded
frames. Mean CPU wall times: readback 0.552 ms per attempt, fence waits
0.475 ms per attempt, mapping/copy 0.054 ms per copied frame, and texture
update 0.186 ms per upload. Fence waits dominate the measured readback
path. The thread and subset caveats above apply; no zero-copy change was
made. Player core settings and saves were isolated in temporary storage.

Validation: both Windows extension targets built; native counter and pixel
swizzle tests passed; the AV suite passed 370 checks; full/reference images
were identical in all 209 cases; packed-region and OSD GPU assertions passed
1,350 checks. Removing packed-region bounds deliberately failed eight
checks. Fast/full images differ by design: the fast tier omits full glass,
grain and glow. A four-second full/fast animation was also inspected.

## Pacing trace in the room

`XENU_PACE_TRACE=1` in the environment adds `Scripts/Objects/systems/pace_trace.gd`
(via `QualityManager`) and prints a `[PaceTrace]` line a second, also written
line-flushed to `user://logs/pace_trace.log` so it can be read while the session runs:
the room's fps, main-thread process ms and mixer underruns, then per running machine
its fps, ms inside `retro_run` (and the worst call), ms asleep on the audio brake, ms
parked on a link bus (`XENU_LINK_WAIT_DIAGNOSTICS=1`, else 0), link advance calls and
how many parked, peers, and the front voice's queue floor..ceiling. A machine that is
slow runs long and parks little; one waiting on another parks for most of it. Off,
nothing is added. `ps2-ilink.md` has the worked example.

## Desktop frame rate cap

GRAPHICS > DISPLAY > Frame Rate Cap (desktop only; Off, 30-144) is
`QualityManager.frame_cap`, saved in `graphics_prefs.json` and applied as
`Engine.max_fps` when the menu restores the desktop window. A headset always runs
uncapped (`apply_frame_cap` checks OpenXR itself: naming `MenuStyle` from that
autoload made a class cycle that broke 13 suites). The desktop room otherwise draws
at the panel's refresh, about 100-120 fps on the laptop in `ps2-ilink.md`, on the same
fast cores the consoles need; what a cap buys them there is not yet measured.
`spawn_menu_tests --only=frame_cap`.


## Arcade cabinets (2026-10-20)

Reported: four cabinets spawned lag a lot, and one game (Cadillacs) played for minutes lags at the first
boss. `Tools/perf/arcade_scale_probe` (cost of N cabinets, scenes only or with a core running) and
`arcade_soak_probe` (one run of minutes, one CSV row every 5 s, and which series GROW) measure it;
`run_arcade_matrix.py` runs the first over a matrix, one Godot process per row (never loop cores in a
process), repeated and interleaved, and prints the table. `arcade_mesh_census` lists every mesh of a
cabinet with its triangles and shadow mode. `arcade_perf_common.gd` is the shared stage and readings.

```bash
# on a shell whose libc is older than the extensions' (a flatpak VS Code) add --wrap "flatpak-spawn --host"
python RetroXR/Tools/perf/run_arcade_matrix.py --godot "$godot" --rom ~/retroxr/roms/mame/dino.zip \
    --phase all --repeat 2 --out /tmp/arcade_matrix          # `--phase scene|core`, `--quick`, `--only=`
"$godot" --path RetroXR --display-driver x11 --disable-vsync --resolution 640x360 \
    res://Tools/perf/arcade_soak_probe.tscn -- --core=fbneo --n=4 --minutes=12 --rom=<dino.zip> --shots=<dir>
```

**What a number means here (each cost a wrong conclusion once):**
- **The window's own GPU time is mostly the wait for the compositor** (about half the frame whatever the scene
  held), so the scene is drawn in a SubViewport and ITS time is read. And **a window is paced by the compositor** whatever
  `--disable-vsync` says (60, sometimes 120 fps): read `main cpu ms/frame` (main-thread CPU from `/proc`,
  per frame) and the GPU cost, not fps. fps is a symptom.
- **On a laptop the integrated GPU's clock is not a constant, and it is what moves.** The same scene read 12 ms
  and 80 ms of GPU depending on what the CPU was doing. Every window therefore records the GPU clock
  (`gt_act_freq_mhz`), the package temperature, the CPU clock and how many cores the REST of the machine was using
  (`other cores busy`); `gpu_mcycles` is GPU ms x MHz, which is comparable across windows. Compare rows only at
  the same `other cores busy` (about 0.4-0.6), and repeat. **A transcoder running beside the first matrix, and a
  probe that hung in teardown and kept drawing, both made fps read 10-115 in one family of rows**; the runner now
  reaps stray probes. Never `pkill -f` a pattern that is also in your own command line: it kills the shell.
- A paced core always reads 60 fps; **`XENU_UNTHROTTLED=1`** (the `unthrottled` rows) shows what it costs.
- A soak player that attaches the panel TOGGLES it (a second press lets go and nobody plays), and a coin close to
  START is the chord that opens Cadillacs' I/O TEST screen; the first 10-minute run sat in it for nine.

**Measured** (Iris Xe laptop, 1280x720 viewport, a stage with a directional and four omni lights casting shadows,
FBNeo and MAME running Cadillacs; `other cores busy` 0.4-0.6; 2 repeats):

| | scene only (door shut) | FBNeo running | MAME running |
|---|---|---|---|
| 1 cabinet, main-thread CPU ms/frame | 3.2 (0 cabinets: 1.8) | 4.2 | 4.2 |
| 4 cabinets, main-thread CPU ms/frame | 3.9 | 6.0 | 6.9 |
| 4 cabinets, process cores busy | 0.47 | 0.82 | 1.08 |
| `retro_run` ms/frame per core (60 fps) | - | 1.3 | 2.2 |
| core cost flat out, 1 core: fps | - | ~1000 | ~570 |
| draw calls / triangles, 4 cabinets | 261 / 233k | 588 / 378k | 590 / 378k |
| RSS, 4 cabinets | 786 MB | 1.19 GB | 2.05 GB |

- **A cabinet is cheap; the machine is what throttles.** About 0.5 ms of main-thread CPU a cabinet idle and about 0.6 running,
  0.3 M GPU cycles; a core 1.3 ms (FBNeo) or 2.2 ms (MAME) of a 16.7 ms frame; texture upload 0.1 ms a frame. What lags
  is the package: the integrated GPU ran 460 MHz with one cabinet, 320-440 with four and **100 MHz when the four cores ran flat
  out (4.4 cores busy)**, at 70-80 C with the CPU at 1.3-2.2 GHz, so anything that burns CPU also slows the GPU
  and frames that the GPU cannot finish are what the player sees as lag. `cast_shadow` off on every mesh changed the GPU cost
  by under 1 ms (the shadow RECEIVERS, the lit floor and the lit panels, are the fragment cost, not the cabinets' casters).
- **Nothing grows.** 12 minutes with four cabinets (the screenshots show a street, a green screen, a dark scene and, from about
  minute 9, the I/O TEST screen again: the scripted player is not a faithful one, and what ends it there was not found), and 4 minutes
  of one cabinet played in the street: nodes, objects, resources, orphans, static
  memory and RSS flat, `retro_run` flat (1.05-1.3 ms; worst call under 27 ms), the core logs 0.04 KB/s. The dips
  (fps 24-30 for two minutes) lined up with `other cores busy` rising to 1.2-1.8 and the GPU clock falling to 220-360 MHz.
  **The lag at the first boss is NOT reproduced**: the scripted player never gets past the first street (it holds RIGHT and
  mashes attack and does not fight), so a boss screen with its extra sprites and QSound voices has not been measured; what
  the run shows is that nothing in the room or the bridge degrades with time, and that a hot, power-limited machine
  (70-72 C from the first minute here) is the likely cause. To check in the room: `XENU_PACE_TRACE=1` and read
  `user://logs/pace_trace.log` through the boss (`run` per machine and the room's `proc` ms), and
  `cat /sys/class/drm/card*/gt_act_freq_mhz` beside it.
- **MAME vs FinalBurn Neo:** MAME costs 1.7x the CPU per core (2.2 vs 1.3 ms), 0.86 GB more RAM for four cabinets (2.05 vs 1.19 GB), and a 4-cabinet room
  at 1.08 cores vs 0.82 slowed the GPU clock from 437 to 324 MHz. MAME also refuses `dino` without `qsound.zip` BESIDE the
  romset (the probe's scratch folder holds a copy; the player's `roms/mame/` does not). The user's `core_defaults.json` maps
  `arcade` to MAME and the shipped default is FinalBurn Neo.

**Kept** (each by an A/B on the same machine, alternating the old and new code; the gains are small, 3-5%, which is
what a cabinet's own scripts are worth here):
- `ArcadeControlModule.show_state` and the stick settle: a panel redrew its seven caps and its stick every frame for ever (a
  `position =` dirties the transform and goes to the renderer even when it holds the value); it now draws when the mask changes, and the lerp snaps and stops.
- `ArcadeInput._send`: the core is told an input once (`_heard_mask`/`_heard_axes`), cleared when the machine is off.
- `ArcadeShadowBudget`: parts under 10 cm cast no shadow (cabinet, bay and board: 71 of 134 shadow draws per light a
  cabinet); the shell, deck and door keep theirs. Four cabinets with every light casting: draws 261 -> 186, triangles 233k -> 113k; the picture does not change, and the GPU
  time on this machine does not measurably either (the A/B read 7.6 -> 7.4 M cycles, inside the noise). It is a Quest-shaped saving, OWED there.

**Tried, not kept:** telling the core nothing shows its picture (`GET_AUDIO_VIDEO_ENABLE` without VIDEO, and dropping any frame it still
hands over): FBNeo `retro_run` 0.99 -> 0.78 ms (-21%), MAME 1.77 -> 1.62 (-8%), the upload to zero, main thread 7.5 -> 6.7 ms.
That is 0.2 ms a cabinet out of view on desktop; it needs a visibility test in the room (`VisibleOnScreenNotifier3D` in a headset is
unproven here) and a rebuild for windows AND android, so the extension change was dropped. What it would take: `Wrapper::SetVideoMuted`
(an atomic), `GetAudioVideoEnable` answering without `RETRO_AV_ENABLE_VIDEO`, `RefreshCallback` returning (after
`CompleteFrameWithoutReadback`) before it converts anything, `Libretro.SetVideoMuted`; `arcade_scale_probe --mute=video` measures it.

**A run writes the cores' saves** (`dino.hi`, `dino.nv` under `libretro/save/fbneo/fbneo/`): `run_arcade_matrix.py` snapshots and restores `core_options/` and the
save folders, the soak probe and ad-hoc runs do NOT, so take a copy of the folder first.

**OWED:** the Quest (4 cores plus the render thread compete there; the cores cost several times more per frame than on this laptop,
so core cost per cabinet and the muted-video idea matter more), a headset, a boss screen, and a second, unthrottled-by-heat
machine to see what the same scene costs when the GPU gets its clock.

## Whole-room profile with Tracy (Starlight Arcade autosave, 2026-11-04)

Reported: 50-60 fps on the RTX 5070 laptop. At 165 Hz with vsync a frame over 12.1 ms waits for
every third refresh (55 fps), and the room's main thread was ~12-14 ms on AC. The GPU was 3 ms.

**Measuring traps, each cost a wrong conclusion here:**
- `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` are the WORST value of the last second, not a mean
  (they read 35 ms in a 17 ms frame). Time frames yourself.
- Jolt reports 0 for `PHYSICS_3D_ACTIVE_OBJECTS`, `_COLLISION_PAIRS` and `_ISLAND_COUNT`.
- On battery the panel drops to 60 Hz and frames pin at 16.7 ms whatever runs: check `PowerOnline`
  (`root/wmi BatteryStatus`) before any timing.
- Switching one thing off at a time and comparing frame times has ~±2 ms of noise across launches and
  ~±0.5 ms within one: it inflated a 0.44 ms saving to "1.3 ms" once. A/B inside ONE process, alternate
  the legs, or use Tracy.

**Tracy recipe** (the engine's own `profiler=tracy`; every GDScript function and the main loop are zoned):
`git clone --depth 1 --branch v0.14.1 https://github.com/wolfpld/tracy ~/tools/tracy`, build
`capture/` and `csvexport/` with CMake, then in `~/godot`:
`~/.local/bin/scons platform=windows target=editor profiler=tracy profiler_path=<tracy> optimize=speed lto=none accesskit=no d3d12=no -j16`
(12 min). Run `tracy-capture -o room.tracy -f -s 75`, then the built editor binary with `--path RetroXR`
(do one warm-up launch first: the custom build recompiles its shader caches), then
`tracy-csvexport -u room.tracy` and analyse a steady window on the main thread by nesting (self time).
The traces are in `~/tools/traces/`.

**Per frame, 25 s steady, 1,391 frames:**

| | ms |
|---|---:|
| Jolt step (`3D physics`, 1.6 steps a frame) | 5.09 (3.2 a step) |
| physics callbacks (`physics_process`: grab drivers 0.46, player body 0.53, cables 0.19, ropes in the 0.67 self) | 2.46 |
| `process` (of which handhelds' `ControlPoke` polls via `handheld_input._local_state`: 1.6-1.9) | 4.69 |
| `RenderingServer::draw` (viewport render 3.34, `draw_graph.end` 1.69) | 5.57 |
| all GDScript functions, own time | 5.96 |

- **The Jolt step is the area monitoring**: all 431 monitoring areas off, 3.2 -> 0.49 ms a step. By group,
  the 151 `XRToolsSnapZone`s are -1.2 ms a step (~8 us each); everything else (109 VRButtons ~1.2 us each,
  ports, slots, hinges) is within noise one group at a time and makes up the rest together. Fixed below: an
  empty zone that snaps only DROPPED objects watches only while a hand holds something.
- 20 motionless rigid bodies never sleep, because the locked main `Table` (frozen KINEMATIC) never falls
  back asleep and Jolt keeps everything touching an active body awake. Measured cost: none.
- The 60 s autosave is a ~37 ms main-thread stall (snapshot 30 ms, encode 5.6 ms).
- Draws: 1,496 calls, 691k triangles; the 20 consoles are 712 of the calls.

**Fixed (2026-11-04), same room, Tracy, one process, the snap-zone rule A/B by its kill switch:**

| | before | after |
|---|---:|---:|
| frame (uncapped) | ~18 ms vsync-paced; 14.48 with only the snap rule off | **11.24 ms (88.8 fps)** |
| Jolt step | 3.2 ms a step | **0.46 ms a step** (269 -> 0 of 367 zones watching) |
| `ControlPoke.poll` (28 a frame) | 1.63 ms | 0.26 ms |
| autosave snapshot + encode | 36-38 ms | ~20 ms (byte-identical slot) |

- Snap zones (`snap_zone.gd`, the xr-tools fork): `_wants_monitoring()` -- an empty DROPPED-mode zone
  watches only while a pickable is held by anything but a zone (`note_hold`, called from
  `XRToolsPickable.pick_up` / every `dropped.emit` / `_exit_tree`); off again `IDLE_OFF_DELAY` (0.5 s)
  after the last hand lets go, because the drop is taken in deferred handlers and reported 0.1 s on.
  RANGE zones always watch; full zones stopped watching already. `idle_unmonitored` is the kill switch.
- `ControlPoke.poll` returns at once with no hand near and nothing held, after `SETTLE_FRAMES` (45) for a
  let-go cap to ease back (`control_poke_tests` `idle_stops` / `idle_wakes`).
- The snapshot no longer walks every object's subtree three times by class name: VRHinge, VRKnob and
  VRSlider join `ScenePersistence.CONTROL_GROUP` in `_init`, LightSwitch joins `SWITCH_GROUP` (WindowBlinds
  `BLINDS_GROUP` and TimeOfDay `CLOCK_GROUP` likewise, 2026-11-11: the slot's `"blinds"` {path, drop, tilt}
  and `"time_of_day"` {path, time} sections, `scene_tests --only=blinds`), and the
  snapshot files those lists in tree order (`is_greater_than`) so an object's list is what its own
  `find_children` gave. A whole-room `find_children` by class name was tried first and was SLOWER
  (8 ms a type: it checks every node's script). Ropes are an engine class and keep their walk.
  `scene_tests --only=descendants`.
- A locked object freezes STATIC (`ObjectLock`), its own mode restored on unlock: the locked table is no
  longer a woken kinematic body holding twenty objects awake (`scene_tests --only=lock`).

**Not done, and why:**
- 60 Hz physics on desktop: `QualityManager.apply_display_rate`'s note keeps the tick fixed for the rope
  solver (tuned and regression-tested at it; `rope_bench`/`rope_stress` are bit-exact oracles), and
  `_desktop` is true for PC VR too. With the step now 0.46 ms it would save ~0.5 ms, not 2.5.
- Rendering (now the largest part, ~5.2 ms of CPU): the main view's render is 3.2 ms and `draw_graph.end`
  1.6 ms; the 40 `render viewport` zones a frame are every ACTIVE viewport, opened before the skip
  check, not 40 renders. The lever is the 712 draw calls of the 20 consoles, which is model work.
- Grab drivers (99 a frame, 0.29 ms) and handheld input's own animation pass (0.9 ms incl.) are left.

**The separate render thread (2026-11-07, Windows only: `rendering/driver/threads/thread_model.windows=2`).**
Godot's default draws on the main thread after scripts and physics; with the SEPARATE model frame N is
drawn while frame N+1 runs, so a frame costs the slower half, not the sum. Measured in the Starlight Arcade
with the stock 4.7.2 binary and every fix above, vsync off, 20 s a run, `--render-thread safe|separate`
alternated, two runs each:

| | safe (main thread) | separate |
|---|---:|---:|
| frame, mean | 8.53 / 9.58 ms (117 / 104 fps) | **5.05 / 5.16 ms (198 / 194 fps)** |
| p95 / p99 | 12.2-12.3 / 14.1-15.0 ms | 8.7-8.8 / 10.2-10.5 ms |

- Godot marks the model EXPERIMENTAL ("several known bugs which can lead to crashing, especially when using
  particles or resizing the window"). Measured here: 40 resizes and 4 fullscreen toggles, three runs, no
  crash; all 104 suites pass on it; the room draws the same (safe vs separate differ on 0.28% of pixels,
  all on cables, the robot and the clock; two safe runs differ on 0.20%).
- **A readback stalled the main thread on the render thread** (fixed): `get_image()` on a viewport texture
  is a round trip that waits for the render thread (and, in either model, for the GPU), which
  `screen_cast_light.gd` did every `screen_light_interval` frames while a picture showed and
  `gb_camera_eye.gd` while it films. Both now go through **`AsyncTextureRead`**
  (`Scripts/Objects/async_texture_read.gd`): `RenderingServer.call_on_render_thread` +
  `RenderingDevice.texture_get_data_async`, the pixels back a frame or two later; with no RD (headless,
  Compatibility) or an unmapped format it reads synchronously as before. Measured with 17 of the probe's
  OWN `ScreenCastLight`s sampling, 20 s a run (`AsyncTextureRead.synchronous` is the A/B switch):

  | | async | blocking `get_image()` |
  |---|---:|---:|
  | separate | **4.14 / 4.58 ms** (242 / 219 fps), p99 8.2-8.8 | 13.09 / 11.69 ms (76 / 86 fps), p99 23-27 |
  | safe | 7.47 ms | 14.74 ms |

  The probe needs lights of its own: feeding the room's lights a picture does nothing, as each TV or
  handheld re-drives its light from its real screen every frame and an off set switches it back off
  (the first table's "17 lights sampling" row, since removed, measured no sampling at all).
- **Never hand the RenderingDevice a GDScript callable that can still be pending at quit.**
  `Main::cleanup` finishes the script languages BEFORE `finalize_display` flushes and frees the RD, so a
  lambda in a pending `texture_get_data_async` was called or freed with no GDScript left: a segfault on
  every quit with a read in flight (3 of 3; 0 of 3 blocking). `AsyncTextureRead` gives the RD only
  native callables (`Callable.create(Callable(owner, method).bind(w, h, fmt), "call_deferred")`); the
  owner takes `(data, width, height, format)` and calls `AsyncTextureRead.image_from()`. 3 of 3 clean
  with 5-9 reads in flight at quit.
- **Fixed in the ENGINE: quitting logged `This function (finalize) can only be called from the render
  thread` and leaked the RD's textures**, only in this model. Not Betsy: `RenderingServerDefault::
  _assign_mt_ids` makes the main RD current on the render thread, `finish()` never hands it back, and
  `DisplayServerWindows` frees the RD on the main thread, so `~RenderingDevice`'s `finalize()` fails its
  `ERR_RENDER_THREAD_GUARD` and returns early, leaking every RID it owns. `finish()` now calls
  `rd->make_current()` once the render thread has exited: `docs/godot-4.7.2-render-thread-rd-handback.patch`
  (in `~/godot`, not yet committed on `retroxr-4.7.2`). Verified with an editor build: no finalize error,
  no leak report; stock 4.7.2 still shows both. **Desktop ships the OFFICIAL templates**, so the stock
  error stays on Windows until upstream fixes it (exit only, harmless). The custom/Tracy build also
  exited 3 on `Thread::release_main_thread` (`!is_main_thread_assigned`), `--version` included: Tracy's
  static `s_profiler` touches a `thread_local` during CRT start-up, MSVC's `__dyn_tls_init` then runs
  EVERY thread-local initialiser, and `Thread::caller_id` took `id_counter.increment()` before
  `id_counter(1)` was dynamically initialised -- 0 + 1 = `MAIN_ID`, so `make_main_thread()` returned
  early without setting the flag (found with a stack dump and a `/MAP` link). Upstream fixed it on master
  (30b9a76d04, `SafeNumeric`/`SafeFlag` constant-initialised), never backported to 4.7: carried as
  `docs/godot-4.7.2-safe-numeric-constexpr.patch`. Any `profiler=tracy` Windows build needs it; the
  Quest's (no profiler) has no known trigger.
- `QualityManager` logs which thread draws (`rendering on a separate render thread` / `the main thread`),
  read from `RenderingServer.is_on_render_thread()`: ProjectSettings does not report the override.
- The Quest (Mobile renderer under OpenXR) and Linux/macOS are untouched; try them separately.

## Restoring a room (2026-11-10)

`Tools/perf/restore_perf_probe` replays a slot READ-ONLY, windowed (headless loads no shell threaded and draws
nothing, so it measures a different restore): each entry timed by type (its asset wait and its spawn), the
connection pass, then 120 frames. `--noprefetch` is the control for the prefetch, `--boot` starts the shell warm
alongside, `--twice` restores again once everything is cached (what is left is node building), `--roomload=` times
the room scene alone. **Copy the slot first and point `--file=` at the copy**; never run the real app against the
player's `user://` while another instance is up (its autosave writes the same slot). Run under the Tracy editor
build (recipe above) to see where a frame went: `tracy-csvexport -u`, then self time inside the long
`Main::iteration`s, stack-nested by interval.

Starlight Arcade autosave, 151 objects, desktop, stock 4.7.2, separate render thread. Runs vary by a few
seconds with other Godot instances on the machine:

| | before | after |
|---|---:|---:|
| pass 1 (spawn every object) | 15.1 s (6.8 spawn + 8.3 waiting on models) | 4.8-7.6 s (asset wait 5-700 ms) |
| first frame after | 0.67 s (the waits had drawn frames all along) | 1.3-1.6 s |
| restore to settled (pass 1 + connections + 120 frames) | 18.7 s | 8.2-10.9 s |
| everything cached (`--twice`) | 3.2 s | 2.1 s |

What it was, and what changed:
- **Models were loaded one entry at a time.** `_acquire_entry_assets` requested an entry's GLBs only when the loop
  reached it, so the loader threads idled between entries. `ScenePersistence.prefetch_assets` requests every
  entry's models up front, in restore order, and the loop's awaits find them done (`ModelWarmer.prefetch`). A
  system's model SCENE is in the list too (`SystemModelRegistry.packed_scene` load()ed 13 of them on the main
  thread, 1.06 s). A model row's `requires` names EVERY regional GLB (a Genesis waits for eight); with the
  prefetch they load side by side rather than in series.
- **Threaded loads are low-priority pool tasks**: `low_priority_thread_ratio` 0.3 of the pool, so ~6 loader threads
  on a 20-thread desktop and ONE on the Quest (`max_threads.android=4`, which is deliberate: the app is confined to
  three cores, commits `341ced9d` / `d33e46a8`). That is why the boot's shell warm now waits:
  `SceneManager._after_boot_room` holds `request_shells` + `warm_shells` until the boot room's content is ready
  (120 s cap). Started at once, it queued its 13 GLBs ahead of the restore's (FIFO) and built and drew each shell on
  the main thread under the curtain: 10-13 s and +1.4 GiB of texture beside this restore. Only a process that
  booted through `BootScene` waits; probes and suites warm as before.
- **Every pickable traced its outline at `_ready`**: `PickableHighlight` 1,372 smoothed-normal copies, each
  `surface_get_arrays` a round trip to a render thread busy uploading the room's textures (4.6 s under Tracy, the
  largest single cost). Overlays are now built with no mesh and traced the first time they SHOW (cached per mesh
  as before); `WidgetOutline.set_source` likewise traces on the first `sync(true)`. The first hover of a model not
  outlined before pays its trace then (a few ms; a big console's many meshes, more).
- **Every control walked the whole tree for the controllers**: `find_children("*", "XRController3D")` in each
  VRButton/VRKnob/VRSlider/VRHinge/PageGrab/pad `_ready`, 2.5 s for 230 buttons. `XrControllers.all(tree)` answers
  the same list and walks again only when a controller enters or leaves the tree.
- **`ModHooks` tested every added node against every watcher** (1.39 M `_matches` for 13,605 nodes, ~1.7 s).
  `_classes_of` works the answer out once per native class and per script; watcher changes drop the caches.
- `restore_speed_tests` holds each of these to the answers the slow way gave.

Left, measured, not done:
- Texture memory, +0.9-1.2 GiB by 120 frames after (`RENDER_TEXTURE_MEM_USED`), is NOT uncompressed mod
  textures. Counted (2026-11-11): the 444 imported `.ctex` the restore loads are ~405 MiB and all but one
  VRAM-compressed (BC7 234, BC5 normals 82, BC1 65 MiB; mod packs included), read from each file's header by
  `Tools/perf/texture_census.py` over a `--verbose` log; the textures made at run time are ~254 MiB
  (`restore_perf_probe --runtime-textures`), 175 of it the five books' pages, RGBA8 on desktop BY DESIGN (books.md:
  a Quest's pages are ETC2, and stock templates have no BC encoder); viewports ~60 MiB; labels ~16 MiB; the rest is
  the renderer's own (shadows, MSAA, reflections). Asset waste, FIXED 2026-11-11: `xenu.panasonic`'s LOD1 and
  LOD2 embedded the same images as LOD0 byte for byte, and Godot extracts a GLB's images per GLB, so the set
  loaded every map three times. 1.0.7 is built with RetroXR-models `build_mod.py`'s `share_images` (assets.json),
  which takes the staged GLBs' images out into files they all refer to: desktop textures in the pack 17 -> 7
  (34.6 -> 11.5 MB), the pack 6.8 -> 3.3 MB, every LOD rendered with the one decal texture. Any mod whose LODs
  repeat their images can list them the same way. `Textures/Media/rxr_disc_label.svg` (a texture only) imports
  VRAM Compressed, high quality: 1200^2 BC7 with mipmaps instead of 7.3 MiB lossless.
- What the uploads cost: the first frame after a synchronous restore is 3.3-3.6 s cold against 1.3-1.4 s with
  every texture already on the GPU (`--twice`, `SECOND first 10 frames`), so ~2 s is uploads and first draws. The
  async restore spreads that over its frames; what its 19.7 s is made of is ~150 frames of a settling room at
  60-100 ms each (scripts, physics, live viewports -- the probe has no camera, so not drawing the room).
- The first physics step with 151 new bodies (~430 ms under Tracy) and five books opening their PDFs in `_ready`
  (~220 ms with `pdf_cache` warm, 1.3 s cold).
- Spread across pass 1, none over ~350 ms: port covers' `create_convex_shape` (`cover_slots.gd`), model
  instantiation, mod object scene `load()`s, the core info database's one-time lazy load (399 `.info` files,
  `CoreInfoDatabase.load_from_project`, ~135 ms, paid by whichever object first asks), a mod's `_wear`.
- The room scene itself: 0.8-1.1 s by `load()` (BootScene) on desktop; `use_sub_threads` made no consistent
  difference.
- The Quest is not measured: the boot-warm wait should matter more there (one loader thread), and is OWED on device.

## The Starlight Arcade on a Quest 3, Perfetto (2026-11-13)

The desktop's autosave (242 entries: 31 consoles, 67 cables, 11 NAOMI bays, 9 cabinets) restored on a Quest 3
(Horizon OS 14), debug export of `master` + the working tree. **11-15 fps against 72.** The bare room (no slot)
holds 72 fps at App 5.9 ms, so it is the objects.

**Verdict: CPU-bound on ONE thread.** The main thread (`VkThread`, Godot's main loop on Android) is Running 98.5%
of wall time; every other app thread is under 3% (`_thread_loop` is a GDScript `Thread`, here the web file server's, not
the render thread). Godot's own `Frame time` counter: 58 ms. Physics runs 2 ticks a frame
(the cap), so the room also runs at half speed.

The GPU is NOT what holds it there (31% utilised, `app_gpu_ms` 16.75), but it is over 72 Hz's 13.9 ms on its
own: the 4x MSAA 2064x2163 eye buffer is 15.4 ms of it, the three full-size MSAA-1 surfaces ~0.6 ms each, a
2200x1643 surface (a viewport) and the 516x540 / 258x270 / 2x2 chains (glow / luminance) the rest. Fix the CPU
and the GPU is next. (53 ms of GPU in the first minute is texture upload and the shell warm, not steady state.)

Main thread, simpleperf with DWARF call graphs (no trace session running, so no tracer overhead), share of samples:

| | share | ~ms/frame |
|---|---:|---:|
| `SceneTree::physics_process` (2 ticks) | 53.5% | 31 |
| of it **`Xenu::VerletRope::_physics_process`** | **32.7%** | **19 (9.5 a tick)** |
| - `SolveSurfaceCollision` -> `get_rest_info` (a `Dictionary` per query through godot-cpp) | 16.5% | |
| - `SweepParticleContacts` -> `intersect_ray` | 9.6% | |
| - `StepEnd` -> `CapsuleShape3D::set_height` (every segment collider re-built every tick) | 4.2% | |
| `RenderingServerDefault::_draw` (of it `swap_buffers` / `_end_frame` = Adreno submit 14%) | 18.6% | 11 |
| `SceneTree::process` | 17.9% | 10 |
| all GDScript (`GDScriptInstance::callp`, both trees) | 22.8% | 13 |

Jolt's own step is 2.8 ms; the Jolt time in the flat profile (`QuadTree::CastRay` / `CollideAABox`, ~20%) is the
ROPE's queries. Script ranking from the Perfetto zones (inflated by the tracer, use for order only):
`grab_driver.gd` `_physics_process` 425 calls a frame (~212 live drivers a tick: everything seated in a snap zone
keeps one), `composite_cable.gd` 94, the nine cabinets (`arcade_cabinet_model` `_process`/`_physics_process`/
`_update_ghost` + `arcade_input._show_hands_only`) ~7 ms together, `handheld_input`, `animated_controller`, 21
`vr_hinge`s. A Theora decode (`VideoStreamPlaybackTheora`, the welcome clip?) shows at 1.5%.

**Levers, in order:** the ropes (why 67 settled cables are awake at all -- `XENU_ROPE_DIAG=1`; then raw
`PhysicsServer3D` queries without the `Dictionary`, and no `set_height` on an unchanged segment); grab drivers of
objects resting in snap zones; the cabinets' per-frame work while nobody is near; then the GPU's MSAA eye buffer.
Not measured: a RELEASE export (GDScript is slower in a debug template; the rope extension is `-O2` either way).

### Recipe: Perfetto on a Quest

- **The engine can emit Godot's zones into Perfetto** (`profiler=perfetto`; every engine zone and every GDScript
  call, through the system backend). Build the SDK amalgamation once (`sdk/perfetto.{cc,h}` from the v50.1 tag into
  `~/tools/perfetto-sdk`), then `ANDROID_HOME=C:/android/sdk ~/.local/bin/scons platform=android arch=arm64
  target=template_debug generate_apk=no profiler=perfetto profiler_path=~/tools/perfetto-sdk debug_symbols=yes`,
  `llvm-strip --strip-debug` a copy for the APK and keep the unstripped one for symbols (same build id).
  `place_engine.py --target debug --so <copy>`, export with `RETROXR_STOCK_ENGINE=1`, then `place_engine.py
  --target debug` to put the shipping engine back in the shared template.
- **Stock 4.7.2's `PerfettoScriptTracer` crashes within 30 s** (SIGSEGV in `~PerfettoScriptTracer`, any thread that
  runs GDScript): `__tracing_system_call` is one unlocked `static HashSet<StringName>` shared by every thread, and
  `tracing` is uninitialised. Fixed in `~/godot` `core/profiling/profiling.h` (`static thread_local`, `= false`);
  it touches only `profiler=perfetto` builds.
- `python Tools/perf/quest_perfetto.py capture --seconds 15 --categories godot --out x.pftrace`, then `analyze`.
  The Quest's GPU sources are `gpu.counters.oculus` / `gpu.renderstages.oculus` (no counter ids to list: it sends
  its own set). `godot_scripting` is ~270k events/s in this room: a 192 MiB ring wrapped and the lost interning
  packets made EVERY later Godot event unreadable (3.5 M `packet_skipped_seq_needs_incremental_state_invalid`) --
  hence `incremental_state_config` and a DISCARD buffer. `trace_start()` can be hours early (stale process stats):
  bound windows by `sched`.
- **A GDExtension's time is NOT zoned**: it shows as `physics_process` SELF time. Ask simpleperf:
  `simpleperf record --app com.xenu.retroxr -e cpu-clock:u -f 500 --call-graph dwarf,16384 --duration 5`, pull it,
  `binary_cache_builder.py -i perf.data -lib <dir with the unstripped libgodot_android.so>` (NDK `simpleperf/`),
  then the NDK's `simpleperf.exe report --symfs binary_cache --tids <main tid> --children --sort symbol`. `-t` alone
  and kernel events are refused on a retail headset; `--app` on a debuggable build works.
- The room slot folder on device is `user://scenes/xenu.starlightarcade%3Aarcade/` (the colon escaped, as on
  desktop); an older `…:arcade/` folder beside it is read by nothing. Copy a desktop slot in through `run-as` and
  rewrite its absolute `C:/Users/<you>/retroxr/` paths to `/sdcard/Android/data/com.xenu.retroxr/files/`.

### The cause was not the rope: cabinets pushing on their own doors (same day)

`XENU_ROPE_DIAG` / `rope_frametime` on the headset: 47 of 68 cords awake, 26 with an END moving 100-340 mm a
tick. Restored on a desktop (`restore_perf_probe --room=<mod room> --no-replay --rope-census`, under a scratch
`APPDATA` so the room's own restore reads a COPY of the slot), the ends were on NAOMI cabinets (New Net City, Aero
City, NAOMI Universal: mod models through `ArcadeCabinetFromModel`) flying about the room at up to 14 m/s and
26 rad/s. 8d764ebf / b8eba004 / cff1e958 gave a model's doors and tray solid `AnimatableBody3D`s on the World
layer, as CHILDREN of the cabinet's RigidBody3D, whose mask takes that layer: Godot does not exempt a body from
its descendants, so each cabinet pushed against its own doors for ever. Fixed with a collision exception
(`_exempt_from_own_cabinet`; `arcade_bay_tests` "every door body is exempt", 0 of 3 before). Desktop, same slot:
awake cords 37 -> 5, rope 6 -> 1.1 ms a tick, probe frame ~27 -> ~11.8 ms.

**Probe trap:** a mod room whose root is `xr_init.gd` with a `scene_id` restores its own slot; replaying `--file`
on top (the probe's default) doubles every object, bodies inside bodies, and reproduces nothing real.

### What is left on the Quest: the GPU (18 fps, 47-53 ms GPU)

With the cabinets standing where they belong (they had flown out of view before), the eye viewport is GPU-bound.
`vrsprobe.cfg` `"sweep"` (QualityManager; several what-ifs in one boot, each against a fresh baseline, because a
relaunch points a headset on a desk somewhere else), eye viewport GPU per frame:

| removed | GPU ms | saves |
|---|---:|---:|
| (baseline, 1,230 draws, 1.06 M primitives) | 53 | |
| every spawned object | 7.1 | 46 |
| the room's `Set` (its 18 lights, probe, shell) | 28.1 | 25 |
| the 18 lights | 39.3 | 14 |
| all but the 4 strongest lights | 45.7 | 7.4 |
| the reflection probe | 53.2 | 0 |
| lights AND probe | 27.6 | 26 |
| MSAA 2x -> off | 39.1 | 14 |
| lights, probe and MSAA | 21.1 | 32 |
| every cord (VerletRope tubes, 243 k primitives) | 48.1 | 5.3 |
| outside backdrops / neon / glass / shell | | <= 1.6 |

`bisect_scenes`: only `system` (31) saves real time alone (10.6 ms), the TVs 2.4; the rest is +-2 ms noise
each and 46 ms together. The cost is the props being SHADED by Godot's lit path: the Starlight Arcade bakes its
shell but lights every prop with 18 real lights (no `ShellLighting` / `PropLighting`, which the built-in rooms
use on a headset to put props on a baked, unshaded shader). Lights alone off is the cheap variant only once the
probe goes too (26 ms); the count of lights barely matters (4 kept: 7.4). `debug_draw` 3 (overdraw) SIGTRAPs the
mobile renderer: do not sweep it. The CPU is next after that: ~35 ms of the 58 ms frame is real work at two
physics ticks a frame (the rest is the driver waiting on the GPU).

### The GPU follows the DRAW count (same day, more sweeps)

The props' cost is not their lighting model and not their pixels. Measured on the headset (eye viewport GPU, the
same pose within each run):

| what | GPU ms | draws |
|---|---:|---:|
| baseline | 52.5 | 1,222 |
| every StandardMaterial3D per-VERTEX (3,276 of them, census-checked) | 52.8 | 1,211 |
| mesh LOD threshold 1 -> 64 px | 50.2 | 1,231 (prims 1.06 M -> 0.79 M) |
| eye buffer 0.85 / 0.7 | 43.4 / 38.0 | |
| eye 0.85 + MSAA off / eye 0.7 + MSAA off | 30.3 / 28.9 | (a floor that does not follow pixels) |
| hide parts under 5 / 15 / 40 cm | 39.3 / 29.2 / 16.5 | 707 / 316 / 136 |
| hide everything past 3 m / 2 m | 17.2 / 4.1 | 257 / 8 |
| **detail cull k 150 / 80 / 40** (below) | **41.2** / 36.3 / 29.7 | 790 / 585 / 338 |
| k 40 + MSAA off + eye 0.7 + no prop lights | 12.7 | 335 |

Roughly 30-50 us of GPU a DRAW on a Quest 3 here, lights included, and pipeline compiles were flat across every
step (not the ubershader fallback). The memory counters (~138 MB written a frame, the size of the whole 4x
eye buffer) say the driver renders this pass to system memory rather than in tiles, which is why MSAA costs
14 ms; that it does so for a 1,200-draw pass is the driver's heuristic, not something Vulkan exposes.

- **Shipped: size-scaled detail culling** (`QualityManager.detail_cull_k`, 150 on a Quest, desktop untouched): a
  part `s` m across stops being drawn beyond `s * 150` m (~8 px on the eye buffer; never under 1.5 m), set as its
  `visibility_range_end` when it enters the tree; a range its author set is kept. 52.5 -> 42.1 ms, 1,222 -> 787
  draws; the room runs 21 fps where it ran 17-19. `vrsprobe.cfg` `"detail_cull_k": 0` is the control.
- **Not shipped, and why:** per-vertex shading (no gain, coarser specular); `rendering/shading/overrides/
  force_vertex_shading.android` HANGS the room's restore for good (every thread asleep right after the model
  prefetch, twice, the stock 242-object slot too): it compiles vertex lighting into every custom shader as well.
  MSAA off, a lower eye buffer and fewer prop lights all reach 72 only together and at a visible price.
- **What would reach 72 without that price is fewer draws a console**: 25-65 each (`nds_primitive` 65,
  `ps2slim` 53, `gamecube` 52, `playstation` 49), one per surface. Merging each model's static surfaces by
  material (at export, RetroXR-models, or at spawn on the headset) is the remaining lever; the CPU, ~35 ms a frame
  of real work at two physics ticks, is the other half of reaching 72.

`vrsprobe.cfg` keys added for this (`QualityManager._probe_sweep`): `sweep` [steps of `hide`, `hide_groups`,
`hide_class`, `hide_small` (m), `hide_far` (m), `lights_off`, `max_lights`, `msaa`, `eye_buffer`, `lod_threshold`,
`debug_draw` (1 = unshaded; 3 = overdraw SIGTRAPs the mobile renderer), `detail_cull_k`, `shading_census`], each
printing the pipeline-compile counters too. `restore_perf_probe` gained `--gpu-census --no-shadows` and `--set-census`.
- **Tried and taken out: merging each object's static surfaces at spawn** (one mesh a material, originals on
  `layers = 0`, unmerged when a hand comes near or a part changes). Merged whole, the small parts lost their own
  culling: 1,054 draws and 1.29 M primitives against 815 / 0.78 M culled, +4.6 ms GPU. Merged by size bucket with
  each bucket's far distance: still 1,019 draws against 816, +2.9 ms. Per-part culling drops more than merging
  saves in this room; a merge pays only at EXPORT, with LODs and culling designed around it (RetroXR-models).
- **The CPU is the other half**: VrApi CPU+GPU 90-96 ms at 20-21 fps, the main thread ~35 ms of real work at two
  physics ticks a frame. Fixing only the GPU leaves the room under 30 fps.

### The pipeline on the Quest, later the same day (what moved the frame rate)

Measured by VrApi FPS/App on the headset, the Starlight Arcade save, the headset resting in one pose:

| change | fps | App (GPU) ms |
|---|---:|---:|
| cabinet self-collision fixed, detail cull k 150 | 21 | 37 |
| + `RuntimePropVolume` and double-sided prop shader (props off Godot's lit path) | 22 | 28 |
| + separate render thread on Android (`thread_model.android=2`) | 26 -> 33 | 27 (frame synthesis removed) |
| + detail cull k 80, eye buffer 0.85 | 46 | 19 |
| + MSAA off | 56-60 | 13 |
| + k 60, eye 0.8 (CPU-bound from here, GPU 75%) | 60-63 | 11 |

- **CPU and GPU were SERIAL** on Android: one thread ran the scripts, recorded the frame, then waited in
  `swap_buffers` for the GPU, so a frame cost CPU + GPU. The separate render thread overlaps them. Two engine fixes
  were needed for it and for cold shader caches (both committed on `retroxr-4.7.2` in `~/godot`; engine-patches.md):
  - `shader_rd.cpp`: a POOL thread compiles a shader group inline instead of queueing a group task and blocking on
    it (`wait_for_group_task_completion` does not run queued work): mesh loads held all four Quest workers in
    `mesh_generate_pipelines` and the restore hung for good on any cold cache (first boot after a shader change).
  - `worker_thread_pool.cpp`: the render thread (the pool thread holding the pump task in separate mode) never
    collaborates on queued work while it waits. It picked up a resource load whose `texture_set_path()` flushed the
    render queue on the same thread, re-entering `_draw` while the main thread held the loader's locks: 1 boot in ~11
    hung. A first fix in `pipeline_hash_map_rd.h` (only the pipeline-compile wait) was not enough; this one held 10/10.
  Stacks were taken with lldb-server via run-as (quest-device.md) and symbolised by relinking `bin/obj` without `-s`.
- **The rope went NaN under the render thread** (5 M `must be normalized` lines, 6 fps). Guarded in the extension
  (StepBegin re-lays a non-finite cord, CouplePlug never applies a non-finite force) and in `PlugTether.reel_in`.
- **Frame synthesis** (`xr/openxr/extensions/frame_synthesis`, XR_EXT_frame_synthesis) is available on a Quest 3 and
  enables, but VrApi never showed SpaceWarp engaged (`SP=N/N/N`) and it cost ~6 ms GPU: removed.
- **Rope switches on a headset: clear them with an EMPTY value** (`setprop debug.xenu.rope_diag "''"`). `0` is a value,
  and `RopeSwitch` treats any value as ON: every measurement after "switching them off" ran with diag and frame timing.
- Uniform light specialization (one pipeline per material, `MULTIPLE` light loops for every draw) measured WORSE
  (51.6 vs 42 ms) and was reverted; per-vertex shading measured nothing.
- What is left is CPU at ~16 ms with the render thread: GDScript ~50% of the main thread, the rope ~24% (queries
  returning Dictionaries; handed to the rope session), the welcome panel's Theora clip ~6% while it is open.

### Release build, the same room (2026-11-13, evening)

A RELEASE export installs over a debug one with the debug key
(`GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD` = `%APPDATA%\Godot\keystores\debug.keystore`,
`androiddebugkey`, `android`); it is not debuggable, so the probe cfg goes to
`/sdcard/Android/data/com.xenu.retroxr/files/vrsprobe.cfg`. Release GDScript is cheaper: the CPU stopped being
the limit and the GPU became it.

| settings (release) | fps | App ms | GPU% |
|---|---:|---:|---:|
| eye 0.8, MSAA off, detail cull k 60 | 69-71 | 13.0 | 98 |
| eye 0.75, MSAA off, k 60 | 65-69 | 13.1 | 97 (resolution no longer moves it) |
| eye 0.8, MSAA off, **k 40** | **70-72** | **11.3** | 88 |

- The remaining GPU follows draws and vertices, not pixels: what is left to buy is fewer draws a model and LODs
  on the dense models, not resolution.
- Changing foveation mid-session (to MAX) got the app killed by lmkd (`LMKKillNotifier ... RetroXR`): free memory in
  this room runs 290-900 MB, and the swapchain/VRS reallocation tipped it.
- Script profile (`vrsprobe` `profile_scripts`, debug): 7.7 ms a frame in 619 callbacks of 127 scripts; the 213
  grab drivers are 0.9 ms (call overhead, the rest early-out), everything else 0.05-0.6 ms each.

### Physics ticks once per displayed frame on a headset (2026-11-13, late)

With the quality governor at its last step the room held 68-71, not 72, with the GPU at 88-92% and App ~11.4 ms:
room to spare on both, so the misses were a periodic spike. Physics ticked at the project's 90 Hz under a 72 Hz
display, so every fourth frame ran TWO physics ticks (Jolt, every awake cord, grab drivers, every
`_physics_process`). `QualityManager._match_physics_rate` now sets `Engine.physics_ticks_per_second` to the
display rate on a headset (desktop stays at 90: the rope oracles are measured there). The rope steps with the delta
it is given (`slice = delta / substeps`), so the longer tick is a longer step, not a stiffer cord; anything counted
in TICKS (a rope's forced sleep after 720, a grab driver resting after 30) now takes 1.25x as long.
`vrsprobe.cfg` `"physics_hz": 90` is the control arm.

| release, default settings, governor at step 6/6, 40 s each | mean fps | seconds under 71 |
|---|---:|---:|
| physics 90 Hz (control) | 71.1 | 11 |
| **physics 72 Hz** | **72.1** | **1** |
