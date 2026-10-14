# §2x — Game Boy cartridges

### 2x. Game Boy cartridges — one body, a moulded colour, a scraped sticker

`RetroCartridge` builds a `gb` cartridge (`.gb` and `.gbc`), and a `gbc` one the same
way (`GbCartShell.is_shell`; Game Boy Color is a secondary platform of the Game Boy
cores with its own tile and `roms/gbc/` folder, not an alias of `gb`), from
`imported-assets/carts/game_boy/gb_cart.glb`: the unbranded Quest
close export of the Codex Kirby's Block Ball model, 14,386 triangles, 57 × 65 × 7.5 mm,
connector on −Y and label on +Z, so it drops into the frame with no turn. The LODs are
Godot's own (`meshes/generate_lods`), not Codex's `_lod1` file. `MediaDimensions`' `gb`
size is the model's own, so it is not stretched.

**The shell** is chosen by `GbCartShell` from the ROM header (0x150 bytes, never
hashed), from `Resources/gb_cartridge_shells.tres`:

| Header | Shell |
| --- | --- |
| title `POKEMON_GLD` / `POKEMON_SLV`, Nintendo | gold / silver (metal flake), every market |
| title `DONKEYKONGLAND…` / `SUPERDONKEYKONG`, Nintendo | yellow: Donkey Kong Land, 2 and III, and Japan's Super Donkey Kong GB and Donkey Kong Land (its Land 2), every market |
| title `POKEMON RED` / `POKEMON BLUE` / `POKEMON YEL…`, Nintendo, destination 0x14A ≠ 0 | red / blue / yellow |
| same, destination 0x14A = 0 (Japan) | grey: the Japanese Red, Green, Blue and Pikachu were standard grey |
| CGB flag 0x143 = 0x80 (runs on both machines) | black |
| CGB flag 0xC0 (Game Boy Color only) | not this shell: the clear Game Boy Color one (below); grey if forced into this one |
| anything else | grey |

The titles are one per game across languages: every European Red is `POKEMON RED`,
every Gold `POKEMON_GLD` + a game code. Measured 2026-09-22 on every Pokemon ROM in
a No-Intro `gb`/`gbc` set: destination is 0 on every Japanese release and 1 elsewhere,
Korea included. Every value in the palette is a visual approximation; grey is the model's
own imported plastic, so the default is the model as authored.

The Land games use the old 16-byte title, so 0x143 is a title letter, not a CGB
flag: `DONKEYKONGLAND95`, `DONKEYKONGLAND 2`, `DONKEYKONGLAND 3`. A beta with a
garbled licensee stays grey.

Assumptions still open: Japanese Gold/Silver are coloured (the source checked says
nothing); the Japanese Land carts are yellow (sources name the series, not
the Japanese run); Japanese Pikachu is grey
like Japan's other first-generation carts.

**Painting.** `CartridgeColor` takes a system id (`apply_preset(cart, &"red", "gb")`);
N64 is the default and keeps its palette. The GB moulding is four materials:
`Gray_ABS_Textured` (front), `Rear_ABS_Rough`, `Gray_ABS_Smooth` (rails and bowl, one
mesh across both halves) and `Shell_Seam_Shadow` (the rim round the sticker).
`SHADE` keeps the model's own ratios to the front, 1.03 and 0.65, so the rim stays
darker than the shell in any colour and grey reproduces the model; `OWN_ROUGHNESS`
keeps each one's roughness. PCB, contacts, screw, cavity and label are never painted,
and `demetal` does not run (contacts and screw are metal).

**Forcing a shell**: held for a second, a `gb` or `gbc` ROM row opens
`_show_cart_spawn_options`, the N64's sub-menu with a Body row of the two shells
(Auto, Game Boy, Game Boy Color), then the swatches of the Game Boy palette and the
Game Boy Color one. The id lands in `RetroCartridge.shell_preset` (saved by
`scene_persistence`) and brings the body whose palette holds it (below); an id
neither palette holds, an N64 one included, is ignored and the ROM's own shell is
used. The sub-menu's Custom
colour (`shell_color`, `shell_flake`; see n64-cartridges.md) keeps the rim's 0.65
and the rails' 1.03 shade of it, and a flake mix takes the GB gold's flakes.

**The sticker**: the scraped `media/label/<rom>.png` is painted onto the UV-mapped
`Label` mesh (`_UV_LABELS`), which covers 0–1 with the image's top left at the
label's top left; the embedded 4 × 4 white is only a placeholder.

**The export leaves the rear shell unmapped** (876 triangles at one UV), the same
Blender bug as the N64 front shell: run `Tools/glb/fix_unmapped_uvs.py` on any
re-export. `gb_cart_tests` `uv/` fails otherwise.

`gb_cart_tests` (71 cases): resources, model, branding, uv, surfaces, color, flake,
kept, lookup, cartridge, forced. Mutation-tested: dropping the destination check, the rim
shade, or `gb` from `_UV_LABELS` each fail their own cases.

### 2x-gbc. The Game Boy Color-only cartridge — clear smoke, and Pokemon Crystal's clear blue glitter

A game that runs only on a Game Boy Color (CGB flag 0x143 = 0xC0) came in the clear
CGB-002 shell, not the Game Boy's: its own shape, with a raised head at the top of the
front and the board showing through. `GbcCartShell` gives such a ROM, `gb` or `gbc`,
one of two bodies in `imported-assets/carts/game_boy_color/`, both RetroXR-models/nintendo/gbc/cart/photos's
**debranded mobile LOD0** (own work, `LICENSE-gbc-cart.txt`):

| Body | Board | Picked for | Triangles |
| --- | --- | --- | ---: |
| `gbc_cart_large.glb` | DMG-KGDU-10, coin cell (the board inside Crystal) | a battery in the cartridge type at 0x147 (a game that saves) | 15,882 |
| `gbc_cart_small.glb` | DMG-A09-10, MBC5 only | everything else | 14,114 |

Real saving boards vary (only the MBC3 ones carry a clock crystal): the board is the
nearer of two, not the game's own. Both are 57 × 65 mm, 9 mm over the head and 7.2 mm
at the body, connector on −Y, label on +Z; `MediaDimensions.CART_SIZE_GBC` is that
size and `cart_size()` returns it for either body, so neither is stretched (the `gb`
and `gbc` rows stay the Game Boy shell's, which dual-mode games still spawn in).
Seated, the body's AABB centre is on the seat like any cart, so the flat body sits
0.9 mm off it, away from the head; in the detailed GBA's slot that leaves 0.30 mm to
the front wall and 0.35 mm to the back one (measured against RetroXR-models/nintendo/gba/console's
slot numbers, not probed), and the head starts 3.3 mm above the back wall.

The GBC-only Korean Pokemon Gold and Silver keep the Game Boy's shell in gold and
silver: a CGB-only ROM takes this body only when `GbCartShell` has no title shell
for it.

**The shell** (`Resources/gbc_cartridge_shells.tres`, palette id `gbc`):

| Header | Preset |
| --- | --- |
| title `PM_CRYSTAL`, Nintendo (new licensee `01`), every market | `crystal`: clear blue with metal glitter |
| any other | `smoke`: the standard clear smoke |

Assumption open: the Japanese Crystal (`BXTJ`) is the same clear blue.

**Clear glitter.** Crystal is a `METAL_FLAKE` preset with opacity below 1, which
`CartridgeColor` now paints as clear plastic with flakes in it, not as the solid flake
shader: both clear passes include `cartridge_clear_flake.gdshaderinc`, placing the
flakes exactly as `cartridge_flake_plastic.gdshader` does. The surface pass lights a
flake as a tilted mirror, fading to its average once a flake is under a pixel, and
the filter, drawn after it (the clear passes' fixed order, gba-cartridges.md), lets
the flake's light through untinted. `flake_amount` 0 is plain clear
plastic, so every other clear shell renders as before. A mixed metal-flake colour
borrows Crystal's flakes but is always solid (`flake_finish` sets opacity 1). A solid
metal-flake preset (the gold and silver) still goes to the solid flake shader.

**The export** (`RetroXR-models/nintendo/gbc/cart/export_retroxr.py`, from the saved .blend)
makes the shell solid, one smoke colour and no frost texture, so the preset does all
the clear work; the four moulding materials are `GBC_Shell_Front`, `GBC_Shell_Rear`
(stipple normal map, 10 mm per UV) and `GBC_Shell_Smooth` / `GBC_Shell_Edge` (the
polished lettering and ridges, which keep their own roughness when solid). Board parts
are renamed `Interior_*` so frost blurs them; `Contacts_32` stays sharp at the open
mouth. The front shell leaves 44 triangles unmapped per body: run
`Tools/glb/fix_unmapped_uvs.py --tile 10` on any re-export.

**The colours are fitted**, as the GBA's are: `Tools/models/gbc_cart_render_probe`
(`--fit`, windowed) lays each preset on the large board, label up, on white under flat
light, ortho from above at 10 px/mm (near/far 0.1-0.3 m), wearing the scraped label of
the cartridge photographed, and takes the per-channel linear median of the shell
outside the recess divided by the median of the label's pale side strips (the exposure
and white-balance reference; a red label's median is not). Targets from the same frame
of each photo: smoke `(0.268, 0.299, 0.220)` from RetroXR-models/nintendo/gbc/cart/photos IMG_1634 (an
Oracle of Seasons, whose ScreenScraper label the fit wears), Crystal
`(0.598, 1.067, 1.331)` from ScreenScraper's CGB-BYTE-USA photo. Fitted within 1 % on
every channel: smoke `#7e8587` opacity 0.75, Crystal `#a2c3d7` opacity 0.9 (re-fitted
2026-09-30 for the clear passes' fixed draw order). Opacity and
frost (0.45 both, so the glitter is not lost in cloud) are set from the photos, then
the colour is fitted. Re-fit rather than retune by eye.

`gbc_cart_tests` (102 cases): resources, model, branding, uv, surfaces, clear,
glitter, kept, lookup, size, cartridge, forced, menu. Mutation-tested: dropping the
CGB-only rule fails 12 cases, clear presets losing their glitter
fail 4, and dropping the Korean Gold/Silver exception fails 2.

### 2x-cgb. The Game Boy Color itself — a stand-in of its own

The `gbc` tile wore the Game Boy's shell until 2026-10-13: its registry row
(`game_boy_color_primitive`) loaded `game_boy_primitive.tscn`, whose script is
`RetroSystemModelGameBoy`, whose panel is `gameboy_lcd.gdshader`. **Every Game Boy Color
game was drawn in the DMG's four greens.** The row keeps its id, because saves and peers
name it, and now loads `game_boy_color_primitive.tscn` under
`RetroSystemModelGameBoyColor`, which sets no LCD shader: the handheld base's pixel-AA
default shows the picture in colour. The Game Boy's row and shell are untouched.

The shell is the CGB-001 as one box, 78 × 133.5 × 27.4 mm, in grape: a 44 × 39.6 mm
(160:144) panel high in its lens, the power lamp left of it (`PowerLED`, lit by the
model script on power), D-pad, A above and outboard of B, SELECT and START slanted the
way A and B are, and the speaker as a patch of face. Everything is named in the shared
stand-in vocabulary (`DpadBar1/2`, `FaceButton1/2`, `StartButton`, `SelectButton`), so
the handheld base animates it with no code here.

| Where | What | Note |
| --- | --- | --- |
| top edge, back | cartridge mouth, `CartSeat` | the base's pose moved 5 mm toward the back of the shell, as on the hardware |
| top edge, front | `IrWindow`, 8 mm square, glossy black | 0.5 mm proud so its face is not the shell's plane. Its child `IrPort` is the infrared link (port 1, beam along its -Z, out of the edge): two units whose windows can see each other are linked by `IrBus`, and the model script makes the window glow faintly while they are (`gb-link.md`, "In the room") |
| left flank | EXT `LinkPort`, then the volume slider below it | the socket is `R_y(-90)` written as rows, the transpose of the Game Boy's; the Game Boy's own plug family |
| right flank | power switch, up the edge is ON | |
| bottom edge | video-out lead, at the headphone jack | `configure_cable_attach` is overridden: the base moves a narrow body's lead to the right flank, which is where the switch slides |

The cartridge seat is why the window fits: seated on the body's mid-plane, as the Game
Boy stand-in seats one, a cart takes the middle of the top edge and the window has
nowhere to go but through it.

`Tools/models/game_boy_color_probe` settles each of those by a number (36 checks
headless: the row's scene with the `gb` row as its control, both facings of the panel,
the window proud of the edge and in front of the slot, the socket's `+Z`, the lead's
exit, the switch's throw, the lamp, the animated controls, and a cartridge seated
through `restore_cartridge()` standing 18.2 mm out, behind the window). Windowed it also
photographs the shell into `probe_out/gbc/`, the last frame beside the Game Boy:

```bash
"$godot" --headless --path RetroXR res://Tools/models/game_boy_color_probe.tscn
"$godot" --path RetroXR --resolution 320x240 --position 20,20 res://Tools/models/game_boy_color_probe.tscn
```

`romm_tests` `gbc/` pins it with five cases, mutation-tested: the row back on the Game
Boy's scene fails three, the window moved behind the slot fails one, and sunk inside the
shell fails one. `link_tests` walks its socket in the lead × socket matrix, and
`ir_tests` `machine/` pins the port: there, on link port 1, looking OUT of the edge its
window is on, the glow following its link. Nobody has held it in a headset or run it on
a Quest yet.

### 2x-cam. The Game Boy Camera — a cartridge with a head, and a ball a hand swivels

The Game Boy Camera is not a game in a shell: it is the cartridge, lens and all.
`GbCameraShell` knows it by the **cartridge type at 0x147, 0xFC** (POCKET CAMERA), which
no game has, and never by hashing. Measured on Game Boy Camera (USA, Europe): title
`GAMEBOYCAMERA`, type 0xFC, Nintendo (`01`), destination 1. Its body is a stand-in made of
primitives, `Scenes/Objects/media/game_boy_camera_body.tscn`, 110.4 mm long with a 30 mm
ball. **The head's proportions are from photographs, not from a measured unit.**

`GbcCartShell.body_model_for` answers the camera first: when the `camera` body is forced
(`GbCameraShell.BODY_CAMERA`, the hold menu's fourth Body choice on a `gb` or `gbc` row), or
when no body is forced and the header is the camera's. Either cartridge shell can still
be forced onto the camera's ROM. A forced *shell* only repaints it, where on a game it
would bring the body its palette belongs to. A mod's shells for the system still stand in
for all of it (`RetroCartridge.body_model_for` asks `ModCartShells` first).

**The overhang.** A body's child named `Overhang` (`RetroCartridge.OVERHANG_NODE`) is the
part of it that stands OUTSIDE the slot, and it is not in the cartridge's size:

- `_cart_model_aabb` leaves it out, so what is fitted is the cartridge that goes in, and
  `MediaDimensions.cart_size` needs no row for the camera: 57 × 65 × 7.5 mm, scale 1.
- `_add_overhang_shapes` gives it an `OverhangShape` on the cartridge (to rest on and be
  taken by) and one under `PointerArea` (to be aimed at), fitted to the meshes DIRECTLY
  under `Overhang`: its fixed housing.
- What is deeper is a moving part with a grab of its own. It gets an
  `OverhangMovingShape` on the cartridge, as it lies at rest, because the cartridge rests
  on it and is lifted by it (without one the ball sank 4 mm into whatever the camera was
  laid on), and **none to be aimed at**: a ray at it is for its own grab, which an aim box
  of the cartridge's would stand in front of.
- None of them is touched by the passes that rewrite the cartridge's own two shapes
  (`_apply_system_size`, `set_seated_grab_stub`, `reset_grab_shapes`), so in a handheld's
  slot the body is cut to its stub and the head stays in reach: it comes out by the head.

So the camera seats wherever a Game Boy cartridge does, with no seat code of its own.
`gb_camera_tests` `seated/` compares its pose with a game's in the same slot, in a Game
Boy Color (its own system's) and a Game Boy Advance (a foreign one, seated by the
connector): identical.

**Everything outside `Overhang`, the sticker included, must add up to the cartridge's size
exactly.** The first build laid the sticker 0.2 mm proud of a full-thickness cartridge:
the fitted bounds were 7.7 mm deep and the whole body, head and ball with it, was
squashed 2.6 % in thickness. The plastic under the sticker is 7.3 mm, 0.1 mm off centre,
so the sticker's plane is what ends the bounds.

**The ball stands on top of the housing with nothing either side of it, and swivels about
its UPRIGHT axle**: the lens swings round sideways, like a head turning, from the label
side to the back. That is the real one's motion (it "swivels horizontally"; the picture
stays the right way up when it is turned on the player). The first build was wrong
twice: it cradled the ball between two cheeks and tipped it over the top on a
`VRHinge`. A suite case holds the lens LEVEL through the whole turn.

- It is a `VRKnob` (`Overhang/LensKnob`, pivot `KnobPivot`), which turns its pivot about
  the pivot's own Z, so the knob is laid over to put its +Z along the cartridge's +Y:
  `R_x(-90)`, **written as its rows** (`1,0,0, 0,0,1, 0,-1,0`). In that frame the lens is
  on -Y, the label side. Written as the transpose the axle points down and the lens
  starts at the back; `body/the ball's axle stands upright` reads the basis.
- A `VRHinge` cannot do this from the pivot alone: Node3D's Euler order is YXZ, so the X
  a hinge drives is applied about the PARENT's X turned by the pivot's yaw only, and
  never leaves the parent's XZ plane.
- **Half a turn either way from the front**: `deg_at_zero` -180, `deg_at_one` 180, value
  0.5 at the front, 0 and 1 both the back, reached by the cartridge's -X and +X. **The
  real ball stops at the front and goes round one side only, and which side is not
  known here** (no source found says). When it is, it is one stop: set the front to an
  end of the range.
- At value 0.5 it looks the way the label faces, which is out of the back of the console
  once seated; at 0 or 1, at whoever is looking at the screen.
- It is taken on the **trigger**, the room's rule for a control on something pickable: grip
  takes the cartridge, by the housing or by the ball. Desktop: press the ball with the
  reticle and roll the wheel, ten notches front to back.
- **Saved and network-synced with no code here**: `ScenePersistence` and `NetObjectSync`
  both walk every `VRKnob` under a spawned object, and this one is at
  `CartModel/Overhang/LensKnob`. The save round trip is in the suite; a netplay session
  with one is OWED.

**Plastic.** Cartridge and head wear one material, `GBCamera_Shell`, listed in
`CartridgeColor.EXTERIOR_PLASTIC`. One ROM served every colour the camera was sold in, so
the header has no shell to give: it is the Game Boy palette's `blue`, and that palette's
other shells or a mixed colour repaint cartridge and head. The ball, the lens and the
sticker are never painted. The sticker is a `Label` quad, UV 0-1, so the scraped label is
painted on it like any Game Boy cartridge's, and the title stands in when there is none.

**It is a camera, on mGBA** (2026-10-14). The lens is a `GbCameraEye`
(`CartModel/Overhang/LensKnob/KnobPivot/LensEye`), a node a tenth of a millimetre outside
the glass. While the cartridge is in a running machine's own slot and the core has
STARTED its camera, the room is drawn from there into a 128 × 112 viewport and each
picture is handed to the core through libretro's camera interface
(`Libretro.PushCameraFrame`), which is what the game shows in its viewfinder and
photographs. Which way the ball is turned is now which way the game looks.

Where the eye looks:

- **Its basis is set in code** (`GbCameraEye.LENS_BASIS`, by columns), never typed into
  the scene, where it would be read by rows. The lens is the pivot's -Y and a `Camera3D`
  looks along its own -Z; its up is the pivot's Z, the axle, so the cartridge's +Y however
  the ball is turned. At the front its right is the cartridge's -X, which is the SCREEN's
  right once seated: the viewfinder is the room as seen through the console. Turned on the
  player it is a camera's view of them, not a mirror's.
- **The `Camera3D` lives under the eye's own `SubViewport`** (`Feed/Lens`), made the first
  time a core asks. Anywhere else it would be a camera of the player's viewport, and the
  first camera in a viewport becomes its current one. A viewport hands no transform down,
  so `_aim()` rebuilds the pose from the lens's look and up (`Basis.looking_at`, so a body
  fitted per axis carries no scale into the picture) each time it is armed, and the camera
  has physics interpolation OFF: posed from `_process`, an interpolated one is drawn where
  the lens was.
- **It follows the stand-in's lens, straight out of the ball.** The real ball is set at an
  angle so the lens looks ahead with the console held tilted; that is still not modelled.
  **The 43° it takes in, top to bottom, is an ESTIMATE**: Nintendo published no angle, and
  no source found gives the lens's focal length. One write-up measured the sensor at
  3.6 mm and SUSPECTED the lens of being a 35 mm-equivalent 35, which is about 4.1 mm; the
  game reads 112 of the sensor's 123 rows.

What it costs, and the rules that keep it there:

- **Never `UPDATE_ALWAYS`.** The viewport is armed `UPDATE_DISABLED` then `UPDATE_ONCE`
  (as `ScreenCastLight`) and the pass is read the frame AFTER, never waited for. One eye
  arms a process frame. No MSAA, `positional_shadow_atlas_size` 0, and the 3D scaling left
  alone (it breaks the mobile XR viewport).
- **So many pictures a SECOND, not one every so many frames**: `RATE_DESKTOP` 30,
  `RATE_MOBILE` 12 (one frame in six at 72 Hz). Counted in frames, the first probe run
  pushed 2947 pictures at a core that could take 2110, because a desktop window runs at
  whatever its monitor does.
- **It films for as long as a Game Boy Camera is switched on**, viewfinder or album.
  "Active" is `Libretro.IsCameraActive()`, the core having started its camera, and mGBA
  starts it as the game loads and stops it as the game unloads; the interface has no way
  to say a photograph is being asked for. Idling it would take a change in the fork. **A
  second pass over the room on a Quest is not measured**: its draw calls, the readback,
  the first-arm hitch, and how bright the picture comes out under the sRGB-view patch.

What mGBA does with the interface, read out of `libretro.c` and then measured:

- It asks for it on EVERY Game Boy load and starts it only for cartridge type 0xFC, so a
  core that merely asked is not active.
- It starts it inside `retro_load_game` and `retro_reset` and stops it inside
  `retro_unload_game`, not inside `retro_run` as libretro.h says, so `start` and `stop`
  only set a flag. It stops it as every Game Boy game unloads, started or not.
- **It frees its copy of the picture at every start, so every start redelivers.** With
  nothing delivered it starts the camera again on every photograph it is asked for
  (measured: 179 starts with delivery taken out) and takes none.
- **The picture must be exactly the size it asked for** (128 × 112,
  `GetCameraFrameSize()`). It centre-CROPS a larger one, and it copies `pitch` bytes a row
  into a buffer it regrows only when width or height grow, so a pitch that varied would
  write past its heap. `CameraStream` refuses any other size and always delivers at
  `width * 4`; the eye brings a picture to size before pushing.
- It turns the picture grey before it is seen, so **the channel order can be pinned only
  in the C++ harness** (`camera_stream_test`), never against the core.

In libretro-godot: `CameraHandler` (as long-lived as its `Wrapper`, like the microphones,
because the main thread pushes at it whether or not a core is up) and the Godot-free
`CameraStream.hpp`. The main thread only leaves a picture; **the core is handed it on the
emulation thread immediately before EVERY `retro_run`**, at the two call sites themselves
and not beside the audio status callback, which a replay after a rewind skips.

**The ROM names its core.** `GbCameraShell.boot_for` answers `{"core": "mgba"}` on a `gb`,
`gbc` or `gba` machine, through `ExpansionLaunch.expansion_boot()`, the way a Slot-2
cartridge names melonDS DS: ahead of the player's own pick, and only while it is in the
slot. Keyed on the ROM's header and not on the body, because a camera ROM forced into a
game's shell is still a ROM Gambatte cannot load: **Gambatte refuses cartridge type 0xFC
and the load fails**, so before this the camera did not boot at all in a Game Boy Color,
or in a Game Boy on a Quest. SameBoy runs the cartridge but asks for no picture. A zipped
ROM is not pinned (the header read sees the archive), the limit the body already has.

**mGBA is told which Game Boy it is** (`ForcedCoreOptions.game_boy_model`). The camera's
header says Super Game Boy enhanced (0x146 = 03), Autodetect makes mGBA a Super Game Boy,
and `mgba_sgb_borders` defaults ON: the picture is the TV border, **256 × 224 on a
handheld's screen** (measured, with the pin taken out). So `gb` pins "Game Boy", `gbc`
"Game Boy Color", and all three lose the border. A Game Boy Advance keeps Autodetect: the
model there would recolour every Game Boy cartridge on the core that machine runs by
default.

**Netplay: the camera runs for the host alone.** It photographs the room as one peer's
machine draws it, and no two draw it alike, so `RetroSystem.net_boot_spec` answers `{}`
for the camera's ROM and `_report_netplay_blocked` says why in words of its own. Lockstep
would need every core shown the same thing, which is the blank, and that is exactly what
`CameraHandler` hands a machine that is in a session anyway (as a microphone reads
silence there): the safety net for a camera console pulled in by a link cable. A real
two-peer session with one is OWED.

`Tools/cores/gb_camera_feed_probe` is the real core and the real ROM, windowed, in a
scratch home (it writes the cartridge's battery, so it refuses to run without
`retroxr/probe_home.txt` in the data root, which wants `libretro/cores/mgba_libretro.dll`
beside it). The room holds two black walls, one each side of the console, each with ONE
white quarter: up and to the right of the lens on the far side, down and to the left on
the near side. They are placed from the cartridge and the glass, never from the eye under
test, so a picture turned over or mirrored lights the wrong quarter of the viewfinder.
One core and one leg a process, and each control proves it reached the viewfinder:

```bash
USERPROFILE=<scratch home> "$godot" --path RetroXR --resolution 640x480 --position 20,20 \
    res://Tools/cores/gb_camera_feed_probe.tscn -- "--rom=<Game Boy Camera>"
... -- ... --away      # the ball turned half round: the OTHER target, not the first
... -- ... --nofeed    # the eye stopped, then the lens turned: the game goes on showing the first
... -- ... --system=gb|gbc|gba
```

Measured 2026-10-14 on Windows with the released mGBA v8, on a Game Boy Color that had
been given Gambatte: mGBA resolved and loaded, a 128 × 112 camera asked for and started,
a 160 × 144 picture, the viewfinder reached in three presses with the lit quarter reading
0.99 and the other three 0.00, about 295 pictures pushed and all but two or three handed
over, none refused. `--away` shows the other target; `--nofeed` goes on showing the
first with nothing more pushed, then follows the lens once the eye runs again. The same
on a Game Boy and a Game Boy Advance. Two faults were put in to see it go red: the model
pin taken out (256 × 224), and the delivery before `retro_run` taken out (nothing handed
over, 179 starts). **Keep the rig clear of the origin**: the lens films the window's own
world and the boot splash stands there, so the first run photographed "RETRO XR /
STARTING UP", legibly and the right way up. **In a headset, on a Quest, and with a second
peer it is all still OWED.**

`Tools/models/game_boy_camera_probe` (39 checks headless) twists the ball with a point
where a latched hand would be and seats the cartridge in a Game Boy Color; windowed it
photographs the camera into `probe_out/gb_camera/`, and `-- --film` writes the swivel as
frames for an mp4:

```bash
"$godot" --headless --path RetroXR res://Tools/models/game_boy_camera_probe.tscn
"$godot" --path RetroXR --resolution 320x240 --position 20,20 res://Tools/models/game_boy_camera_probe.tscn -- --film
```

`gb_camera_tests` (156 cases): lookup, body, cartridge, ball, saved, seated, menu, and
the camera's four: `eye/` (it looks where the lens points, the cartridge's top up, a
camera's right on its right, BY SIGN at four turns of the ball; just outside the glass;
its camera under a viewport of its own and the room's viewport with no camera gained),
`feed/` (a `FakeMachine` and a still of four unlike quarters: nothing for a machine that
is off or a core that has not started; so many a second; each corner where the still had
it; brought to the core's size and to RGBA8; a library with no camera in it never
called; a headless run draws nothing), `binding/`, and `core/` (the ROM names mGBA
whatever the machine was given, the model pin, the "Core not installed" card naming
mGBA, and the netplay refusal). No core runs in it. `camera_stream_test`
(`libretro-godot/tests`, 43 checks) is the delivery rule and the channel order.
Mutation-tested: 24 faults in the GDScript and 6 in the C++, each failing its own cases.

The body's cases are mutation-tested too, each fault failing its own. On the first build: the header rule
dropped, the head counted in the fit, no box for the head, the lens authored on the back
of the ball, the sticker proud of the cartridge's depth, the menu row gone, and the
camera painted as a game's shell. On the swivel: housing risen beside the ball again (4),
the knob's basis written as its transpose (17), no box for the ball to rest on (1), a
one-way range from an end stop (9), and the ball's box used as an aim box (1). Nobody has
turned the ball in a headset yet.
