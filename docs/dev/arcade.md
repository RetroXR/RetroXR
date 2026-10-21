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
**Primitive Arcade Cabinet**, and a ROM is drawn as a **JAMMA board**.

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
lead (`_OWN_AV_LEAD` in `spawn_catalog.gd`). **Spawned, it is handed to the hand that asked for it, like any machine, and the
player stands it where they want it** (`spawns_on_floor()` is false; it used to be set on the floor a stride away, and the
hook stays for a model that wants it). It is NOT locked: it is carried by **holding the grab on it for one second** (`HoldToGrab`:
a ring fills, around the crosshair on desktop and at the hand in VR; an object opts in by answering `grab_hold_seconds()`, so a stray
squeeze or click never carries a 1.8 m box off; a spawn hands it over directly, no ring). While it is in a hand it is **see-through**
(`GeometryInstance3D.transparency`, dithered per instance: no sorting or blending of a huge surface, no material to swap) so the room
behind it can be seen. **A cabinet always comes to STAND**: its centre of mass is low (`CENTER_OF_MASS_Y`, the base and the board,
not the marquee) and, while nobody holds it, `_physics_process` turns it back upright about the horizontal at a rate proportional to
its tilt (`right_angular_velocity`, capped), leaving its HEADING alone. Released upright it stays upright; released leaning, or let
fall, it rights itself. The old yaw-only axis lock kept whatever tilt it was let go at, which is why it was dropped. A frozen or
locked cabinet is never touched: the lock in the object's options still pins it where it stands. Origin on the floor at the centre of the base, front toward +Z,
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
**The monitor** is built as on a real upright: the glass IS the cabinet's own slanted front edge (the side silhouette `PROFILE` runs from the control deck up to the marquee along it, so the pane lies ON that edge, never in front of it as a floating pane and frame), the tube sits `TUBE_DEPTH` (7 cm) behind the glass and the picture is painted on its face, and the whole monitor leans back about 27 degrees (`arcade_tests` pins all three: glass on the silhouette within 1 cm, picture more than 5 cm behind it, lean 20-35). The marquee overhangs only a little and is closed underneath (`MarqueeUnder`). Edit `Tools/gen/gen_arcade_cabinet.gd` (`GLASS_A`, `GLASS_B`, `TUBE_DEPTH`) and re-bake; the `side` shot of the probe shows it. Notices hang PARALLEL to it (a `Transform3D` from `toast_anchor`, half a metre off the glass).
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
found it: **current MAME** wants `qsound.zip`; FinalBurn Neo has the QSound DSP built in and runs the same zip. `arcade`'s default core is FinalBurn Neo on desktop (2026-10-20: the most games that start at once; MAME runs more sets but wants its own romset version and device ROMs), so pin the core anyway with `--core=fbneo|mame`. The probe's `--audio` (with `--play` for a coin and START) prints the loudest bus peak: a silent attract screen reads -200 dB and is not a fault (dino on FBNeo: -200 dB until a coin and START, then -14 dB; Bubble Bobble and SF2 sound at once). Needs a windowed run and the probe's own camera: a 3D voice nobody listens to also reads silence.

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

## Performance

How much a cabinet costs, what grows over minutes (nothing, measured), and what was kept: `performance.md`,
"Arcade cabinets". The probes are `Tools/perf/arcade_scale_probe`, `arcade_soak_probe`, `arcade_mesh_census`.
`ArcadeShadowBudget` (parts under 10 cm cast no shadow) runs when a cabinet, a bay unit or a board is built; `arcade_tests perf/`.

## OWED

A headset and a Quest; a real game with a coin, START and the stick (no arcade ROM was available
here, so the bridge's geometry was measured on no real core); two peers in a session (the door
hinge and the input route are the existing paths, and are untested in a session); a light gun in
a front socket (a pad was seated; the gun shares the connector rule and is only offered); real coin
and door sounds; GLBs; the Neo Geo MVS (a bay host, not a cabinet); per-game boards and scraped
board art; a `ModApi` wrapper for bay kinds; a grabbable stick behind a "physical controls" option
(off by default); the geometry for `RetroTV`.

**Attaching claims the keyboard (2026-10-18).** `ArcadeInput` first copied `HandheldInput` but not the two things that made a pad's keys arrive: the system's key map in the global InputMap (`DesktopBindings.apply_for_system`, applied only while the capture holds it, as `RetroController._sync_desktop_scope`) and the capture itself. A pad needs Scroll Lock/F3 as well, but a panel you pressed has no other way to say it, so `_on_attach_changed` turns the capture on (`ScrollLockCapture.set_active(true)`; it needs the machine powered, which is why a panel attached to a machine that is off lets go). Pinned by `arcade_tests attach/` (a key plays only the attached player's port).

**The keyboard layout and the speakers (2026-10-19).** A cabinet with no key map of its own plays from `ArcadeProfiles.DESKTOP_KEYS` (MAME's: Ctrl, Alt, Space, Z, X, C for the six buttons, START on 1, the coin on 5), applied by `DesktopBindings.apply_for_system` after the global layer and only when the player has saved no map for `arcade`. The stock map put the buttons on the numpad and the coin on Shift, so a keyboard with no keypad could not hit a button. Pinned by `arcade_tests input/` (no two actions share a key; the six buttons and START and the coin have one). **Speakers:** a cabinet's sound comes from a stereo pair in its own front, `SPEAKER_L`/`SPEAKER_R` (x ±0.22, y 0.34, z 0.44, facing the player), on the apron and kick panel either side of the coin door, and `SystemAudio` uses them when no TV is connected (it used to be the middle of the body, 9 cm apart). Upright cabinets carry a stereo pair low in the front; JAMMA itself is one mono channel, so a mono board drives both speakers at once. There is no centre or sub: that is not a cabinet layout. Pinned by `arcade_tests cabinet/` (a pair, left and right, low and in front). The wiring in `SystemAudio` is NOT pinned by a case; listening is OWED.

**BIOS and device sets are firmware (2026-10-19).** RetroXR knows a BIOS only if the core's `.info` declares it (`FirmwareRequirements`), and finds it on RomM's firmware list by file NAME (`RommFirmware`). FinalBurn Neo's declares 23 (all optional); MAME's vendored `.info` declared none, so `neogeo.zip`/`qsound.zip` were nowhere on the BIOS list and nothing could download them. `libretro-core-info-retroxr/mame_libretro.info` (a whole copy plus a firmware block) now declares fifteen, all optional and all `mame/bios/<name>.zip`: MAME searches the ROM folder, `SYSTEMDIR/mame/bios` and `SYSTEMDIR/mame/roms`, and a stand-in `neogeo.zip` in `system/mame/mame/bios/` was found by the core (the error changed from NOT FOUND to WRONG LENGTH, measured). The set follows FinalBurn's plus `qsound.zip` (every QSound game and every CPS-2 one, MAME only: FinalBurn has the DSP built in) and `stvbios.zip`. Which sets a given game wants is MAME's own information and is NOT derived from file names; a refused game still names the missing files in its notice. The notice now also fires for FinalBurn's "is required" wording. Pinned by `arcade_tests profiles/` (the overlay removed turns three cases red). Whether the files really arrive from a RomM that holds them is OWED: no server was reachable.

## The other cabinets (2026-10-19)

The generic upright is one of six, all the same shell: **never a fork of the model script**, only a scene (baked by
`Tools/gen/gen_arcade_cabinet.gd -- --variant=<name>`, the variants are DATA in `_variants()`) and a registry row
(`model_registry.gd`; THE IDS ARE PERSISTED). Generic stays first of the `arcade` rows, so it is the tile's default.

| id | system | panel | bay | guns |
|---|---|---|---|---|
| `arcade_cabinet_generic` | `arcade` | stick + 6 buttons, x2 | `jamma` | sockets |
| `arcade_cabinet_lightgun` | `arcade` | START alone, x2 | `jamma` | 2, holsters; pedal drawn |
| `arcade_cabinet_neogeo` | `neogeo` | stick + 4 buttons (A B C D), x2 | `mvs` | sockets |
| `arcade_cabinet_daphne` | `daphne` | stick + the sword button, x1 | `laserdisc` | sockets |
| `arcade_cabinet_daphne_gun` | `daphne` | START alone, x2 | `laserdisc` | 2, holsters |
| `arcade_cabinet_dice` | `dice` | a paddle dial + START, x2 | `discrete` | sockets |

**Cabinet is not romset family.** `ArcadeProfiles.is_arcade_system` (the family: `core_serves_machine` lets the cores of one
run the others' games) stays `arcade`; `is_cabinet_system` is every system some bay takes (board art, the cabinet key layout,
the missing-BIOS notice). A bay row with `romsets: false` is a cabinet only. Putting Neo Geo in the family would have listed
geolith and neocd on the generic cabinet. `SystemInfo` for `daphne` and `dice` now exist; no core of either is installed
here, and no `roms/daphne` or `roms/dice` folder: nothing of either was run.

**Guns are captive, like the Famicom's pads.** The gun cabinets' `Sockets` module carries `PortSeat` (where the cord goes in)
and `Holster` markers; the model's `captive_controllers()` makes one `arcade_light_gun.tscn` per holster
(`Tools/gen/gen_arcade_gun.gd`: the classic optical-gun shape, orange muzzle, no buttons, a 1.4 m cord) and `RetroSystem`
builds them with the machine, plugs them, locks the ports and keeps them out of `spawned`. What made it work, each one a bug
found on the way: **`LightGun` had no `captive`** (`pad.set("captive")` is silent on a property that is not there), so it
joined the group a save sweeps; **a snap zone seats an object by its GRAB POINT**, so the well is the holster marker times
`GUN_GRAB` (it hung 6.2 cm off before); **`LightGun` aimed only at a connected TV's glass**, so a cabinet's guns read off-screen
for ever (`_current_aim` now falls back to the model's built-in screen, and `ScreenAim` meets the quad through the CRT
shader's `fit_scale` like any other glass); **a gun rewrites its mapped buttons every frame**, so the cabinet's START and coin
go in through `LightGun.set_external_button`, ORed with the hand; the held-hint no longer hangs over a gun a holster took
(only a hand holding shows it). The cord is laid down the front, round a U and back up (`captive_cord_routes`, solved against
the rope's length, `CaptiveCord`, shared with `RetroController`) and was measured settling asleep 14 cm off the floor.
**START on a gun cabinet is a `momentary` `PanelGrip`** (a press holds it; there is no controller to attach to) and reaches the
core as the gun's own `LIGHTGUN_START`, the coin as its `LIGHTGUN_SELECT`. UNVERIFIED with a real core: that MAME/FinalBurn read
a lightgun port's START/SELECT as start and coin (no light-gun romset was at hand).

**The pedal is drawn and NOT active** (`ArcadePedalModule`, kind `pedal`, `active = false`, `is_pressed()` always false). It is on
the light-gun cabinet only. The analysis is its own task: the open questions are (1) Time Crisis reads it as a held state
(pressed = out of cover, shooting; released = hidden, reloading), which MAME maps to a keyboard-style input that a lightgun
port does not carry; (2) a VR player has no foot, so it is a button (grip? a held button on the other hand) or a floor
`VRButton` a foot-tracker could press; (3) it must go through `netplay_route`. Which games use one at all is the games',
not the cabinet's (Point Blank and House of the Dead do not).

**What the research could and could not say** (a web search, thin: arcade-museum, StrategyWiki, Wikipedia, a parts seller):
guns hang in HOLSTERS, not mounted (Point Blank); HotD2's panel lists one "Fire" button and reloads off-screen; Time Crisis is
one player with one pedal; Area 51 has a trigger and a grenade input; Operation Wolf's gun has a grenade button. NOT FOUND, so
the numbers here are choices, not facts: where the holster sits, the cord's length, the guns' real size and colour, the
pedal's place. Virtua Cop 2's cabinet was listed at 109 x 90 x 185 cm, a seller's figure. The panel layouts of the laserdisc
(Dragon's Lair: a stick and the sword button) and DICE (Pong: a dial) are from general knowledge, not looked up.

**Not done, and cabinets that are missing:** Naomi / Naomi 2 / Atomiswave (flycast; JVS cabinets, the Atomiswave's own small
one), Sega Model 2 and 3 and ST-V (all `arcade`-folder systems today, but their cabinets are sit-down or wide), racing
cabinets with a wheel, pedals and a seat (a seat/wheel/pedal module set and an analog input struct), dance and drum cabinets,
a Neo Geo MVS with two, four or six slots (the cabinet has the one-slot unit), the laserdisc
player as a visible unit in the bay, and a cocktail table. Pinball and claw machines are not libretro-shaped. OWED for all six: a
real game, the headset, the Quest cost (the boot warms every row without `requires`: six cabinets now), and netplay.

**The Neo Geo MVS is a box with a cassette, not a JAMMA board (2026-10-19).** A Neo Geo game spawns as `neogeo_cart.tscn`
(`Tools/gen/gen_neogeo_cart.gd`): a plastic cassette with the board's edge standing out of the bottom, a red band, a recessed label
and grip ribs, cart frame as every cart (connector -Y, label +Z, `Label` UV-painted). The `mvs` bay holds a RECTANGULAR unit
(`_build_mvs_unit`: a metal tray, the green motherboard, chips and a power block) with the cartridge slot standing up from its
middle, the cassette's edge 20 mm into it, label to the front (a vertical-slot MVS). **What is documented and what is guessed:** the
connector is documented (wiki.neogeodev.org: 240 contacts, 2 rows x 60 a side, 2.54 mm pitch, so about 152 mm; the cassette draws
exactly 240); the cassette's 200 x 130 x 22 mm, its charcoal colour, the band and ribs, and the unit's 340 x 200 mm are ESTIMATES: the
two research passes (a Haiku agent, then pages read by hand) found no dimensions, colour or insertion detail. The naming is real: MV0
(no slot, JAMMA-style edge), MV1 (one slot, listed as horizontal H or vertical V by revision: this models a V one), MV2, MV4, MV6.
Replace the numbers with a measured cartridge and board when there are photos with a ruler. `arcade_variants_tests neogeo/` pins the
shape's invariants (240 contacts, size table = the scene, wider than tall, edge into the slot, no JAMMA socket).

## Shooter fixes, the Neo Geo console and the names (2026-10-19, later)

**The guns did not work under MAME.** Current MAME reads a gun only when `mame_lightgun_mode` says so (default `none`: values none,
lightgun, touchscreen) and lists NO light-gun device among its controllers (`arcade_load_probe --controllers`: RetroPad, Keyboard,
None), so announcing device 4 did nothing. FinalBurn Neo lists "Lightgun" (id 4) and needs nothing. `ForcedCoreOptions.lightgun` pins
`mame_lightgun_mode = lightgun` for the run while any port holds a gun (`RetroSystem._has_lightgun`); other MAME-based cores name it
differently and are NOT covered. **The coin did not count on a gun cabinet:** a port with a gun was given the cabinet's START/coin only as the
gun's own `LIGHTGUN_START/SELECT`; the cores read a credit from the JOYPAD's SELECT (the extension answers a joypad query whatever device
the port announced), so `ArcadeInput` now sends both: the gun's buttons AND the START/SELECT bits of the joypad state on that port (the gun
writes no pad, so nothing fights).

**The shooter is another body.** `gen_arcade_cabinet.gd` has two `_shapes()`: `upright` (every older cabinet, byte-for-byte its numbers) and
`wide` (the gun cabinets): 0.90 wide, 1.90 tall, the glass STRAIGHT (vertical, at z 0.30), a 0.72 x 0.54 tube (35", half as wide again as the
upright's 0.44 x 0.33; a 29" tube was the usual size and a 50" projection the big one, which is what the research found for House of the
Dead), the holsters 90 mm in from the sides. The model reads the shape from its scene (`cabinet_width`, `cabinet_height`, `marquee_bottom`,
`glass_back_z`, `marquee_front_z`, `screen_front_z`: collision, pointer boxes, speakers and the options panel follow it, and a straight
screen gets a collision box of its own for the coin face it leaves open). A marquee title longer than "ARCADE" is set smaller to fit.
**A gun let go goes back in its holster:** `LightGun.captive_well` (the system hands it the zone it built) and `_return_to_well`, deferred, so
a hand taking it out (the zone lets go, then the hand picks it up, one frame) is not undone.

**The consolized Neo Geo MVS is a console** (`neogeo_mvs_console`, `RetroSystemModelNeoGeoConsole`, `Tools/gen/gen_neogeo_console.gd`): a
rectangular dark box (340 x 220 x 60 mm, an ESTIMATE) that takes the same MVS cassettes in a slot on its roof, two controller ports and POWER/RESET
on the front, three phono jacks on the back, so the card offers the composite lead like a SNES. **No such console was ever sold by SNK:** the
research found only community builds and kits (the Orthros MCS-01, a 2023 Kickstarter "MVS Consolizer Kit"); the official home machine was the
Neo Geo AES (325 x 237 x 60 mm, 19 x 14 x 2.5 cm cartridges that do NOT fit an MVS, RF/composite/RGB out, removable memory card), which is not
modelled. AES and MVS carry the same game data (the cores take one romset for either; the BIOS differs: sp-s2.sp1 against neo-epo.sp1; MAME's
AES is a separate software list). The Neo Geo tile now offers the cabinet (still the default) AND the console; the cabinet row says
`"sockets": []` so the card offers the lead only for the console, and `neogeo` left `_OWN_AV_LEAD`. **Names:** RomM lists `neogeomvs` and
`neogeoaes`; ES-DE has one `neogeo` folder. Both RomM names and both folders are the one `neogeo` system (`SystemIds.FOLDER_ALIASES`,
`RommPlatforms.SLUG_MAP`): one system, one romset. Replace the estimates with measurements when photos with a ruler exist.

## Quest 3 findings (2026-10-21)

Five things found with the cabinets in a headset; what was done and what is still open.

- **The gun always shot the middle.** The Quest's arcade core is `mame2003_plus` (`CoreRecommendations`), and every MAME core
  before current MAME reads a game's X-Y from the MOUSE unless an option says otherwise: a gun that never moves a mouse leaves
  the crosshair, and every shot, in the middle. `ForcedCoreOptions.LIGHTGUN_OPTION` now pins it for the run while any port holds
  a gun: `mame` `mame_lightgun_mode`, `mame2003_plus` `mame2003-plus_xy_device`, `mame2010` `mame_current_xy_type` (names read out
  of the cores' binaries; MAME 2010's values `mouse|lightgun|none` were read from the core itself, 2003-Plus's `lightgun` is from
  its documentation, NOT measured: a probe of the real core's option table crashed in this sandbox). `mame2003` and
  `mame2003_midway` have only a mouse-device option and are not covered. Along the way: `ScreenAim.picture_at` ignored the
  arcade monitor's `fit_scale`, so a pillarboxed (vertical) game aimed off by the bars; and `light_gun.gd` carried two
  `cable_instance()` (a rebase artefact: two commits had both added it), which is a parse error that takes `LightGun` and
  `system.gd` with it. `arcade_variants_tests aim/` and `pedal/` pin all three.
- **The holster held on.** A snap zone is taken by a hand only inside its `grab_distance`, measured to the zone's origin, and the
  gun wells were 6 cm: the hand had to be put right on the seat. A gun's well is `RetroSystem.GUN_WELL_REACH` (13 cm) now. Not
  measured in a headset: if it still feels sticky, the number is the lever.
- **Every arcade core on Android.** Checked against the buildbot's `android/latest/arm64-v8a` listing (read 2026-10-21): every
  arcade core it publishes files under `arcade` except `fbalpha` (the last full FB Alpha), which libretro's core-info set has no
  entry for; `libretro-core-info-retroxr/fbalpha_libretro.info` adds it. `mamemess` is `mess`, a softlist build, and was left out.
  `arcade_tests cores/` walks the list by its Android file names.
- **Solid cabinets on the Quest.** `GeometryInstance3D.transparency` did nothing on the mobile renderer, so the held cabinet
  stayed a solid 1.8 m box. Forward+ keeps the per-instance fade; mobile and Compatibility swap the body's `material_override`s
  (the baked cabinet uses those, not mesh materials) for `ALPHA_HASH` copies while it is held and put them back after
  (`_set_ghost_materials`). A part with an override of its own (the monitor) and parts with no material are left alone. The
  first grab compiles the hashed shader variant on the device: a hitch, not measured. Test the headset path on a desktop with
  `--rendering-method mobile`.
- **No sound from the MAME cores on Quest: NOT FOUND.** The cabinet's routing (`SystemAudio`) was read end to end: it is not
  socketed, its speakers are `audio_speaker_positions()`, and the Meta XR voices take a pose and a distance gain like any
  machine's. Nothing arcade-specific explains silence there, and desktop plays (FBNeo `--audio` measured). Open leads: a core
  too slow for the Quest (mame2015/2016 on a System 12 game would be) never fills the sink; and the single-sample
  `retro_audio_sample` path pushes frames at the core's rate without resampling. `bind()` now logs one line
  (`[SystemAudio] … bound N Meta XR voices, live=…, level=…`); the next logcat answers whether the voices were bound and live.

### Second Quest pass (2026-10-21, from the logcat)

The first fixes shipped, the run was read off the headset (`adb logcat -d`), and four things were still wrong:

- **The Quest's current MAME is `mamearcade`**, not `mame` (the buildbot's Android name; MAME 0.289, 28 options, the same as `mame`
  on the desktop). `ForcedCoreOptions.LIGHTGUN_OPTION` only knew `mame`, so no gun option was pinned. It now has `mamearcade` and
  `mamemess`.
- **Which MAME cores read a gun, measured** with `arcade_load_probe --options` (a core running `sf2.zip` on the gun cabinet; one core
  per process): `mame` `mame_lightgun_mode` none|lightgun|touchscreen (default **none**); `mame2003_plus` `mame2003-plus_xy_device`
  mouse|pointer|lightgun|disabled (default **mouse**); `mame2010` `mame_current_xy_type` mouse|lightgun|none (default **mouse**); FinalBurn Neo
  lists a "Lightgun" device (id 4) and needs nothing. All of those are pinned and the run held the pinned value. `mame2003` has NO
  gun value (`mame2003_mouse_device` mouse|pointer|disabled): it is pinned to `pointer` and `LightGun` reports its aim as a pointer
  too (`ForcedCoreOptions.GUN_AS_POINTER`); `mame2003_midway` the same on its own key. Neither of those two was run with a gun game
  (the only gun romsets here are modern). `mame2000` registered no options. NOT checked, no core to hand: `mame2015`, `mame2016`,
  `hbmame` (Android-only builds), whose option names are unknown.
- **START did not work on the gun in MAME 0.289.** A gun in a hand sends its stick click as the gun's own START and the grip as SELECT;
  `mame2003_plus` reads those, MAME 0.289 reads a start and a credit off the JOYPAD only. `ArcadeInput` now also sends the HAND's START
  and SELECT as the joypad's on that port (`LightGun.hand_button`), as it already did for the cabinet's own panel. A game that shows
  nothing and plays no sound in attract mode until a credit and a start (many do, Point Blank 2 among them probably) looked "silent"
  because it could not be started: the audio report of the same run may be this. `SystemAudio` now logs a health line 4 s and 14 s
  after a bind (sink fill, brake, mixer underruns, active voices, gains) to tell a quiet game from a broken bridge.
- **A cabinet's gun is held like any object.** The console gun's toggle-hold (the grip lets go and the gun is picked straight up again
  until the drop combo) felt stuck on a cabinet, and the "back in the holster from anywhere" made it magnetic. A captive gun now falls
  when let go and goes back only if it is let go AT the holster, whose snap zone takes it (`holster` group).
- **Held cabinets are a dithered ghost on the mobile renderer, and cheap.** The `ALPHA_HASH` copies did not show on the Quest (cause not
  found; the first logcat had no line to say whether the code ran, so there is one now: `[ArcadeCabinet] grabbed…` and
  `held: N surfaces dithered…`). The copies are now ONE shared unshaded flat-colour shader that discards pixels in a screen-space
  pattern (no alpha, no light, no texture), and the cabinet's shadow casting is switched off while it is held and restored after.

## The bay is its own object (2026-10-20)

**What changed.** The bay (slot, board seat, harness socket) used to be baked into the cabinet. It is an `ArcadeBayUnit` now
(`Scripts/Objects/arcade/arcade_bay_unit.gd`, one scene per kind in `Scenes/Objects/peripherals/arcade_bay_<kind>.tscn`, baked by
`Tools/gen/gen_arcade_bay.gd -- --kind=jamma|mvs|laserdisc|discrete`; labels "JAMMA / Neo Geo MVS / Laserdisc / DICE Arcade Bay"). It is
a pickable like the 32X's spacer, in the `arcade_bay` group, saved as `arcade_bay_<kind>` (`ScenePersistence.PLAIN_SCENES`) with the
board standing in it (`"board"`). Every cabinet card offers all four kinds and the JAMMA lead.

**The cabinet is still the machine.** It runs the core, takes the panels' and the guns' input, shows the picture, owns the saves and
the netplay identity. Only two things follow the bay (`RetroSystem.link_bay` / `unlink_bay`): WHERE the board stands (`_cartridge_slot`
becomes the bay's snap zone; the cabinet's own, kept as `_home_slot`, is shut) and WHICH system it plays (`systemid` becomes the bay
kind's first). So a generic cabinet with an MVS bay plays Neo Geo and refuses JAMMA boards, and the other way round: the frankenstein.
Taking the bay away stops the game (`_on_cartridge_removed`) and the board STAYS in the bay; a bay that arrives with a board in it
makes the cabinet hear it (`_swap_cartridge_slot` calls `_on_cartridge_inserted` for a board already there, because a snap zone says
nothing about one that was there first).

**Two ways to be joined, never both.** (1) *Docked*: the cabinet's `BayMountZone` (a snap zone at the `BayMount` marker on the
compartment floor, built by `RetroSystemModelArcadeCabinet._build_bay_mount`) holds the bay rigid, so moving the cabinet moves it; the
door gates the docked bay's slot as it gated the old one (`ArcadeBayModule.set_gated_slot`). A FRESH cabinet seeds its own kind of bay
in the mount (deferred; never on a restore, which is the whole truth about what is in there), as an expansion's default occupant.
(2) *Cabled*: a `JammaCable` (`jamma_cable.tscn`, derived from the i.LINK lead; connector `jamma_plug`) between the cabinet's
`JammaPort` (its back, +Z out) and a free bay's (`JammaPort`, `Scripts/Objects/cables/jamma_port.gd`). `JammaCable._resolve` joins them
with `link_bay(bay, CABLE)`; a docked bay is never cabled, and a cabinet that has a bay takes a second one by cable only after the
first is out. A docked bay replaces a cabled one. The cabled bay's slot is never gated (no door in the way).

**A cabinet scene with no `BayMount` is the old format** and keeps the old behaviour (a `CartSeat` inside its bay): nothing breaks for a
mod's cabinet that drew its own.

**Phono IN on the bay.** Three sockets on the back (`VideoIn`, `AudioLIn`, `AudioRIn`, direction IN). A machine cabled to VIDEO IN shows
on the cabinet's screen while no board is running (`ArcadeBayUnit.external_picture`, found through `AvGraph.links_for`, asked when a
cord moves; `RetroSystemModelArcadeCabinet.host_picture`), in the picture's own aspect (the board's geometry describes the board).
**Sound is NOT routed yet:** the external console's audio goes wherever its own cord sends it. There is no BOARD/EXT switch: a running
board wins, otherwise the cabled machine.

**Saved** the cabinet's entry carries `"bay"` when the bay is docked and no `"cartridge"` (the board is the bay's); a cabled bay is
restored by the lead's plugs; the bay's entry carries `"board"`. `_restore_entry` restores the bay first, so the board lands in the
bay's slot and not in the cabinet's shut one.

**OWED.** None of this was run: the sandbox this was written in cannot load the GDExtensions, so only the baked scenes and the files
that need no extension were compiled. Run `arcade_bay_tests`, `arcade_tests` and `arcade_variants_tests` first. Netplay does not
replicate docking or the cable (each peer seeds its own default bay on a restored room's cabinet only when it is a fresh one; a
bay moved by hand is local until `EV_*` events are added), the external sound, a headset, a Quest, and the plug/port geometry (boxes,
estimates) are all still to do. The jamma plug is the i.LINK scene's with bigger boxes, not a measured connector.
