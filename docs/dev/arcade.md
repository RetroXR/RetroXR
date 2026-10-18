# §2z — The arcade cabinet, its JAMMA board and the video geometry

## One system, many cores (2026-10-18)

Five systemids used to be named "Arcade (various)" in the Cores view — `mame`, `fbneo`,
`hbmame`, `daphne`, `dice` — while the room had ONE arcade machine. The tile followed the
EMULATOR, so the same `kof98.zip` could sit under two tiles, the names were identical and a
library was split by a choice the player never makes (they think "Street Fighter II", not
"a FinalBurn set"). The repo's own idiom is the other way round — the tile is the MACHINE and
cores are alternatives (gambatte/mGBA under `gb`; flycast serving `naomi` / `atomiswave` as
`secondary_systemids`) — and so is ES-DE's, whose arcade folders (`arcade mame fbneo fba cps*
model2/3 stv naomi* atomiswave …`) all carry `<platform>arcade</platform>` and each offer the
cores as a list (`neogeo` is the one platform of its own: FinalBurn Neo, **Geolith**, MAME).

Now: **`arcade`** is the one system for every MAME, HBMAME, FinalBurn Neo and FB Alpha core
(`SystemIds.MERGED` reads `mame` / `fbneo` / `hbmame` as it, wherever an old id still turns
up; `FOLDER_ALIASES["arcade"]` reads ES-DE's folders — `mame fbneo fba hbmame cps* model2 model3
stv mame-*` — and **never renames one**: `roms/mame/` holds the player's ROMs). `neogeo`
(Geolith + FinalBurn Neo as a secondary), `naomi`, `naomi2`, `atomiswave`, **`daphne`
("Arcade (Daphne)") and `dice` ("Arcade (DICE)")** stay systems of their own: the test is whether a
family has a core of its own, a BIOS / media of its own, or a different physical machine —
otherwise it is a folder alias of `arcade`. The names come from `CoreInfoDatabase.SYSTEM_LABELS`.
Every one of these was a cabinet in real life (Neo Geo AES, the home console, is why `neogeo`
is separate: MVS = cabinet with a cartridge bay, AES = console, same zips), so what changes between
families is the BAY (JAMMA today; JVS, MVS) and a cabinet scene, never a systemid.

- **Which emulator plays a set is the core's choice**, recommended `mame` (desktop) /
  `mame2003_plus` (Quest) — `CoreRecommendations["arcade"]`; FinalBurn Neo is picked by netplay
  (`NetplayCores`) because it is the one core vetted for rollback. A romset is built for ONE
  emulator version: a set a core refuses is the "This core refused the game" path below.
- **Saves are per CORE** (`SramPaths.PER_CORE_SYSTEMS` has `arcade`): MAME's and FinalBurn Neo's
  NVRAM / EEPROM layouts differ, and keyed by the system two cores would share one file.
- **Known limit — RomM.** A server's `arcade`, `mame`, `fbneo`, `cps2`… platforms all map to
  `arcade`, and `RommPlatforms.collapse_by_systemid` keeps the BIGGEST library and reports the
  rest as not shown (fixed by a `platform_overrides` entry), as it already did for the nine slugs
  that filed under `mame`. The sync is one `platform_id` and one index per systemid
  (`RommCatalog.sync_platform`), so merging several platforms is a catalogue change, not a
  mapping one. OWED.
- `mess2015` / `ume2015` (systemid `mame` in libretro's database, "Multi (various)") and the
  Neo-Geo-only builds `fbneo_neogeo` / `fbalpha2012_neogeo` followed their `.info` into `arcade`;
  none of them has been moved to a better tile.

Issue XargonWan/RetroXR#1. `mame` and `fbneo` (now both `arcade`, see below) used to be data only: a generic box, a
generic pad and a ROM spawned as an anonymous cartridge slab. They now play in a
**Generic Arcade Cabinet**, and a ROM is drawn as a **JAMMA board**.

## What a cabinet is, in code

A real cabinet is a monitor, a control panel, a coin mechanism and a JAMMA harness; the
board is the computer. Modelling that literally means video and input flowing from a
"remote" machine to the cabinet, which is far bigger than the base concept, so **in code
the cabinet is the `RetroSystem` and the board is its media**, the way a handheld is its
own machine and a cartridge its media. For the player it is the same: pull the board and it
powers off (the existing cartridge-deck behaviour), a coin is a credit. The registry id
`arcade_cabinet_generic` is persisted in saved rooms and on the netplay wire (`ArcadeProfiles.CABINET_MODEL_ID`):
it is final. "Board = machine" stays open as an evolution and breaks nothing saved.

The cabinet draws its own body (`brings_own_body`), has its own screen and no video-out
lead (`_OWN_AV_LEAD` in `spawn_catalog.gd`), and is too big to hold: `spawns_on_floor()`
makes the spawn menu stand it a stride away on the floor instead of handing it to a hand,
and it is NOT locked: the player can pick it up and carry it, but only by **holding the grab on
it for one second** (`HoldToGrab`: a ring fills, around the crosshair on desktop and at the hand in
VR; an object opts in by answering `grab_hold_seconds()`, so a stray squeeze or click never carries a
1.8 m box off). While it is in a hand it is **see-through** (`GeometryInstance3D.transparency`, dithered
per instance: no sorting or blending of a huge surface, no material to swap) so the room behind it can be
seen. Only yaw is free (`axis_lock_angular_x/z`), so one set down off-level does not tip onto its
marquee; the lock in the object's options still pins it where it stands. Origin on the floor at the centre of the base, front toward +Z,
0.66 x 1.80 x 0.87 m.

## The module contract (`ArcadeProfiles.CONTRACT_VERSION` = 1)

`RetroSystemModelArcadeCabinet` owns nothing specific to one cabinet. It collects every
`ArcadeModule` in its scene **by type** (never a node name) and each says what it is.
**Additive only**: a kind or a field may be added, never renamed; a cabinet missing an
optional module is valid. A module finds ITS OWN parts by name inside its own subtree.

| kind | script | parts it finds | what it does |
|---|---|---|---|
| `screen` | `ArcadeScreenModule` | `CabinetScreen` (quad) | paints the core's picture, fitted to the glass by the bridge's geometry (below) |
| `stick_buttons` | `ArcadeControlModule` | `Btn1`..`Btn6`, `Start` (caps), `StickPivot`, `PanelGrip` | one player's panel as ONE controller: the caps sink and the stick leans with the input; nothing on it is poked one by one |
| `coin` | `ArcadeCoinModule` | `CoinSlot` (VRButton), `CoinSpawn`, `CoinDrop` | a coin is tossed along an arc, drops with a sound, and ONLY THEN says `coin_inserted(player)` |
| `bay` | `ArcadeBayModule` | `DoorPivot`, `DoorGrab` (VRHinge), `CartSeat`, `JammaSocket`, `PowerSwitch` | the lower door gates the cartridge slot; the door angle is the saved `lid_angle` |
| `sockets` | `ArcadeSocketModule` | `PortSeat1..N` | the front controller / light-gun sockets: places the system's own port zones |

`ArcadeProfiles` (`Scripts/Data/systems/arcade_profiles.gd`) is the data: `BAY_KINDS`
(`jamma` -> `arcade`), which joypad bit is which, the coin pulse length. A mod adds
a bay kind with `ArcadeProfiles.register_bay_kind` (no `ModApi` wrapper yet).

**Adding a cabinet.** Cheapest first: (1) **a scene only** (1P, 4P, cocktail, tate) from the
same modules, as a registry row (or a mod's `register_model` / `override_model`); (2) a new
module kind (trackball, wheel + pedals, seat, card reader); (3) a data row; (4) a new bay
host (a Neo Geo MVS, JVS boards), which should reuse the repo's "unit in a bay" machinery
(`ExpansionCatalog` hosts, `expansion.gd`) rather than invent a second one.

The scene is **baked** by `Tools/gen/gen_arcade_cabinet.gd` (and the board by
`gen_arcade_board.gd`, helpers in `arcade_gen_util.gd`); re-run it to change the geometry:

    "$godot" --headless --path RetroXR --script res://Tools/gen/gen_arcade_cabinet.gd

Run `--editor --quit` first when you add a `class_name`: `--script` mode reads the class cache.
The materials go on the MESH, not as `material_override`, so a later surface override (a
board's sticker) is not shadowed. It is low detail on purpose: an example to be consolidated
by hand. No arcade model existed in the sources the project already uses (the only cabinet
found, Kenney's CC0 Mini Arcade in RetroQUEST, is a single toy mesh with no door or screen
to separate), so it is procedural; a GLB that keeps the module nodes replaces it.

## The JAMMA board

JAMMA (1985) is the cabinet wiring standard: a **56-contact edge connector**, 28 a side at
3.96 mm (about 111 mm of comb), into the harness's female connector. A board is therefore a
flat PCB with a gold comb on one short edge, chips and connectors on top, and no shell.
`Scenes/Objects/media/arcade_board.tscn` is one that stands for all of them (real boards
were every shape): 200 x 300 x 35 mm, `CART_SIZES["arcade"]`, cartridge frame
(connector on -Y, label on +Z), a `Label` sticker UV-mapped 0..1 that `CartridgeLabel` paints.
The label shows whatever the existing path gives (art in `<roms>/<systemid>/media/label/`,
else the printed title). **No new scraping.** Per-game boards are a later evaluation.

The board stands in the socket facing the front; the slot is gated by the door and keyed by
`systemid`, like any cartridge ("JAMMA" is the contract for future bays, not a connector
type). The ROM is the `.zip` romset the core reads as-is (`RomCompat`): it is never unpacked.

## Input

**A player's panel is ONE controller you attach to** (`ArcadePanelGrip`, an Area3D over the stick and buttons): aiming
at the panel lights the WHOLE of it, player 1's or player 2's, whichever you aim at, as aiming at a controller lights the
controller; a press (a desktop click, the laser's trigger, a squeeze with a hand over it in VR) attaches you to it, as to a
pad you do not pick up, and another press lets go. Attaching to one panel lets go of the other (one controller plays one
player), and switching the machine off lets go. While attached, your OWN controller drives that player: the VR controllers
through the per-system `ControllerBindings`, the selected physical pad merged in, and the keyboard behind `ScrollLockCapture`
(`ArcadeInput` is an adapted copy of `HandheldInput`'s forwarding, which assumes the machine is in the hand); WASD and the
thumbsticks stop moving the player. The caps and the stick are pictures of what reached the core. A stick you cannot feel under
your hand is no fun in VR, which is why nothing is grabbed or poked button by button. Everything leaves through `NetworkManager.netplay_route`, then `SetJoypadState`: bypassing it
breaks lockstep.

**The pointer.** A ray stops at the nearest thing on the pointable layer, and the widgets share it with the
cabinet's `PointerArea`. One box over the whole cabinet therefore hid every door, button and coin slot
behind its front face (the desktop reticle selected the whole cabinet instead of the button). The
pointer boxes stand BEHIND everything that can be operated (`_build_pointer_shapes`: the lower block
behind the door's back face, the apron behind the sockets, the deck behind its back edge) and leave the bay
open, so a ray reaches the door's handle, the coin slot, a player's panel (as one thing), the power switch and the board's seat.
The door's `DoorGrab` rides the door (a child of the pivot), so an open door can still be taken hold of.
The door's `DoorGrab` covers only the HANDLE STRIP along its top edge: a box over the whole door made most
of the front a door, and aiming anywhere there worked the door instead of picking the cabinet up
(`Tools/models/grab_map_probe` prints what a pointer aimed at each point would do). A slab behind the SHUT door
(`PointerDoor`, off while it is open) makes a ray at it find the cabinet, not the board behind it.
A hold-to-grab survives the aim wandering off for `HoldToGrab.AIM_GRACE` (0.35 s) while the control stays down.
**The options panel** stands to the cabinet's RIGHT at eye height (`options_panel_anchor`, a hook any tall machine
can use; the default is over the hardware's top, 2.5 m up for a cabinet), and the **System tab has a core
picker** (`CoreOptions2D.populate_cores`, a `VRDropdown`): the installed cores that serve the machine's system,
plus "Default" (the CORES panel's choice). The pick is the machine's own `core_name`, saved with the room;
changing it switches a running machine off first.
**Notices** (a refused game, an achievement) float in FRONT of the monitor, clear of the cabinet (`toast_anchor`
-> `RetroSystem.toast_anchor_world` -> `AchievementToast._place`): laid over a tilted monitor and a marquee a
toast is half inside the geometry. Any machine can name a spot the same way; the default is unchanged.
**The monitor** is tilted back about 18 degrees, so the picture looks up at the player, behind a translucent pane of glass in a black frame, as on a real cabinet. Notices hang PARALLEL to it (a `Transform3D` from `toast_anchor`, half a metre off the glass).
**Power** is the generic power button, seated inside the bay on the shelf beside the JAMMA socket (labelled
POWER): open the door, press it, and the machine starts
the board in the bay with the core of its system, as any machine does.

**A controller seated in a front socket owns its port**: the cabinet sends nothing for it, so
two writers never fight over one `SetJoypadState`. `port_count_is_fixed()` makes the
cabinet's own count (two) win over `SystemInfo.native_ports` (four).

**The coin is the only way to insert a credit.** It is a mesh tweened along an arc: no physics
body, not in `spawned`, never saved. When it drops, the coin door says so and `ArcadeInput` holds
the coin bit for 0.1 s on that player's port. The bit is `SELECT` (`ArcadeProfiles.COIN_BIT`),
where MAME and FBNeo read it on a RetroPad; **that is the standard guess and is not confirmed
against the cores' input descriptors**. Coins are infinite and uncounted. The sound is
synthesised (no recording exists); the `hardware-sfx` workflow replaces it.

## Video geometry and the libretro bridge

Raised by the maintainer, and true: the core's display shape never left C++. What was there:
rotation is applied by the bridge (`SET_ROTATION` -> `VideoHandler::SetRotation`; `QueueFrame`
rotates and swaps width and height, so a vertical game arrives as a PORTRAIT texture, a new
`ImageTexture` whenever the size changes); but `retro_game_geometry.aspect_ratio` was only
logged, and every screen assumed its own shape (`RetroTV` is a fixed 4:3 / 16:9 toggle). So a
rotated core was ALREADY shown stretched on a television. Arcade pixels are not square (CPS1:
384 x 224 for a 4:3 tube), so the frame's pixel ratio is the wrong answer anyway.

Now (`libretro-godot/src/VideoGeometry.hpp`, header-only and Godot-free, tested by
`tests/video_geometry_test.cpp`):

- `Libretro.GetVideoGeometry()` -> `{width, height, aspect, rotation, base_width, base_height,
  core_aspect}`; `GetVideoGeometrySerial()` moves whenever the answer would change, so a
  screen asks one integer a frame. `width`/`height` are the pixels GDScript receives, AFTER the
  rotation; `aspect` is width / height of the glass the picture is meant to be SEEN in.
- `DisplayAspect` takes the MAGNITUDE from the core and the ORIENTATION from the frame the bridge
  produced, so it is right whichever way a rotating core reports its aspect (before or after its
  own rotation; libretro does not say). 4:3 and 3:4 are the same shape either way.
- The initial geometry is read at load (`WrapperEmuThread`), and every `SET_GEOMETRY` /
  `SET_SYSTEM_AV_INFO` and rotation change updates it; the data is mutex-guarded (the emulation
  thread writes, the main thread copies).
- The rotation transform was lifted out of `QueueFrame` unchanged into `TransformFrame`, and
  pinned against an independent quarter-turn oracle: libretro's rotation 1 is 90 degrees
  COUNTER-clockwise, and the `flip_y` interaction (a GL framebuffer is bottom-up) is right.
- `ArcadeScreenModule` fits the picture inside the glass with the shader's `fit_scale`
  (`Shaders/arcade_screen.gdshader`; the TV tube shader is tied to `RetroTV`'s derived uniforms
  and is not reused). A build with no `GetVideoGeometry` (a platform not rebuilt) degrades to the
  frame's orientation and a 4:3 tube, with a warning, rather than failing at call time: **rebuild
  windows AND android**, the binaries are per platform and gitignored (`CLAUDE.md`).

`Tools/models/arcade_cabinet_probe` (windowed) feeds the glass a test card drawn for a TUBE
(round on 4:3, an ellipse in pixels): it reads as a circle on a landscape frame and, pillarboxed,
on a portrait one.

Not done: feeding the same geometry to `RetroTV`, so vertical games stop stretching on a
television. Measured on no real core yet: whether FBNeo / MAME / mame2003+ report the aspect
before or after their own rotation (the code does not depend on it), and the rotation on a real
vertical romset (software and hardware paths).

## Board art, cores, and the merged `arcade` id

**The sticker.** ScreenScraper's `support-texture` for an arcade game is a render of its CABINET, and the
scraper used to put it in the label slot, so every board wore the cabinet. Now the scraper does not take it
for arcade games (it takes a `support-2D` label when there is one, `ScreenscraperClient._extract_media_urls`)
and a board's sticker takes the COVER first: the front of the `box-texture`, which is the box laid flat (the
right-hand end, `ArcadeProfiles.front_cover`), then whatever label was scraped, then the printed title
(`MediaDimensions.load_label_texture`). Files scraped before that still hold the cabinet in `label/`; the cover
wins over them, and a re-scrape fills the label slot properly.

**One `arcade` system.** `mame`, `fbneo` and `hbmame` are the one `arcade` system now (`SystemIds.MERGED`,
`canonical()`): the cabinet, the board, the sizes and the cores are all keyed on `arcade`, and every comparison
in the arcade code goes through `canonical()`, because a saved room, a binding or a core's `.info` may still say
`mame`. Comparing the raw strings is what left every arcade core out of the cabinet's core picker: the cores say
`arcade` and the machine said `mame`. The picker lists every installed core that can run a romset
(`RetroSystem.core_serves_machine`): MAME, FBNeo, the older MAME and FBAlpha cores.

## A game that will not start

A MAME / FBNeo set often needs files that are NOT in its own zip: a BIOS (`cps2.zip`, `neogeo.zip`) or a
device ROM set (`qsound.zip`, for every CPS-2 game with the QSound chip), which the core looks for in the
same roms folder (`roms/mame/`). Without them the core refuses the game, and the player used to be told only
"This core refused the game". The bridge now keeps the last ERROR lines the core reported
(`LogHandler::RecentErrors`) and adds them to the reason, so the toast reads
`This core refused the game. | dl-1425.bin NOT FOUND (tried in qsound_hle qsound dino) | ...`, plus a line for
arcade systems saying where such sets go (`RetroSystem._on_content_load_failed`). The files themselves are the
player's to supply; RetroXR does not download ROM sets. `Tools/cores/arcade_load_probe` (needs a real core and
a romset) starts a set in the cabinet and prints the reason. Cadillacs & Dinosaurs (`dino.zip`) is the case that
found it: it wants `qsound.zip`.

## The title on the board

A cartridge with no art prints its title with a `Label3D` (`GameLabel`) placed on the model's label face
(`_title_on_model_face`). `RetroCartridge._apply_system_size` runs again on EVERY drop and every leave of a
handheld's slot, and used to put that label back where the old procedural box had it, 3 cm off the board, so
the title came away from the sticker the first time the cart was put down (any model with no art). It now
leaves the title alone once a model's label owns it.

## Tests, probe

`Tests/arcade_tests.gd` (groups `profiles input screen bridge board registry cabinet door seat
card ports coin keep`); each case was broken and watched go red. `libretro-godot/tests/run_tests.py`
runs `video_geometry_test.cpp`. The probe photographs front, three-quarter, panel, the bay with a
board and the door open, the monitor in both shapes, and a coin in the air. **A GLB-less checkout
(Git LFS not pulled) cannot run suites that need a console's GLB**; the arcade suite does not.

## OWED

A headset and a Quest; a real game with a coin, START and the stick (no arcade ROM was available
here, so the bridge's geometry was measured on no real core); two peers in a session (the door
hinge and the input route are the existing paths, and are untested in a session); a light gun in
a front socket (a pad was seated; the gun shares the connector rule and is only offered); real coin
and door sounds; GLBs; the Neo Geo MVS (a bay host, not a cabinet); per-game boards and scraped
board art; a `ModApi` wrapper for bay kinds; a grabbable stick behind a "physical controls" option
(off by default); the geometry for `RetroTV`.

**Attaching claims the keyboard (2026-10-18).** `ArcadeInput` first copied `HandheldInput` but not the two things that made a pad's keys arrive: the system's key map in the global InputMap (`DesktopBindings.apply_for_system`, applied only while the capture holds it, as `RetroController._sync_desktop_scope`) and the capture itself. A pad needs Scroll Lock/F3 as well, but a panel you pressed has no other way to say it, so `_on_attach_changed` turns the capture on (`ScrollLockCapture.set_active(true)`; it needs the machine powered, which is why a panel attached to a machine that is off lets go). Pinned by `arcade_tests attach/` (a key plays only the attached player's port).
