# §2z-arc — The arcade cabinet, its JAMMA board and the video geometry

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
**Morphing Arcade Cabinet**, and a ROM is drawn as a **JAMMA board**.

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
behind it can be seen, **not solid** (the held layer and no mask, for the cabinet and the bay, guns and plugs that ride with it; every loose pickable's mask
has that layer taken out, `HeldObjectPhysics`: without it a carried cabinet shoved a pad 1.5 m) and **never thrown** (2026-10-26: `throw_scale()`, 0 for a cabinet: `XRToolsPickable.let_go`
and the laser's release multiply the hand's velocity and turn by it, so a cabinet let go of with the arm swinging is set down where the hand was, not sent across the room
into whatever stood there; a pad keeps its throw). `arcade_hold_tests`: carried through a pad, a cartridge and another cabinet, nothing moves; set down on them, nothing is flung.
Nobody has reproduced a cabinet flying on its own in the sandbox: the throw was the one way found, and a player reporting a cabinet that still flies is owed an answer
(what flew, and when). **A cabinet always comes to STAND**: its centre of mass is low (`CENTER_OF_MASS_Y`, the base and the board,
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
| `stick_buttons` | `ArcadeControlModule` | `Btn1`..`Btn6`, `Start` (caps), `StickPivot`, `PanelGrip` | one player's panel as ONE controller: the caps sink and the stick leans with the input. A headset's hands work the controls too (`ArcadePanelHands`, "Hands on the panel" below) |
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
else the printed title). **No new scraping.** Per-game boards are a later evaluation. (The cabinet itself wears the game's art, see "The game's art on the cabinet" below.)

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
thumbsticks stop moving the player. The caps and the stick are pictures of what reached the core. That is how a keyboard or a
pad plays; a headset's HANDS can also work the controls themselves, no attaching first (2026-10-25, "Hands on the panel"). Everything leaves through `NetworkManager.netplay_route`, then `SetJoypadState`: bypassing it
breaks lockstep.

**A control's pointer shape is the CONTROL (2026-10-27).** The grip of a form with one thing to take hold of is the size of that thing, never of the console round it. After Burner II's stick had a box 0.32 m
across at its head (and a green plate that big): a laser aimed from the seat, or from behind it, at a coin slot 0.8 m in front met the box first, so nobody could put a coin in (`arcade_form_tests grip/`: from
behind the controls, at chest height, every slot and RETURN of a flight cockpit is the first thing a laser meets; it was 0 of 2 on both). Now a flight stick's grip is `STICK_GRIP_BOX` (0.10 x 0.24 x 0.10, its head
and grip), a racing cockpit's wheel is a RING (`ArcadePanelGrip.ring_radius`: twelve boxes along the rim, a hub and three spokes for the pointer, an annulus for the glow, the hole open to a laser as it is to the eye)
and the bars of a bike, a bicycle and a board's rail are a bar deep (`BARS_GRIP_DEPTH`, 9 cm, not 20). The caps and a deck's panel are on the panel's plane and stay as they were. A new form's grip follows the same
rule: measure the part, add a hand's margin, and aim at the coin slot from behind it.

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
board art; a `ModApi` wrapper for bay kinds; the geometry for `RetroTV`. (A grabbable stick was owed here
behind an option; it is built, without one: "Hands on the panel".)

**Attaching claims the keyboard (2026-10-18).** `ArcadeInput` first copied `HandheldInput` but not the two things that made a pad's keys arrive: the system's key map in the global InputMap (`DesktopBindings.apply_for_system`, applied only while the capture holds it, as `RetroController._sync_desktop_scope`) and the capture itself. A pad needs Scroll Lock/F3 as well, but a panel you pressed has no other way to say it, so `_on_attach_changed` turns the capture on (`ScrollLockCapture.set_active(true)`; it needs the machine powered, which is why a panel attached to a machine that is off lets go). Pinned by `arcade_tests attach/` (a key plays only the attached player's port).

**The keyboard layout and the speakers (2026-10-19).** A cabinet with no key map of its own plays from `ArcadeProfiles.DESKTOP_KEYS` (MAME's: Ctrl, Alt, Space, Z, X, C for the six buttons and V, B, N, M for the four more a rhythm game has, START on 1, the coin on 5), applied by `DesktopBindings.apply_for_system` after the global layer and only when the player has saved no map for `arcade`. The stock map put the buttons on the numpad and the coin on Shift, so a keyboard with no keypad could not hit a button. Pinned by `arcade_tests input/` (no two actions share a key; the six buttons and START and the coin have one). **Speakers:** a cabinet's sound comes from a stereo pair in its own front, `SPEAKER_L`/`SPEAKER_R` (x ±0.22, y 0.34, z 0.44, facing the player), on the apron and kick panel either side of the coin door, and `SystemAudio` uses them when no TV is connected (it used to be the middle of the body, 9 cm apart). Upright cabinets carry a stereo pair low in the front; JAMMA itself is one mono channel, so a mono board drives both speakers at once. There is no centre or sub: that is not a cabinet layout. Pinned by `arcade_tests cabinet/` (a pair, left and right, low and in front). The wiring in `SystemAudio` is NOT pinned by a case; listening is OWED.

**BIOS and device sets are firmware (2026-10-19).** RetroXR knows a BIOS only if the core's `.info` declares it (`FirmwareRequirements`), and finds it on RomM's firmware list by file NAME (`RommFirmware`). FinalBurn Neo's declares 23 (all optional; 24 since 2026-10-27, below); MAME's vendored `.info` declared none, so `neogeo.zip`/`qsound.zip` were nowhere on the BIOS list and nothing could download them. `libretro-core-info-retroxr/mame_libretro.info` (a whole copy plus a firmware block) now declares fifteen, all optional and all `mame/bios/<name>.zip`: MAME searches the ROM folder, `SYSTEMDIR/mame/bios` and `SYSTEMDIR/mame/roms`, and a stand-in `neogeo.zip` in `system/mame/mame/bios/` was found by the core (the error changed from NOT FOUND to WRONG LENGTH, measured). The set follows FinalBurn's plus `qsound.zip` (every QSound game and every CPS-2 one, MAME only: FinalBurn has the DSP built in) and `stvbios.zip`. Which sets a given game wants is MAME's own information and is NOT derived from file names; a refused game still names the missing files in its notice. The notice now also fires for FinalBurn's "is required" wording. Pinned by `arcade_tests profiles/` (the overlay removed turns three cases red). Whether the files really arrive from a RomM that holds them is OWED: no server was reachable.

**The BIOS list is generated from MAME (2026-10-27).** The fifteen typed by hand left System 246, 256 and 573 (Taiko no Tatsujin 7 on, Tekken 4; DDR, GuitarFreaks, DrumMania), the whole of NAOMI (`naomi`, `naomi2`, `naomigd`, `awbios`, the F355 and House of the Dead 2 ones), Chihiro, Triforce, Lindbergh, Konami's Viper/Python/GX/GV/Twinkle, every Capcom/Sony ZN board, Taito G-Net/FX-1/Type Zero, Hikaru, HNG64, PlayChoice-10, the Nintendo Super System, Mega-Tech and Mega Play, Atari System 1... off the page, so a player with those games had nothing to download. `Tools/arcade/gen_mame_bios.py` (`python Tools/arcade/gen_mame_bios.py mame0289.xml`, `--check` prints the block and writes nothing) reads `-listxml` and rewrites the firmware block of `libretro-core-info-retroxr/mame_libretro.info`: **a BIOS** is every `isbios` machine a coin-taking game names as its `romof` (through its parent too), plus the arcade boards whose drivers take no coin yet and so look like nothing to that rule (`ALLOW`: System 246/256, Lindbergh, Triforce, Python, System Y2, ALG 3DO); a console, a toy or a PC that shares a driver file with one is `EXCLUDE`d with its reason. **A device set** is a device with ROMs of its own that at least `DEVICE_MIN` (20) coin-taking games use (QSound's DSP, the Namco I/O MCUs, Sega's JVS and MIE boards, the YM2413's patch ROM...), named for the device it is merged with when every ROM is (`qsound_hle` takes `qsound.zip`); the long tail is a computer's keyboard or a disk drive. 101 sets: the original fifteen first, in their order and words, then 62 BIOS by the games that want them, then 24 device sets. **No title is typed from memory**: the family of a well-known board is hand-written (`NOTES`) but its games are MAME shortnames the script resolves to MAME's own description, and a shortname that is not one of that BIOS's games stops the run; every other entry gets MAME's description, its maker and three well-known games (the parents with the most clones). FinalBurn Neo's list was checked the same way against its drivers (`BDF_BOARDROM` in `src/burn/drv`, and the third field of every `BurnDriver`, which names the board ROM a game needs): **its 22 non-console entries were complete but one**, `atarisy1.zip` (27 games name it), now in the overlay. Its console BIOS (`gba`, `astrocde`, the SNES DSPs) are not listed: no tile plays them with this core. The other MAME-family cores (`mamearcade`, `mame2003_plus`, `hbmame`...) declare none, as before. Pinned by `arcade_tests profiles/` (45 cases: no file twice, every one described by its own path and optional, the three the player named and twenty more by name, at least 90 sets, FinalBurn Neo's `atarisy1.zip` and the fourteen it already had); each was broken (the old list, a duplicate, `sys246` gone, FinalBurn's entry gone, one required) and went red. The names are MAME 0.289's: a later MAME adds and renames sets, which is why the script exists.

## The other cabinets (2026-10-19)

The generic upright is one of six, all the same shell: **never a fork of the model script**, only a scene (baked by
`Tools/gen/gen_arcade_cabinet.gd -- --variant=<name>`, the variants are DATA in `_variants()`) and a registry row
(`model_registry.gd`; THE IDS ARE PERSISTED). Generic stays first of the `arcade` rows, so it is the tile's default.

| id | system | panel | bay | guns |
|---|---|---|---|---|
| `arcade_cabinet_generic` | `arcade` | stick + 6 buttons, x2 | `jamma` | sockets |
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

**The pedal** was drawn and not active until 2026-10-25; it is player 1's button 2 now ("The pedal" below).

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
real game, the headset, the Quest cost (the boot warms every row without `requires`: five cabinets now), and netplay.

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
a hand taking it out (the zone lets go, then the hand picks it up, one frame) is not undone. (Only a gun in a HOLSTER: a gun on a post or a rifle is
fixed to its swivel and has no well, "Guns on a swivel".)

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
- **Holding a cabinet's gun held its coin down (found 2026-10-25).** The grip is SELECT on a console's gun, which stays in the hand by
  itself. A captive gun is held only while the grip is (`press_to_hold`), so its SELECT, sent as the gun's own and, since the START fix
  above, as the joypad's credit, was held all the while: every grab was a credit and the coin switch stayed down. A captive gun's grip
  is the hold and nothing else now (`LightGun._pressed_now`); a cabinet's credit is its coin door's. `arcade_variants_tests fire/`.
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

## The game's art on the cabinet (2026-10-21)

When a board (or MVS cassette) goes into the bay, the cabinet dresses itself in the game's scraped art; pulling it
undresses it. **Marquee**: the WHEEL (a logo, with alpha), else the cover, else the baked title as before (the
`MarqueeTitle` Label3D is hidden only while a picture is up). **Sides**: the COVER on the outside of each panel.
Cover = the front of the scraped `box` (`ArcadeProfiles.board_art`), else the scraped `label`, else a RomM cover the
spawn menu already cached (`media/romm/<id>_s.*`, id found by file name in the platform's `.romm/index.{ids,fsnames,exts}`
sidecars, `ArcadeCabinetArt.romm_id`). **Nothing is fetched or scraped for this**: a game with none of them leaves the cabinet plain.

- **Slots** are baked by `gen_arcade_cabinet.gd` `_build_art` into every variant, hidden. `MarqueeArt` (child of `Marquee`, 6.8 mm in front of its
  face) is a UNIT quad with a `box` metadata (metres); `_hang` scales the NODE to the picture's proportions inside it (the QuadMesh is a sub-resource
  shared by every instance of the scene, so never resize the mesh). `SideArtL`/`SideArtR` are the side's own SILHOUETTE (`_side_art_mesh`, 0.5 mm outside
  the panel, normal out, UV 0..1 over the silhouette's bounds, the front on the right of the left flank and on the left of the right one) and FILL the
  whole flank: `_fill` crops the picture to the flank's `aspect` metadata (uv1_scale/offset, centred, what does not fit is cut, never stretched).
  Each puts a per-instance `material_override` on its slot. The extruded sides have no UVs and a BoxMesh cannot show one picture across a face,
  which is why these are separate meshes.
- **Hook**: `RetroSystem._on_cartridge_inserted` / `_on_cartridge_removed` call the model's `on_media_inserted(cart)` / `on_media_cleared()`
  (behind `has_method`; every drop, saved-room restore and re-dock reaches them through `_swap_cartridge_slot`). `apply_art(wheel, cover)`
  is the part a suite drives with its own textures (`ArcadeCabinetArt.test_art` hangs art on a ROM path without touching the data root).
- **Materials are StandardMaterial3D, never a ShaderMaterial**: a carried cabinet dithers BaseMaterial3Ds and HIDES everything else
  (`_set_ghost_materials`). The marquee art takes `emission_texture` = its own picture, switched with `_light_marquee`, so it glows
  with the machine like the marquee did; the sides do not.
- **`MediaDimensions.load_media_image` searches every `RomLibrary.rom_dirs_for_system` folder**, not only the primary one: a game scraped
  from the `mame` tile has its art in `mame/media` while `arcade/` exists, is the primary, and is empty (the board's sticker could not find it either).
- A scene baked before the slots (a mod's cabinet) has no such nodes: the calls are no-ops.
- `arcade_variants_tests` `art/` (106 checks over the six variants: slots hidden and facing out, wheel/cover/fallbacks, power glow, ghosting, the real
  seat/pull path). Look: `Tools/models/arcade_cabinet_probe` shots `artfront`/`artright`/`artleft` (`--rom=sf2.zip`, windowed). Measured with SF2's real
  wheel and cover (both sides read the same way round, so neither is mirrored). Headset, Quest and a game with only a RomM cover OWED.
- Not done: third-party consoles on the composite input; the scraper does not fetch marquee/screenshot art (`screenmarquee`, `ss`) and RomM's are not parsed.

### The DIP Switch tab and the "Cabinet Art" toggle (2026-10-21/22)

- **DIP Switch tab** in the cabinet's menu (`CoreOptions2D`, hidden on every other machine: `RetroSystem.has_dip_tab`, `populate_dip`). There is NO
  physical DIP button (a first version had one beside the power switch, reusing the reset button; it was dropped, the reset button is hidden again).
  What the tab holds depends on the core:
  - **MAME** has the "DIP Switches" screen on the game's own screen, so the tab is one button, "Open DIP Switches" (`RetroSystem.toggle_core_dip_menu`):
    it taps Tab, Down, Return into the core on port 0 (`DIP_MENU_KEYS`, libretro `RETROK_` codes, through the netplay key schedule like a keyboard;
    0.12 s held, 0.25 s apart) and the button then reads "Close DIP Switches", which taps Tab. MEASURED with `Tools/cores/arcade_dip_probe` (sf2,
    `--keys=tab,down,return`): Tab opens MAME's menu (Input Settings, **DIP Switches**, Bookkeeping Info...), the sequence lands on the DIP screen.
    `_core_menu_open` is tracked, cleared on power-off; if the player closed the screen with Esc the next press opens the main menu, harmless.
  - **FBNeo** has no such screen (Tab, F2 and F3 do nothing visible, measured on dino). Its DIPs are core options (`fbneo-dipswitch-<game>-...`,
    `DIP_OPTION_MARK`), so the tab LISTS those rows, and only those, with the same stepper as the Options tab (the same `option_changed` path).
  - A core that publishes no DIPs, or a cabinet that is off with no options read yet, gets a one-line note. Another core's DIP screen is a row in
    `DIP_MENU_KEYS` once measured with the probe. Look: `Tools/models/dip_tab_probe` (windowed). The tab's real behaviour against a running MAME
    through the in-room menu is OWED (the keys are measured through the probe; the tab calls the same code).
- **Cabinet Art** (System tab, on by default): off takes the wheel and cover off the marquee and sides (title back) whatever is in the
  bay, and on hangs them again from the textures kept (`_art_wheel`/`_art_cover`), with no second read of the disk. `RetroSystem.cabinet_art_enabled`
  is saved in the room as `cabinet_art` ONLY when off (a default room file does not change), restored before the model is built. The row is
  shown only when the model has `set_art_enabled` (`supports_cabinet_art_toggle`), through `CoreOptions2D.populate_system`'s two trailing arguments.


## Attract mode: a cabinet that is on shows its game instead of running it (2026-10-22)

`feat/attract-mode`. **OFF by default** (`AppPrefs.arcade_attract_mode`; Options > the toggle under "Override BIOS Boot Options"), because a video decode per cabinet is real
work, most of all on a Quest. Each cabinet has its own say over it (System tab > "Attract Mode": Follow global / Always on / Always off,
`RetroSystem.attract_override`, saved in the room as `attract` ONLY when not "follow").

- **When it applies** (`ArcadeAttract.wanted`, `RetroSystem.attract_applies`): the option is on for this cabinet, a board is in the bay (or its docked/cabled bay), no console is cabled
  to its A/V input (`external_picture_active`) and no netplay session is running. No game or bay: the cabinet behaves exactly as before ("No game inserted").
  `power_on` then does NOT call `StartContent`: it sets `RetroSystem.attracting` (`is_powered_on` stays **false**, which is what every "is a core running" reader means) and
  the cabinet's `ArcadeAttract` child shows the game. The power button reads STOP, the marquee is lit.
- **What it shows**: the video snap (`media/video/<rom>.mp4`, any of mp4/mkv/webm/avi/mov) when this build can PLAY one (`ArcadeAttract.can_play_video`: macOS has no libVLC), else the
  `title` image (the game's title screen; ScreenScraper's in-game `ss` stands in when it has no `sstitle`, never ahead of a real one), else the `wheel`, else the cover (`box` front, else
  `label`) -- `ArcadeAttract.resolve_media`. The scraper is asked for whatever is MISSING (`ArcadeAttract.missing_media`: the video when this build can play one, the title always), so a
  game with only a video still gets its title; a title that lands while the video plays becomes the still at once (2026-10-25: the title used to be asked for only when there was no video,
  so a build without VLC showed the wheel, a logo). A still costs nothing per frame. The screen module fits the picture at its OWN shape (`attract_picture_active`; the core's geometry says nothing yet),
  and `ArcadeCabinetModel.host_picture()` is where the swap happens.
- **When the game really starts** (`ArcadeInput.first_use`, one signal, handled by `RetroSystem.attract_first_use`, which sets `_attract_released` for ONE `power_on`): a coin that DROPS
  (`ArcadeCoinModule.coin_inserted`), a panel attached (`attach_changed`), or a gun/pad in a HAND (polled: `ArcadeInput.held_by_hand`; a gun lying in its holster is picked up by the
  zone, not by a hand, and a pad merely plugged in is nobody). The coin that started it is HELD until the game can count it (see "Coins wait for the game" below; it used to be
  delivered after a fixed 2 s of room time, which a board still loading or testing itself never saw).
  `ArcadeInput` keeps panels attached while attracting (it used to let go whenever `is_powered_on` was false).
- **Back to the attract**: libretro has NO game-over / back-to-title signal and neither MAME nor FinalBurn Neo expose one, so it is a plain idle timer
  (`ArcadeAttract.IDLE_SECONDS` = 120): nobody at the cabinet (no panel attached, no gun or pad in a hand, no coin) -> `RetroSystem.attract_return` stops the core and the attract
  resumes. Only for a core the attract started (`attract_session`); a game started with the option off is never put away. A player attached but standing still never times out (intended).
  An arcade game has no save to lose.
- **What it costs** (`ArcadeAttract.plan`, every 0.15 s for all attracting cabinets; nothing runs for a cabinet that is off or that the option does not apply to -- the node only exists once a cabinet has attracted):
  **EVERY screen the player can see plays its video** (nearest first, up to a safety cap `visible_cap()`: 16 desktop, 8 Android), and a screen out of view is not shown but keeps playing for its SOUND while within
  hearing range (`MAX_AUDIO` 15 m, a metre of hysteresis, up to `audio_only_cap()`: 4 desktop, 2 Android), then holds its still. It plays at `VIDEO_VOLUME` 70% (about -3 dB: at 100 it covered the cabinets that were running). A screen in view uploads a frame, one out of view does not
  (`ArcadeAttract.screen_in_view`, asked EVERY frame for every cabinet with a video: the glass's four corners go through the real projection of each EYE -- a headset's two, asymmetric and far wider than a flat screen's, read from `XRServer.primary_interface`;
  the camera's own on a desktop -- and their box is tested against the picture, so a glass wider than the view, or half out of it, counts as seen; it must also face the head).
  **The first Quest build gave ONE video to the NEAREST cabinet** (`VIDEO_BUDGET_ANDROID` 1), so of seven cabinets in view only the closest ran (Metal Slug, not the one in front). Seen is what decides now, not nearest.
  Sound is ONE mono voice per cabinet (`SpatialAudioEmitter`, `speaker_separation` 0), pulled EVERY frame whatever the distance: the voice keeps a short queue, and the old far-cabinet cadence (a pull every 0.1 s past 6 m) left it dry --
  measured by ear on the Quest as stutter. A cheaper volume/direction law for cabinets out of view was left out: the emitter's own per-frame law is the same few operations, so it would not have changed the cost of a frame.
  libVLC still DECODES a video the screen is not showing (`VlcPlayer` has no "video off" call; adding one is C++ and a rebuild of both targets). Decoding several 640x480 snaps at once on a Quest is UNMEASURED: the caps are guesses.
- **Scraping, on demand** (`ScreenscraperClient.extra_media` / `media_filter`, `AutoScraper.request_media`): the scraper normally fetches only wheel/box/label/manual. With the attract on, inserting
  a board that has no video asks for THAT game's `video` and `title` (ScreenScraper `video`, `sstitle`) -- arcade games only (`ScreenscraperClient._extract_media_urls` checks the system is arcade, `request_attract_media`
  checks `ArcadeProfiles.is_cabinet_system`), one request, only those two files, and only when Auto-scrape is on (no request leaves the app unasked). The cabinet reaches the scraper through the
  `attract_media_listener` group (`SpawnMenu2D.request_attract_media`) because the scraper lives in the menu, and is told when a file lands (`arcade_attract` group, `on_media_arrived`) so a still gives way to the video.
  A cabinet restored already switched on asks BEFORE the menu (and its scraper) exists, so a want with nobody to hear it waits in `ArcadeAttract.pending_media` and the menu takes it in `_init_scraper`
  (the first AppImage lost every such request: no cabinet scraped anything, 2026-10-22). A game already waiting for an ordinary scrape joins it (`ScrapeQueue.add_extra_media`, item key `extra`: fetches the usual art AND the extras);
  one already running does not. Every step logs (`[Attract]`, `[AutoScraper]`): "asking for", "auto-scrape is off", "file is not there", "already queued".
  **ScreenScraper files many arcade games under a SUB-system** (Point Blank answers as 155 "Namco Classics", `parentid` 75): `_parse_jeu` judged the game by 155 alone, found it no arcade game and dropped the extras without a word -- the second real run scraped nothing again. It is arcade/cabinet now by the system it answers under, that system's PARENT, or the system the scrape asked about (`_requested_systemeid`; `ScreenscraperSystems.is_cabinet_systemeid` adds the Neo Geo MVS). This also moves the LABEL of such games from the cabinet render (`support-texture`) to `support-2D`, which is what the board sticker wants. `video-normalized` (2.6 MB for Point Blank) is preferred to `video` (6.9 MB). Pinned by `scrape_tests cabinet_media/`; found by running the real parser on a saved real response, which is the way to check the next media type.
  **Reconsider this if video scraping is ever structured and switched on for everything**: it is deliberately narrow now to save data.
- **The power button is a SWITCH while the attract applies** (2026-10-23; `RetroSystem.power_is_switch` = `attract_applies()`, so only with the option on (or the cabinet forced on) AND a game in the bay): it stays DOWN
  while the cabinet is on (`VRButton.set_latched_pressed`), reads ON / OFF and is lit green when on, dark red when off (`POWER_SWITCH_ON/OFF`); otherwise it is the green START / red STOP it always was. It is redrawn when a board
  comes or goes, on `set_attract_override` and when the Options toggle changes (`refresh_power_switch`, called through the `spawned` group). **The room remembers it**: `attract_on` is saved ONLY while a cabinet whose button is a switch
  is on (attracting or running), `begin_attract_restore` marks the restored cabinet, the arrival of its board (`_on_cartridge_inserted`: the bay's own entry can come after the cabinet's) switches it on again into the attract, and
  `finish_attract_restore` at the end of the restore (`_report_restored`, sync and async) gives up on a cabinet that never got a board. So switching every cabinet on and saving the room finds them all showing their games when it loads.
  A cabinet a player had started for real (a coin) is saved as on too and comes back attracting, not mid-game. `arcade_attract_tests switch/`; picture `arcade_cabinet_probe --shots=switch` (windowed).
- **A game that will not start puts the cabinet back to showing it** (2026-10-24; `_return_to_attract_if_idle`): after `attract_first_use` starts the real game (a refusal at once -- a disc game with no disc, a missing BIOS -- ends `power_on` with nothing running) and from `_on_content_load_failed` (the core's refusal a moment later). The notice still says why. With the option off nothing changes. `arcade_attract_tests fail/`.
- Tests: `arcade_attract_tests` (groups `rules media state screen use idle leave keep switch panel fail`; each case was broken and watched go red -- note a made-up ROM makes the core refuse and power the machine off a moment later,
  so the suite disconnects `content_load_failed` and reads `attract_session` in the `first_use` handler), `scrape_tests cabinet_media/`. How it LOOKS and SOUNDS is not in the suite.
- OWED: a real video (VLC) in the room, the Quest (H.264 decode and the budget of 1), a headset, listening to a far cabinet, a real ScreenScraper video download, two peers (attract is off in a session).

## Games with a disc: CHD, the CD-ROM bay (2026-10-24)

A few arcade games (MAME) need a hard-disc / CD-ROM image beside their board: `roms/arcade/thisgame.zip` and
`roms/arcade/thisgame/anything.chd`. **`ArcadeDiscs` (`Scripts/Data/systems/arcade_discs.gd`) is the one answer to
"what disc goes with this board"**: by NAME and PLACE (the folder beside the zip, never a table of games), so a hand-copied
pair works exactly as a downloaded one. A board needs a disc exactly when that folder holds a `.chd`.

- **RomM lists two entries** (the zip, and the folder as a multi-file ROM). **The list shows one, the zip's**:
  `RommCatalog.compute_hidden_flags(.., disc_folders)` hides a row with no extension whose stem a `.zip`/`.7z` row also carries,
  on the arcade platform ONLY (`ArcadeDiscs.applies`, a legacy `mame` reads as `arcade`); a folder with no zip beside it stays a row of
  its own. `disc_row_for(i)` answers the hidden folder's row for a board's. The badge count agrees (`index.meta.json` `disc_folders`;
  an index counted before it is recounted when warmed). The pairing uses the catalog's lowercase stem sidecar, so a set name with a dot
  in it would not pair: MAME's never have one.
- **Download / delete take both.** The row's download (and its tap) queues the zip and then the folder (`_enqueue_game`; the
  downloader runs one at a time). The folder unpacks INTO `roms/arcade/<folder>/` whether or not RomM's archive carries the folder name
  (`_archive_plan(.., prefix)`; `romm_tests prefix/`), and merges no gamelist row (the board's stands for it). Delete removes the zip,
  the cache group of the folder and the folder (`ArcadeDiscs.delete_for`). A board whose disc is gone (cache eviction is per group, so
  it can happen) offers "Download the disc" instead of the bin: the game cannot start without it.
- **Tapping a game that has a disc opens a choice**, Spawn JAMMA Board / Spawn Disc (`_show_arcade_game_choice`), instead of spawning
  at once. The disc is a `RetroDisc` under the `arcade` systemid with the `.chd` path: `_has_box_size()`/`_apply_cart_model` keep it off
  the board's PCB model and box (`CART_SIZES["arcade"]` is the BOARD's). `ArcadeDiscs.is_disc_object` is the test everywhere; **a disc
  must never be accepted where a board stands** (`ArcadeBayUnit.accepts_board`, `RetroSystem._accepts_media`).
- **The JAMMA bay is one block with a CD-ROM bay under it** (`gen_arcade_bay.gd`: `DriveCase`, a `Deck` node carrying the old shelf, board
  seat and sockets lifted by `DRIVE_H` 50 mm; the origin is still the floor, so docking is unchanged). Only the JAMMA kind has one; mvs,
  laserdisc and discrete do not. `DiscSeat` is the slot's mouth: `ArcadeBayUnit._build_drive` puts a snap zone there and hands it to the
  same `MediaSlot` a console's slot is (the disc rides in flat, label up; 85 mm in so a 120 mm disc is wholly inside a 300 mm drive).
  **EJECT** (`EjectButton`, a `VRButton` on the face) is `toggle_eject`: the disc rides to the mouth and waits, half out, grabbable;
  pressed again it is drawn back. A parked disc is NOT read (`get_disc()` is null). The bay's pointer box is set back 10 mm from the face
  or it hides the button from a ray. The LED lights while a disc is in.
- **The cabinet will not start a disc game without both halves** (`RetroSystem.arcade_disc_gap()`, checked in `power_on` and, a
  moment after a board or disc arrives, announced once through the machine's toast): board only -> "This game also requires a Disc,
  please insert Disc."; disc only -> "...requires a JAMMA Board, please insert JAMMA Board."; the wrong game's disc -> "This Disc
  belongs to another game...". The delay (`DISC_GAP_DELAY`) is so a room being restored, which seats the board and the disc in turn, is
  not told a game is missing the half that arrives a frame later. Attract mode needs no disc (it runs no core); the coin that starts the
  real game does. **A restored room saves the disc in the bay's entry** (`"disc"`, only while loaded).
- **A disc folder already on disk is not fetched again** (`RommDownloader.disc_folder_on_disk`): the worker first asks RomM for the folder's
  file list (names, sizes, `folder_files_of`) and, when every file is under `<folder>/` at that size, registers the cache group and finishes
  at once (a board deleted and downloaded afresh, a disc copied in by hand). Sizes only (a CHD is a container MAME checks itself); an
  unreachable server or an empty list downloads as before. `romm_tests held/ again/` (the second runs the worker against a server that only
  answers the file list and would hang if it asked for the content).
- Tests: `arcade_bay_tests disc/` (each case was broken and watched go red), `romm_tests disc/ prefix/`.
- OWED: a real RomM holding a game with a CHD (the layout of RomM's multi-file archive is handled either way, never seen), a real game
  with a CHD in the core (which MAME sets need which file is MAME's), the look of the drive in a headset, the Quest, netplay (the disc is
  not replicated; a session refuses nothing for it), cache eviction pairing the two groups.

## Cost of a cabinet (2026-10-24)

`arcade_mesh_census` counts a cabinet's parts. **Godot's default CylinderMesh is 64 sides and 4 rings, 768 triangles for a button 3 cm
across, and a cabinet has dozens of them, each a draw call, in a room that may hold twenty cabinets in attract.** The generators'
`ArcadeGenUtil.cylinder` now gives a part the sides its size can show (12 at 1.5 cm up to 40 at 5 cm, one ring) and the stick ball is
24 x 12: a cabinet went from 86,184 to 21,072 triangles (64,680 before the CD-ROM bay and the button rims), draw calls unchanged (226;
the bay and the rims added 28). Re-bake every `gen_arcade_*` after touching the helper. What is left is draw calls, not triangles:
merging the small parts of a panel is the next lever, and nobody has measured the room of twenty on a Quest.

## Buttons (2026-10-24)

A button on the deck is the cap AND a flange of the same colour round it (`<name>Rim`, a short cone 22% wider than the cap, fixed): the
cap sinks into it when its bit is held (`CAP_PRESS` 6 mm, the flange 5 mm proud), as a moulded pushbutton does. The cap tapers a little
toward its top. `gen_arcade_cabinet.gd _cap`; the control module still finds only `BtnN` and `Start`.

## Setting a cabinet down by aiming at the floor (2026-10-24)

A cabinet is handed to the hand that spawned or took it (`spawns_on_floor` is false), and dropped from a hand it lands wherever
it falls. **`GroundPlacement` (`Scripts/Interaction/ground_placement.gd`, added by the model's `configure_cartridge_slot`) lets the
player aim it down instead**: while the cabinet is held and the aim points at the floor, a yellow rectangle the size of its base
(`ground_footprint`, width x 0.80 m, a bar along the FRONT) shows where it will stand; letting go stands it there, upright, at rest,
front toward the player, with no fall (`apply`, through `PhysicsServer3D` like `let_go`). Aim level, up or farther than 4 m and
nothing shows: it is dropped as ever. The aim is the holding controller's -Z in a headset, the camera's on the desktop.
`placement_for` is pure and is the whole decision (the rectangle shows what a release does because a release uses the last answer
it gave); the floor is the XR origin's height. `arcade_tests ground/` (mutation-tested), `arcade_cabinet_probe --shots=ground`.
OWED: a headset, a real hold with a laser and with the desktop hand, a cabinet carried in netplay (the pose is local), the Quest.
The MIN_DOWN (17 degrees below level) and the 4 m reach are estimates; the marker does not know about walls or furniture.

## The cabinet follows the game in its bay (2026-10-22)

A fixed panel (stick + six buttons, x2, two coin doors) is wrong for most games. `ArcadeGameProfile`
(`Scripts/Data/systems/arcade_game_profile.gd`) says what THIS game needs and the modules draw only that: a one-player game has no second
panel, a two-button game two caps, a gun game no stick, a one-coin game one door, and FBNeo's own words on the caps. **Only what is DRAWN
follows the game; the input is never filtered**, so a cap hidden by a wrong guess still plays from a controller or the keyboard.

- **Two sources, the second wins where it speaks.** (1) MAME's `-listxml`, boiled down by `Tools/arcade/gen_game_index.py` into
  `ArcadeGameTable` (28,701 romsets / 1,328 profiles from MAME 0.289, 299 KB as one string constant; a profile is `p<players>c<coins>b<buttons>w<ways>:<kinds>`,
  kinds `joy twin stick paddle pedal gun touch dial ball btn other`, then since 2026-10-25 the attributes of the cabinet the game came in: `r` the
  monitor's rotation, `s` its screens, `g` its light guns, `t` its form, `o` a cockpit's roof, `f` a gun pedal, `a` one panel for alternating players,
  `v` the game reads a service / test switch (MAME's `<input service="yes">`: 14,977 of the 28,701 romsets, Silent Scope and Street Fighter II among them,
  Time Crisis and Pac-Man not), `m` the tube's class, and since 2026-10-26 `h` (a dial that is a steering wheel: Bad Lands), `n` (a stage's arrows when not four: DDR Solo's six) and `i` (which rhythm
  controller a `music` cabinet has: `ideck ipopn iguitar idrums itaiko iconga`); every clone tied to its parent (`sf2=sf2ua`, `sf2ce<sf2`); the lists and which of it is MAME's are in the
  script's docstring. `python Tools/arcade/gen_game_index.py mame0289.xml`, the XML from the release's `mame0289lx.zip`, checksum-verified against
  its SHA256SUMS). (2) The core's `SET_INPUT_DESCRIPTORS` through `Libretro.GetInputDescriptors()` (`[{port, device, index, id,
  description}]`; the C++ already stored them in `InputHandler::m_devices`, nothing read them). `RetroSystemModelArcadeCabinet._poll_descriptors` asks twice a second from power-on until the
  first non-empty answer.
- **MEASURED (`Tools/cores/arcade_descriptors_probe`, one core per process): FBNeo describes THIS game** (sf2: 14 pad ids per port named "Weak Punch" ... "Coin"; dino: "Attack",
  "Jump"), **MAME describes the whole RetroPad for every game** (160 rows, all 16 ids, "A", "B", "Joy Left"). So a port that publishes all sixteen ids is ignored
  and the table stands. FBNeo calls pad id 2 **"Coin"**: that CONFIRMS `ArcadeProfiles.COIN_BIT` = SELECT (it was a standard guess). The ports and
  caps follow the descriptors when they speak; `ptblank` and `hotd` give FBNeo no descriptors at all (not its games), so the table does it.
- **Where it applies.** `on_media_inserted` for the `arcade` family only (the Neo Geo, Daphne and DICE cabinets keep their own panels); an unknown romset leaves the cabinet whole.
  `ArcadeControlModule.apply_profile` (panel, stick, caps, labels), `ArcadeCoinModule.set_door_enabled`. A panel the game does not use is out of the pointer's reach
  (`ArcadeModule.set_pointable`) and refuses `set_attached`. A coin door uses `VRButton.set_interactive`.
- **Labels** are printed on the DECK, not on the caps (a cap is 31 mm and tilts away; words on it were unreadable in the first picture): the monitor-side row of caps is labelled above, the
  rest below (`_mean_cap_y`), or the top row's words land on the bottom row's caps. Two lines of six letters (`ArcadeGameProfile.shorten`). The panel's cap order is the historic bit order
  (B A Y X L R), so a fighter's kicks and punches are not in a tidy row: the labels make that visible, they do not change it.
- Tests: `arcade_tests game/` (profiles: table, descriptors in both flavours, the control leg of MAME's generic pad; cabinet: caps, panels, doors, labels, board out). Mutation-tested
  (`button_visible`/`panel_visible` forced true: 7 cases red). Picture: `arcade_cabinet_probe --shots=game` (windowed).
- **Since 2026-10-25 the cabinet also takes the game's SHAPE** (its panels, guns, cockpit or stage, its monitor): "The cabinet takes the shape of the game" below. What this section
  describes is still what a cabinet does inside its form, and all of it a cabinet does that has no row to follow (a mod's, an unknown romset). The Quest is OWED: Android was not rebuilt, so `GetInputDescriptors`
  does not exist there until it is (the cabinet does not check `has_method`: rebuild both targets).

## Coins wait for the game; RETURN gives one back (2026-10-25)

A coin is a pulse on SELECT; a board that is still loading or running its power-on tests never sees it. **A coin the game cannot count yet
is HELD** (`ArcadeInputState.CoinEscrow`): the one that starts a game from the attract, and any put in while the core is still coming up.
They go in once the core has run **one wait, the same for every game, in its own frames** (`ArcadeProfiles.COIN_WAIT_SECONDS`, 4 s at the core's
own rate `GetDeclaredFps`, counted in `Libretro.GetFrameCount`, emulated frames, so a slow load or a Quest running below full speed waits as long
as the game does). MAME does not say when a game counts a coin; **the table holds no boot time per game** (there was a per-driver estimate, `k`,
until 2026-10-25: nobody had measured it, so it went), and 0 would let a coin in on the first frame. One at a time, a pulse and `COIN_GAP_SECONDS`
apart (a game counts the EDGE). **START lets them in at once** on a game that has run `COIN_MIN_FRAMES` (a player who knows the game is up), and START itself is
held back until the credit has landed and `START_AFTER_COIN_SECONDS` more: a START tapped meanwhile is queued and sent once, after it. The
slot's lamp blinks while a coin is held. (`GetFrameCount` is the bridge's own counter, which the pace trace reads too; a bridge without it would count the room's time instead.)

The coin door's RETURN cap is a button (`ArcadeCoinModule.return_pressed`): it gives back a HELD coin, which drops into the cup with a rattle
of its own (synthesised, `rattle()`). A coin put into a switched-off cabinet rolls straight out; switching off with coins held rolls them all
out. **Nothing a game has counted comes back**: no core has a refund input, and on the hardware the button is mechanical (it frees a jammed
coin). `arcade_attract_tests coins/`, `arcade_tests input/ game/ coin/`, the probe's `--shots=return`. OWED: real cores (does 4 s hold for a
CPS3 or a NAOMI on Flycast, which take longer?), the Quest, a game that counts coins on a level rather than an edge.

## The cabinet is built from a spec (2026-10-25)

`ArcadeCabinetBuilder` (`Scripts/Objects/arcade/arcade_cabinet_builder.gd`) builds a cabinet's nodes from a SPEC, a Dictionary
(`ArcadeCabinetSpecs`, `Scripts/Data/systems/arcade_cabinet_specs.gd`): the body (`shape`: `upright`, `wide`, `racer`), the look, the bay
kind, a panel per player, the coin doors, front sockets or guns, what stands in front. **The same code bakes the shipped scenes**
(`Tools/gen/gen_arcade_cabinet.gd` is a thin wrapper now; `ArcadeParts` holds the primitives, `ArcadeGenUtil` delegates to it) **and builds a
form again in the room** (`build_form`). The baked scenes were re-baked and diffed with the unique ids normalised: identical but for 1-ulp float
noise, so they were left as they were. Every top-level node a form owns carries `FORM_META`; the bay, the JAMMA socket and the composite input
are built only when baking and never rebuilt (a board, a docked bay, a cord and the power button hang on them). The baked scene names its row
(`VARIANT_META`), which is how a cabinet in the room knows its own spec. **Change a part in the builder, then re-bake every variant; never
hand-edit a cabinet scene.**

## The cabinet takes the shape of the game (2026-10-25)

`ArcadeCabinetSpecs.for_game(base, profile)` turns the cabinet's own row and the game's profile (`ArcadeGameProfile`, from the table) into the
spec of the cabinet the game came in; `RetroSystemModelArcadeCabinet.morph_to(spec)` builds it in place of the one standing. A game that wants
exactly what the cabinet is (Street Fighter II in the generic cabinet: two panels of six, two doors) gets the cabinet's own row back and
**nothing is rebuilt** (`_same_form`). The look (body colour, trim, marquee, title) and the bay are the cabinet's and never change.

- **Players and panels** (`layout_panels`): a panel per player, each the kind of control the game has (`panel_kind`: two sticks `twin`, a
  trackball `ball`, a paddle `dial`, `buttons` alone, else a `stick`) with exactly its buttons (`button_grid`: a row of up to three, Neo Geo's
  arched four, three over two, two rows of three). Two players stand where the generic cabinet's always did (the layout reproduces its numbers
  exactly, which is what keeps a six-button two-player game from rebuilding); three to six make the BODY wider (`body_width`: the panels' span and
  8 cm, at least 30 cm of deck a player: 0.90 m for three, 1.20 for four, 1.92 for six, as the real ones were: Konami's four-player was 1.2 m,
  the monitor in the middle and the marquee as wide as the body). **Never a plate with wings on a standard upright**: that was the long ugly bar
  of 2026-10-25 and its wings are gone. A form never rebuilds the bay (it is baked with the cabinet, `door_width` is the door's own, 0.60 m on the
  generic one), so a body wider than the door is closed beside it (`LowerFaceL/R`); the same closes a gun cabinet's 0.90 m front. Coin doors stand
  under their player's panel when there is one for each (a game with fewer slots, Cotton 2's two, spreads them over the body), and so do the pad
  sockets (otherwise spread over the apron). `arcade_form_tests wide/`. **An alternating game** (the table's `a`: Pac-Man, Donkey Kong, Kuri Kinton) has ONE panel in the middle, labelled
  1P, and a momentary START labelled 2P beside it, which is player 2's START (MAME reads player 1's controls for both turns on an upright).
  A front socket per player, up to the four ports a machine has (`socket_count`).
- **Coin doors**: as many as the game has coin slots, no more than it has panels, up to four, each to its own player's port (a game with more
  doors than panels still has each door's coin sent: `ArcadeInput._door_ports`). One for an alternating game.
- **The monitor** (`screen`: `ArcadeCabinetBuilder.tube_for`): stood on its side for a vertical game (the table's `r`), several side by side for a
  game with several screens (`s`), and of the game's class (`m`: 19 inches before 1985): the body's own tube is its `inches`
  (upright 25, wide 40, racer 27; a CRT's picture is about 87% of its class), and a game's is scaled from it, then made to fit the glass the
  body has, whole, never squashed. The screen module's `glass_size` follows, so the picture is fitted to the tube it is in.
  **A monitor on its side gets its own body, `tate`** (2026-10-25, `ArcadeCabinetSpecs.shapes()`): the upright's lower body, deck and 27 degree
  lean with the glass 0.65 m up the slant instead of 0.51 and the marquee above it (1.92 m tall), and a 0.48 x 0.36 tube (a true 25 inch
  class) stood up, 0.36 x 0.48 m. On the upright's glass a tate game's picture was 0.30 x 0.40 m, floating in a landscape recess; that was
  the whole complaint ("the screen does not adapt to the game"). **The window is cut to the tube in every build**: the pane is the tube and
  3 cm round it (`Glass`, so the picture is seen through a tall narrow opening or a small one), and what is left of the front is the
  cabinet's OWN board (`FrameSide*`/`Frame*`, the body's colour, not the black recess the first bakes had), so the shape of the picture is the shape
  of the opening. The five baked cabinets were baked again for it (the node ids in a scene are drawn at random each bake, which is the
  whole of the churn in the diff). `arcade_form_tests` group `tate/` pins it: every body is one silhouette (glass edge and marquee meet at
  its corner, the height is the top), the tall body is the upright's with a longer glass up the same slope, which games get it, the window
  is the tube and 3 cm, and a board pulled gives the upright back.
  **A wide body gets a picture to match** (2026-10-26, `ArcadeCabinetSpecs.wide_picture`, `arcade_form_tests picture/`): three and four player cabinets
  were drawn on a deck 0.9 to 1.5 m wide with the upright's own 0.44 x 0.33 m tube, a picture 49% of the body (3 players) down to 29% (4 players
  with four buttons) where a two-player upright's is 67%: "Cadillacs and Dinosaurs and Turtles in Time have a mini screen". The picture now takes
  `PICTURE_SHARE` (58%) of the body's width, never less than the upright's, never more than the glass holds with its 3 cm of black round it
  (`PICTURE_FRAME`): up to a 29 inch class the body stays the upright; past it the **`tall` body** (the tate body with the glass `TALL_EXTRA` = 0.10 m
  longer again, 0.75 m of glass, 2.01 m of cabinet, a 0.77 x 0.58 m / 40 inch class at most; `ArcadeCabinetSpecs.lengthened` derives it, so a change
  to the tate body is a change to this one). A monitor on its side keeps the tate body however wide the panels make it.
  | players x buttons (stick) | body | picture | share |
  |---|---|---|---|
  | 2 (any) | 0.66 | 0.44 x 0.33 | 67% (as before) |
  | 3 x 2 (Cadillacs and Dinosaurs) | 0.90 | 0.52 x 0.39 | 57% (was 49%) |
  | 3 x 3 (Alien vs. Predator) | 0.98 | 0.58 x 0.43 | 59% (was 45%) |
  | 4 x 2 (TMNT, Turtles in Time, Simpsons, Captain Commando) | 1.20 | 0.69 x 0.52 | 57% (was 37%) |
  | 4 x 3 (Gauntlet Legends) | 1.29 | 0.75 x 0.56 | 58% (was 34%) |
  | 6 x 3, two screens (X-Men) | 1.92 | 1.54 x 0.58 | 80% (was 46%) |
  What the research does and does not say (`research/multiplayer_cabinets.md`, `research/seat_cabinets.md`, web summaries only, nothing opened in full): real
  four-player cabinets were about 0.93 to 0.94 m wide (TMNT's panel 0.94 m, Gauntlet Legends 0.93 m with a 25 inch tube), about 47% picture; **no source
  gives the monitor of Cadillacs and Dinosaurs, TMNT or the Simpsons**, and X-Men is two ordinary CRTs joined by a mirror into one double-wide picture,
  size unknown. So the 58% is a proportion (a bigger upright, not a small screen in a long box), not a measurement. **The deck itself is wider than the
  real one**: `PANEL_PITCH_MULTI` is 30 cm a player where TMNT's panel was 23.5 cm; tightening it is a separate decision (hands, sockets and coin doors
  follow the pitch). **Mounted-gun cabinets** (Operation Wolf, Beast Busters, Line of Fire, Rail Chase 2) were given a 25 inch tube in the 40 inch
  frame of the wide body (`screen_inches` lacked `FORM_GUN_MOUNTED`); they have the body's whole 0.72 x 0.54 m now, as every other gun cabinet.
- **Guns** (`gun`, `gunm`, `rifle`): the WIDE body, as many guns as the game has light guns (up to 3), START alone for each. `holster`: hung on
  the apron (one gun on the right, as Time Crisis's); `mounted`: resting level on a post on the deck's front edge, aimed at the screen (one in the
  middle: Operation Wolf's Uzi, Terminator 2, Beast Busters' three); `rifle`: one rifle on a taller post in the middle (Silent Scope, Golgo 13),
  `Scenes/Objects/peripherals/arcade_light_rifle.tscn` (`gen_arcade_gun.gd -- --variant=rifle`: the pistol's grip, trigger and cord boss in the
  same place, so the cabinet seats and cords it with the pistol's numbers; a barrel, a forestock, a stock and a scope tube; its muzzle stops 3 cm
  short of the glass). **A gun on a post is FIXED to it** (2026-10-25: it used to be taken off the post like a pistol and put back; the real ones
  are bolted to the cabinet and only turn in their housing): see "Guns on a swivel" below. **Pedals only where the game had them** (`f`: Time Crisis): one under each gun, or one in the middle for one gun;
  each its player's button 2 ("The pedal"). Three guns put the coin doors either side of the middle holster.
  **Every shooter is one, MAME's own typing or not** (2026-10-26): MAME files a light gun only where its driver reads one, so Time Crisis 3 and 4
  and Vampire Night (a System 246 driver that declares no controls at all, so no profile existed and the cabinet stayed an upright), House of the
  Dead III and 4, Ghost Squad, Virtua Cop 3, Let's Go Jungle, Ninja Assault and the Atomiswave hunters (a joystick panel) and Alien3, Jurassic Park,
  Gunblade NY, Rail Chase 2 (analog sticks, like Terminator 2) and World Combat's 4P sets (two buttons in MAME: its gun axes are an undefined TODO there) were plain uprights. `UNTYPED_GUNS` in `gen_game_index.py` names them, by parent
  romset, with their form and number of guns; MAME's own `g` wins where it counts guns, and a driver with no `<input>` is given a profile
  (players and coin doors to a gun). `arcade_tests game/` pins a roster of 69 shooters (the form and the pedal), and a census over the whole
  table: **no profile that names a light gun is left an upright** (bar five whose "gun" is a hammer, a seat or a stage: `odd`).
  **A gun MAME reads as an analog stick is also the pad's left stick** (`ArcadeGameProfile.aims_as_stick`: a gun game with the `stick` kind):
  libretro-mame binds `IPT_AD_STICK` to the pad's LEFT stick and a light gun to the light-gun device alone (`ah_assignmenthelper.cpp`, `input_retro.cpp`),
  so a rifle or a mount sending only a light-gun position aimed nothing in Silent Scope, Terminator 2 or Operation Thunderbolt. `ArcadeInput._gun_axes`
  sends `LightGun.last_aim` (the light gun's own coordinates; y grows downward in both) as `alx`/`aly` on the gun's port while the gun is in it.
  Not run against a core (none in the sandbox): that a game reads the aim there, and the sensitivity, are owed.
- **A sit-down driving cockpit** (`race`; `ArcadeCabinetBuilder._build_cockpit`): the `racer` body (a lower monitor, leaning back, its middle at
  1.1 m for a SEATED driver) and in front of it, clear of the bay door's swing, a platform, the seat, a dash holding the wheel, the gas and brake
  pedals in the footwell, a gear lever by the right hand and START on the dash; a ROOF over the seat for the Model 3 twins (`o`: Scud Race, Le
  Mans 24, Daytona 2...). The driver's controls are ONE controller (Player1, taken hold of at the wheel), as a panel is.
  **The seat is a seat** (2026-10-25, `CockpitSeat`, seats.md "A cockpit's own seat"): press the cushion to sit; **the eyes are at the height of
  the middle of the glass** (1.12 m: the `racer` body is built for it; MAME says nothing of where a driver sat, so the screen is what a seat is
  fitted to) and a sitting adult's eye height (0.72 m, the racing seat furniture's) above the cushion; you get up beside it on the driver's side.
  **The monitor stands under a HOOD** (2026-10-26, the shape's `hood`): the platform and the dash must start where the bay door's swing ends (0.80 m
  out), which put the glass 1.6 m from the seated eyes and made the picture fill 16 degrees of the view ("the screen is too far or too small", After
  Burner). The `racer` body's glass now starts at the front lip of a shelf (0.34 m deep, 0.80-0.88 m up: over the door, never in it) so the
  wheel stands 0.36 m from the glass's lower edge and the eyes (`SEAT_Z` 1.58) 0.96 m from the picture: 26-28 degrees, a real cab's about 30. **Anything
  that moves the seat, the dash or the glass must keep that**: `arcade_form_tests hood/` measures the distance, the angle and that nothing stands in the line
  of sight. The hood and the glass's wedge are SOLID (`solid_boxes` -> `SOLID_BOXES_META` -> the model's collision, the glass cut into four steps along its
  slope) but are NOT a pointer box: over the coin doors one would stand between a laser and their slots (`reach/`). The cabin's walls carry the glass's line
  up to the roof and down to the platform. `Tools/models/arcade_cabinet_probe --forms=daytona` takes the view from the seat (`formseat_`).
  **The pedals** (both gun and driving) are real-pedal shaped since the same day: a gun pedal is a pressed-steel base with a cheek each side of
  the hinge pin, a tread hinged at its heel (toward the player) with its toe toward the screen raised 22 degrees, a matt black ribbed rubber face and
  a toe lip, and a boot and a cord to the cabinet; a driver's two are organ pedals on one axle over a footplate with a heel mat, brake (left) the
  wider pad, rising 32 degrees toward the screen. Every proportion is an estimate: no photograph of Namco's or Sega's pedals could be fetched
  from here (the egress proxy). `arcade_form_tests pedals/`.
- **A sit-down flight cockpit** (`fly`: After Burner II, G-LOC, Galaxy Force II, Space Harrier, Thunder Blade, Night Striker, 41 romsets, 2026-10-26; `arcade-cabinets.md` 2b is the catalogue):
  the driving cockpit's platform, dash and seat, with **a stick between the knees** (`StickPivot`, a frame standing up, a 30 cm shaft, the first two buttons on the grip's head) and **a throttle lever by
  the left hand** (`ThrottlePivot`, the next two buttons on its knob) for a game whose driver reads a Z axis (the table's `z`, read out of the driver sources by `Tools/arcade/cockpits.py`), in
  a **cabin** where the game's had one (the table's `q` flag `c`: slanted side panels, a roof running forward over the monitor, five lock-on lamps). `q` is also read by the driving
  cockpit (Out Run, Power Drift, Super Monaco GP, which MAME's DIP calls "Moving") and by the gun rides. **What MAME's Cabinet DIP offers (Moving, Cockpit, Deluxe) says a sit-down cabinet existed even when its
  factory setting is an upright**, which is why Out Run was filed `stand` before. The throttle is the right stick's Y (forward up), and **stays where it was left** (`ThrottleGrab`: a hand moves it, and the
  larger of the lever and a pad's right stick is what is sent).
- **A moving base** (`MotionPivot`, `q` flag `m`): the platform, the dash, the seat, the controls and the cabin of a cockpit are one node that `ArcadeControlModule.tick` tilts about the platform's centre:
  banked into the turn (4 degrees at full stick or wheel), nosed up with a pull or the gas (3 degrees), eased at 4 a second, level again when the run ends. **Options > Cabinet Motion** (`AppPrefs.arcade_motion`):
  automatic (on at a desk, off in a headset), always, never. `CockpitSeat` carries a seated player with the seat (`SeatSitting.follow`: position only, the view never turns with the base; seats.md). The
  base is driven by the stick and the wheel, not by the game: the API gives the cabinet nothing of the game's own motion.
- **A driving cockpit with guns** (`racegun`: Lucky & Wild, 2026-10-26; `arcade-cabinets.md` section 2): the `race` cockpit with TWO seats, a driver on the left (wheel and pedal) and a gunner on the right, 0.90 m wide,
  a START at each end of the dash (the gunner's is player 2's own controller) and **a gun each in a holster on the dash's face** (`gun_style` `dash`: a plate, a cup and a strap, the cord into a grommet beside it). The
  game is filed by hand (`RACEGUN` in the generator) because no MAME control says "a driver and a gunner"; `is_gun()` and `is_driving()` both answer for it. `arcade_form_tests racegun/`, `seat_tests pair/`.
- **A bench for a ride** (`bench`: Rail Chase, The Lost World, Jurassic Park, Line of Fire): a platform in front of the guns (which stay on the deck) and a seat a gun, two at most, side by side on it
  (`CockpitSeat`, eyes capped at 1.20 m: a 1.33 m glass would make a stool). It does not move.
- **A stand-up driving cabinet** (`stand`: Pole Position, Out Run, Final Lap): the wheel stands out of the panel, a gear lever beside it, and the
  two pedals on the floor in front, clear of the bay door (the real ones were on the kick panel: the door is there).
- **A ride-on bike** (`bike`: Hang-On, Harley-Davidson, Manx TT): a motorbike on a stand in front of the `racer` body; it LEANS with the steering
  (`LeanPivot`), the rider takes hold of it at the bars. **The saddle is a seat** (2026-10-26, `RiderSeat`, a `CockpitSeat`: press the saddle to sit, the eyes 0.68 m above it, 1.05 m from the
  picture, getting up onto the floor beside the stand): **NOT on the part that leans** (a bike that leaned its rider 14 degrees would swing a head 30 cm; the rider's body does the leaning),
  and **no pointer box over the saddle** (the machine's boxes stop under it: a box over it would stand between the laser and the cushion). A bicycle's saddle is one the same way (`cycle`).
- **A ride-on bicycle** (`cycle`: Prop Cycle, 2026-10-25): a bicycle on a stand in front of the WIDE body (its own 40 inch tube: a rider's head is above the saddle),
  one controller taken hold of at the bars. `BarsPivot` turns and tips with the LEFT stick (X steers 28 degrees about the stem, Y tips the grips 12; pulled toward the rider is DOWN),
  `CrankPivot` pedals with the RIGHT stick's Y, up being forward and the deflection the pedalling SPEED (MAME's `AD_STICK_Z` "Cycle Pedal"; libretro-mame binds it to the right stick's Y);
  START on the bars' clamp. The pointer box of the stand stops under the bars or a laser could not reach their grip.
- **A rider standing on a rocking board** (`skate`, `snow`, `ski`: Top Skater, Alpine Surfer, Alpine Racer and Ski Super G, 2026-10-26; `arcade-cabinets.md` 2f): the WIDE body's big screen at standing height and, 0.84 m out, a stand with a plate rocking on a lengthwise axle
  (`LeanPivot`, leaned by the steering as a bike is) carrying a skateboard, a snowboard or two skis and a rail the rider holds (posts, side rails and a crossbar in front with START on it, 1 m above the floor). The rail leans with the plate and its grips are what a hand takes
  (`BarsGrab`, as a bike's bars: sideways 15 cm is a full lean); **the bars' middle is the middle of the two grips**, so a full throw is within the let-go distance. One rider a machine, no seat, no collision; the pointer box is the stand's and stops under the rail.
- **A hologram window** (`holo`: Time Traveler): the upright with its monitor's picture `HOLO_DEPTH` (30 cm) behind the glass at the far end of a black tunnel cut to the window, a plinth
  in front of it for the props (the real cabinet threw its CRT's picture on a curved mirror; the picture is drawn where the image appeared).
- **Two levers in one slot** (`slot`: Panic Park): the tall body (a 33 inch class screen, table `m33`) with a `SlidePivot` carriage on a shared `SlotRail` for each player (red and blue), `SLOT_TRAVEL` 14 cm either side of where it
  rests, so that both reach the middle and neither passes it; the lever's position is the left stick X (an analog position: MAME's port has `CENTERDELTA(0)`). The handle is a flat dome 9 cm across
  and START a big round button in the player's colour.
- **A dance stage** (`dance` four arrows, `pump` Pump It Up's five panels, DDR **Solo's six**: the table's `n6`): the wide body, a square of nine 30 cm panels per dancer (one or two),
  a safety bar behind each; each dancer's arrows belong to that player's panel (`Pad<Dir>` sink with the directions, Pump's `Btn1..5` with the
  buttons; Solo's up-left and up-right corners, on the screen's side, are `PadUpLeft` and `PadUpRight`, MAME's buttons 3 and 4: ksys573.cpp's `ddrsolo` ports name them "P1 Up-Left 1/2" and
  "P1 Up-Right 1/2"; which panels were the real six is the research's: the four arrows plus up-left and up-right), taken hold of at its START on the deck.
  **The platform is 10 cm high (`STAGE_H`, 2026-10-27; it was 2 cm, which sank into a floor that was not dead flat and left the arrows half buried: the base may clip at its foot, the arrows
  may not), with the panels flush on its top, and it is walked on or stood on** ("Feet and the standing seat", `arcade-cabinets.md` 9.2b).
- **Music** (`music`, the table's `i` says which) has a controller of its own for six instruments: a beatmania deck (turntable and five keys, a deck a player), pop'n music's nine domes, a GuitarFreaks guitar a player, DrumMania's five pads and the
  bass drum's pedal on the floor, a Taiko drum a player (four zones, sectors of a ring) and Mambo a Go-Go's three drums of three pads (`ArcadeInstruments`, `ArcadeCabinetBuilder._build_instrument`, `arcade-cabinets.md` 2c). The panel has ten buttons
  for them (`ArcadeProfiles.BUTTON_COUNT`: MAME's buttons 7 to 10 are the pad's L2, R2, L3, R3, an estimate), a cap may move its own way (`press_offset`) and a fingertip zone may be a sector (`sector`).
  **The remaining rhythm games** (beatmania IIDX and III, Keyboardmania) **and the unique cabinets** (`odd`) are uprights until they have a module of their own: `arcade-cabinets.md` lists each with MAME's own control names.
- **What the panel shows moving** (`ArcadeControlModule.show_state(mask, axes)`, fed the axes now as well as the mask): a wheel turns (left stick X,
  else LEFT/RIGHT, 120 degrees to lock), the gas and brake tip with R2 and L2 (MAME's PEDAL and PEDAL2, which the extension sends as digital
  buttons: it does not answer ANALOG_BUTTON), the lever with button 1, a bike leans, a trackball rolls, a second stick leans with the right stick
  or the face buttons (Robotron's fire stick is the diamond), a dancer's arrows sink. Eased, and a settled part is not written again.

**How a form changes** (`RetroSystemModelArcadeCabinet._request_form` -> `morph_to`):
- **A form is built on a stage that is NOT in the tree and moved onto the cabinet whole** (`ArcadeCabinetBuilder.build_form`). A node scripted
  AFTER it entered the tree never runs its `_ready`, and a baked scene never shows it (its scripts and properties are saved, so `_ready` runs
  fully set up on load): the grip that makes itself pointable in `_ready`, the coin slot and RETURN buttons, a hinge. Built directly under the
  cabinet, as the first morph was, every panel, wheel, bike bar and coin button a morph built was DEAD: it could not be aimed at, lit or taken
  hold of, the RETURN gave nothing back, and only the baked cabinet's could (found 2026-10-25: Cotton's panels, every wheel; `arcade_form_tests
  reach/` casts a laser at every panel and coin button of every form). Never `set_script` on a node that is already in the tree.
- **Deferred and coalesced**: built at the end of the frame, once; never inside the callback that asked (a snap zone handing over a board does it
  while the tree is busy with the nodes it moves: removing a form there failed with "Parent node is busy"). **Never under a running core**: its
  ports and the guns on them are in use; a form asked for then is built when it stops (`on_power_off`). The attract runs no core, so a board in
  an attracting cabinet changes it at once.
- What hangs on the parts follows: the attached panel lets go (that panel is gone; `ArcadeInput.rewire`, coins held stay held), the guns on the
  old holsters are unplugged the way a hand would (`RetroSystem.before_cabinet_form`: the port is unbound, the core told) and freed, and after the
  build (`after_cabinet_form`) the port zones go on the new sockets, a pad in a socket the form does not have (or one a gun now takes) comes out,
  the guns of the new form are built and plugged in, the collision and pointer boxes are laid again (removed first: `configure_collision` and
  `_build_pointer_shapes` run again on every morph), the art and the game's profile are hung again, the cabinet stays see-through if it is in a
  hand, and the rectangle on the floor follows (`GroundPlacement.set_footprint(size, center)`: a cockpit's base reaches 2 m forward).
- **No collision for what the form adds** (a cockpit, a stage): a player walks into a cockpit and sits on their own chair, steps onto
  a stage with their own feet. Those parts are POINTER boxes (`FORM_BOXES_META`, aimed at they are the cabinet, to hold and carry) and the footprint
  (`FOOTPRINT_META`, a Rect2 in x/z).
- **Pulling the board gives the cabinet its own form back.** A clone takes its parent's form (the table gives it the same key).
- **There is no shooting cabinet to spawn** (the `arcade_cabinet_lightgun` row, scene and variant were removed 2026-10-25): a gun game in the generic
  cabinet's bay makes it one. The laserdisc gun cabinet stays: Daphne is not MAME, so nothing tells the generic one what the game is.
- **There is no switch for it** (the System tab's "Cabinet Shape" was removed 2026-10-25, with its `cabinet_shape` key in the room): the cabinet
  always follows the game. A cabinet baked from no row (a mod's) keeps its form, and the model keeps `set_morph_enabled(false)` as a seam for the
  tests and the probes, which look at what the profile alone hides.
- **Netplay**: the form is derived from the board, so two peers build the same one (it decides whether a port is a gun or a socket). Not measured
  with two peers.
- Tests: `arcade_form_tests` (groups `specs layout build board reach guns ports input animate running boxes footprint bezel odd seating hood scope racegun grip stage`; `arcade_tests game/`
  switches the shape off through the seam and keeps testing the hiding). Mutation-tested: 19 breaks of the code, each turned a case red (the first pass found eight
  that did not, among them a duplicate collision box Godot had renamed out of the count and a freed gun that compared equal to null). Pictures: `arcade_cabinet_probe --forms=sf2,pacman,tmnt,...`
  (windowed; `form_<romset>.png` and `formside_<romset>.png`).
- **The test games asked for** (none run here: no ROMs, no cores; each has its own entry in `arcade-cabinets.md`): `timetrv` is `holo`, `propcycl` `cycle`, `panicprk` `slot` (Panic Park is NOT
  working in MAME 0.289), `sscope`/`sscope2` the rifle (NOT working in MAME 0.289: its two displays arrive as one frame, the monitor shows the first and the scope's lens the second, "Several screens"), `finalap3` a sit-down cockpit (the real one is a
  twin: two seats, two screens; MAME runs one unit), `kurikint` an alternating upright (one panel and a 2P START).
- OWED: a headset (taking hold of a wheel, a stage under the feet), the Quest (building a cockpit at run time on device), real cores for which pad ids the
  driving and dance games read, two peers, the twin cockpits (Final Lap 3, Daytona's linked twins) and the multi-screen games on a real core ("Several screens").

## Several screens: where each one goes (2026-10-26)

**The core hands over ONE frame.** libretro-mame draws the first of the game's views that shows EVERY screen (`render_target::view_for_screen`, `render.cpp`): the layout the driver names
(`GAMEL(...)`'s last argument, else `set_default_layout(layout_...)` in its machine configuration, the configurations it builds on followed), else what MAME generates
(`Left-to-Right`: every screen in a unit square, a 4:3 one 1 x 0.75, a rotated one 0.75 x 1, 1% apart). So a two-screen game arrives as two pictures in one frame, and which part is which
is the LAYOUT's. `Tools/arcade/layouts.py` reads that out of MAME's driver sources and `.lay` files (`<MAME src/mame> <-listxml>`, output `layouts.json`, committed) and
`gen_game_index.py` writes it into the table as `c`: each screen's `x,y,w,h` in the layout's own units, in screen order, `c0,0,4,3/4.03,0,4,3` for two side by side, `c0,0,4,3/0,-3.03,4,3` for the second
over the first. `ArcadeGameProfile.screen_rects()` / `screen_frame()` / `frame_aspect()` / `screen_part(i)` (as fractions of the frame, y down) read it; 356 machines have it, none of the table's
multi-screen games is without (a view that nests its items in groups or repeats, like the CES golf machines', is not evaluated and falls back to the generated one).

| MAME layout (the first view with every screen) | frame w:h | romsets | the cabinet |
|---|---|---|---|
| `dualhsxs` Dual Side-by-Side (and the generated Left-to-Right for two) | 2.68 | 175 | the tube is two screens wide, the body at least 1.0 m; a four-player pair (Run and Gun) grows to take 80% of its body |
| `playch10`, `dualhuov` Dual Under-Over (PlayChoice-10, Mega-Tech) | 0.66 | 104 | a portrait tube in the `tall` body (0.38 x 0.58 m, two screens over one another) |
| `dualhovu` Dual Over-Under (Punch-Out!!, Hang Pilot, Armwrestling) | 0.66 | 13 | the same |
| `cdi` Main Screen + LCD (Quizard) | 1.24 | 17 | a 0.78 m body, the tall glass |
| `triphsxs` and kin: Darius, Ninja Warriors, TX-1, Buggy Boy, Race Drivin' Panorama, Drive Yeah | 4.0 | 18 | a 1.1 to 1.6 m body (a racing housing widens, there is no taller glass for it) |
| `firebeat` Dual Side-by-Side of portrait screens (Keyboardmania), `default-rr` | 1.51 | 5 | the tate body, 0.85 m |
| the custom ones: `nbmj8688` (a mahjong table: a screen with two LCD strips), `rocknms`, `spbactnp` (two stacked), `spdheat` (2 x 2), `ppsatan`, `aquastge`, a five-screen row | 0.46 to 6.7 | 27 | each in the shape of its own frame |

**The tube takes the shape of the frame** (`ArcadeCabinetSpecs.tube_for`, `screen.aspect`): n screens' worth of glass in the frame's shape (area-preserving: the old "n screens side by side" for
two is the same 0.88 x 0.33 m), scaled down whole if the glass cannot hold it, never squashed. **The body follows it** (`screens_body`): the first of upright, `tall` (the tate body with the glass 0.10 m longer) whose
glass is tall enough, and wide enough for the pictures between its sides; a pair over one another (PlayChoice-10: 56 romsets, Mega-Tech 48, Punch-Out) fits the usual 0.66 m. Before, every multi-screen game was drawn as "n
screens side by side" whatever its layout: the 120 stacked ones got a 2.7:1 tube for a 0.66:1 frame, a picture a third of the glass. `arcade_form_tests screens/`.

**Silent Scope puts its second screen in the scope.** `hornet.cpp`'s `sscope` configuration (every Silent Scope, 44 romsets, builds on it) has `lscreen` 512 x 384 and `rscreen` 768 x 236 "for scope", in that
order; the layout is `dualhsxs`, so the frame is 8.03 x 3 units with the monitor's picture in the left half and the scope's in the right. The table says `l1` (the lens is screen 1). The monitor shows the left half
alone, 4:3 on the wide body's whole 0.72 x 0.54 m tube; the rifle's eyepiece (a cup flaring to 10 cm) carries a 7.4 x 5.5 cm screen (`ScopeScreen`, baked by `gen_arcade_gun.gd --variant=rifle`, facing the eye) that shows the right half.
`ArcadeScreenModule` does the cutting with the shader's `view_rect`, found by name among the cabinet's parts, **and only while the core's frame is the shape the table expects** (`crop_applies`, 4%): any other
view (a layout of the player's own artwork) shows the whole frame on the monitor and a dark lens, rather than the wrong part. Every Silent Scope set is `MACHINE_NOT_WORKING` in MAME 0.289, so none has been
seen to run; the cut is made from MAME's layout numbers, not from a picture. Golgo 13's rifles (and Silent Scope EX's, `sscopex`) have one screen and no second one to show, so their scope is a
DIGITAL one: the lens shows the part of the monitor's own picture the rifle points at, 2.5 times (`scope_zoom`, `ArcadeScreenModule.follow_rect`; `arcade-cabinets.md` Silent Scope).

OWED: a real run of any of it (Silent Scope does not run in MAME 0.289; a PlayChoice-10 or Mega-Tech could be tried with a core and the ROMs), a headset to look into the scope, the real cabinets' monitor sizes (no source
gives them; the pairs are drawn at the class of two upright tubes), and whether the real scope's LCD showed the whole second screen (the lens shows all of it).

## Bezels (2026-10-25)

**The scraped bezels are not taken.** ScreenScraper's six bezel types (`bezel-4-3`, `bezel-16-9`, `bezel-16-9-v`, `bezel-4-3-v`, `bezel-16-9-cocktail`,
`bezel-4-3-cocktail`; PNG, each with the hole as `posx posy posw posh` on a 1920x1080 or 1024x768 canvas) are community overlays for a TELEVISION:
captured responses for different games all carry posx 246 / posw 1431, one 16:9 template with a 4:3 hole, and no entry says who made it or from what.
The Bezel Project is the same (measured: sf2 and 3countb share one generic CRT frame with the game's art laid into its wings). A cabinet in a room
already has the frame round its tube; what it wants is the print on the real cabinet's glass.

**MAME's artwork is that print**: a zip (or a folder) per romset (Mr. Do's scans, the progettoSNAPS "Official" pack), whose layout (`<set>.lay`, else
`default.lay`) names each picture, where it stands and where the screen is, and whose credits say whether the bezel was SCANNED ("Scanned bezel provided
by Mr. Do") or drawn ("Realistic bezel by ...", "Custom Widescreen"). `ArcadeBezel` (`Scripts/Objects/arcade/arcade_bezel.gd`) reads the player's
`<data root>/artwork/` the way MAME does: the romset's own, else its PARENT's (the game table ties every clone to its parent now: `tokens_of`,
`ArcadeGameProfile.parent_of`, 6.5 KB more). Of a layout's views it takes the bezel round the screen (the old `<bezel element>` item, or a version-2
`<element ref>` drawn over the screen or named bezel; a picture under the screen is a backdrop), passes over a widescreen or cocktail view and a 16:9
canvas, and takes nothing when the credits call the bezel drawn. The hole is the screen's bounds inside the bezel's. Loaded off the main thread
(a scan is several MB of PNG; every task is waited for once it is done, or Godot aborts at exit), kept at 1024 pixels on its longest side.
The screen module hangs it just behind the glass, scaled so the hole holds the whole tube and centred on it, cut to the monitor's opening; the black
frame makes way while it hangs (`ArcadeScreenModule.set_bezel`). "Cabinet Art" off takes it down; pulling the board too; a morph hangs it on the new
tube. **Nothing is downloaded and nothing ships**: the art is the games' makers', and Mr. Do's terms forbid reproduction for sale.
Not read: `<group>`s and `<repeat>`s of version-2 layouts (a bezel inside a group is not found), overlays and backdrops, the marquee art in the
pack, the Arcade Database's `url_image_bezel` (unknown origin) and its artwork previews (a screenshot with the bezel composited in: no hole).
`arcade_form_tests bezel/`. OWED: a real Mr. Do pack (none was available here), how one looks in a headset, the Quest's decode time.

## Unusual cabinets (2026-10-25)

Moved to `arcade-cabinets.md` (2026-10-26): the seven named games one by one, every form that is built, what a MAME control becomes in libretro-mame, and every cabinet that is not built, with the
survey this section held, and each control's name read in MAME's own driver sources.

## Guns on a swivel (2026-10-25)

**Silent Scope's rifle is fixed to the cabinet and turns about its pivot; so are Operation Wolf's Uzi, Terminator 2's and Beast Busters'** (the
`mounted` and `rifle` forms). Verified against what could be read: the search summaries the research could reach say the rifle is "affixed directly to
the cabinet" (Giant Bomb's wiki: "a hefty plastic rifle fixed onto the machine itself"; KLOV/MOG: "a sniper rifle fixed to the cabinet") and that the game
"learns where it points from the analog hard mount beneath it"; none of them says it comes off, and Operation Wolf's is "a fixed swivel mounted light gun
controller attached to the cabinet". What no source gave: the mount's type, its travel in degrees, its height and the cabinet's dimensions. **Every
number here is an estimate** (the web research for this was blocked twice: the egress proxy refuses the arcade sites, and the search budget of the turn was
spent), and a photograph of the real cabinet is still wanted before the 3D structure is called faithful.

- **How it is built** (`ArcadeCabinetBuilder._gun_mount`): a post on the deck's front edge, a collar and a BALL on its head (no cradle: a cradle's cheeks
  were in the way of a turning gun), and the `Pivot<n>` marker at the ball's middle, which the gun is bolted to; `Holster<n>` is where the gun's origin
  lies at rest, a rifle's grip 25 cm behind the pivot (a pistol-shaped gun's 8 cm), so the gun's body lies in the same place as before.
- **How it is held** (`LightGun.fix_to_mount`, `constrain_grab`; RetroSystem calls it for a gun with a mount instead of building a well): the gun has NO
  snap zone, is `FROZEN` on release (it never falls, never goes anywhere), cannot be called from afar and ignores a second hand. A hand that takes it
  turns it about the pivot: **the grab driver asks the gun where the hold puts it** (`XRToolsGrabDriver`, a RetroXR patch before the pose is pushed:
  `constrain_grab(destination)`), and the answer is the gun with its pivot on the post and turned by yaw (40 degrees either way) and pitch (12 down, 28 up) to
  where the hand aims it, never rolled. A VR hand holding a RIFLE turns it by where the hand IS (the lever: the barrel runs from the hand through the pivot,
  so a few centimetres of the hand are a few degrees, as on a real stock); a hand within 18 cm of the pivot, a short gun, and the desktop (the camera's way)
  go by the way the hand points. Let go, the gun stays as it was aimed and goes with its cabinet (`LightGun._physics_process` pins it to the mount while no
  hand holds it). Carried off by the hand it cannot be: the pivot stays on the post whatever the hand wants (`arcade_form_tests mount/` drives the real
  grab driver with a hand two metres off).
- **Not changed:** a pistol in a holster is still taken out and carried (Time Crisis, Point Blank, House of the Dead), and its well still puts it back where it
  was let go near. The cord follows the gun's cord boss as before.
- **What a fixed gun looks like** (2026-10-27, the spec's `gun_scene`, `ArcadeCabinetSpecs.GUN_SCENES`, the table's `y` on a gun game): the pistol by default, else `stick` (Rail Chase's: a joystick-like handle)
  or `blaster` (Laser Ghost's: a 40 cm gun with a laser imaging unit on its back). Each is the pistol's scene with its own parts (`gen_arcade_gun.gd --variant=stick|blaster`) and the SAME cord boss, grab point and cord, so
  the mount, the wells and the cord route need nothing of their own; the post's height and how far ahead of the grip the swivel is depend on the shape (`_gun_mount`: blaster 16 cm and 22 cm, stick 10 and 5, pistol 13 and 8, rifle 20 and
  25) so the muzzle rests short of the glass (`arcade_form_tests guns/` measures it). A gun game whose player also works a stick (`j`: Gunbuster) has a stick and two buttons beside each gun, and those
  bits reach the core on the gun's port (`_gun_stick_bits`): `arcade-cabinets.md` 9.2c.
- **Owed:** a real hand on a real headset (the lever's feel, the travel, how the hidden controller reads); a second hand on the forestock; that the 2-screen game
  shows its second screen in the SCOPE and not beside the main picture (the cabinet draws two tubes side by side for `s2`); photographs of the real cabinet.

## Service switches (2026-10-25)

**TEST and SERVICE stand in the compartment, on the side opposite the power switch** (`ArcadeServiceModule`, kind `service`, baked with every
cabinet; the module contract grew one kind, additive as the contract says). Every JAMMA cabinet had them, inside the coin door or on a bracket in
the cabinet: TEST toggles the game's own operator menu (a Silent Scope cabinet wants it to set the scope up) and SERVICE puts a credit in without a
coin. They are VRButtons that stand up out of the compartment's floor as the power switch does (at x -0.22 and -0.12 against the power switch's +0.17), so a
hand or a laser reaches them from above once the door is open; a small bracket carries them and a legend lies flat in front of each.

- **When they are there.** MAME says whether the game reads a service switch: `<input service="yes">` in `-listxml`, the table's `v`
  (`ArcadeGameProfile.has_service`). A game that reads none has them taken away and out of the pointer's reach
  (`ArcadeServiceModule.set_enabled`, from `apply_game_profile`, as an unused coin door is); no game, or one the table does not know, shows both.
  MAME's `tilt` is not a switch a player works (a pendulum in the cabinet) and is not built.
- **What a press does** (`RetroSystem.press_core_service`, then `ArcadeServiceKeys`). **What the core calls it is believed over a guess**: the
  descriptors (`Libretro.GetInputDescriptors`) are searched for words that say test (`Test`, `Diagnostic`, `Service Mode`) or service (`Service`,
  `Service 1`, which are never the test input), joypad ids and keyboard keys only. A pad id is held on its port for 0.12 s through the cabinet's input
  (`ArcadeInput.tap_pad_bit`, so a gun port gets it too); a key is tapped through the same path the DIP screen's keys take (`_tap_core_keys`, netplay-aware).
  A core that names nothing gets MAME's own keys: F2 (`IPT_SERVICE`, Service Mode) and 9 (`IPT_SERVICE1`). No core running, nothing is pressed.
- **The words are white, outlined in black** (2026-10-26: they were near-black on the grey bracket and could not be read), and **a second bracket in front of
  the two carries the operator's SELECTOR**: LEFT, DOWN, UP, RIGHT and ENTER (`LeftButton`...`EnterButton`, five VRButtons at z 0.305, 4.5 cm apart). Most games'
  test menus are worked with the first player's stick and button 1 (a JVS I/O board had its own Up Select, Down Select and Enter for the System 23 games), and a
  cabinet with a wheel, a gun or a dance stage has neither: the selector sends one tap of the first player's direction, or of button 1 for ENTER, on port 0
  (`ArcadeServiceKeys.selector_bit`, `RetroSystem.press_core_service`, through `ArcadeInput.tap_pad_bit`: a gun port gets it too). Sega's menus want TEST to
  select and SERVICE to step (Out Run's TEST is `PORT_SERVICE_NO_TOGGLE`, a momentary press, and SERVICE is `IPT_SERVICE1`): the two buttons do exactly that.
  A game that reads no service switch shows none of the seven.
- **Pressing TEST or SERVICE while the cabinet only shows its game starts it, as a coin does** (`RetroSystem.press_core_service` while `attracting`:
  `attract_first_use(&"service")`), and the press WAITS for the game like a held coin: `ArcadeInput.hold_service` keeps it until `game_ready()` (the core has
  run `COIN_WAIT_SECONDS` of emulated frames: a board still testing its RAM reads no switch), then makes it, one every half second, in the order they came. A press that
  waited for a run that stopped, or for a game the core refused, is let go. The selector starts nothing (no menu is open yet).
- **TEST is also how a game's own memory is put right** (Silent Scope's BACKUP DATA ERROR: it is Konami's check of its Timekeeper chip, not a MAME error). The cabinet says so on the
  first start of a game whose default memory is hand built, and **Options > DIP Switch > Game memory** sets a memory aside or puts one back: `arcade-backup-memory.md`.
- **NEVER RUN AGAINST A CORE here** (the sandbox has no core and no ROM). Measured elsewhere in this file: FBNeo does nothing visible on F2 on dino and its pad
  descriptors for sf2 do not include a service input (`arcade_cabinet_probe`'s recorded lists end at the six buttons and the directions); whether it names the
  service input on a key descriptor, and what Silent Scope does with F2 under MAME, are OWED to a real run with `Tools/cores/arcade_descriptors_probe`.
- Tests: `arcade_form_tests service/` (the flag for Silent Scope, Street Fighter II, Time Crisis, Pac-Man and an unknown romset; the descriptor lookup; the
  switches on the other side of the compartment from the power switch, on its floor; there for Silent Scope, gone for Time Crisis and back for the next; F2 and 9 with
  nothing named, a pad id and a key when the core names them, a tap that lets go; nothing with no core; the white words, the selector's place and its taps);
  `arcade_attract_tests service/` (TEST starts a showing cabinet, a game still coming up is not pressed, SERVICE and two in order, a press let go with a refused game and with a
  run that ends). Each case was broken and watched go red.

## The pedal (2026-10-25)

**A gun game's foot pedal is its player's button 2, and a headset reads no feet.** What MAME 0.289's source says: Time Crisis
(`namco/namcos22.cpp`, `timecris`) and Time Crisis II and Crisis Zone (`namco/namcos23.cpp`) name `IPT_BUTTON1` "Gun Trigger" and
`IPT_BUTTON2` "Foot Pedal". libretro MAME's gun device (`src/osd/modules/input/input_retro.cpp`) makes the gun's Aux A its item
`BUTTON2`, and P1 BUTTON2's default sequence (`inpttype.ipp`) holds `GUNCODE_BUTTON2_INDEXED(0)`: a gun's Aux A IS its player's pedal.
The joypad device maps RetroPad A to BUTTON2 (`button_mapping`, B A Y X L R; none of the three games is in its remap lists). The note
that stood here, "MAME maps it to a keyboard-style input that a lightgun port does not carry", was wrong. The table's `f`
(`GUN_PEDAL` in `gen_game_index.py`): `timecris`, `timecrs2`, `crszone`, each ONE gun (a System 22/23 board is one player's; the twin
cabinets are two boards linked), and `timecrs3` and `timecrs4` (System 246, two guns and a pedal under each: their driver declares no controls, so the
guns and the pedals are the curated list's, not MAME's).

**Three kinds of switch (2026-10-27, the table's `f<kind>`, `ArcadeGameProfile.pedal_kind()`)**, all on a gun's own `claim_button`, all worked by the same gestures below:
- `cover` (`f`, Time Crisis, Crisis Zone): DOWN while the player is out of cover, taking cover lifts it. Everything below is written for this one.
- `action` (`fa`, **Virtua Cop 3**: the research, three agreeing snippets, says a foot pedal switches the ES mode on and the sources name one pedal; one under each gun is assumed,
  as for Time Crisis): the other way round. Up with the gun in a hand, and the SAME gestures (A or X, `arcade_pedal`, the free hand's trigger, ducking) step on it. Its hint says "Hold {g} to step on the pedal"
  (`pedal_act*`). An ES mode that is on for the whole game would be a game played in bullet time.
- `sensor` (`fs<n>`, **Golgo 13** `golgo13` `g13knd` on MAME's button 2 "Sensor", Juusei no Requiem `g13jnr` on button 3 "Scope Sensor"): a rifle's proximity switch in the scope, not a pedal at all (no plate:
  a small box on the deck beside the post, `ScopeSensor`, with a lamp, `SensorLamp`, that lights while it is on). **MAME's own comment on it** (`namcos10.cpp`): "If the player is 10cm or closer then this will be on.
  For playability, make it so that the player has to explicitly toggle the scope to be off to simulate stepping away from the scope instead of always having to hold the scope sensor button". That is why Golgo 13
  "only fired in the menus": the game's shooting waits for the sensor and nothing sent it (`arcade-cabinets.md` Golgo 13). It is on while the rifle is in a hand (a headset reads no eye, a desktop no head: the gestures above take the
  eye OFF the scope, the way they take cover), and **while the head is within 10 cm of the eyepiece's lens, kept to 13, whatever the hands do** (`ArcadeInput._eye_at_scope`, `SCOPE_NEAR`). The pad bit is the MAME
  button's (`ArcadeProfiles.button_bit`: button 2 is the pad's A and the gun's Aux A, button 3 the pad's Y and the gun's Aux B). Estimated: what the game does with the sensor off (nothing found says), that a held rifle should mean "sensor on".

- **How it is worked** (`ArcadeInput._step_pedal`, since 2026-10-25 later; first it was pressed by a held A/X or key, which tired
  the thumb for the whole game): **while that player's gun is in a hand the pedal is DOWN, out of cover, and taking cover lifts it**;
  with no gun in a hand it is up. `AppPrefs.arcade_pedal_mode` (Options, Systems, "Gun Game Pedal") says what takes cover:
  - in every mode the gun hand's A or X (the gun's own Aux A, so it follows the light gun bindings; on the desktop its key) and
    `arcade_pedal` (`ArcadeInput.PEDAL_ACTION`: Space in `project.godot`, rebindable on the Controls page beside the trigger; RB on
    the player's pad, `DesktopPad`; a foot switch that types the key, stepped on to HIDE: NOT tried);
  - `button` (the default): nothing else;
  - `free_hand`: the other hand's TRIGGER as well, when it is tracked and holds nothing. Its laser is off meanwhile
    (`VrPointerBlock`, given back when the mode changes, the gun is let go or the cabinet goes off), or the squeeze would click
    whatever it pointed at. Not the grip: it is the grab, and held on the cabinet for a second it picks the cabinet up (`HoldToGrab`);
  - `duck`: the head 18 cm under the highest it has been since the gun was taken, back out above 12 (`DUCK_DEPTH`,
    `DUCK_HYSTERESIS`), over the `XROrigin3D` the camera stands in. The highest, not its height at the grab: a gun taken from a low
    holster would otherwise ask for a duck under that. Measured afresh at every grab; seated, A/X is the way.
- **The cabinet takes the gun's Aux A over** (`LightGun.claim_button`): the game must hear the PEDAL, which the hand's Aux A only
  lifts, so a claimed button's hand press no longer reaches the core (`LightGun._told`) and the cabinet's own does
  (`set_external_button`). A gun on a port with no pedal keeps its Aux A.
- **The hint**: a gun at a wired pedal carries a held-hint row per mode (`LightGun.set_cabinet_hint`, ids `pedal_cover`,
  `pedal_cover_free_hand`, `pedal_cover_duck`, `pedal_cover_desktop`, each learned on its own), declared while the cabinet is off as
  well, so the grab that starts the game shows it. `HeldHint.glyph_name` has two new tokens for it: `{ax}` the holding hand's A or X,
  `{other}` the other hand; on a pad the desktop row names RB (`DesktopPadService.PAD_ROWS`).
- **What it sends**: the pedal as the gun's Aux A AND the joypad's A on that port (`_send`, through `netplay_route`), as START and
  the coin already go twice, so button 2 is pressed whichever device MAME reads it from.
- **The plate** (`ArcadePedalModule`): `show_pressed` with what was sent, eased 15 degrees down about `PedalHinge` in 0.08 s (toe first,
  the heel on its pin) and back to exactly where it rested. Local: a peer does not see another player's foot.
- **Wiring**: a pedal is a switch on its player's button 2, as on a real cabinet converted to another game: `active` (true unless a
  scene says otherwise) and `port()`, its player, or player 1 for one that names none (a mod's). A form builds a pedal only for a game
  that had one (`for_game`; no shipped cabinet has one of its own any more). Switched off or only showing its game, every pedal comes up and no gun keeps it pressed.
- **The ways that were weighed and not built**: holding A/X to step OUT (the first version; tiring), aiming the gun off the screen to
  hide (no button, but every hide costs the aim). The free hand's grip (see above). Ducking is the most natural and the most tiring:
  hundreds of hides a game.
- `arcade_variants_tests pedal/` (up in the holster, down in a hand; the gun hand's A through the real binding and a fake tracker
  taking cover with the hand's own Aux A not sent; the key; an unwired pedal and player 2's gun keeping their Aux A; the free hand
  in either hand, its laser off and given back; ducking with its hysteresis, the highest head and a fresh grab; the hints per mode;
  the setting saved and an unknown one read as the default; let up when switched off), `arcade_form_tests guns/` (the morph's pedal
  wired to the input), `desktop_pad_tests map/` and `rows/`, `binding_tests` (the arcade's Controls page). Mutation-tested. OWED: a
  real Time Crisis romset on MAME (none here: that the core takes button 2 from the gun, the joypad or both is read from its source,
  not measured), a headset (how ducking and the free hand feel, the hint), the Quest, two peers.

## Hands on the panel (2026-10-25)

**A headset's hands work the controls themselves**: a fingertip presses a cap, the trigger takes hold of a stick, a wheel, a dial, a
trackball, a gear lever, a motorbike's bars. No attaching first. Attaching (`ArcadePanelGrip`) stays, and is how a keyboard or a pad
plays; the two add up. `ArcadePanelHands` (one per `ArcadeControlModule`, made in `attach`) does it; `ArcadeInput` adds what it holds to the
player's state BEFORE the state is sent (`_with_hands`), so it leaves through `netplay_route` like an attached controller's, through the
player's own stick bindings (`_map_sticks`, factored out of `_direct_state`: a hand-held stick is the LEFT thumbstick, a second stick the RIGHT,
a wheel, bars, dial and trackball the left stick's X or XY, so "left+dpad" sends the analog axis and the D-pad bits, "dpad" only the bits).

- **Fingers** (`Poke`): a fingertip (`PokeTip.tip_of`) inside a cap's own mesh box, grown `POKE_SIDE` (5 mm) at the side, `POKE_OUT`
  (10 mm) above the face and `POKE_IN` (25 mm) through it, presses it, and HOLDS while the finger stays (a Wii Remote's 1 and 2, `VRButton.is_held`'s contract,
  with its slack: `RELEASE_SCALE` 1.8 and `CONTACT_GRACE` 0.05 s). A hand presses ONE cap, the nearest the tip is to the middle of, and a finger
  rolled onto the next cap lets the first go at once. A hand that holds a gun or a pad (`PokeTip.is_poking`) or a control presses none; a cap
  the game does not use (hidden by `apply_profile`) cannot be pressed and a press on one that becomes hidden is let go. **The zone is where
  the part RESTS, not where it is drawn**: a pedal under a finger goes down 16 degrees and a zone that went with it would let go of the finger
  pushing it. The racer's two pedals (`GasDeck`, `BrakeDeck`: R2, L2) and the dance stage's arrows are the same thing. The caps are 52 mm
  apart and 31 mm across, so the zones of two never meet.
- **Feet** (2026-10-27): nothing tracks feet, so the body is the HEAD's place on the floor (`ArcadeInput._body_point()`: the camera's x and z, the XR origin's y, or 1.6 m under the camera
  where there is none). A panel of a dance stage (`stage_panel` meta on the plate, `Poke.foot`) is pressed while that point is over its square grown by `FOOT_MARGIN` (2 cm) and the floor
  under the player is within `FOOT_BELOW` (18 cm) under the panel's top (walking up from the room's floor onto the platform) to `FOOT_ABOVE` (6 cm) over it (`ArcadePanelHands.foot_on`, pure).
  `update_body(Vector3.INF)` (the machine off, no camera) lets every arrow up. The press joins the hands' (`buttons()`, `active()`), so the panel needs no attaching for it and the
  netplay route is the same as a fingertip's.
- **Taking hold** (`ControlGrab` and its kinds): the TRIGGER's rising edge (`TRIGGER_ON` 0.6, off at 0.4) with the tip within the handle's reach: `STICK_REACH`
  5 cm of the ball, `DIAL_REACH` 4.5 of the knob, `BALL_REACH` 6, `LEVER_REACH` 5.5, `BARS_REACH` 7 of a grip, the wheel on its rim (0.45..1.4 of
  its radius, within 7 cm of its plane). **A trigger already held on the way in takes hold of nothing**: only the edge does, or sweeping a hand past
  with a held trigger would pick things up. Let go with the trigger, when the hand loses `is_poking` (it picked something up), or when it is
  `LET_GO_DISTANCE` (35 cm) from the handle (a stuck trigger, a lost tracker). **There is deliberately no grip**: a squeeze is how a hand picks a
  pickable up, a cabinet IS one (`HoldToGrab`, a second on the cabinet carries it), and on a panel a squeeze is the ATTACH; VRKnob's rule, for the same reasons.
- **What each does with the hand**: *stick* leans where the hand takes it from where it was taken (`STICK_THROW` 3 cm is a full lean; the ball itself
  travels 23 mm, so it follows within 7 mm), from the lean it had (a key holding it over does not snap it), a square gate, a dead zone of `STICK_DEAD` 6%,
  and the ball is drawn at the hand's lean with no easing; let go, it springs back as it always did. *wheel* turns with the hand about the axle, to the lock
  (`WHEEL_LOCK_DEG`) and no further: it is accumulated a step at a time and clamped, so **a hand that goes past the lock winds nothing up**, and
  turning back turns the wheel back at once; the wheel is NOT the hand's absolute angle (a test pins that), and a tip near the axle has no angle so it
  is ignored; let go, it comes back to centre by itself. *dial* turns freely; the SPEED it is turned at is the deflection (one turn a second is full), as
  holding LEFT or RIGHT turns it, because that is what the games read; held still it sends nothing. *trackball* rolls where the hand pushes it, the
  surface speed under the hand against `BALL_SPEED` times the ball's radius (what the picture rolls at full deflection); a speed too. *lever*: past 60% of its throw it is in
  high gear and STAYS there when let go (a gear lever stays), pulled back under 40% the same way; what high gear SENDS is the game's (one tap of the game's own shift
  button for a toggle, the button held for a held shifter, `up`/`down` taps for a sequential box: `arcade-cabinets.md` section 2, Final Lap 3). *bars*: the bike leans by the sideways push (`BARS_THROW` 15 cm
  is a full lean, 14 degrees at the 62 cm the bars stand over the stand), and a BICYCLE's bars (Prop Cycle) also take the push forward and pull back (`BARS_PITCH_THROW` 10 cm is the whole of it, the
  stick's Y, pulled being DOWN) with their own let-go distance (`BARS_LET_GO`, the grips stand 30 cm out); *crank*: the trigger at a pedal (`CRANK_REACH` 6 cm) and the hand turns it like a dial: the
  SPEED it is turned at is the right stick's Y (forward up), and a hand on the axle has no angle; *slide*: a lever in a slot (Panic Park) taken at its ball (`SLIDE_REACH` 5.5 cm) and pushed along it,
  `SLOT_TRAVEL` 14 cm being all the way (the left stick's X); the bars' handle is the middle of the bars, not the pivot the bike leans about (the
  hands are 60 cm above it and the let-go distance took hold of nothing); *throttle* (a flight cockpit's lever): taken at its knob (`THROTTLE_REACH` 6 cm), pushed or pulled
  (`THROTTLE_THROW` 10 cm is all of it) and **left where the hand left it** (`ThrottleGrab.value`, sent as the right stick's Y while it is anywhere but the middle; the machine switched off or the run
  over puts it back, `reset_latched`); a flight STICK's throw grows with its shaft (`StickGrab._throw`: 3 cm for the deck's 8.5 cm, 9.5 cm for the cockpit's 36 cm: the grip stays with the hand).
- **Clockwise seen by the player is RIGHT**, for the wheel, the dial and the bars. The dial used to turn the other way (a turn about +Z, which is toward the
  player, is counter-clockwise); `_dial_angle` is now clockwise-positive and drawn `Basis(BACK, -angle)`. Holding RIGHT and a hand agree.
- **The laser** (`VrPointerBlock`): a hand within `REACH_SCALE` (1.5x) of a control it could take, or holding one, has no laser (back the moment it is
  not), or the trigger it pulls for the stick would also click whatever the laser was on. And `ArcadePanelGrip` takes no press from a hand that is
  reaching (`ArcadeControlModule.hand_reaching`, asked afresh from the hand's place, not from last frame's state: the pointer's press can come before the panel's step). A finger on a cap keeps
  its laser. The reticle (no hand) attaches as before. Everything a hand held or blocked is given back by `release_all`: the machine off, the panel hidden
  or freed (`_exit_tree`, a morph under a held stick), a hand lost. An owner that leaves a laser blocked leaves it dead for the session, so this is pinned.
- **The fist round a control is the control's** (the squeeze, not the trigger): `RetroSystem.can_pick_up` is false for a hand that holds or reaches for a control
  of the cabinet (`RetroSystemModelArcadeCabinet.hand_busy`), or the squeeze that goes round a stick would start the carry ring (`HoldToGrab`) and, held a second,
  pick the whole cabinet up under the player's hand; and `ArcadePanelGrip` takes no squeeze from it either (a squeeze round the stick does not attach). A squeeze on the
  panel clear of the controls attaches as it always did, and every other hand picks the cabinet up as before. `reaching` is the one test all three ask (the laser, the
  press, the squeeze, the carry), from where the hand is now. For the wheel the "reach" is the rim's own radius and a wider band off its plane, not 1.5 times the radius
  (that would be the whole panel).
- **Somebody is at the cabinet**: `ArcadeInput.engaged()` is true while a hand presses a cap or holds a control (`hands_busy`), or a hand-only player's attract
  game would be put away after 120 s (`ArcadeAttract._watch_idle`), and a finger on a cap or a hand on a stick starts the game from attract as a coin or an
  attached panel does (`first_use` `&"panel"`). Hands step even while attracting (so that they can) and are let go when the machine is off.
- **Hover**: a control a hand could take is outlined green, amber while held (`WidgetOutline`, made the first time a hand is near, one per control); a pressed cap shows
  by sinking, and the fingertip's contact disc lands on the face it presses (`PokeTip.claim_box_face`). Haptics: a click on a press and a take, a softer one on a release,
  a tick as a stick crosses the point its switch would close (`HAPTIC_KEY`).
- **Not built**: grip-held sticks (above); hands on the foot pedal of a gun game (it is down while the gun is in a hand; there is nothing to press); the stick's
  8-way gate (a hand that drifts across the 35% line gets a diagonal; MAME's `ways` is in the table and could snap it); two hands on one wheel (the first holds it);
  hands for the desktop (it attaches, and the keyboard plays).
- `arcade_hand_tests` (167 checks, no core and no headset: a fake hand, an `XRController3D` on a tracker, puts a tip and a trigger where the case says, on panels
  the cabinet really builds): the pure zone; caps (press, hold, grace, slide, two hands sharing, hidden caps and panels, a hand holding something, the machine off, a lost
  controller); pedals; the stick (reach, edge, directions, diagonal, dead zone, the 35% line, drawn at once, spring back, a key's lean kept, one hand, 35 cm, hidden);
  twin sticks; the wheel (rim only, the sign, the lock, no wind-up, drawn at once, back to centre); the dial's sign and speed; the trackball; the lever's latch;
  the bars; a bicycle's bars and crank and Panic Park's two levers (`cycle/`, `slot/`); a flight cockpit's stick and throttle (`fly/`: the throw by the shaft, the lever staying put, a pad's larger deflection winning, put back when the machine goes off); the port (a cap on the right port, the cap sinks, the bindings apply, off sends nothing, a pad and a hand add up); the laser (off, on, given back by a release, the
  power, a morph) and the panel's press; the carry (a hand on a control cannot pick the cabinet up, the other hand can; the squeeze); attract. Mutation-tested (48 mutants of the
  hand code, every one caught: the tests that let three through, a pedal zone that followed the pedal down, the dial's direction under a key and a swapped gas and brake bit,
  were made to catch them; and 20 more for the bicycle's bars and crank and the slot's levers, 19 caught and one that cannot be: the crank's `end()` clearing a speed that `begin()` clears too). **OWED: a headset.** Every number above is an estimate: reach, throw, zones, speeds. They are consts so the feel can be tuned on
  a device, and nothing here says how it feels. Also owed: hand tracking (Capsense's index tip and pinch trigger go through the same `PokeTip` and `trigger`, not tried), the Quest's cost
  (a few distance tests a frame a panel when a hand is within 2 m, none otherwise), two peers.
