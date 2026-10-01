# The patched Quest engine

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### The Quest ships a PATCHED engine

The stock 4.7.2 Android template has eight defects on a Quest 3 that each have
a fix: a boot deadlock in the Forward Mobile shader lock scope; a Vulkan
pipeline cache that is thrown away on every launch, and a shader cache that never
saves a group nothing asked for (both below); colour and
depth buffers stored every frame though nothing reads them (and their
subsampled twins); the swapchain loaded into tile memory every bin though the
pass overwrites it; the foveation density map left blank after any MSAA or
eye-buffer change (the update mode ONCE was demoted to DISABLED and never
re-armed, 28 ms instead of 13); and every frame going through a 10-bit scene
buffer plus a tonemap subpass even when that subpass is a copy. The fixes are
`docs/godot-4.7.2-*.patch`, applied on the engine branch `retroxr-4.7.2`
(4.7.2-stable + all of them) in `~/godot`, pushed to
https://github.com/RetroXR/godot/tree/retroxr-4.7.2. The prebuilt arm64
libraries from that branch live under `Tools/engine/` (Git LFS) and
`Tools/place_engine.py` swaps one into the Android build template's AAR:

```bash
python Tools/place_engine.py --target release   # what release.yml runs before the export
python Tools/place_engine.py --target debug     # for a local Quest export
python Tools/place_engine.py --target debug --check     # exit 1 if the AAR is not ours
python Tools/place_engine.py --target debug --restore   # deliberate stock A/B ONLY
```

**The template must stay patched, and exports now see to it.** The AAR under
`RetroXR/android/build/libs/` is shared by every export from the checkout, so a
`--restore` "to undo" after a probe build (the advice this file used to give) silently
made every later local build stock. That happened on 2026-09-27 and was found on
2026-09-30 as "the Quest is stuck on the loading screen": stock hung 4 launches of 4
at the first stereo frame, the patched engine booted 5 of 5. Main thread and all four
`WorkerThread`s were parked in `futex_wait` (stacks: quest-device.md). Since then
`addons/retroxr_build_stamp`'s export plugin runs `place_engine.py --target <debug|
release>` at the start of every Android export (a no-op when the AAR already carries
the library; it compares the zip entry's CRC), and errors loudly if it cannot.
`RETROXR_STOCK_ENGINE=1` skips it for a deliberate comparison. At run time a stock
engine names itself: the banner says `4.7.2.stable.official` (ours: `custom_build`)
and `boot_scene.gd` logs `[Boot] running STOCK Godot` as an error.

### The ETC2 encoder (`godot-4.7.2-etc2-encoder-android.patch`)

Not a defect: a capability. Godot registers its texture ENCODERS only with
`TOOLS_ENABLED`, so an export template can decode ETC2/ASTC but `Image.compress()` returns
`ERR_UNAVAILABLE`. RetroXR compresses PDF pages at run time on a Quest (books.md), so the
etcpak wrapper and its registration now also build with `ANDROID_ENABLED`. The encoder
sources (`ProcessRGB`, `ProcessDxtc`) were in every build already; the library grew 34 KB (debug) and 43 KB (release).
`PDFBook._can_compress_pages()` asks rather than assumes, so a stock engine falls back to
RGBA8 pages instead of half-converting them. ASTC's encoder is still editor-only.

### The pipeline cache (`godot-4.7.2-pipeline-cache-size.patch`)

`user://vulkan/pipelines.mobile.adreno_(tm)_740.cache` was rewritten on every boot and
rejected on the next one (`--verbose`: "Invalid Vulkan pipelines cache header",
then `Startup PSO cache (0.0 MiB)`). `pipeline_cache_serialize()` sized its buffer from
the last size query, recorded the size `vkGetPipelineCacheData` actually wrote in the
header, and returned the buffer at the queried size; the Adreno driver writes a few
hundred bytes less than it reports (349 of 16 MiB), and the loader requires
`data_size == file length - header`. So every launch recompiled every pipeline:
**~95 CPU-seconds of `libllvm-qgl.so` on all four workers from 13 s to 61 s**
(simpleperf, quest-device.md), which also starved the threaded loads queued behind it
and stalled single frames for 9-11 s. The patch trims the buffer to what was written,
and reads an old padded file up to its `data_size` instead of discarding it. Upstream
master has the same code as of 2026-09-30. Arcade slot, Quest 3, steady state:

| | room restored | curtain lifts |
|---|---|---|
| before | 37-41 s | 72-75 s |
| cache patch | 17.5 s | 39 s |
| + 2048 px page cap (books.md) | 17.3 s | 25-26 s |
| + ETC2 pages, model textures VRAM | 17.2 s | 19.7 s |
| + shader cache, no stand-in warm | 18.4 s (31 objects) | ~18.4 s |

The last row's room had grown from 17 objects to 31; the curtain now lifts when the
restore ends, and the room holds 72 fps from ~3 s after (with the warm it ran 1-9 fps for
up to 20 s more).

**The stand-in warm is gone** (`SceneManager._warm_models`, `ModelWarmer.skip_stand_ins`).
It built and drew every stand-in under the curtain because a cold spawn of the 3DS one
took 3.9 s, nearly all pipeline and shader compiles that both caches threw away. With the
caches kept, a cold spawn measured on the Quest (no warm, 2026-09-30): GBA 37 ms, Wii 76,
N64 19, DS 184, PSP 78, Famicom 48, Virtual Boy 81, Lynx 54. That is what the warm saved,
for 2.5-7 s of curtain, and run after the curtain it would put all of them into the room
at once. The bespoke shells' GLBs still load at boot, off the main thread
(`request_shells`, `warm_shells`). Anything that loads a model GLB in `_ready` must be
fetched with `ModelWarmer.acquire()` before it is built: cartridges were not, and an N64
cart's body was a 625 ms frozen frame in the arcade restore (`RetroCartridge.body_model_for`,
`scene_tests` `cartbody/`).

Remaining, measured but not fixed: ~7 s from engine start to the first autoload
`_ready` is the autoloads' transitive preloads (UI nobody sees at boot among them: the
controller-diagram art, the HSV wheel shader, the toast host); and a build deployed with
remote debugging on (its command line carries `--remote-debug tcp://localhost:6007`)
spends 3.3 s at launch failing to connect when no editor is listening. A CLI
`--export-debug` does not.

### The shader cache (`godot-4.7.2-shader-cache-unused-group.patch`)

`ShaderRD` saved a compiled group to `user://shader_cache/` only in
`_compile_version_end`, which runs when one of the group's variants is ASKED for. Every
material eagerly compiles all its enabled groups, and on a Quest in XR the scene is drawn
with the multiview ones, so the plain group of a material drawn only in stereo finished
compiling and was never committed: discarded unsaved, compiled again next launch. The same
13 `SceneForwardMobileShaderRD` groups every boot (`--verbose`: "Shader cache miss"), 8 of
them on the main thread before the autoloads were ready, 0.6 s with one 585 ms stall, plus
worker time the threaded loads queued behind. Now each group compile carries a countdown of
its variants and the last to finish saves the group from the worker (if every enabled
variant compiled); `_compile_version_end` only releases the countdown. The miss message
names the group. Measured: 0 misses on the second boot after install (a room with new
materials compiled 153 on the first, and kept them).

**The direct render path is a project setting**,
`rendering/renderer/mobile/render_directly_to_target` (on in `project.godot`;
the engine default is off). With it the scene is drawn in one subpass straight
into the swapchain, or resolved into it under MSAA, and the scene shader
applies the environment's tonemapper in its epilogue, and so does the sky
pass. It only engages when the tonemap subpass would be a copy: no glow and no
colour adjustments (a sky room measured 3.70 -> 3.59 ms, same picture).
`rendering/renderer/mobile/direct_target_srgb_view` (default on) draws through
an sRGB view so the hardware encodes and blending stays linear; off, the shader
encodes and transparent surfaces blend on encoded values. Measured 2026-09-09,
arcade slot, MAX foveation, GPU 545 MHz, App ms:

| view                        | subpass | direct |
|-----------------------------|--------:|-------:|
| full view 1.5x, MSAA 2x     | 5.7     | 4.3    |
| empty frame 1.75x           | 3.4     | 3.1    |
| full view 1.5x, no MSAA     | 3.3     | 3.7    |

So it is the MSAA path it pays for; the per-fragment Filmic costs more than the
subpass on a plain view. **Do not read an sRGB-view experiment off a screencap
alone**: RenderingDevice used to declare a framebuffer on a shared view with
the OWNER's format, so an sRGB view stored raw linear values (a picture three
times too dark in the mid-tones) with no error anywhere. Fixed in the same
patch; the resolve path had encoded correctly all along, which is how it was
caught.

Rebuild both libraries when a patch changes (each ~1 min incremental, the
first build of a tree ~5 min):
`cd ~/godot && ANDROID_HOME=C:/android scons platform=android arch=arm64
target=template_release generate_apk=no -j14` (and `template_debug`), then
copy `platform/android/java/lib/libs/<target>/arm64-v8a/libgodot_android.so`
over `Tools/engine/android/arm64-v8a/libgodot_android.template_<target>.so`.
Commit on the engine branch FIRST and build after: the banner's hash is HEAD at build
time, and a library built from an uncommitted tree names the commit before its fix.
`scons` is not on PATH in Git Bash: `$APPDATA/Python/Python314/Scripts/scons.exe`.
A shader include placed under `shaders/effects/` is not a dependency of the
forward_mobile shaders (their SCsub globs `*_inc.glsl` and `../*_inc.glsl`), and
one placed inside the `!MODE_UNSHADED` guard is missing from every unshaded
variant, which fails at pipeline creation with "no matching overloaded
function" and a SIGTRAP in a worker thread, not at build time. Measured earlier
the same day at 1.5x: App 13.1 -> 11.5 ms for the discardable and clear
patches; the deadlock fix booted 10/10 where stock hung on launch 2.
