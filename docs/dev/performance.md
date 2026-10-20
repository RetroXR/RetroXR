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
