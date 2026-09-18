# Repo-root Tools/

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

## Tools

Reusable, out-of-band scripts live in the repo-root `Tools/` (distinct from `RetroXR/Tools/`,
which holds in-editor probe scenes like `netplay_spike`).

What they need is declared in `Tools/requirements.txt` — numpy, pillow, scipy and
the imageio pair — so a fresh checkout does not discover them one ImportError at a
time: `python -m pip install -r Tools/requirements.txt`. Blender's `bpy`/`bmesh`/
`mathutils` are deliberately absent: `Tools/glb/*.py` run inside
`blender --background --python`, never as plain Python.

`RetroXR/imported-assets/` holds the CC BY / CC0 room and prop assets, which carry
LICENSE files and are credited in the About panel. The hardware wears the procedural
stand-ins in `RetroXR/Scenes/Objects/system_models/`.

**Only add 3D assets this project has the right to ship.** Everything in the repo must
be either our own work or licensed for redistribution, with its licence and attribution
carried alongside it.
- **`Tools/download_pdfium.sh`** — fetches prebuilt PDFium from bblanchon/pdfium-binaries into
  `godot-pdfium/external/pdfium/`. All five packages by default (`-p
  linux|win|mac|mac-x64|android` for one, `-r <tag>` to pin a release, `-n` to dry-run).
  Bash, so it runs on Linux, WSL, macOS and Git Bash; it superseded
  `Tools/download_pdfium.ps1`, which had no Linux or macOS platform at all. The `.ps1` is
  still in the tree but is NOT maintained — use the `.sh`. The
  `include/` headers are shared by all packages, so a **partial** run leaves them alone by
  default (`--headers` to force) — new declarations against an unrefreshed binary is how you
  get a link error on the platform you weren't building. Each `lib/<plat>/` carries a `VERSION`
  stamp of the release it came from, and the top-level one belongs to `include/`; they are
  allowed to differ, and the script prints them so you can see when they do.
- **Controller art** — three sources feed the Controls remap diagrams, and the
  licence of each is recorded in `RetroXR/Textures/Controllers/ATTRIBUTIONS.txt`.
  `bake_controller_art.py` bakes the Quest Touch art from a glTF (MIT), because a
  Touch controller's shape cannot be guessed. `gen_gamepad_art.py` DRAWS its pad —
  circles, capsules and a cross on a symmetric body — which keeps the anchors as
  chosen coordinates that cannot drift from a render; it is an Xbox *layout* and
  deliberately not an Xbox, so there is no mark being borrowed. The NES pad is a
  Wikimedia Commons drawing by Fant0men used under **CC BY-SA 3.0** with the
  Nintendo wordmark's eleven paths deleted — the repo's ONLY share-alike asset,
  so it carries two live obligations: the About panel must keep crediting it,
  and the modified file stays CC BY-SA (it does not relicense anything else).
  Its anchors are MEASURED out of a Godot render by
  `Tools/art/nes_pad_anchors.py` (red discs → A/B, black cross → d-pad, black pills →
  Select/Start) rather than chosen. That tool also counts leader-line
  intersections over a sweep of panel sizes, and the count must stay 0.
  ```bash
  python Tools/art/nes_pad_anchors.py RetroXR/probe_out/nes_colour_raw.png
  ```
  **A console pad's art is drawn inside `_draw()`, not parented as a TextureRect**
  — a Control renders its own `_draw()` behind its children, so a child texture
  hides the leader lines and anchor dots. Invisible with line art, whose body is
  nearly transparent; total with a colour illustration.
- **`Tools/gen_gblink_rom.py`** — builds the four Game Boy ROMs the link probes run,
  two at the Game Boy's clock and two at the Game Boy Color's. Ours, so they ship
  freely; the header logo carries only its first four bytes, which is the signature
  a loader matches to decide a file is a Game Boy ROM at all (mGBA refuses one
  without them) and not the artwork.
- **`Tools/glb/decimate_glb.py`** — Blender-headless triangle reduction for a downloaded shell.
  Sketchfab assets arrive subdivided for renders: the Atari 2600 console shipped 1,080,733
  triangles and 57.7 MB, against 27,893 for the NES. **Weld first** — these exports are
  triangle soup (that console was 230,787 disconnected islands, median one triangle), and
  Collapse cannot reduce an isolated triangle, so without the weld the body floors at 54 k
  however low you aim. Also drop the custom split normals and re-derive shading by angle:
  carried through a 98% cut they describe a surface that is gone, which showed up as a smeared
  cartridge slot and starburst facets across flat panels.
  ```bash
  "/c/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background \
    --python Tools/glb/decimate_glb.py -- --in <src>.glb --out <dst>.glb --target 25000
  ```
  `Tools/glb/glb_report.py` dumps a GLB's node tree, world AABBs and triangle budget;
  `Tools/glb/glb_diff.py` compares two and is the check that matters — every model's seat,
  port and jack constant is a hand-measured position in the GLB's frame, so a round trip has
  to preserve names, hierarchy, world placement and image names. Note the GLBs are **Git LFS**,
  so `git show HEAD:<path>` yields a pointer: pipe it through `git lfs smudge` to get a
  baseline to diff against.
