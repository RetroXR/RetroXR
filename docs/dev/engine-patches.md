# The patched Quest engine

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### The Quest ships a PATCHED engine

The stock 4.7.2 Android template has six defects on a Quest 3 that each have
a fix: a boot deadlock in the Forward Mobile shader lock scope; colour and
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
python Tools/place_engine.py --target debug --restore
```

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
`scons` is not on PATH in Git Bash: `$APPDATA/Python/Python314/Scripts/scons.exe`.
A shader include placed under `shaders/effects/` is not a dependency of the
forward_mobile shaders (their SCsub globs `*_inc.glsl` and `../*_inc.glsl`), and
one placed inside the `!MODE_UNSHADED` guard is missing from every unshaded
variant, which fails at pipeline creation with "no matching overloaded
function" and a SIGTRAP in a worker thread, not at build time. Measured earlier
the same day at 1.5x: App 13.1 -> 11.5 ms for the discardable and clear
patches; the deadlock fix booted 10/10 where stock hung on launch 2.
