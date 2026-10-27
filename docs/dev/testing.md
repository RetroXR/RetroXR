# Headless testing, suites and probes

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

## Headless Testing & Validation

There is no unit-test framework in the xUnit sense, but there **is** a runner and it
gates CI. `Tools/run_tests.py` runs every `RetroXR/Tests/*.tscn` that has a `.gd` beside
it, in a stable order, and `.github/workflows/tests.yml` builds the six extensions and
runs it on every push. Beyond that the project is validated by running the Godot editor
**headless** for compile/scene checks, plus small "probe" scenes for functional tests.
All of it works without a VR headset (desktop fallback) and without a display.

```bash
python Tools/run_tests.py            # every suite
python Tools/run_tests.py --list     # name them and exit
python Tools/run_tests.py --update-baseline   # after deliberately adding cases
```

**A case count that DROPS fails the run.** `Tools/test_baseline.json` records each
suite's count, and the runner compares against it — because a suite whose group
quietly stops running still passes every case it did run and still exits 0,
which is the same blind spot as a suite nested in a subfolder. Only a drop
fails: a rise is how the suites grow, and a suite missing from the file is new
rather than broken, so adding cases never needs a second commit. A filtered run
(`--only`, or a forwarded `--only=<group>`) skips the check, since a lower count
there is the point. When a drop is deliberate, re-run with `--update-baseline`
and commit the JSON with the change that caused it.

**Every suite extends the one harness, `RetroXR/Tests/test_suite.gd` (`TestSuite`),
by path** (`extends "res://Tests/test_suite.gd"` -- a headless run reads class
names from the editor's cache, and a suite must not depend on that being fresh).
It owns `_ok(cond, what, detail)` / `_eq(got, want, what)`, the tally
(`_pass_count`, `_fail_count`, `_case_count()`), and `_finish()`, which prints the
ONE summary line the runner reads and quits with the matching exit code:

    [<tag>] RESULT <passed> passed, <failed> failed: PASS|FAIL

Set `suite_tag` first thing in `_ready`; `quiet_passes` prints failures only (av,
combo_tv, gb_printer) and `show_pass_detail` prints a passing case's measurement
(rope). Hooks: override `_wanted(what)` to skip-and-not-count a check outside a
`--only=` group that is matched on the check's own name (archive, card, ra,
spawn_menu, quality), and `_on_fail(what)` to note which CASE a failing check was
in (av, combo_tv, speaker). Helpers: `_wait_until(cond, timeout_s)` polls a
condition once a frame up to a generous bound -- use it instead of a fixed timer
for anything asynchronous (a shrink-and-free, a retry on a SceneTreeTimer, an
audio device draining), and count physics frames instead where the production
code runs on the fixed physics delta; `_snapshot_file` / `_restore_file` put a
player's `user://` file back byte for byte; `_app_prefs_round_trip(values)` saves
through the live AppPrefs and reads back through a fresh, out-of-tree one, and
`_app_prefs_default(key)` is a fresh install's value -- the behavioural check for
"this pref is saved, read back and defaults to X", in place of grepping
`app_prefs.gd`. **A suite that exits 0 without the summary line is reported
`NOSUMMARY`, not OK**: it quit some way other than `_finish()`, so its count
(and so the baseline guard) means nothing. A case is never `_ok(true, ...)`:
assert the state the case names, or, for "does not crash", that the case really
reached the race it is about (deck_tests `_free_mid_decode`).

**A `SCRIPT ERROR` inside a suite fails the run (2026-10-26).** GDScript abandons the function that hit it, so every
check after the line is never run and the process still exits 0. The runner used to say OK, and the only trace was a
count that fell: `arcade_form_tests` lost 13 checks that way (2026-10-25: a spec key a test still read had been
removed) and re-baselining the drop made it official for a day; `link_tests` had been skipping four since a plug lost
a property (its `systemid`), and `av_tests` and `system_tests` printed one each (`RetroSystem._reopen_port` waiting on
a tree a machine had left, `_unbind_port` assigning a freed controller to a typed variable). The runner now reads the
output, after the noise filter: a suite that exits 0 with a line that starts `SCRIPT ERROR` is **`SCRIPT`**, listed
with its lines like any other failure. `--allow-script-errors` reports it and does not fail the run, for finding out
what an environment prints. A drop in a count you did not set out to make is still a bug until proven otherwise:
grep the suite's output for `SCRIPT ERROR` before touching the baseline.

Because the runner globs `Tests/*.tscn` **non-recursively**, `Tests/` stays flat. Do not
nest it into subfolders — a suite in a subdirectory is silently never run, which is the
one failure mode a green CI cannot show you. (`RetroXR/Tools/` is the opposite: it is
foldered by topic, see below.)

**The bar for living in `RetroXR/Tests/` is exact:** a scene that checks itself, runs
unattended with no ROM, core, headset or device, and **exits non-zero on failure**, so it
can gate a commit. **It also boots with no mods:** `ModManager._is_test_run()` sees the
`res://Tests/` scene on the command line and skips pending installs, discovery and
mounting (the state file is still read, so a save writes it back unchanged). With the
player's `xenu.ps2` enabled, a modded PS2 has no stand-in shelf (`system_tests` `tray/`)
and its shell's `ILinkPort` MARKER came first by name (`link_tests`; look a socket up with
`ILinkPort.on()`). Probes under `Tools/` keep the player's mods.
The suites, with their measured case counts and runtimes (Windows,
debug build, 2026-08-27 — all passing):

| suite | cases | time | covers |
|---|---|---|---|
| `netplay_tests` | 685 | 32 s | the whole lockstep stack, two NetworkManagers deep (§2f) |
| `romm_tests` | 312 | 17 s | the pure-logic half of the RomM stack |
| `binding_tests` | 254 | 12 s | which control map a platform resolves to, and the keys a scope is said to have without the InputMap being touched (`DesktopBindings.display_name_for_system`, the same layers as `apply_for_system`) |
| `object_sync_tests` | 127 | 8 s | the shared-room network layer, 2–3 real ENet peers |
| `scene_tests` | 247 | 20 s | SceneManager and the save gates around it. `cartbody/`: a restored cartridge's body GLB comes in through `ModelWarmer.acquire` before the cartridge is built (it loads synchronously in `_ready`; cold, an N64 cart was a 625 ms frozen frame on a Quest). Mutation-tested: drop the restore's cartridge branch and it fails. `curtain/`: a slot loaded into the room already standing goes up under the loading screen (owner `slot_load`), stays covered until the load hands back, shares one screen between two overlapping loads, and raises nothing for Clean Room or a slot that will not read. Mutation-tested, 3 breaks. `multitap/`: a real SNES with the multitap in its second port and pads in sockets 1 and 3, saved, cleared and loaded: the tap comes back plugged in, at its SELECT setting, each pad in its socket and players 2 and 4 again, the console's first port still empty. A tap's entry (`retro_multitap`) owns its sockets, so a pad in one saves NO console port: the console files that pad under the port the tap fans out to, which is also one of its own sockets, and it came back plugged into the console (into its FIRST port, the tap's being taken). The tap's port is found by its PLUG (`cabinet_port_of_plug`), because at 5P the port's holder is the pad in socket 1. Mutation-tested, 4 breaks. |
| `poster_tests` | 112 | 11 s | the posters feature, stick/peel/conform |
| `rope_tests` | 90 | 75 s | what a cable does when it meets furniture |
| `av_tests` | 41 | 35 s | what reaches a television's inputs (§2c) |
| `system_tests` | — | — | the machine controller's port, pad, save and disc rules |
| `link_tests` | — | — | which socket each end of a link lead belongs in |
| `ir_tests` | 119 | 10 s | the Game Boy Color's infrared link, which has no lead (§2e-ir): `view/` is `IrBus.in_view` on bare transforms (reach, beam angle, hysteresis, BOTH ways round, never what is behind a window, and side-by-side units whose beams overlap seeing nothing); `pair/` `hold/` `power/` `nearest/` step the bus by hand over stub machines -- each `IrPort`'s own tick is switched off, or a look arriving between two steps is a dwell nobody counted; `sight/` puts a real `StaticBody3D` between two windows (the room and loose objects block, a hand's collider does not); `netplay/` is the hand-off against a stub session (scheduled by the host and not joined, once, on port 1; nothing for a non-host, a half-covered pair, or a session still starting); `machine/` and `room/` use real `system.tscn` machines -- the port's beam leaves the edge its window is on BY SIGN, the Game Boy has none, the glow follows the link, `net_link_bus` finds the pair once, and a unit's own seated cartridge, which the sight line really passes through, does not hide its partner. No core runs, so nothing here lights a window by itself: the glow follows the cores' peer count. The gift itself is `Tools/link/gbc_ir_room_probe`. Mutation-tested, 38 breaks |
| `state_tests` | — | — | savestate capture/restore rules |
| `expansion_tests` | — | — | the expansion units and their catalog |
| `bay_tests` | — | — | cartridge bays |
| `arcade_tests` | 507 | 10 s | the arcade cabinet and its JAMMA board (§2z-arc): the data (a JAMMA bay takes arcade boards only; ten buttons (a rhythm game's, MAME's 7 to 10 the pad's L2 R2 L3 R3), START and the coin are twelve different bits, the coin SELECT; a mod's bay kind adds and removes its systems), the pure input (masks, 8-way, panel + the player's own controller OR together, the coin pulse about a tenth of a second, a controller in a front socket silences that panel), the screen fit (a vertical game pillarboxed on a landscape glass; without geometry a landscape frame is 4:3, not its 1.71 pixel ratio), the bridge exposing `GetVideoGeometry` with every field and 0 for an idle machine, the board (size, comb of 28 + 28, a `Label` on the component side facing +Z, spawned at 1:1 with art painted), the registry and the spawn card (the cabinet, a pad and a gun; no box and no video lead), a built cabinet (modules found by type, two sockets whatever `SystemInfo` says, six collision boxes, the power switch in the bay), the door (the slot gated by it, the lid angle round trip, the hinge driving the same gate), a board seated and pulled, a pad plugged into a front socket owning its port, a coin that lands and only then says so, a ray aimed at the door, the coin slot, the power switch and any part of a player's panel reaching THEM (the panel as one pointable thing) and not a box over the cabinet, the panel lighting whole when aimed at and attaching on a press (one panel at a time, let go when the machine goes off; attached, the keyboard plays that player with no Scroll Lock, and only that player), the caps sinking and the stick leaning with the input, the hold-to-grab state (fills, restarts, finishes once; the cabinet asks for two seconds, an ordinary console does not; it goes see-through in a hand), the board's title staying on its sticker after a drop, the ASYNC restore (what the loading overlay waits on) finishing with a populated cabinet in the room, the options panel standing to the cabinet's right at eye height (other machines keep it over their top), notices (an error, an achievement) floating clear in front of the monitor, the board's sticker taking the cover (the front of a laid-flat box) and never the cabinet render, the cores a cabinet lists (either tile's, and the ones filed under `arcade`), the System tab's core picker (none without a core installed, "Default" the empty choice, the pick saved with the room), and a saved room bringing the cabinet back with its door as it was. Needs no GLB; the visual proof is `Tools/models/arcade_cabinet_probe`; the cabinet FOLLOWING the game in its bay (`game/`, §2z-arc): the MAME-derived table (sf2 6 buttons, dino 2, the gun games, a paddle with a pedal as a driving game), FBNeo's own words on the caps and MAME's generic whole-pad descriptors ignored, panels, sticks, caps and coin doors drawn or taken away and put back when the board leaves, an unknown romset leaving the cabinet whole; the BIOS list generated from MAME (`profiles/`: no file twice, every entry optional and described by its own path, System 246/256/573, NAOMI and twenty more boards by name, at least 90 sets, FinalBurn Neo's `atarisy1.zip` and the fourteen it had); the table's banks of monitors (`d`: TX-1, Buggy Boy's sit-down sets, Race Drivin' Panorama and Driver's Eyes list their three parts left to right whatever order MAME numbers them in; the upright Buggy Boy, Darius and Ninja Warriors are no bank) |
| `seat_tests` | 169 | 5 s | the seats (§2z-seat): the pose arithmetic on bare transforms (the head lands over the eye point, on the floor, facing the seat; standing puts it over the floor point), sitting and standing through a stand-in rig (head, heading, desktop camera height, the body STAYING ON, the origin pinned, locomotion held, one seat at a time, a seat picked up or freed or the room left letting go), the cushion's pointer event, every family's markers, a sit-down cabinet's OWN seat (eyes level with the middle of its glass and 0.72 m over the cushion, pressed to sit, one seat at a time with a chair, a cabinet picked up or its form taken down or the room left letting the player go, no pointer box over the cushion: `cockpit/`), a motorbike's and a bicycle's saddle as a seat (eyes over it, the cushion on its top, a floor to get up onto beside the stand, off the part that leans so a full lean leaves the head still, no pointer box over it: `rider/`), a cockpit of TWO seats (Lucky & Wild: the driver's and the gunner's each with eyes at their own side of the glass, getting up on the outside of their own seat, one at a time, a cord to neither: `pair/`), and the plain-scene save round trip. The real rig is `Tools/models/seat_look_probe` |
| `arcade_form_tests` | 990 | 19 s | the cabinet taking the shape of the game in its bay (§2z-arc, `arcade.md` "The cabinet takes the shape of the game"): the spec each kind of game asks for (Street Fighter II the generic cabinet itself, an alternating game one panel and a 2P START, a tate 19-inch tube, a monitor on its side the tall `tate` body with the window cut to the picture (`tate/`), three, four and six panels on a body as wide as the deck needs (no wings) with a door and a socket under each panel and the front closed beside the bay's door (`wide/`), twin sticks, a trackball, guns in holsters, on posts and a rifle with their pedals only where the game had them (wired to the input after the morph, the plate tipping), the fixed guns that are not pistols (Rail Chase's joystick-like ones, Laser Ghost's three blasters, Gunbuster's pistol and stick stations: the scene each gun is built from, every gun fixed, the muzzle clear of the glass, the stick's bits on a gun's port), a sit-down cockpit with and without a roof, Road Blasters' yoke (`helm/`: the upright and the three cockpit sets, one gas pedal, buttons 2 and 3 and no button 1, the yoke's own pointer shapes, Pole Position's and Daytona's wheels as they were), a stand-up wheel, a bike, a dance stage of four or five arrows (`stage/`: a 10 cm platform with every arrow above its top, a standing seat on each square with its eye and step-down points, the panel attaching when the player stands up and letting go when they step down, the body over each arrow of both squares pressing it and nothing else, off the square, on the room's floor and in the air, the machine off, a morph rebuilding the seats), and the three particular cabinets: Prop Cycle's bicycle, Time Traveler's deep stage, Panic Park's two levers in one slot with a deck deep enough that START stands above each, handles inside the walls at the ends of the slot and nothing off the deck's edge, `odd/`, every line of their code mutation-tested); the sit-down cabinets (`seating/`: the table's seat, cabin, moving-base, ring and throttle flags for 34 games, the uprights you sat at (Darius's bench of two seats a hand's reach from the sticks, its platform under them, nothing of the deck in the line of sight; Sega's Star Wars Arcade a bench of two seats in front of a stick each and a 50 inch class screen; Ninja Warriors, Atari's Star Wars and the rest standing), a flight cockpit's seat, stick, throttle, cabin and lock-on lamps, the base tilting the right way by the right amount about its centre and level again when the run ends, the player's choice of motion, the bench for a ride and a standing gun game with none; the line of each mutation-tested); a rifle game of ONE screen's digital scope (`scope/`: the window a 2.5th of the picture, centred on the rifle's aim and never outside the picture, the monitor whole, the lens dark while the game is only on show or another machine's picture is on the glass, Silent Scope's own cut untouched; the bigger eyepiece cup and screen in `screens/`; the line of each mutation-tested); the sit-down cabinet's monitor under its hood (`hood/`: the picture a metre from the seated eyes and filling 26-28 degrees of the view for six games, the glass starting at the hood's lip over the door's swing, nothing of the cockpit in the line of sight, the hood and the glass's wedge solid and cut to the slope within a centimetre, a morph away taking them back; the line of each mutation-tested); DDR Solo's six-panel stage (`solo/`: the table's six games, the layout of the square, the six panels named and placed, buttons 3 and 4 sinking the corners and nothing else, a fingertip zone for each, the two-player stage unchanged; the line of each mutation-tested); the audit of the games a player asked about (`audit/`: Taito F3's spare dials gone from all 34 games but Arkanoid Returns, Darius Gaiden's two players, the modern boards' driving games as sit-down cockpits and Namco's MotoGP a bike, Road Blasters and Night Driver stand-up, World Combat's four sets as two-gun cabinets (MAME lists three of them as two buttons), Bad Lands' two wheels with no pedal, TX-1's three screens in a seated cockpit, Wing War's pod; the line of each mutation-tested, the generator's too: `Tools/arcade/gen_game_index.py` was broken seven ways and regenerated each time); the R-360 pod (`ring/`: the three sets carry rings where the cabin was and no other flight cockpit does, the spec, the parts and where they stand (a hoop outside each side of the platform, one behind the seat, the axle through the seat's middle), each hoop's plane, four brackets a quarter apart on each, no collision, a pull turning the outer ring about the axle and the push the rear one about the view's axis, eased with the base, the seat's eyes staying put, level again, still with Cabinet Motion off, G-LOC's own keeping its cabin; the hood group's sight line takes the pod too; the line of each mutation-tested, the generator's included: 22 breakages, all red); a rider standing on a rocking board (`rider/`: which romsets are a skateboard, a snowboard and skis, one rider a machine, and nothing else is; the spec; every part of the rig built on a real cabinet and nothing of the other vehicles; the rail at the waist, a grip each side of the middle, the bars taken from the middle of the grips, the crossbar in front with START on top of its middle; everything on the stand, the stand clear of the bay door; the ends turned up by their own slope, the wheels on the plate, the bindings, the skis apart; the plate clear of its stand at full lock either way, the plate and the whole rail leaning into the turn and upright again; nothing between a standing rider's eyes and the picture; the pointer box under the rail; no collision; the upright given back; the line of each mutation-tested, about fifty breakages of the rig, the spec and the profile, all red); a controller that is not a ball on a stick (`styles/`: the table's `y`; Star Wars, The Empire Strikes Back and Red Baron have a flight yoke, every Bass Fishing set a rod, and no other game a style at all; uprights with one panel, never driving cabinets; a yoke's panel wider than a stick's with its handgrips inside it and the caps clear of them; the column, hub, bar, a handgrip a quarter of a metre apart each end with a trigger on its front; RIGHT leaning the yoke and a hand taking it at the hub, no collar; the rod's grip, half a metre of blank, reel and a crank on a mount of its own, rising toward the angler, RIGHT swinging the rod and winding the reel about its own axle, a hand on the grip and another on the crank a few centimetres apart; a street fighter's stick keeping its ball; the line of each mutation-tested, the generator's too); a rotary joystick (`rotary/`: a dial with a stick, never with a paddle, a trackball or a pedal, is a stick whose shaft turns; the panel as wide as a stick's, a collar on the shaft below the ball with a knob and a mark, RIGHT leaning the stick and turning the collar clockwise and LEFT back, a hand's two grabs a few centimetres apart and a quarter turn of the hand through the leaned stick's frame turning it a quarter, nothing else with a collar; the line of each mutation-tested, the generator's too: Arkanoid Returns keeps its dial and loses the F3 board's joystick, keeping its four buttons); the rhythm games' own controllers (`music/`: the instrument of every beatmania, pop'n music, GuitarFreaks, DrumMania, Taiko and Mambo a Go-Go set and none for IIDX, Keyboardmania and beatmania III, the panels and the deeper deck each asks for, a mirrored second deck with its keys numbered from the left and a mirrored sector's angles, each part's name, place and MAME button, every cap shown, the panel's grip covering all of it and START clear of every part, a sector's mesh facing out whichever way round its angles are given, a finger in one of Taiko's four zones and not its neighbours' (through the hands' own pokes, and at the right height), the turntable taken at its platter's edge, the bass drum's pedal on the floor going straight down, the nine domes' colours, the two guitars' colours; the line of each mutation-tested: 71 breakages of the data, the specs, the builder, the control module and the hands, every one red but a disc that stands on nothing); a driving cockpit with guns (`racegun/`, Lucky & Wild: only that game filed as one, the spec a racing body 0.90 m wide with two seats, two guns and no panel or gear lever, a driver and a gunner side by side each getting up on the outside of their own seat, the wheel and pedals in front of the driver alone, a START at each end of the dash, a holster on the dash's face for each gun with its cord seated and the farthest within reach, the driver's gun the left one, the picture a metre from each seat with nothing in the way, a coin door each, the form taken away leaving no part behind; the line of each mutation-tested); the layout (the generic panels reproduced exactly, N panels side by side and centred, every kind as wide as its parts); each form built on a real cabinet (modules, parts, the tube on its side); the real path (a board changes the form, pulling it gives the cabinet's own back, a game that changes nothing rebuilds nothing, the art follows); a gun on a swivel (Silent Scope's rifle, Operation Wolf's Uzi) fixed to its post: the pivot stays on it whatever a hand wants, turned within its travel and never rolled, a rifle by its lever, the real patched grab driver driven by a hand two metres off, moving with its cabinet, a holstered pistol not fixed (`mount/`); the TEST and SERVICE switches opposite the power switch (there for a game MAME says reads one, gone for one that reads none; F2 and 9, or what the core names; `service/`); the pedals built as real ones are (a gun pedal's base, cheeks, pin, ribbed rubber tread and toe lip clear of the open bay door; a driver's two organ pedals on one axle, the brake the wider; `pedals/`); the guns built, plugged, hung and freed with their ports; a pad coming out of a socket the form loses or a gun takes; the input rewired (the attached panel let go, a fourth door's coin reaching port 4); the wheel, pedals, bike, second stick and arrows moving; a form asked for under a running core built when it stops; collision and pointer boxes laid again, not added to, a cockpit with pointer boxes and no collision; the floor rectangle following; **every panel, wheel and coin button of every form pointable and first under a laser aimed from where a player stands** (`reach/`); the game's own bezel from a MAME artwork zip (its parent's for a clone; a widescreen view, a 16:9 canvas or a drawn bezel refused; hung round the tube, cut to the opening, down with Cabinet Art). The look is `Tools/models/arcade_cabinet_probe --forms=...` ; `grip/`: a control's pointer shape is the control (a flight stick's box and plate, a wheel's ring with its hole open to a laser, a bar's depth, and from behind the controls every coin slot reachable); `bank/`: three monitors turned toward the player (TX-1, Buggy Boy's cockpit, Race Drivin' Panorama, Driver's Eyes: the layout's invariants for any yaw and unequal parts, the spec of each set and none for Darius or the upright Buggy Boy, the build with its wings hinged on the centre one and every case BEHIND its picture, the screen module's every state: each third, another shape, attract, a picture from another machine, the core's 3% rounding, no picture), and a Taiko drummer's sticks (`sticks/`, 47 checks, `arcade.md` "Captive gear": the data, the cord's lay, the build on a real cabinet, the lie in the cradles, the mates and the cradle's gate, the cords, the laser reaching a stick and not the panel's grip, every zone's bit on every stick's own port, the swing's crossing and its rearm, the mouse (leader, turns, Shift, the middle button), the hand-over when one is let go, the reach and the reel-in, a stick put to sleep in the air pushed down, the morph and the board pulled; a synthetic click is pushed at a point OUTSIDE the viewport because the loading overlay's panel still covers the 64 px window of a suite and the GUI takes the click before `_unhandled_input`), and GuitarFreaks' guitars (`guitar/`, 49 checks, `arcade.md` "Captive gear: GuitarFreaks' guitars": the data, the wide cabinet and its two bays, the guitars' build, hang and cradle, the cords hanging IN FRONT of the apron once settled, the pedals, the five places and who may take which, how a guitar lies in a hand, the hint's glyphs and keys, the desktop's keys, click and wheel, the one-player bay, the form's removal) |
| `arcade_hand_tests` | 383 | 40 s | a headset's HANDS on a panel's controls (§2z-arc, `arcade.md` "Hands on the panel"), fake hands (an `XRController3D` on a tracker of its own) on panels the cabinet really builds: the pure zone of a cap, of a foot on a dance arrow (`foot_on`: its margin, the floor under it within reach of the top) and of a yoke's grips (`near_helm_grip`); fingers (press, hold, grace, slide, two hands sharing a cap, a cap or a whole panel the game does not use, a hand holding a gun, the machine off, a lost controller); a racer's pedals (the zone is where the pedal RESTS); the stick (reach, the trigger's rising edge, the four directions and the diagonal, the dead zone and the 35% line, drawn at once, springing back, a key's lean kept, one hand, 35 cm, hidden, hands off a stick the game has not); twin sticks (left and right thumbsticks); the wheel (rim only, the sign, the lock, no wind-up, drawn at once, back to centre); the dial's sign and speed (clockwise is RIGHT, for a hand and a key alike); the trackball; the gear lever's latch; a bike's bars; Road Blasters' yoke (`helm/`: taken by a grip and not by the top of its bar, 135 degrees all the way and 120 not, turned back through the middle, A / X and B / Y its two buttons, none once it is let go); a standing rider's rail (`rider/`: the grip taken, a full throw of 15 cm still held at 0.49 m from the rail's middle, the plate drawn leaning, a hand a metre off let go, START pressed by a fingertip, for a skateboard, a snowboard and skis); a bicycle's bars (turned about the stem by one hand or two, tipped by their lift; `cycle/`) and crank and Panic Park's two levers (`slot/`); a pair of bars taken by a squeeze or a trigger, a second hand on the other grip, joining and leaving without a jump, both grips outlined (`handlebars/`, 37 checks); a flight cockpit's stick and throttle (`fly/`: the throw by the shaft, the lever staying where it is left, a pad's larger deflection winning, put back when the machine goes off); the port (a cap on port 0, the cap sinking, the player's stick bindings applying, a pad and a hand adding up, the machine off); the laser (off at a control, given back by a release, the power, a morph; the panel taking no press from a hand on a control); the carry (a hand on a control cannot pick the cabinet up, its squeeze does not attach); attract (a finger or a hand starts the game). The look is `Tools/models/arcade_cabinet_probe --shots=hands,handswheel`, and a Taiko drummer's sticks in a headset's hands (`sticks/`, 22 checks: a fake hand takes a stick out of its cradle through the real pickup function; trigger, A and B on each hand and each stick, the latch, the hand's own side, the second player's port, a stick that reads its hand by itself every frame, a slow and a fast swing, a stick held over the drum NOT drawn back into its cradle (the preview radius), shown in the cradle with the grip there and seated on release, a stick in a hand starting an attract game), and GuitarFreaks' guitars in a headset's hands (`guitar/`, 42 checks: a fake hand takes one out of its bay through the real pickup function, the second hand takes the other end, the frets under the neck hand, the strum, the wail and its latch gap, the knob, the neck's tilt, the body hand's stick and the neck hand's, what reaches the port through `_with_hands`, the left-handed way about, the hint ON the guitar, an attract game started by taking one), and what a panel says when a control is taken (`prompts/`, 39 checks, `arcade.md` "Control prompts": the words for every kind of control and the glyphs they name, the buttons by the core's words or by number, a controller's rows by the player's own map and the keyboard's by the cabinet's keys, a bicycle's bars, its crank, a stick with the game's buttons said once, a verb taught in three takes, another game's buttons said afresh, a wheel's pedals, a motorbike's lean, the hints switched off, the hint floating over the control that was taken, attaching with the keyboard and with a controller; the counts of what has been taught are kept in memory and put back) |
| `arcade_attract_tests` | 189 | 30 s | a switched-on cabinet that shows its game instead of running it (§2z-arc, `arcade.md` "Attract mode"): the rules (when a cabinet attracts, what is in view, who gets a video, how far it is heard), the video -> title -> wheel -> cover chain read from a scratch ROM folder, a built cabinet that shows the game and runs no core, the glass taking the picture at its own shape, a coin, a panel, a gun or a pad in hand starting the game once, coins the game cannot count yet held and let in when it is up, TEST and SERVICE starting it as a coin does, nobody at the cabinet putting the core away, the board pulled and the power button ending it, the scraper asked for that game only, the cabinet's own override saved, the latched ON / OFF switch, the System tab's row. The picture and the sound are `Tools/models/arcade_attract_probe` (windowed) and a headset |
| `arcade_memory_tests` | 81 | 11 s | an arcade game's own memory (§2z-mem, `arcade-backup-memory.md`): where MAME 0.289 keeps it and which cores are managed, what is saved in numbers and in words, the size rule (a Timekeeper file whose size is not the chip's is the only judgment made, and a file of the right size is never touched), the whole folder set aside under a stamp with a manifest and every file's SHA-1 (a pair stays a pair, a clone is a folder of its own), the exact inverse restore (itself reversible), the 20 newest copies kept, a start that sets aside a damaged memory and touches nothing else, the table's `b`, the cabinet (what the DIP tab is told; a Reset refused while the game runs, for 8 seconds after it stops, with another cabinet on the same game and in a netplay session; the start's two cards read off the cabinet's notice card), and the DIP tab's Game memory section (Reset asks twice, the copies to put back, nothing when there is none). Needs no core and no ROM: a throw-away save directory |
| `arcade_hold_tests` | 10 | 8 s | an arcade cabinet in a hand (§2z-arc, `arcade.md`): not solid (it, its bay, its guns and their plugs on the held layer with no mask, every loose pickable's mask without it) and never thrown: carried through a pad, a cartridge and another cabinet at floor level nothing is moved; set down inside another cabinet or on a pad and a cartridge nothing is flung; let go of with the arm swinging (6 m/s, 9 rad/s) it is set down where the hand was, upright, while a pad let go of the same way is thrown; the laser's release asks too (read from the source). A hand is faked (`Tools/vr/pad_drop_probe`'s): the REAL pick_up, let_go and HeldObjectPhysics run. A headset is OWED |
| `arcade_bay_tests` | 114 | 15 s | the arcade bay as an object of its own (§2z-arc, `arcade.md` "The bay is its own object"): every cabinet comes with its own kind of bay clipped into the mount; the bay rides with the cabinet when it is moved and turned (relative pose measured before and after); pulling it stops the game, leaves the board in the bay, shuts the cabinet's own slot, and clipping it back makes the board the game again; an MVS bay makes a generic cabinet play Neo Geo (takes a cassette, refuses a JAMMA board) and a JAMMA one puts it back; a JAMMA lead joins a free bay to the cabinet only with BOTH ends in, a board in the far bay is the game, a pulled plug ends it, a docked bay replaces a cabled one; the four bay kinds have scenes, a restore row and a card row, and the lead is restorable. Never run when written: no GDExtension loads in the authoring sandbox |
| `arcade_variants_tests` | 496 | 30 s | the other cabinets (§2z-arc): each of the five cabinets has a persisted registry row (and no shooting one: the generic cabinet becomes it) (the generic one first, so it stays the arcade tile's default) and a baked scene; the bay each takes (MVS -> Neo Geo, laserdisc -> Daphne, discrete -> DICE) and that Neo Geo is a cabinet but NOT of the romset family (or the generic cabinet would list its cores); the controls each has (six, four, one or no buttons, a stick or none, a paddle dial that turns with LEFT/RIGHT, START alone as a momentary panel, the coin doors, the bay kind); the guns on the gun cabinets (the generic one with a gun game in its bay, or the laserdisc one; built with the machine, plugged in, out of the group a save sweeps, hung exactly on their holsters muzzle-down, player 1 on the left, the gun scene matching the numbers the cabinet assumes); the cord route spending the cord's own length, above the floor and anchored at both ends; the cords settling above a physical floor, unstretched and asleep; START and the coin reaching a gun as its own START/SELECT; a gun aiming at the cabinet's own tube (and a ray past it reading off-screen); the gun cabinets being WIDE with a big straight screen (at least half again the upright's tube, vertical glass, holsters inside the width, an extra collision box for the coin face), a gun let go going back in its holster, MAME told to read a gun, the consolized Neo Geo console (two ports, three phono jacks, the cassette standing in its roof slot, the card offering both machines and a lead) and `neogeomvs`/`neogeoaes` read as the one `neogeo` system; the Neo Geo MVS cassette (not a JAMMA board: 240 contacts, the table's size, label front, edge down) and the rectangular MVS unit whose slot takes its edge; a cabinet STANDING (released leaning it rights itself, with no gravity to help; released upright it stays; heading kept; low weight; no axis lock; a pinned one untouched); the pedal as player 1's button 2, down while the gun is in a hand and lifted by taking cover (the gun hand's A or X through the real binding, its own Aux A claimed and not sent; the pedal key; the free hand's trigger with its laser off and given back; ducking with its hysteresis and a fresh grab; the hint per mode; the setting saved; the gun's Aux A and the joypad's A both sent; the plate tipping about its hinge; let up when switched off; the other two kinds, `pedal/`: Virtua Cop 3's ACTION pedal (up with the gun in a hand, down for the gestures that take cover in Time Crisis, a pistol with no eyepiece for a head to be at) and Golgo 13's scope SENSOR on a rifle (down while the rifle is held, lifted by the same gestures, switched on by a head within 10 cm of the lens and kept to 13, its lamp lit, button 3 for Juusei no Requiem: Aux B and the pad's Y)) and a cabinet's gun grip being its hold, not SELECT; a board of each system seating and its game going when it is pulled; the spawn card for arcade, neogeo, daphne and dice. Needs no GLB; the look is `Tools/models/arcade_cabinet_probe --model=<id>` |
| `card_tests` / `deck_tests` | — | — | memory cards; the decks, a tape's place, `.m3u` playlists (`--only=playlist`, a stand-in `FakeVlc`), and `label/` (62 cases) -- the pictures a tape, cassette or record wears, all found BESIDE its file and never saved or sent (a peer without the file sees the title text). **VHS:** `Name.mp4` is labelled by `Name.png` (or `.jpg`/`.jpeg`/`.webp`) for the front sticker and `Name spine.png` for the spine strip on the top edge (`MediaLabelArt.sidecar`); a label made in a generator drops in as downloaded. **Cassette and vinyl have two sides:** `Name.png` or `Name A.png` is side A, `Name B.png` is side B, and with no B the A picture is used on both (`MediaLabelArt.album_side`); a folder album also takes `cover`/`folder`/`front`/`album` (A) and `back` (B) inside it, or `Folder.png`/`Folder B.png` beside it. The decode is ONE `MediaLabelLoader` node per item: a pool task per slot, polled in `_process`, waited on in `NOTIFICATION_PREDELETE`, capped at `MAX_SIDE` 1024 px with mipmaps. Flat faces are fitted INSIDE the paper on a `QuadMesh` made in code (`MediaLabelArt.show_quad`; a `BoxMesh`'s UVs are an atlas, so it cannot carry a whole-face picture). A record's label is a circle, so its picture is centre-cropped square (`square`) and drawn by `vinyl.gdshader`'s `label_tex` / `label_tex_b` (the underside is told apart by `VERTEX.y < 0`, B sampled at `(u, 1-v)` so it reads upright when the record is flipped about its X axis) through a per-instance duplicate of `Mat_lp`. The text steps aside for side A's picture except while a netplay transfer reports progress. How it LOOKS needs a windowed render, not this suite (measured 2026-10-18 with placeholder art: every face upright, B not mirrored). **Not modelled, so not labelled:** a VHS cover or sleeve, a cassette spine or J-card, a record sleeve -- the objects do not exist. The vhs.texs.org export is paid, so there is still no real label source for any of the three. Mutation-tested: the text toggle, the downscale height, the cassette B-to-A fallback, the per-instance vinyl material and the square crop each fail exactly the cases that name them |
| `motion_tests` | — | — | accel/gyro/IR device frames |
| `screen_cast_light_tests` | — | — | light the screen throws into the room |
| `book_tests` | 52 | 3 s | a book answers the pointer only where it IS: dead page-grab zones and the `PointerArea` outline are checked per state (unloadable, closed, open, last page, failed reload) with a real ray on the pointer layer (the `disabled` flag is what the fix sets, the ray is what the reticle does). Builds its own CBZ, so no PDF or godot-pdfium. Writes one file under the REAL roms root for the manual-follows-its-folder case and removes exactly what it made. **Its exit code is a case too**: a book whose `WorkerThreadPool` render tasks are never waited on segfaults the process at quit, after every case has passed. `cache/` is the 2026-09-19 page-turn stutter: a page already in `user://pdf_cache/` must come back through the POOL like any other (the oracle is that `_get_page_texture` hands back `_loading_texture` and queues it, never a texture decoded on the spot), and `_drain_uploads` must cap itself per frame and take the open spread first — queue the pages furthest from the spread first, or the ordering case passes whatever the queue does. `unloadable/` also pins what a book that CANNOT open looks like: its body and pointer boxes sit on the one cover quad still drawn rather than the authored open spread centred on the spine (the 2026-09-20 "odd collision" on a Quest), and it says so on itself, because a `push_error` is invisible in a headset. `retry/` covers a manual still being WRITTEN (a half CBZ here; a PDF truncated to 55 % in `manual_probe`): it must reopen itself once the file is whole, and must GIVE UP — that half is driven by calling `_fail_or_retry` directly rather than waiting out 1+2+3+4 s of backoff, which would dominate the suite. `cap/` is the 2026-09-30 boot: an oversized scan's pages must render at `MAX_PAGE_PX` on the long side (not past it, not far below), a letter page keeps `render_dpi`, and a big page already in the cache must arrive capped AND be rewritten capped, with no `.tmp` left. `etc2/` forces `compress_pages` on (it is off on desktop): pages arrive ETC2 with mipmaps, cached as blocks with no PNG beside them, the spine strip still set, a page read back from its blocks, an old PNG migrated, and a damaged blocks file dropped and then re-rendered. Mutation-tested, 8 breaks + 2 for `cap/` + 4 for `etc2/` |
| `spawn_menu_tests` | 135 | 12 s | the spawn menu's decisions, never its widget assembly (a `Viewport2Din3D` hangs headless): the system filter, which systems get a Cartridges tile, the formatters, `HoldPress` and the cartridge sub-menu it opens (built on a bare view, no viewport: what SPAWN hands on for Auto, a swatch, and the Custom sliders, colour wheel and flake switch), and `delete/` — the trash can on a poster / video / DVD / album row. `SpawnMenuSpawnView` has no `_ready` and tolerates a null menu, so `delete/` drives the REAL `_add_media_row` and press handler. `RomLibrary.delete_library_entry` takes its root as an argument precisely so the group can run in a scratch `user://` folder and never touch the player's posters or music; keep it that way. It refuses anything that is not a DIRECT child of the root (the root itself, a `..` climb, a track inside an album), and unlinks a linked album folder rather than walking into it. `objects/` and `locate/` are SCENE > Objects (`SceneObjectsPage`, `LocateArrow`): rows are `Trash.can_delete`'s set, one per SPAWNED ROOT (a lead is one row, deleted through a plug), nearest first, re-sorted by moving rows and never rebuilding them, the item menu's two-tap Delete (the games list's `DELETE_FOREVER` glyph, `ERROR` while armed; Locate is `MenuIcons.LOCATE`, U+EE2B); the arrow's `place()` is pure, so the bearing cases need no renderer. The arrow stays up for the whole `GIVE_UP_SECONDS` and stands OVER the object, pointing down, while it is in view (a 2 s "found" end was tried and the outline alone did not find a cartridge on a shelf). Other groups leave spawned bodies behind, so a case reads only its own rows (`_object_rows`) |
| `book_flop_tests` | 203 | 14 s | a soft-cover book hangs from the hand (`docs/dev/books.md`). `sim/` steps `BookFlop` alone with a fixed `dt` and asserts SIGNS and orderings, never tuned magnitudes — face-up droops negative, face-down positive, gravity along the spine bends nothing, the thin half is the floppy one, a fan is pinned at EXACTLY zero face-up and peels in order face-down, 3000 ticks of seeded shaking never reach 90°, a second hand supports the half IT is on (one on each end locks both hinges), a spread held at both ends SAGS (`sag/`: the gutter drops, the paper in each hand does not move, the halves still meet at the binding, unequal hands give one drop and two slopes, a released hand never whips the slope — that one shipped red first), a page LIFTED over a drooping spine is carried across nearly unstretched (`leaf/`, with a control showing the halves' own bend stretches it 3.7×) and the turning hand is still found on the flat page, the page being turned BENDS instead of snapping into a crease (`bend/`: a small pull is a broad curve, the cycloid carries the grip exactly, the curl becomes the roll with no seam) and FOLLOWS the hand (`follow/`: no lift for a low pull so the old roll-over is untouched, 0.0 mm from a hand pulling up, taut and POINTING at a hand out of reach with the paper still its own length, handed over to the roll on the far half, and — judged by a point on the PAPER, not the lift angle — never leaping as the hand is carried over the spine), and `hardback` boards do not bend, open barely past flat, still swing shut and still fan. `bend/` keeps the CPU and GPU halves one function: the shader's `FLOP_HINGE_LEN` is read out of the include and pinned to the script's, `unbend(bend(p)) = p`, arc length is conserved. `book/` is the wiring on a real CBZ book: **every surface on a side carries ONE bend** (a block bent differently from its sheet comes through the page — that class shipped twice), a cover turned 180° bends toward the book's +Z, the grab zone goes down with the page, the fan hands its pages to the right faces, the tick disarms with the book EXACTLY flat, a hand takes hold at the nearest point ON the book (`_grip_point`, per state), and `hardback` round-trips through `ScenePersistence` with old saves defaulting to soft covers. **No case drives a real grab** — the two-handed pose itself is a headset check. The suite's book is frozen and unheld so its tick is off; the suite steps `book._flop` and calls `_push_flop` itself. A check that can ERROR instead of failing is not a check: `float(null)` on a missing uniform aborted the rest of the book cases and the suite still exited 0 on fewer of them — keep such reads null-safe. `thick/` loads a 400-page CBZ (a 2 cm block) and opens it in the middle: surfaces still agree per side, the binding's bend radius stays well clear of the block's half-thickness under violent shaking, the fan takes its pages from the middle of the book, and the grip still lands on the hand with the leaf hinging 5 mm off the neutral plane. `outline/` pins each generated `outline*_bent.gdshader` to its original (strip the marked lines and it must be the original, to the character) and checks each cover's and block's outline overlay carries its own side's bend, rebuilt overlays included; `pointer/` sweeps a pointer that sends NO events across the book and the latched page follows its ray all the way, half turned over the gutter. Mutation-tested 2026-09-19, 59 breaks. How it LOOKS is `Tools/vr/book_flop_probe`, not this `leaf/` pins the page UNDER a turning leaf through a mid-turn refresh (it was re-laid with the page being turned); `ends/` checks each end turn leaves exactly the surfaces its reverse does; `spine/` checks the far half follows a held page as well as the near half at 5 and 10 cm, and that a page brought straight down lands without a leap; `thick/` checks a page set down at either end of a 400-page book never sinks more than 3 mm into the far block (it went 30 mm with no hand-over); `release/` lets go of a page from heights either side of `SETTLE_FALLS_OVER_ABOVE`, on the thin AND thick book, and checks every settle frame never goes under the far page and the last lies ON it. Mutation-tested: winding the lift back, never falling over, and falling over without lowering onto the far page each go red — the last only on the thick book. |
| `texture_import_tests` | 5 | 1 s | every raster texture under `imported-assets/` imports VRAM Compressed, with mipmaps and an ETC2/ASTC file, and every `_normal` map as a normal map (tools.md). Reads `.import` files only; skips an orphaned `.import` whose image is gone. A walk that finds fewer than 100 textures fails, or every case would pass on nothing. Mutation-tested: one label flipped back to Lossless, one normal map unflagged. |
| `tv_resize_tests` | — | — | the TV's own geometry |
| `web_server_tests` | — | — | the built-in file server |
| `prop_lighting_tests` | 17 | 1 s | which of a room's meshes go on the baked prop shader, late spawns and despawns included |
| `scrape_tests` | 76 | 10 s | the ScreenScraper queue over a fake client: thread allowance, accept vs review, media wait, quota stop, the AutoScraper gate |
| `microphone_tests` | 55 | 25 s | the capture service: when the device opens, one read fanned out, the distance gain, a seated microphone's position, the DS pins, the DOL-022's slot value and its save round trip, and the HKT-7200 in a pad's slot |
| `famicom_tests` | 101 | 16 s | the Controller II microphone: the volume slider's threshold curve, the gate and its hysteresis, the level measured in C++, the service's one-measurement fan-out, which port the bit may reach, both pads, the captive pair's cords and wells, and the `famicom` systemid's table rows |
| `n64_vru_tests` | 37 | 30 s | the Voice Recognition Unit: no two coplanar faces on the dongle or the microphone, the device id a socket announces through the unit's own plug, seating in socket 4, the microphone in and out of the 3.5 mm jack, which way both cords leave, and the save round trip |
| `n64_cart_tests` | 128 | 10 s | the N64 cartridge: regional bodies, that they carry no mark and no unmapped normal-mapped triangle, which half each moulded part belongs to, per-instance and per-half shell materials, flake parameters and normal maps, repeated switch and reset, the label helper, the coloured-cartridge lookup by header and MD5, the scraped region, a spawned cartridge, and a shell forced from the spawn menu -- a preset, or a mixed colour, solid or metal flake, saved and restored |
| `gb_cart_tests` | 78 | 5 s | the Game Boy cartridge: that the model carries no mark and no unmapped normal-mapped triangle, which surfaces are moulding, colour with each moulding's shade and roughness kept, flake presets, the parts no colour reaches, the header lookup (Pokemon titles by market, dual-mode black, GBC-only in grey only when forced into this shell), a spawned cartridge with its scraped sticker, and a shell forced from the spawn menu |
| `gb_printer_tests` | 111 | 12 s | the Game Boy Printer's room half (§2e-prt): offered on the `gb` and `gbc` cards and no other, spawned and restored by its token, one `link_plug` socket on its BACK facing out of it, POWER/FEED buttons and a paper that tears on the TRIGGER only, the strip exactly as long as the lines the core fed (along its bend) and sent back by the slot, Nintendo's three rolls (white/sepia, yellow, blue) chosen from the menu's choice row, saved as `"paper"` (old saves load white) and baked into a print's file, `GbPrinterStrip` stepped alone (curls to the roll's radius weightless, a short piece stands, a long one flops and settles, tipped it falls the other way, shaken it swings, it lies on the cover and the table, never in or under the printer, lifted off the table and set down again it never jumps more than 20 mm in a frame, and carried and stopped it lags, swings back past its rest and settles where it was), a print written as the whole 38 mm sheet with the dots centred and unflipped (an asymmetric pair of dots) and never over another, the `net_*` surface (`no_content` boot, its own pad), the lockstep-only `NetplayCores` row, the `CoreSources` row and a core-info overlay that names NO platform, the BIOS / Extras rows, and a Poster's picture travelling in netplay. No core runs: the printing is the core's own `ctest` and `Tools/link/gb_printer_probe`, `gb_printer_room_probe`, `gb_camera_print_probe`, `Tools/netplay/gb_printer_netplay_probe`. Mutation-tested (the gbc row, the Poster transfer, contact off, the curl reversed, the air's terminal speed, the solid under the printer, the swing) |
| `gb_camera_tests` | 156 | 13 s | the Game Boy Camera (§2x-cam): the header lookup that picks its body, the cartridge that wears it with its head outside the fit, the ball swivelled by a stand-in hand, the save round trip, the seat it shares with a game in a `gbc` and a `gba`, the hold menu's Body row; and the camera it is — `eye/` (the lens eye looks where the lens points with the cartridge's top up and a camera's right on its right, BY SIGN at four turns of the ball; its `Camera3D` is under a viewport of its own, and the room's viewport has gained none), `feed/` (a `FakeMachine` and a still of four unlike quarters: nothing for a machine that is off or a core that has not started its camera, so many pictures a second, each corner where the still had it, brought to the core's size and to RGBA8, a headless run drawing nothing), `binding/`, `core/` (the ROM names mGBA whatever the machine was given, mGBA's model pinned, the "Core not installed" card, the netplay refusal). No core runs: the real one is `Tools/cores/gb_camera_feed_probe`. Writes one label PNG into the REAL roms root and removes it. Mutation-tested, 24 breaks in the camera's groups |
| `gbc_cart_tests` | 102 | 5 s | the Game Boy Color-only cartridge (§2x-gbc): both boards' bodies at 57 × 65 × 9 mm, debranded, exported solid, no unmapped normal-mapped triangle; the four moulding materials, both halves; smoke clear (filter + surface passes, stipple carried, board frosted, contacts sharp) and back to solid and reset; Crystal's clear glitter (the same flakes on both passes, taken out again by smoke, a mixed flake colour solid with Crystal's flakes, gold still solid flake); kept parts; the header lookup (CGB-only by board, dual-mode and the Korean Gold/Silver stay Game Boy, forced bodies and presets, `PM_CRYSTAL` Nintendo only); `MediaDimensions` by body; spawned and forced cartridges unstretched with the scraped label; the hold sub-menu's Body row and both palettes. Writes one label PNG into the REAL roms root and removes it |
| `gba_cart_tests` | 81 | 5 s | the Game Boy Advance cartridge: the tintable model imported solid, which surfaces are moulding, colour with baked roughness kept, the five clear Pokemon shells (filter + surface passes, colour, opacity, normal map, the filter sorted after the surface pass) and back to solid, the parts no colour reaches (label, screw, and the photographed board, contact strip, chips and battery, all solid; board and strip share the photos, at most 1024 wide; out of focus behind a frosted shell and back on their own materials when solid or reset), frost (FireRed/LeafGreen frostier, both passes patchy, moulded roughness grain, blur by mip bias), the header lookup (Pokemon game code by market, Classic NES Series `F` codes in NES grey but not Japan's Famicom Mini, maker `01` only; NES grey held equal to the NES cartridge's plastic), spawned cartridges, and a shell forced from the spawn menu |
| `ds_cart_tests` | 33 | 5 s | the DS and 3DS Game Cards (§2y-ds): both models load, carry no mark and no unmapped normal-mapped triangle, match `CART_SIZES` (the 3DS tab on +X only), keep the connector on −Y and the label on +Z; the sticker's UVs put the art's top-left and bottom-right where the label's are; a spawned card paints its scraped art on the sticker, shows the blank sticker and title without it, keeps metal contacts and is not stretched |
| `snes_cart_tests` | 122 | 5 s | the Super NES cartridges (§2y-snes): both bodies load, carry no mark (the rear sticker's copyright strip blank, MODEL NO. printed) and no unmapped normal-mapped triangle, match `CART_SIZES`, share one rear shell; the label's front covers the art 0-1; which surfaces are moulding (bezel included), colour with the grain and roughness kept, the parts no colour reaches and their metal; the header lookup (title, market by file-name tag then destination byte, copier header, checksum pair, the red and black shells by title and market), the body by market and release date, spawned cartridges (a Japanese ROM gets the Super Famicom shell; the scraped label painted on the sticker), and a body and shell forced from the spawn menu. Writes one label PNG into the REAL roms root and removes it |
| `sfc_cart_tests` | 159 | 6 s | the Super Famicom / PAL cartridge (§2y-snes): the six PAL rear stickers (art present, debranded, distinct), which one a scraped region, a file name's tag or a header byte picks, and that spawned European ROMs wear theirs on a shared material while Japanese and US ones keep their own; the body loads at 128 × 87.5 × 20 mm, carries no trademark (no oval; the sticker's SUPER FAMICOM mark and trademark line blank, MODEL NO. and serial printed; MADE IN JAPAN kept) and no unmapped normal-mapped triangle; the label covers the art 0-1; the ribbed rear panel and the moulded lettering are moulding; colour, kept parts and their metal; jp/eu/au markets and header fixtures pick it, a US ROM does not, and it can be forced; `MediaDimensions` sizes it by body, so Japanese, PAL and forced carts spawn unstretched, centred, with a body box the shell's size. Writes one label PNG into the REAL roms root and removes it |
| `sega32x_cart_tests` | 20 | 5 s | the Sega 32X cartridge (§2y-32x): the model loads with every part, matches `CART_SIZES` (112.8 × 73 × 17 mm), keeps the connector on −Y, the label on +Z above the grip slots and the screws on the back; carries no mark and no unmapped normal-mapped triangle; the sticker is the measured 75 × 43 mm, one surface, its UVs putting the art's top-left and bottom-right where the label's are; a spawned cart paints its scraped art on the sticker, shows the blank sticker and title without it, keeps metal contacts and screws and is not stretched. Writes one label PNG into the REAL roms root and removes it |
| `genesis_cart_tests` | 26 | 5 s | the Sega Genesis cartridge (§2y-gen): the model loads with every part, matches `CART_SIZES` (the measured 108 × 67 × 17 mm), keeps the connector on −Y 1 mm inside the mouth, the label on +Z and the screws and caution plate on the back, the side notches 7 mm deep up to 40 mm with the lip left; carries no logo and no unmapped normal-mapped triangle, its only normal maps the grain and the lettering; the sticker's front is the measured 74 × 60 mm, one surface, its UVs putting the art's top-left and bottom-right where the label's are, with the plain fold over the top; a spawned cart paints its scraped art on the front and leaves the fold plain, shows the blank sticker and title without it, keeps metal contacts and screws and is not stretched. Writes one label PNG into the REAL roms root and removes it |
| `nes_cart_tests` | 41 | 5 s | the NES cartridge (§2y-nes): the model loads with every part at `CART_SIZES`' measured 120 × 134 × 17 mm, connector on −Y inside the mouth, label on +Z, screws and caution sticker on the back, the mouth unlit black from 3 mm to its 20 mm floor in both halves; no Nintendo mesh, material or map (the plaque and sticker textures are the clean ones); no unmapped normal-mapped triangle; the sticker's front is 55 × 90 mm, one surface, corners right, the plain fold over the top; the palette is grey (the model's own plastic) and a METALLIZED gold; `NesCartShell` gives Zelda outside Japan gold and everything else grey, by scraped name or file name; gold coats every shell surface of both halves keeping each molding's maps, leaves the label, sticker, board, screws and mouth alone, and grey puts the plastic back; spawned carts paint the scraped art, a Zelda ROM spawns gold, a forced preset beats the ROM's own and a mixed color paints. Writes one label PNG into the REAL roms root and removes it |
| `speaker_tests` | 130 | 38 s | the surround rig (§2r): both cabinets' facing, the cabinet's own socket, a lead on each of the set's six outputs, the fold-down and its gains, the AUDIO OUTPUT key, the 1.2 m and 1 m stands, and the save round trip |
| `xbox_tests` | 176 | 13 s | the Xbox (§2u): every table that makes `xbox` a machine (descriptor, disc/tray, ScreenScraper id, the Systematic art, the overlay `.info` and its BARE firmware paths), a core with a branch and no release, and lifting one game's saves off the shared hard disk — `Qcow2Image`, `FatxVolume`, `XboxDisc`, the deterministic archive. Builds every fixture itself (a sparse 8 GB qcow2, fragmented FATX chains, an XISO whose tree makes `default.xbe` a left turn). `unit/` is the Memory Unit's FATX, read AND written — the round trip is the oracle (a save put in comes out byte for byte), a 40-file save GROWS its folder past a 2 KB cluster's 32 entries, a delete gives all its room back, and a hard-disk lift inserts into a unit. `slots/` spawns a real pad and console: both of a pad's slots, which pads take a unit, staging into `memory_unit_port<N>[b].img`, every empty slot switched OFF, a drain that goes to the unit that FILLED the file and refuses one cut off inside a save. It writes two images into the REAL `save/memcards/xbox_mu/` under `__xbox_selftest_*` and removes exactly those. `torn/` is the point: each corruption must fail the WHOLE lift, and its unbroken-disk control is what proves the fixture lifts at all — a `PackedByteArray` read from a `Dictionary` is a copy, and poking one silently does nothing |
| `pointer_fit_tests` | 323 | 9 s | a plug's and a memory card's pointer target is what it DRAWS (`PointerFit`, Scripts/Interaction): `scene/` every plug and card the game ships (the PointerArea box is the meshes shown, and no body box on a layer the desktop ray stops on stands proud of them); `swap/` `set_plug_mesh` to a PlayStation and a PS/2 connector and back to the molding, whose authored body box comes back, and a real pad's plug; `dress/` a mod's shell hung on a plug or a card with the stand-in hidden, a model put on a frame late, and a body box a mod sets at run time, which is left as it set it; `resolver/` `InteractionResolver.resolve_desktop` aimed 5 and 10 mm off what is drawn does not take the thing, aimed at it does, and the padded target it had, put back, would have (the control); `seated/` a Controller Pak in an N64 pad: down through the pad over the pak's tongue is the pad, up at the pak is the pak. Mutation-tested: without the body trim, a plug dressed smaller than its molding is taken 5 mm beside it |
| `pointer_hover_tests` | 42 | 2 s | two lasers, two hovers. A panel's viewport has one mouse and Godot never hovers on touch, so a second laser lit nothing: `PointerHover` (Scripts/UI/widgets) hovers the other pointers and the local edits in `viewport_2d_in_3d_body.gd` drive it. `hit/` pins `PointerHover.find_control` to the engine's own answer (the mouse hover after a real motion) over a caption that ignores the mouse, a clipped scroller, a top-level control and a hidden tile. `panel/` drives the REAL addon body over a bare SubViewport (no Viewport2Din3D, which hangs headless): both lasers' tiles lit, a tile stays lit until the LAST pointer leaves (either order, mouse or not), the mouse laser leaving the panel darkens its tile (upstream left it lit), `mouse_entered`/`mouse_exited` balance, and a laser that presses and takes the mouse presses once while the one it took it from stays lit. `widgets/` is VRButton, VRSlider, VRKnob, VRHinge, VRLever and PageGrab staying hovered while the other laser is still on them. Mutation-tested 2026-10-24, 7 breaks |

| `quality_tests` | 70 | 9 s | QualityManager's decisions (`Scripts/quality_manager.gd`): what each preset drives and never touches (render scale, eye buffer), that moving any one row makes the preset Custom (a CPU level does not: the control), every setter's clamp, `graphics_prefs.json` both ways (a moved row comes back Custom with the rest of its preset; a hand-edited file loads clamped; a non-bool switch keeps its default; a saved file outranks the device's starting eye buffer, a first launch takes it), which headset a string names (3S before 3, the Quest 2's UUID is no model), what SMAA, render scale and stencil materials stand down to, and a light's and an Environment's configuration per tier. Pure decisions on a FRESH instance that never enters the tree; setters on the live autoload, put back afterwards; the prefs file snapshotted and restored. Nothing that needs OpenXR initialised beyond "not offered on a desktop" |
| `held_physics_tests` | 16 | 9 s | HeldObjectPhysics (the `HeldPhysics` autoload): the held layer (bit 17) cleared from every body's mask and nothing else, an Area3D keeping it, continuous CD on pickables; a pickable released 8 cm into a world shelf stepping out toward the camera with its layer/mask/freeze back, and the three controls left alone (resting ON the shelf, frozen, inside another pickable); riders coupled while their support is held and still under them, woken and uncoupled once it is carried off, a side neighbour and a frozen body never riders; a pickable below the world recovered to where it last sat. Real Jolt queries; overlaps set up on purpose carry a collision exception so the solver cannot undo them before the release. Waits are counted in physics frames (the autoload's timers run on the fixed delta), not wall time. No real grab is driven |
Counts are what the suite printed, not a target — they drift upward as cases are added,
so re-measure rather than trusting this table, and treat an unexplained DROP as a signal.

**Everything else is a probe and lives under `RetroXR/Tools/<topic>/`**, including the
ones that assert: they want real cores and ROMs (`cores/azahar_probe`, `cores/sram_probe`,
`cores/vb_probe`, `cores/nds_probe`, `cores/handheld_probe`, `cores/gl_video_probe`), a
headset or a Quest (`netplay/netplay_spike`), or they are reproductions of open bugs and
report failures BY DESIGN (`rope/three_plug_probe`). Moving one of those into `Tests/`
would make a red run meaningless.

### Where the probes live

`RetroXR/Tools/` is foldered by topic. A probe's scene, script and `.uid` sit together,
and a scene refers to its script by literal path, so a probe moved between folders needs
its `.tscn` rewritten too.

| folder | what it holds |
|---|---|
| `av/` | TVs, tuners, phosphor, decks, spatial audio |
| `cores/` | core behaviour, BIOS boot, options, dual-screen, GL video |
| `gen/` | mesh/material generators run with `--script` (no scene); `gen/plug_materials.gd` is the shared one |
| `input/` | controllers, bindings, mice, lightguns, memory cards |
| `link/` | link cables and two-core buses (§2e, §2g) |
| `models/` | geometry authoring, shell audits, model registry, room renders |
| `netplay/` | sessions, rollback, determinism, state transfer (§2f) |
| `perf/` | Quest device probes, spawn/menu cost, VRAM census, arcade cabinets (`arcade_scale_probe`, `arcade_soak_probe`, `arcade_mesh_census`, `run_arcade_matrix.py`) |
| `room/` | tables, spawn menus, furniture placement |
| `rope/` | cables — the bit-exact oracles `rope/rope_bench` and `rope/rope_stress` |
| `state/` | save/restore, persistence, scene soak |
| `vr/` | grabs, pokes, pointers, sliders, capsense |

Three data directories sit beside them and are deliberately not foldered by topic:
`gblink/` (the ROMs `Tools/gen_gblink_rom.py` writes), `scan/` and
`azahar_stereo_homebrew/`.

`RetroXR/Tests/rope_tests.tscn` is the behaviour half of the rope's cover. Two kinds of
case: where a cord LIES (contact/ — table, over a corner to a floor socket, round a pipe,
on a ledge, heaped, bridging a gap; loose/ — a whole lead dropped flat, across an edge,
from height) and what a player DOES to one (handling/ — a real lead's plug yanked at
5 m/s, towed 2.5 m across the floor, pulled out through a 100 mm slot, carried over a
partition, a cord wrapped round a post and hauled tight), plus inextensibility,
determinism, anchor pinning, teleport re-lay, `set_rope_length` and sleep/wake. 90 cases,
~70 s, no GPU. It complements rather than replaces the two BIT-EXACT oracles in `Tools/`
(`rope_bench --settle` prints `settled_at_tick=49 still_awake=0`, `rope_stress` diffs a
22-row table): those catch arithmetic drift, this catches a cord that jitters, tunnels or
will not settle.
(The bench printed 15 until 2026-08-17: DepenetrateLay freed wedged lays and three more
bench ropes settle; the stress rows that moved are the two impossible lays. Re-baselined
deliberately — an UNINTENDED move in these numbers is still a stop-everything signal.
Re-baselined again 2026-09-22 for Coulomb friction and force-coupled plugs, `rope.md`:
every bench rope now settles, where 7 stayed awake on the build before, and `rope_stress`
moved on two rows — "slack over floor" squash 0.96 → 0.95, and "dragged through wall"
worst segment 6.89 → 30.82 with jitter 81 → 3.7 mm, the other impossible lay.
`loose/` gained three cases for a composite lead's plugs lying still on a floor, and three
more for `PlugTether` — slack, the velocity it kills, the sweep — each mutation-tested.
`contact/` gained two for a cord looped over itself on a floor (strands kept in order, no
pops), red on the solver before the self-collision fix; that fix moved `rope_stress`
again on small rows only — "nudged mid-span" jitter 2.9 → 5.2 mm and "dragged through
wall" 3.7 → 4.4 mm, neither of which sleeps before or after.)
Two defects this suite caught and got fixed the same day: `AlignAnchorPlug` used to apply
uncapped rotation steps about the cable anchor, a per-tick transform teleport that carried
a dropped lead's plug through a 100 mm floor (capped then; the turn itself is gone since
2026-09-22, the plug is pushed by forces — `rope.md`); and a cord
laid straight through furniture — every restore/teleport re-lay can do this — left
particles wedged inside it for ever (now freed by `DepenetrateLay` on the first tick after
a lay). `Tools/rope/rope_video_probe.tscn` renders the same cases to PNG frames (windowed, not
`--headless`) for when a case has to be WATCHED — most of the traps below were caught on
its footage, not by an assertion.
```bash
"$godot" --headless --path RetroXR res://Tests/rope_tests.tscn
"$godot" --headless --path RetroXR res://Tests/rope_tests.tscn -- --only=contact
```
Four traps it already hit. **Measuring jitter after a rope sleeps measures nothing** —
`step()` on a sleeping rope is a no-op, so the answer is a confident 0.000 mm however
badly it chattered; the cases hold the cord awake with `wake()` and measure the tail
window of the hold (the first wakes just finish a slump sleep froze mid-way). **A rope
built with `VerletRope.new()` takes the C++ defaults**, which are softer than anything
that ships — these mirror `cable.tscn` (8 iterations, `collision_radius` 0.0045,
self-collision on) or every threshold describes a cord the room does not contain.
**Never initialise a cord in a state no hand can produce**: a straight lay from a
table-top socket to a floor socket passes through the slab and wedges particles 11 mm
inside it (a particle born inside a solid has no contact plane), and a lay pre-compressed
between close sockets buckles into a 318 mm standing arch and sleeps there — the cases
lay the cord clear and `_carry()` the end to its socket the way a hand does. And **a
long free-hanging span cannot be held awake at all**: `wake()` every tick feeds the edge
contact's chatter into the span's pendulum mode and pumps a 0.4 m swing the room cannot
reach, because the sleep system cuts that loop off — the corner case asserts what the
room actually does (brushed awake once, asleep again in 30 ticks, 8 mm of drift).
Everything else measures 0.0003–0.07 mm/tick held awake, heaps included.

`RetroXR/Tests/romm_tests.tscn` asserts the pure-logic half of the RomM stack — pair-QR
parsing, slug mapping and systemid collision, the sync fingerprint, cache path safety,
and the `scan_roms` disk walk. 312 cases, ~17 s, no server, no headset, no network.
```bash
"$godot" --headless --path RetroXR res://Tests/romm_tests.tscn 2>&1 | grep -a "\[test\]"
```
Every case in it is a bug that actually shipped, so it doubles as the regression record —
add to it when you fix something in that layer rather than starting a new probe. It uses a
scratch `__romm_selftest` system folder under the real roms root (the path is derived from
the systemid and cannot be pointed elsewhere) and removes it at both ends.

`RetroXR/Tests/scene_tests.tscn` covers SceneManager and the save gates around it — which
rooms keep slots, the per-room active slot and its prefs round-trip (including the legacy
single-room key), which room a launch opens in, the `is_room_ready` / `is_scene_content_ready` boundaries, the transition
state machine's coalescing, the periodic autosave, clearing and reloading the room you are
standing in, two restores racing into one room, a machine's core outliving its machine, the room's own
movable furniture, the video decks' teardown contract, and slot-manifest CRUD.
120 cases, ~10 s.
```bash
"$godot" --headless --path RetroXR res://Tests/scene_tests.tscn
"$godot" --headless --path RetroXR res://Tests/scene_tests.tscn -- --only=autosave
```
It deliberately does **not** drive a real transition: `change_scene()` loads MainScene.tscn,
whose SubViewports render every frame, and a headless run has no GPU to service them — that
hangs rather than fails (see the SubViewport gotcha below). The cases drive `_transitioning`
and `_pending_scene_id` directly and assert the decisions made from them.

Two traps it hit that the next case will hit too. A spawned system also registers its
captive cable in the `"spawned"` group, so the group is always bigger than the entry list —
measure a baseline rather than hardcoding a count. And tear a group's room down with
`clear_scene()`, not by freeing the systems: freeing only those leaves the cables standing
in the next group's room.

`curtain/` drives `SpawnMenuController._on_slot_load` — the in-place Load, which has no room
change in front of it and so brings its own `LoadingOverlay` owner — without building a
controller: the script is set on a node ALREADY in the tree, so `_ready` never runs (a whole
controller finds the rig, builds the menu's SubViewport and restores the player's own room),
and the handler is started by signal, as the menu starts it. Three things the next case
there needs. `SceneManager._ready` claims the boot curtain, and on a machine whose boot room
has a slot nothing in this suite ends it, so end every owner and wait out `HOLD_S` before
counting `overlay_shown`. Ask whether the screen is still owned at the MOMENT a load hands
back (`active_slot_changed` is the handler's last act), not on the frames either side: the
restore reports progress every frame and each report re-raises the owner, so a dropped one
is back before a per-frame poll can see it. And assert the restore spans frames, or a load
that finished inside the press passes every "stays covered" case with nothing to cover.
How it LOOKS is a windowed run of the real room, in a scratch home (it writes slots and
`prefs.json`): give the window `WINDOW_FLAG_NO_FOCUS`, or the rig's desktop mouse-look
follows the real mouse and swings the view mid-shot.

It writes to the player's real `user://scenes` — the slot dir is derived from the room id
and cannot be pointed elsewhere — so it snapshots `prefs.json`, the arcade manifest and the
active slots up front and restores them byte-for-byte at the end. Restoring the manifest
matters beyond deleting the test's own entry: any rewrite round-trips it through JSON, which
turns its version int into `1.0`.

`RetroXR/Tests/poster_tests.tscn` covers the posters feature — the image load and the
sheet it sizes (alpha scissor vs opaque, mipmaps, aspect, per-instance sub-resources),
sticking to a surface on release, riding the object it stuck to, peeling, conforming to
a curved shell, the options-menu contract, and the save/restore round trip. 112 cases, ~11 s.
```bash
"$godot" --headless --path RetroXR res://Tests/poster_tests.tscn
"$godot" --headless --path RetroXR res://Tests/poster_tests.tscn -- --only=conform
```
Physics runs fine headless — the dummy renderer stubs RENDERING, not Jolt — so the stick
and conform cases are real raycasts against real bodies. It writes its own PNG into the
player's posters folder (`scan_posters` derives that path) and removes it at both ends.

Two traps worth knowing before adding a case. A stuck poster is REPARENTED under its
host, so anything that walks the host's meshes sees the poster's own sheet — that is what
made the first conform sample every interior ray at depth zero. And a poster is placed by
RAY as often as by hand, where `dropped` never fires; a release has to be detected from
`freeze`, so a test that only simulates a hand grab proves nothing about the real gesture.

`RetroXR/Tests/binding_tests.tscn` covers the resolution rules behind per-platform
control overrides. Both stores — `ControllerBindings` (VR controllers) and
`GamepadBindings` (a real pad) — merge default → global → per-system, and a platform's
stored profile IS its override switch; there is no separate flag. So three rules are
load-bearing and each has cases here: a platform with no profile is indistinguishable
from global, a profile shadows global completely INCLUDING global edits made after it
(which is why a profile is always written whole), and clearing one puts that platform
back on global without touching anyone else's. DesktopBindings is the odd one
and has its own cases: its consumers all read the process-global InputMap, so a
platform's keys cannot be looked up per system — they are APPLIED, and the Scroll
Lock capture decides when (RetroController._sync_desktop_scope). Its legacy flat
file is read as the global layer, which is covered too, because losing it would
wipe every desktop player's key map on first launch. It also covers ConsolePadArt, the
table a platform's own controller is drawn from — that a control key's index in
GamepadBindings.TARGET_ORDER really is its RetroPad bit (the trick that lets one
table serve both the XR and the physical-pad sections), and that every control
has an anchor and a row. `ids/` reads libretro.h out of the libretro-common submodule
and holds every light gun button, the thumbstick's d-pad and the device ids a
peripheral announces to the header's numbers (they were hand-numbered once and went
askew from Aux C on); `calibrate/` holds that the default gun map puts Start and
Select on two buttons, neither the trigger. 243 cases, ~7 s.
```bash
"$godot" --headless --path RetroXR res://Tests/binding_tests.tscn
```
It writes the player's real `user://controller_bindings.json` and
`user://gamepad_bindings.json` — the paths are consts on the two classes and cannot be
pointed elsewhere — so both are snapshotted up front and restored at the end.

`RetroXR/Tests/object_sync_tests.tscn` covers the shared-room network layer with
two and three real in-process ENet peers: initial and replacement snapshots,
host/client spawning and despawning, rigid-body transform flow, grab arbitration,
release velocities, disconnect cleanup, event relay, plain + spring-latched
hinge mechanics (including push-push trays), knobs, plain + spring-return
sliders, levers, remote head/hand avatars, and a playlist tape's recordings
fetched and put back in the host's order. Momentary button depression is
deliberately not replicated;
the semantic action it triggers is. The event cases cover platform power/reset,
tray/eject and media insertion, every TV bezel/remote action (power, volume,
mute, CRT, stereo/audio modes, aspect, source and channel), deck transports,
cables/ports, book controls, wall and pull-chain lights, blinds and time of day.
Late-join snapshots also carry the TV control state and those fixed room controls,
not only spawned objects. Articulated updates are capped at 64 per reliable
packet, with overflow retained for following packets rather than discarded. It
has no ROM, headset or display dependency.
Each group is independently runnable.
```bash
"$godot" --headless --path RetroXR res://Tests/object_sync_tests.tscn
"$godot" --headless --path RetroXR res://Tests/object_sync_tests.tscn -- --only=hinges
```

That a binding reaches a RUNNING core is deliberately not here: it needs a real system,
a real controller and the `binding_consumers` fan-out, and lives in
`Tools/input/binding_live_probe.tscn`. Drive that probe through the view's OWN
`_global_editor` rather than a fresh `ControlsBindingEditor` — a detached editor writes
to disk and reaches nobody, so every "applies immediately" case fails for a reason the
player never sees.

**For anything visual, a photo (or a VIDEO if it's animated — mp4 preferred over
animated GIF) is the preferred proof of validation, delivered inline in the chat.**
Headless runs catch parse/scene/shader errors but cannot confirm how something *looks*
(glyphs, layout, colors, animation). When a change is visual, capture a screenshot or
short recording and surface it inline — don't just report that the headless import
passed. To encode mp4 from probe PNG frames: `imageio` + `imageio-ffmpeg` are pip-installed
(`imageio.get_writer("out.mp4", fps=15, codec="libx264", pixelformat="yuv420p")`).

Godot binary (Windows) — use **Godot 4.7.2** (the project targets 4.7):
```
C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
```
**The doubled name is real** — the 4.7.2 download unpacked into a FOLDER called
`Godot_v4.7.2-stable_win64.exe` holding the exe and its `_console.exe`. The old
`Godot_v4.7-stable_win64\` folder is still installed beside it and is NOT the one to
use: `android/build` is stamped 4.7.2 (`android/.build_version`), so a 4.7 binary
fails every Quest export with `Android build version mismatch: Template installed:
4.7.2.stable / Requested version: 4.7.stable` — and that error names the template,
not the editor, so it reads as a broken template rather than the wrong exe.
Use the `_console.exe` variant so stdout/stderr is captured. `$proj` below is the
`RetroXR/` folder inside your checkout.

Godot binary (Linux): `~/Godot/Godot_v4.7.2-stable_linux.x86_64`
(the project targets Godot 4.7 — see `project.godot config/features`; `Godot_v4.6.3` also
sits in that dir). `$proj` on Linux is `<checkout>/RetroXR`. Note Godot
4.7 promoted "Not all code paths return a value" to a hard parse error for `Variant`-returning
virtual overrides (bit two `_property_get_revert` overrides in godot-xr-tools — fixed with a
trailing `return null`).

### Menu under load — `perf/download_ui_probe`

What the spawn menu's MAIN thread pays when a download, a RomM sync or the scraper
reports back. The transfers were always on workers; the stutter was the menu's
response, often several times in one frame, and just as much with the menu put away.
`perf/menu_perf_probe` is its sibling for opening and searching a platform.

- Windowed on desktop (`--resolution 640x480 --position 20,20`), never `--headless`:
  the menu is hosted as `player_rig.tscn` hosts it (a Viewport2Din3D at 2200x1800 with
  its CurvedPanel) because the toast pop-out only attaches to that host. It shows the
  SPAWN view's Cartridges tab before opening a platform — a page on a hidden tab never
  lays out, so its list binds rows but cannot scroll, and the numbers lie.
- On the Quest: preset "Quest download UI probe" (`com.xenu.retroxr.dluiprobe`, the
  probe-only export above). `DataPaths.android_root()` follows the running package, so
  the probe has its own sandbox and writes a 3147-row synthetic `gba` index into it;
  it used to be pointed at the real app's folder, which Android hides from another
  package, and every write failed. Desktop reads the real index and writes nothing.
- Desktop timings wander ±2x between runs on a busy machine. The Quest's are the ones
  to quote; its idle frame is the 72 Hz vsync (13.8 ms), so read the spikes above it.

Quest 3, before → after (2026-09-27):

| lands on the menu | before | after |
|---|---|---|
| core install finished (genesis_plus_gx, 6 systems) | 560 ms frame | 177 ms with SPAWN on screen and a 3k list open (117 of it re-running that page); ~12 ms from the CORES tab, the rest owed until SPAWN is shown |
| ROM download finished, list open / menu hidden | 72 / 70 ms | 47 ms (one rebuild, not two) / nothing over the 13.9 ms frame |
| 6 art arrivals in one frame | 19 ms (24 ms p95) | nothing over the 13.9 ms frame |
| one row of scroll (was a full-window re-bind) | 8 ms | 1.4 ms |
| core unzip (12 MB) | 49-65 ms, inside the download's callback | 0.02 ms to hand to the pool; frames stay at 13.8-15.2 ms while it runs |
| gamelist dedupe, 1,000 games | 1.7 s | 9.8 ms (3,000: 15.6 s → 31 ms) |
| toast tick (notify + refresh) | ~1 ms, a refresh per tick | 0.2-0.6 ms, one refresh a frame |

The rules that fell out of it (the commits `perf(menu)`, `perf(cores)`,
`perf(library)`, `perf(cartridge)` of 2026-09-27 carry the detail):

- **Owe a rebuild, don't run it.** SpawnView's `_owe()` marks the grids or the ROM list
  stale and one pass at the end of the frame pays — only while the menu is out
  (`_menu_shown`) AND the SPAWN tab is on screen; otherwise when it next is, and then
  synchronously, before anything binds a row against an index a sync rewrote. A ROM
  list is rebuilt only if its page is open (`_romm_detail_systemid` outlives the page).
  A core serving six systems emits six `default_core_changed`: one rebuild.
- **A Control inside a SubViewport reads as visible when its 3D host is hidden.**
  `is_visible_in_tree()` stops at the viewport. Gate on the host Node3D or on
  `_menu_shown` — ToastPanel, PS2IconView and SpawnView all had to.
- **Re-bind the rows that changed.** Landed art finds its row by rom id (RomM) or the
  ROM file's stem (scraped art); VirtualRowList keeps row i in slot i % pool, so a
  scroll step binds the rows that came into view. `rebind_visible()` is for data that
  changed under every row.
- **Nothing file-sized in a `request_completed` callback.** Unzips and hashing belong
  on a pool task (`CoreDownloadManager._unzip_task`); a digest a worker already
  checked is handed over (`FirmwareState.note_verified`), not recomputed.
- **Toasts:** one refresh a frame (MenuToasts), and the quad's arc — a mesh upload and a
  collision cook — only when the host's curve or the quad's size changed.

### 1. Compile / import check (catches parse, shader & scene-load errors)
```bash
"$godot" --headless --path "$proj" --editor --quit
```
This reimports resources, recompiles every GDScript, compiles shaders, and (critically)
**regenerates the global `class_name` cache**. Run it after adding or renaming any
`class_name`, or a probe that references the new class will fail with
`Could not find type "X" in the current scope`. Filter output for
`SCRIPT ERROR|Parse Error|SHADER ERROR|Failed to load|Failed to instantiate`.

### 2. Functional probe (exercises real code paths)
Write a tiny `probe.gd` (`extends Node`) + `probe.tscn`, run it, print `[probe] ...`
lines, then `get_tree().quit(0)`:
```bash
"$godot" --headless --path "$proj" res://probe.tscn 2>&1 | grep -a "\[probe\]"
```
Always **delete the probe `.gd`/`.tscn` (and generated `.uid`/`.import`) when done.**
Include a `get_tree().create_timer(5.0).timeout.connect(...quit)` safety net so a probe
can never hang the run.

### Gotchas
- **Warnings are treated as errors** for some warnings — notably inferring a `:=`
  variable from a `Variant` (e.g. `var x := ClassDB.instantiate(...)`). Use an explicit
  type (`var x: Object = ...`). `unsafe_method_access` (calling a method not on the
  static type, i.e. duck typing) is **not** an error, so it's fine.
- **A `SubViewport` with `render_target_update_mode = ALWAYS` hangs a headless run**
  (no GPU to service the render target). It renders fine in a real session — just don't
  drive extra `await process_frame`s over such a viewport in a headless probe; test the
  logic/wiring instead and eyeball the visual on-device.
- **Known headless noise to filter out** (pre-existing, not your change): OpenXR
  `xrCreateInstance failed`, missing GDExtension DLLs in the `template_debug` path
  (`libgodotopenxrvendors`, `godot-pdfium`, `libretro_godot`), `.NET Sdk not found`, and
  `xr_staging_shim.gd ... is_xr_class ... placeholder instance`. Grep these out.
- **A renamed/deleted source texture can leave the editor filesystem cache
  pointing at a dead `.godot/imported/*.ctex`.** Re-running an ordinary import
  may keep trusting that stale entry. Move/delete
  `RetroXR/.godot/editor/filesystem_cache*`, then run `--editor --import --quit`;
  Godot rebuilds the class cache and replacement texture imports. This is
  generated local state, not a file to commit.
- **A `.tscn` `Transform3D` lists the basis by ROWS**, not the columns the
  `Transform3D(x_axis, y_axis, z_axis, origin)` constructor takes. For a rotation the
  two differ by a transpose — an inverse — so a hand-written rotation comes out
  backwards. Copyable forms: `R_y(+90)`, local +Z → world +X, is
  `0, 0, 1, 0, 1, 0, -1, 0, 0`; `R_y(-90)` is `0, 0, -1, 0, 1, 0, 1, 0, 0`;
  `R_x(-90)` is `1, 0, 0, 0, -4.371139e-08, 1, 0, -1, -4.371139e-08`. **Never check one
  against a 180° or an otherwise symmetric matrix** — those read the same under both
  conventions and confirm whichever reading you already had, which is how the Wii
  ports and then the Game Boy link socket were both authored inside out. Print
  `node.transform.basis.x/.y/.z` from a throwaway probe and compare it with what you
  meant, before rendering anything.
- **Every suite "CRASHes" on its way out (`0xC0000374` under the runner, exit 127 /
  0x7F by hand) with every case passing: look at `RetroXR/.godot/extension_list.cfg`.**
  A Quest export leaves `RetroXR/android/build/` holding copies of every extension's
  `.gdextension`; without `android/build/.gdignore` the next editor scan (an open
  editor, or `--editor --quit`) registers all of them, and every process then tries to
  load seven extensions whose libraries are not there and dies at exit. Measured
  2026-10-14: `autoload_order_tests` exited 0x7F with them listed and 0 without. Put
  an empty `.gdignore` back in `android/build/` and delete the `res://android/` lines
  from the list. Both are local state, not files to commit.
- **A suite that CRASHes (0xC0000005) now and then, mid-run or after its RESULT line, with
  nothing in the log: a model loading on a loader thread.** A `--headless` run uses the
  dummy renderer, whose mesh RID owner is NOT thread-safe (the real renderers' are). A GLB
  loaded with `load_threaded_request` builds its meshes on the loader thread, and racing
  the main thread's own meshes it hands out a bad RID: stderr shows `Attempting to
  initialize the wrong RID` and `Parameter "m" is null` from
  `servers/rendering/dummy/storage/mesh_storage.h`, then the process dies. Stdout often
  stops short of the crash, so read stderr. `SceneManager._warm_models` started
  `ModelWarmer`'s shell warm in EVERY process, suites included, so any suite could lose
  the race; `headphones_tests` lost it about 1 run in 15 (2026-10-31). Fixed in
  `ModelWarmer.loads_threaded()`: headless it never loads threaded and skips the shell
  warm (nothing is drawn), and `acquire()` loads on the caller's thread. **Never add a
  threaded load that can run headless without that check.** To count a crash like this,
  loop the suite the runner's way (`subprocess`, piped output, 4 at a time): it was 4 in
  60 before the fix and 0 in 40 after.
- **Debugging one of these: `Godot_..._console.exe` is only a WRAPPER.** It starts
  `Godot_v4.7.2-stable_win64.exe` as a child and returns its exit code, so a debugger on
  the console exe sees a clean `exit` and nothing else (WinDbg's `cdbX64` showed 72
  "clean" runs that way). Give it `-o` to debug the child too, e.g.
  `cdbX64 -G -o -c "sxd -c2 \".echo AV; kn 60; lm; q\" av; g" <console exe> --headless ...`.
  Godot's own crash handler stays silent in these, and Windows Error Reporting keeps
  nothing a normal user can read.
- **Still open (2026-10-31): `combo_tv_tests` and `speaker_tests` crash 0xC0000005
  mid-run without that fix's stderr**: `combo_tv_tests` about 2 runs in 12 one at a
  time, always within the five frames after a set builds its VCR and DVD in (not the
  DVD tray's mesh collision: 12 in 40 without it). Not yet traced.
- **PowerShell buffers `& $godot ... | Out-String` until the process exits**, so a
  backgrounded run shows an empty output file until it finishes. The Bash tool with
  `timeout 90 "$godot" ... 2>&1 | grep` streams and bounds the run — prefer it.

### Verify with a check that can fail

**A green check that cannot tell the two outcomes apart is not a check.** Ask what
the WRONG version would look like before believing the right one; if the answer is
"the same", that is not the check to use.

Two of them in a row cost the Game Boy link socket a whole round trip. It was
authored facing INTO the shell, and the render looked identical because a
rectangular port recess is symmetric, while the room probe passed either way because
a snap zone does not care which way round a plug goes in. Both were green and
neither could have gone red. What settles a facing is a printed basis, or a render
of something ASYMMETRIC — a seated lead, not an empty socket.

**And read the note before authoring, not after the bug.** The gotchas above and the
session memory are each one line in an index, which is enough to recognise a topic
and not enough to act on; acting from the summary is how the same mistake arrives a
second time. `.tscn` transforms, a model's facing and a port's seat all have notes,
and all three were sitting in the index while that socket was written backwards.

`libretro-godot/tests/run_tests.py` is the small Godot-free C++ harness for the
link coordinator, the sensor-id encoding, the microphone stream and level, the pixel
swizzles and the camera stream (`camera_stream_test`: what a core is handed and when,
and the one place the channel order of a camera picture can be pinned, since mGBA turns
it grey before anything is seen).

**`RetroXR/Tests/archive_tests.tscn` is the one GDExtension with a self-checking
suite**, because `RommArchiveExtractor` is the one that needs no display, codec,
core or server. 83 checks over a well-formed archive, the plan validation, a
damaged/truncated/non-ZIP/missing one, cancellation, `FirmwareInstaller`'s unpack of
a support archive (`firmware/`) and of a speech pack's remapped parts (`pack/`); every
fixture is built under `user://` at run time, so it carries no binary.

Two of its cases are hand-built STORED archives, and that is not fussiness.
**For a DEFLATED member the declared CRC is handed to `StreamPeerGZIP` as a gzip
trailer**, so a corrupt payload dies inside decompression and
`RommArchiveExtractor`'s own `crc != entry.crc32` comparison is never reached — a
"bad CRC" case built by flipping payload bytes passes with that check compiled
out. Only a STORED member isolates it. `ZIPPacker` always deflates, hence the
hand-rolled fixture.

The other four extensions stay probes and rebuild-plus-load: `verlet-rope` has
the bit-exact oracles in `Tools/rope/`, and `vlc-godot`, `godot-pdfium` and
`metaxr-audio` all need a display, a codec or Meta's blob. Adding a suite for
one of those would mean a red run that depends on the machine it ran on.


### 3. Capturing a real screenshot on Linux (for visual validation)
`--headless` uses the dummy renderer — it **cannot** produce a screenshot (a probe that awaits
`RenderingServer.frame_post_draw` just hangs; `get_image()` is blank). To actually render a
RetroXR scene on this box, run Godot **on the real display** (`DISPLAY=:0`,
Vulkan Forward+ — a window briefly appears on the desktop, ok'd for validation) and draw into a
**`SubViewport`**, not the window viewport (the uncomposited window swapchain reads back as
clear-colour only). Xvfb does not work here (bwrap/glycin abort in the sandbox). Recipe:
```gdscript
var sv := SubViewport.new()
sv.size = Vector2i(1000, 750)
sv.own_world_3d = true
sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
add_child(sv)   # add WorldEnvironment + DirectionalLight3D + your scene + Camera3D as children
cam.current = true              # make_current() does NOT work inside a SubViewport
for i in range(8): await get_tree().process_frame
await RenderingServer.frame_post_draw
await get_tree().process_frame
sv.get_texture().get_image().save_png("res://shot.png")
```
Run `DISPLAY=:0 "$godot" --path "$proj" res://shot.tscn` (import first with `--headless … --import`).
Then **surface the PNG inline via the Read tool** — the user sees it through the Claude app (the
terminal itself doesn't paint it). Don't save renders to a folder; delete the probe + PNG when done.

## game_search_tests — Games-tab search beyond one system

`GameSearch` (`Scripts/Data/game_search.gd`): system aliases (systemid, `SystemIds.folder_names`,
every `RommPlatforms.SLUG_MAP` slug mapped to it, the server platform's `slug`/`fs_slug`) so
"gba" finds Game Boy Advance, and `search_all`, the worker-safe cross-system search (local
folders + synced RomM index sidecars via `RommCatalog.search_dir`, which never touches the
loaded index). The suite writes a real index in the sync's sidecar layout. The results page is
the browser pseudo-system `GameSearch.PAGE_ID` (`__` prefix = never hideable); the server's own
search (`RommClient.search_roms`) covers platforms never synced. Packed arrays are VALUES: an
`(x as PackedStringArray).append()` on a dictionary entry is lost (the suite caught this).
The page's look, a real RomM query and a headset are OWED (headless cannot show them).
