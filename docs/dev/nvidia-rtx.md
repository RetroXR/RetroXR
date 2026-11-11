# NVIDIA path tracing and DLSS (desktop, experimental)

NVIDIA's Godot fork (github.com/NVIDIA-RTX/godot, branch `nvidia-pt-dlss`) adds a
hardware path tracer and DLSS (Super Resolution + Ray Reconstruction) through
NVIDIA Streamline. RetroXR offers both in the GRAPHICS tab **only when it runs on
that engine**: the shipped build is stock 4.7.2 and never shows the rows.

## What the fork is

- **4.8-dev, not 4.7.** `nvidia-pt-dlss` is 4.7-stable + upstream master + two
  squashed commits: `9b854bebc2` "NVIDIA: Dependencies" (Streamline 2.10.0 headers,
  glslang/re-spirv/spirv-reflect patches) and `49a825dc52` "NVIDIA: Pathtracer +
  DLSS" (~36.6k lines). There is also `backport/nvidia-pt-dlss-4.6.3`; no 4.7.
- **Forward+ only, Vulkan or D3D12, Windows only for DLSS** (`use_streamline` is
  forced off elsewhere). Nothing for the mobile renderer, so never the Quest.
- **No stereo.** Neither the path tracer nor DLSS has multiview; DLSS keeps one
  viewport handle per Godot viewport. PCVR stands both down, as Render Scale is.
- Cherry-picking `49a825dc52` onto `retroxr-4.7.2` conflicts in 15 files (it leans
  on 4.8-dev renderer APIs); merging the branch conflicts in 22. Not attempted.

## Building it (2026-11-12)

The test checkout is `~/godot-rtx`, a `git worktree` of `~/godot`, on branch
`nvidia-pt-dlss-test` = NVIDIA's branch + one fix of ours (below). `~/godot` and
its Quest build stay on `retroxr-4.7.2`, untouched.

```bash
cd ~/godot-rtx
python misc/scripts/install_accesskit.py           # a fresh checkout has neither
python misc/scripts/install_d3d12_sdk_windows.py
~/.local/bin/scons.exe platform=windows target=editor -j18     # ~12 min cold
```

**Runtime DLLs are not in the repo.** The engine `LoadLibrary`s `sl.interposer.dll`
from beside the executable; without it DLSS silently does not exist. Copy
`bin/x64/*.dll` from the Streamline SDK release matching the headers' MINOR
(`sl_version.h` 2.10.0 -> `NVIDIA-RTX/Streamline` release `v2.10.3`, 213 MB zip)
into `bin/`. Streamline verifies NVIDIA's signature on each and logs it.

## Our fix on top: `4bdd1f149b`

`scene_depth_fetch()` (the new `SCENE_DEPTH` built-in) built a `sampler2D` from
`depth_buffer` in multiview DEPTH variants, where it is a `texture2DArray`, so
every multiview depth variant failed to compile and the process then crashed in
deep recursion. Any project with OpenXR enabled compiles those variants even on a
flat desktop; NVIDIA's own samples have XR off. Guard is now plain
`USE_MULTIVIEW`, as the mobile renderer already had it. Worth sending upstream.

## Running RetroXR on it

The project imports clean under 4.8-dev (no script/shader errors) and every
GDExtension built for 4.7 loads. **Never open the real checkout with it** -- the
editor converts project files. Test from a copy:

- `~/RetroXR-rtx` is a robocopy of `RetroXR/` (no `android/`), with
  `config/use_custom_user_dir=true` + `custom_user_dir_name="RetroXR-rtx"` so its
  `user://` is `%APPDATA%/RetroXR-rtx`, seeded from the real one minus caches.
  Before that was set, runs read AND wrote the player's real saves and prefs.
- `rtx/rtx_shot.gd` (an autoload in the copy only): `RTX_SHOT=secs,...` saves
  the root viewport and logs luma, fps and the environment; `RTX_ENV=k=v,...`
  changes the environment at 30 s (`tonemap exposure ambient glow debug`);
  `RTX_ROOM=<id>` changes room at 12 s; `RTX_DUMP=1` lists the room shell's meshes.
- Never judge it with `--write-movie` or `--fixed-fps` (bug 2 below).

## The GRAPHICS rows (`QualityManager`, `graphics_view.gd`)

- **Upscaler** FSR 1 / DLSS, shown when `supports_dlss()`: Forward+, no XR, the
  engine has `Viewport.SCALING_3D_MODE_DLSS`, and the `Streamline` singleton's
  `get_capability(DLSS)` is true (it is false without the DLLs or an RTX card).
  DLSS clamps Render Scale to 1.0 (DLAA): above that the engine only downsamples.
- **Path Tracing** on/off, **Bounces** 1-8, **Samples per Pixel** 1/2/4, shown
  when `supports_path_tracing()`: Forward+, no XR, `Environment` has
  `set_pathtracing_enabled`, and the device has `SUPPORTS_RAYTRACING_PIPELINE`.
- **The path tracer always brings DLSS with it** (`effective_dlss()`): its
  denoiser is Ray Reconstruction, which runs only inside the DLSS pass. Without it
  every frame is raw one-sample grain (measured on a Cornell box).
- It is set on each room's own `Environment` in `configure_environment`, like AO.
- Every `SubViewport` gets `use_pathtracing = false` (`_keep_raster`): one that
  shares the room's world (Game Boy Camera lens, thumbnails) would otherwise run a
  whole path-traced frame of its own with no DLSS pass to denoise it.
- Every property and constant of the fork's is reached BY NAME (`set()`,
  `ClassDB`) so the scripts parse on stock 4.7.2. `quality_tests rtx/` holds on both.
- Prefs `path_tracing pt_bounces pt_samples dlss` are kept on any engine.

## Measured (RTX 5070 Laptop, 1280x720)

| scene | raster | path traced | path traced + DLSS 0.58 |
|---|---|---|---|
| Cornell box (`~/godot-rtx-test`) | 234 fps | 69 fps, grainy | 158 fps, clean |
| Bedroom (base game) | ~160 fps | -- | ~161-165 fps, correct |
| Starlight Arcade (mod) | ~84 fps (High) | -- | **white-out**, see below |

## Open problems

1. **Pre-lit rooms blow out.** The Starlight Arcade (mod `xenu.starlightarcade`,
   source not in this repo) bakes its light into `EMISSION`
   (`baked_surface_shadowed.gdshader`) and darkens shadows with NEGATIVE twin
   lights limited by cull mask to the shell. In a path tracer every wall is then a
   light, `ALBEDO = c * 0.8 / total` reads `total` from uniform arrays it does not
   fill (so x80), and the negative lights are not culled. Mean luma 0.92 vs 0.22.
   Fix belongs in the room: under path tracing, real albedo, no baked emission, no
   twin lights. The base game's rooms keep Godot's lighting on desktop
   (`shell_lighting.gd` swaps to the unshaded twins only on a headset) and trace
   correctly.
2. **DLSS under `--fixed-fps` renders black** (and so under `--write-movie`), path
   traced or not; real time is fine. NVIDIA bug, not chased.
3. **Intermittent hang entering a room**, path tracing on or off: about 3 launches
   in 14 stopped right after Streamline loaded its plugins, never past it.
4. **Four RetroXR shaders have no ray-tracing hit shader** and vanish from traced
   rays: thermal print paper (`sampler2DArray` uniform), CRT screen (`dFdx`), a
   frosted label (`textureQueryLod`), a `texture()` with a bias. The fork skips a
   failed hit group instead of falling back; the sources are dumped to
   `%TEMP%/rt_shader_hg*_closest_hit.glsl` with an `.err.txt`.
5. Godot 4.8-dev logs ~11k "causing RenderingServer synchronizations" warnings a
   run with RetroXR's separate render thread, raster or traced alike.

Headset: impossible (no stereo). A shipped build would need the fork on 4.7.2 or
RetroXR on 4.8, and the Streamline DLLs (NVIDIA's licence) in the Windows package.
