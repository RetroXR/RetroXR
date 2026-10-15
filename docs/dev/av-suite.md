# §2c — the A/V suite

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### 2c. The A/V suite — the one thing here that is an actual test suite

`RetroXR/Tests/av_tests.tscn` — 62 cases over what reaches a television's inputs and
what it shows. Headless, ~90 s, **exits non-zero on failure**, so it is the one probe
that can be run as a gate rather than read.

```bash
"$godot" --headless --path RetroXR res://Tests/av_tests.tscn
"$godot" --headless --path RetroXR res://Tests/av_tests.tscn -- --only=display
```

Groups: `routing/` (real TV + VCR + composite leads — cords into the wrong sockets, a
crossed pair, two leads on one deck, a cord pulled — and, under `wiring/`, the aerial,
the RF switch's ANT socket and the Famicom's CH1/CH2 slide, see `tv-aerial.md`), `display/` (which input is shown,
what a blank input paints, a source that stops, a set switched off, snow on an
untuned aerial channel, a VGA monitor with no phono row, a source's own shader
stage, two sets sharing one machine), `guard/` (`can_paint` / `paint_screen` /
`release_screen`) and `audio/` (only the selected input is heard; a machine wired to
nothing is silent). Every case is a bug that shipped at least once.

Three things it took to make routing cases behave, all of them real behaviour rather
than test scaffolding:
- **Pulling a plug needs the whole panel shut.** Dropping one leaves it standing in a
  60 mm grab zone with four video sockets 18 mm apart around it, and the log reads
  `pulled VIDEO on TV` immediately followed by `seated VIDEO on TV`. `_unplug()` shuts
  every RcaPort in the room for the move.
- **And the plug frozen.** A live one falls back down past the panel and is caught by a
  socket on the way, ending up a perfectly good picture cord in the wrong input.
- **The phosphor accumulator hides the source.** With persistence on, the CRT material's
  `source_tex` is the ping-pong buffer, so the oracle is the set's own `_crt_source_tex`.

It is mutation-tested: reverting the deck to reading one cable, disabling the paint
guard, or restoring the frozen-frame bug each fails exactly the cases that name them.
Adding a case that cannot fail is worse than no case, so break the code and watch it go
red before believing a new one.

### A light gun aims at the picture, not at a plane (2026-10-15)

`LightGun` used to meet a flat plane through the screen mesh's origin and read x and y
off the mesh's bounds. The origin is the tube's RIM, and the glass bulges in front of
it (the stock tube 9 mm, the Panasonic CT-20D10B's 24.9 mm), so a ray from above ran
on past the point aimed at and the core was told a point below it. From a standing
desktop eye (1.65 m) 1.5 m from the Panasonic that was 40 px low on a 448-line frame,
61 px at 1.0 m, with a sideways error to match when standing off-axis. The stock set
added up to 11 px across: its 1.4:1 glass carries a 4:3 picture shrunk by `fit_scale`,
which the bounds knew nothing about.

`ScreenAim` (`Scripts/Objects/peripherals/screen_aim.gd`) meets the ray with the
glass's own triangles (`TriangleMesh`), interpolates the UV where it lands and runs it
through the CRT stage's own sums, `crt_warp` then `fit_scale`, read off the material on
the glass. A miss, a bar, or the glass seen from behind is offscreen. `LightGun` looks
it up every frame and rebuilds it only when the set or its tube changes. Three
`TriangleMesh` traps it met:
- **The triangle test is not watertight.** A ray straight down an edge two faces share
  meets neither; both tubes are grids with edges on the picture's centre lines, so the
  top middle of the picture fell through. A miss is retried 10 µm off the edge.
- **The returned normal faces whoever asked**, so it cannot tell front from back. The
  face's own normal, turned to +Z (every face of a tube bulging toward the player leans
  that way), is the front.
- `intersect_segment` falls through the same cracks; it is no way round the first.

`display/a light gun is told the picture point it is aimed at` holds the stock set to
half a pixel from a raised, off-axis eye, and to offscreen behind, past the edge and on
the bar. `Tools/av/lightgun_aim_probe` (headless; `--shell=` any installed cabinet,
`--curvature=`) prints the old plane's error beside the new one for six eyes and fails
if the control shows none: Panasonic 61 px → 0.12, stock 26 px → 0.11. Dropping the fit
or the warp from `ScreenAim` fails it (13.7 and 24.4 px). The Wiimote's pointer
(`wiimote.gd`) still meets the old plane.
