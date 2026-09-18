# §2b — the bedroom's saved visual probe

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### 2b. The bedroom's saved visual probe

`RetroXR/Tools/models/bedroom_probe.tscn` — do NOT hand-roll another one. It carries the
still framings for that room (overview, bed, desk, window, TV corner, bookcases,
wardrobe, light switch) plus a flythrough: 360 deg in place at the room centre,
then a lap walking forward round a circle sized to clear the furniture.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20     res://Tools/models/bedroom_probe.tscn -- --mode=stills      # or flythrough, both
```

Windowed, not `--headless` — the dummy renderer returns a blank image. PNGs land
in `res://probe_out/` (gitignored). Encode a flythrough at 24 fps with imageio and
**pass `-crf 24`**: the default quality puts an 11 s clip at 21 MB, CRF 24 at 2 MB
with no visible difference.

It forces the ceiling-light energy to 0.6 on purpose. The scene authors 1.2 and
`QualityManager._adjust_lights` has not run that early, so a naive probe renders
the room brighter than any player sees it.

**Overwriting a texture in place needs a reimport.** A game run keeps serving the
cached `.ctex`, so two successive recolours of the bed's atlas appeared to do
nothing at all. Run `--editor --quit` between the overwrite and the render.
