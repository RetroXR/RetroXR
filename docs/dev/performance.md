# Screen rendering and frame-transfer profiling

The fast CRT tier now covers ordinary TVs, packed/stereo screen windows, VHS
and analog static. QualityManager.crt_fast selects it (the mobile default);
desktop retains the full tier. Source signal code is shared by both variants,
including VHS effects, packed regions, stereo selection and OSD. The fast tier
uses unshaded glass, an opaque alpha-scissor corner and the existing mobile
mask/beam stage. Packed windows use four clamped minification taps rather than
nine; no tap may sample an adjacent packed screen.

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
