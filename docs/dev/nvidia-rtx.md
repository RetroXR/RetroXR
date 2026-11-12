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

**The DLSS model DLLs are NVIDIA's own SDK's, newer than Streamline's** (2026-11-12): `nvngx_dlss.dll`,
`nvngx_dlssd.dll` (Ray Reconstruction) and `nvngx_dlssg.dll` in `bin/` are **310.9.16** (the DLSS 4.5
generation, second-gen Ray Reconstruction), from `github.com/NVIDIA/DLSS` tag `v310.9.16`,
`lib/Windows_x86_64/rel/` (signature checked: NVIDIA Corporation). Streamline 2.10.3's bundled 310.5.2 are kept in
`bin/dlss-310.5.2-backup/`. The interposer stays 2.10.3 (the engine's headers); the driver loads its own Streamline
plugins over the air (2.14.16 here, `C:/ProgramData/NVIDIA/NGX/models/sl_*`). Which DLL is really in use is read
off the running engine's modules (the child `godot.windows.editor.x86_64.exe`, not the console wrapper), never the
log: Streamline does not log the `nvngx` it opens. RetroXR sets no DLSS preset (Streamline's default).

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

- `~/RetroXR-rtx` is a DETACHED git worktree of this repo (`git worktree add
  --detach ~/RetroXR-rtx master`; refresh with `git -C ~/RetroXR-rtx checkout --detach
  master`). Its only local edits are test scaffolding, visible in `git diff`:
  `project.godot` gets `config/use_custom_user_dir=true` +
  `custom_user_dir_name="RetroXR-rtx"` (so `user://` is `%APPDATA%/RetroXR-rtx`,
  seeded from the real one minus caches), the `RtxShot` autoload and
  `pathtracing/max_transparency_layers=0`; `rtx/` is untracked. Never carry those,
  or the `.import` files the 4.8 editor rewrites, to master. GDExtension binaries,
  `.godot/` and mod packs are gitignored: copy them in. A plain copy (the first
  attempt) drifted, and runs before the user dir was set read AND wrote the
  player's real saves and prefs.
- `rtx/rtx_shot.gd` (an autoload in the copy only): `RTX_SHOT=secs,...` saves
  the root viewport and logs luma, fps and the environment; `RTX_ENV=k=v,...`
  changes the environment at 30 s (`tonemap exposure ambient glow debug`);
  `RTX_ROOM=<id>` changes room at 12 s; `RTX_DUMP=1` lists the room shell's meshes;
  `RTX_LOOK=<name>` puts a camera before a spawned object and `RTX_HOVER=<name>`
  shows its hover highlight (35 s); `RTX_NO_DLSS=1` drops to bilinear at 30 s.
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

1. **Pre-lit rooms blew out -- FIXED for the Starlight Arcade** (RetroXR-models `5e50d6a14`). Its shell
   bakes its light into `EMISSION` (`baked_surface_shadowed`), reads a light total from uniform arrays the
   tracer never fills (`ALBEDO` x80), and shadows with NEGATIVE twin lights culled to the shell, which a
   tracer does not honour: mean luma 0.92, white. Under `effective_path_tracing()` the mod swaps the shell's
   materials to `pt_surface` (real albedo; painted glow and the bake's own lamps, bright in the bake AND
   unsaturated, as emission), hides the twins and lets the
   shell cast; live through `QualityManager.path_tracing_changed`. 0.213 traced vs 0.225 raster. Its neon,
   EXIT letters, troffer lenses and tubes swap to `pt_emissive` (RetroXR-models `de4be8032`), and the guessed
   lamps are off (they lit the sign's white board into a blob). **Baked lighting is the Quest's only**: path
   traced, the shell keeps none of its bake (`bake_fill` 0, RetroXR-models `pt.bake_fill`), the tracer lights the
   room (0.089/0.112 vs 0.102/0.126 with 0.8 baked). An untraced desktop keeps the baked shell: it has no
   traced lighting to use. Any other pre-lit room needs the same.
   **Two tracer rules that cost a round each:** an `unshaded` material's ALBEDO is NOT light to the tracer (it
   is shaded as paint: write EMISSION, render mode shaded); and the tracer does NOT fill uniform ARRAYS
   (`uniform vec3 palette[8]` read as zeros, so the tubes emitted black; use one uniform per slot).
2. **DLSS drew black under `--fixed-fps` / `--write-movie` -- FIXED** (engine `6596d3acd3`): `Main::iteration`
   returned before the marker that fetches Streamline's frame token, so every frame reused the first one.
3. **Hang entering a room -- FIXED** (engine `cf4c66767a`), path tracing on or off. Not NVIDIA's: upstream
   4.8-dev made the shader-cache load a pool group task (#119123), and a pool thread that queued a group then
   waited on it in `ShaderRD::_compile_version_end`, holding the version mutex. A group wait runs nothing
   itself, so a room of meshes starved the pool (cdb: 20/20 workers held or waited on version mutexes, the
   render thread blocked in `enable_group`, main in `push_and_sync`). A pool thread's batch now runs inline.
   5 of 6 launches hung before, 0 of 8 after. Stock 4.7.2 predates #119123. Capture recipe: attach cdb
   (WinDbg package, `amd64\cdb.exe -p <pid> -pv`) to `godot.windows.editor.x86_64.exe`, the CHILD of the
   console wrapper, with a `debug_symbols=yes` build.
4. **A material whose hit shader fails to compile drops out of the traced scene**
   (no fallback; sources dumped to `%TEMP%/rt_shader_hg*_closest_hit.glsl` +
   `.err.txt`). Engine commit `e7868a64a1` adds stand-ins for `dFdx`/`dFdy`
   (+Coarse/Fine, zero) and `textureQueryLod` (level 0, a MACRO: Vulkan GLSL refuses
   a sampler constructor as a call argument), as the fork already had for
   `fwidth`: 14 of RetroXR's 20 failing groups compile and the bedroom has none
   left. Still failing: `sampler2DArray` uniforms (the fork's bindless textures are
   2D only: the printer paper). `texture()`/`textureProj()` with a bias are now
   their Lod forms in hit shaders (engine `342d992bfa`, `function_renames_by_arity`), so only the
   `sampler2DArray` case is left.
6. **Raster-only tricks are traced as solid geometry by default.** The hover
   highlight is an inflated overlay mesh (stencil mask + outline, `depth_test`
   disabled); at the default `max_transparency_layers` (4) every alpha-pass material
   is traced, so the overlay became a shell over the object and hid its labels. At
   0 the engine rasterises the alpha list over the traced image instead -- which the
   test worktree sets; RetroXR's `project.godot` does not yet.
7. **MSAA swallowed that overlay -- FIXED in RetroXR (`8f55d951`).** The tracer
   writes its image to the internal texture and the fork skips the colour MSAA
   resolve, but the transparent pass draws into `get_color_pass_fb()`, the
   MULTISAMPLED buffer when MSAA is on, which nothing resolves: a TV's picture (the
   CRT material writes ALPHA for its glass edge) and the hover outline vanished,
   DLSS on or off. `QualityManager.effective_msaa()` is off while path tracing
   (`quality_tests rtx/`). Proven by `RTX_LOOK=tv RTX_HOVER=tv` with the saved MSAA
   at 4x: screen, outline, labels and the VCR display all drawn, 165 fps. Upstream,
   the transparent pass should draw into the non-MSAA target under the tracer.
5. Godot 4.8-dev logs ~11k "causing RenderingServer synchronizations" warnings a
   run with RetroXR's separate render thread, raster or traced alike.

Headset: impossible (no stereo). A shipped build would need the fork on 4.7.2 or
RetroXR on 4.8, and the Streamline DLLs (NVIDIA's licence) in the Windows package.
