# The Game Boy Printer (§2e-prt)

A Game Boy Printer (MGB-007) in the room, printing from any Game Boy game on
**gambatte** or **mGBA** over the ordinary Game Boy link lead. Neither Game Boy
core changed.

## The pieces

| Piece | Where | What it is |
|---|---|---|
| The core | `RetroXR/gbprinter-libretro` (MIT, its own repo, `~/libretro-cores-retroxr/gbprinter-libretro`) | No CPU, no game. Joins the link bus (env 94) on `gb-sio`, the wire gambatte and mGBA already speak, and answers as the printer. Its video frame is the paper, its sound the motor and head, its input FEED and TEAR. |
| The room object | `Scripts/Objects/peripherals/gb_printer/gb_printer.gd` (`GbPrinter`), `Scenes/Objects/peripherals/gb_printer.tscn` | A pickable with its own `Libretro` node (VmuCard's arrangement, not a RetroSystem), an EXT.IN `LinkPort` on the back, POWER, FEED, and the strip out of the slot. |
| The print | `GbPrinterPaper` (`gb_printer_paper.gd`) | A torn print as a file: the 160 dots centred on the real 38 mm sheet, written to `<data root>/prints/`. The printout itself is a `Poster`. |
| Plumbing | `CoreSources` row `gbprinter`; `libretro-core-info-retroxr/gbprinter_libretro.info`; `NetplayCores` row; the `gb`/`gbc` rows of `SpawnCatalog._PERIPHERALS`; `cores_view._BIOS_EXTRA_CORES` | |

The printer is offered on the **Game Boy and Game Boy Color cards**, and its core
is fetched from **OPTIONS > Cores > BIOS / Extras > Game Boy** (a download row on
the `gb` and `gbc` pages, through the Download tab's own downloader). The `.info`
names **no systemid on purpose**: a systemid is a platform, a spawn tile and a
roms folder, and a printer runs no games.

## The wire

The message is gambatte's and mGBA's own, 8 bytes, broadcast:
`[0]` 1=STATE / 2=CLOCK, `[1]` bus index, `[2]` SB, `[3]` ARMED|FAST. A printer is
always the external-clock end: it never sends a CLOCK. It publishes
`STATE{ARMED, reply}` and, on each CLOCK at its own tick, hands the byte to the
packet machine and publishes the answer to the NEXT byte. The Game Boy reads the
peer's last published byte the moment it clocks, so an answer only has to land
before the next clock: 8192 ticks after the last one started.

Timing (all in link ticks, 8388608 a second):

- **Frames are the Game Boy's**: 140448 ticks (70224 cycles) a `retro_run`, at
  4194304/70224 fps. A frame of any other length drifts on the bus and wedges a
  lockstep session.
- **GRAIN, REPLY and HORIZON are all 2048**, and REPLY can be no later: a Game
  Boy Color in double speed takes a byte in 4096 ticks, and its clock reaches the
  printer 2048 in, so an answer has 2048 ticks to land. Super Mario Bros. Deluxe
  runs its link that way. v1 promised a 4096-tick horizon (below) and every
  answer was late: the game said **Error 02**. 2048 is enough because the printer
  publishes a horizon past a tick only once it has answered every clock up to it.
  The core's wire test runs back to back at double speed; a 4096 horizon fails it.
- **It publishes its position at the end of every frame.** A session holding
  every core at one frame (`_all_cores_at_link_boundary`) needs each machine's
  promise to reach the frame edge; without this the printer's fell up to a grain
  short (140448 is not a multiple of 2048) and a Game Boy waited on it for ever.
- **KNOWN LIMIT, mGBA:** the bus anchors a machine's clock where it first calls in
  after a cable is made. gambatte calls in at its frame start, as the printer does,
  so their frame edges coincide. mGBA calls in at its next timing event, up to a
  grain into its frame, so its edges can sit before the printer's -- and a session
  holding every core at one frame WHILE they are cabled (a lead PULLED mid-game)
  can wedge. Seating a lead, and printing, are unaffected (both cores 20/20 in
  `gb_printer_netplay_probe`). v1 closed this with a late anchor and a 4096
  horizon, which is what broke double speed; the real fix is mGBA's driver calling
  in at its frame start, or the coordinator anchoring on a frame edge. OWED.

## The protocol

Written from Pan Docs' printer chapter; the RLE scheme read off mGBA's
`src/gb/sio/printer.c` (MPL, so facts only, no code):

`88 33 | cmd | comp | lenLo lenHi | data | sumLo sumHi | 00 | 00` - the printer
answers 0x81 to the first trailing byte and its status to the second, 0x00 to
everything else. Commands INIT 1, PRINT 2 (sheets, margins hi/lo nibble, palette,
exposure), DATA 4 (0x280 bytes = two tile rows; empty closes the buffer; RLE:
`0x80|n` repeats the next byte n+2 times, `n` is n+1 literals), BREAK 8, STATUS
0xF. Status: 0x08 after DATA, the PRINT packet itself reads 0x08, then 0x06 while
burning, 0x04 when done, 0x00 after INIT; checksum error 0x01 and the packet is
dropped. A PRINT without the empty DATA before it is ignored, as on hardware.

**Estimates, marked so in the code:** the line rate (~35 lines a second,
`GBP_LINE_TICKS`), the margin unit (16 lines), the dot pitch's line spacing
(lines as far apart as dots), and every figure of the sound. The 22 mm print on
38 mm paper is Wikipedia's; 135 x 70 x 60 mm is the Science Museum's (object
co8184142). Where POWER, FEED and the slot sit on top is from descriptions, not a
unit.

## The paper

The core's video frame was the strip hanging out of the slot: 160 dots wide, one
row a line, oldest at the top, the newest at the head; no paper is a 1x1 frame,
and a frame is sent only when the strip changes. That is still what a frontend
gets by default (every installed game takes the core's latest release), up to
4096 lines. But it cost the whole strip a frame, some 2.6 MB at 56 cm for two or
three new lines, and a NEW texture each time, as the frame grew a row at a time.

So `GbPrinter` asks for window frames (core option `gbprinter_paper_frames` =
`window`, set before `StartContent`; the extension holds it until the core
declares it): a frame that never changes size, 160 x 129, a header row then 128
lines. The newest go whenever the strip changes; once it stops, the core sends
older windows back over the 4096 lines it keeps, each held 4 frames, so lines in
frames the extension collapsed (it uploads only the newest of a backlog) come
back a moment later. `GbPaperLines` (`gb_paper_lines.gd`) keeps every line by the
printer's own numbering in 256-line chunks, one layer each of a `Texture2DArray`,
and uploads only the chunk a frame touched. The core keeps only its newest 4096
lines, so the strip can be far longer than it: 65280 lines, about 9 m (255
chunks, so it never spans more than the 256 layers every GPU takes). A core from
before windows never answers the option and the printer draws its whole frame
as it did. Measured through the real extension: 12 s of FEED, 407 lines, 329
window uploads in 2.2 ms all told.

`GbPrinter` draws the strip coming out of the slot (`gb_printer_paper.gdshader`,
`layered` for the room's lines), as long as the lines times the dot pitch, sent
8 degrees back by the slot. The mesh is laid again only once a point of it has moved
0.05 mm (`VRButton.mesh_changed` drops the outline's cached copy).

**The paper is ONE sheet and one solver wherever it is (2026-11-12):**
`GbThermalRibbon` (`gb_thermal_ribbon.gd`) keeps it and paper-godot's
`PaperSheetSolver` steps it. On the printer its rows inside the slot are pinned; in a
hand the row in the hand is; loose, nothing is and its rigid body owns the fall. Two
particles a row, one on each edge of the 38 mm, in the frame of the body it belongs to
(the printer, the print).

It was two models, each kept twice: a 2D chain of up to 48 hinges on the printer
(`GbPrinterStrip` + `PaperStripSolver`) and this sheet for a torn print
(`PaperRibbonSolver`), each a GDScript solver with a native port matched to the bit.
The chain is gone, and why is worth keeping:
- **48 hinges whatever the length**: a metre of paper was 2 cm segments, 9 m of it
  19 cm. The paper bends over its own weight in about 8 cm
  ((EI / (m g))^(1/3) with EI 3.2e-5 N m^2 and 5.7 g/m), so past 40 cm the chain could
  only be a polyline.
- **Every hinge carried all the paper past it**, as a cantilever, whether or not that
  paper lay on a table: contact was a position fix afterwards with no reaction. A hinge
  with half a metre of tail on the table saw several radians' worth of torque, lost,
  and was pushed back by contact every step: the zig-zag pleats, and the buzz
  `REST_SPEED` hid.
- **Its contact could fold it to any angle**, read back off the points up to half a
  turn, and zeroed the folded hinge's speed, so nothing relaxed it.
- One direction (slot to tip), no friction, one plane (the printer's YZ, so a turned
  printer swept its whole strip round), flat normals a row, and a swing (`sway`) added
  by hand because the hinges, each critically damped on its own, never swung back.

**How it bends (`PaperSheetSolver`, C++, `paper-godot/src/`).** A step:
1. Each free particle is carried on by its velocity, the frame's apparent gravity
   (`GbPaperMotion`: gravity less the slot's acceleration) and its turn, with air drag.
2. **Bending and twist, implicitly and exactly** (`bend()`): the positions minimizing
   inertia + EI/2 per rail on each rail's second difference toward the roll's curl +
   GJ on each row's rung turning from the last. One symmetric banded system over the
   particles (half-bandwidth 4), the same for all three axes, factored and solved in
   O(rows). Bent row by row (Gauss-Seidel, as the torn print was) a correction crosses
   a row an iteration: at 6 mm rows eight iterations left it a third as stiff as EI
   says and a fold closed to a 7 mm hairpin, and the thirty-two that got it right cost
   3 ms a step. With no twist term the rails resist twist only at second order, and a
   strip fed straight wandered 13 cm to the side.
3. A few iterations of: **both rails to their length, each as one chain** (`rails()`, a
   tridiagonal Newton step; taken a gap at a time 25 cm hanging read 27 cm long), the
   rungs and diagonals, the **fold limit** (no tighter than `MIN_RADIUS` 8 mm: the bend
   energy's pull back falls off past a right angle and is nothing on a fold laid flat,
   so a loop falling over could snap shut into a crease and stay), the tether (no row
   farther from a pinned row than the paper between them), the sheet against itself,
   the printer's boxes, the room's patches, fingertips, the pins.
4. **Friction**, Coulomb (0.45 static, 0.35 kinetic), on what each particle did along
   what it was pressed on against how hard it was pressed; against the ROOM for the
   room's patches (the frame's own velocity and turn are handed in, so paper lying on a
   table is dragged by the table when the printer is carried) and against the printer
   for its boxes. Paper on paper rubs the same way. Then no point moves faster than
   `MAX_SPEED` (0.8 m/s), and velocities are what the particles did.

**The step is always 1/240 s** (`GbThermalRibbon.STEP`): a frame takes as many whole
ones as have come due and carries the rest over, eight at most (a hitch is not caught
up). Where the sheet rests depends a little on the step (the bend solve and the length
projection are split), and cut to fit each frame the paper never came to rest in a
window, whose frames are not all alike: 13-30 mm/s for ever, found by the windowed
probe and not by any fixed-step suite. `paper_sheet_probe -- --feed --uneven` is that.

**Rows are places ON THE PAPER.** A row every 6 mm (`ROW`), counted in whole rows from
the free end, so feeding slides the two rows still in the slot out along it and lets
the one at the mouth go; what is already out is never re-laid (the chain re-laid every
hinge on every line). Past 200 rows (1.2 m) every other row is dropped and they are
12 mm apart, and so on (`_coarsen`); 9 m of paper is 48 mm rows, coarse again but
rare. More paper than a row at once (a core sending the whole strip) comes out of the
slot at `FEED_MAX` (0.2 m/s) rather than being laid across the room inside the table;
`paper_length()` is what the core fed, `paper().out` what is out so far. Less is a
tear: a fresh end of roll.

**One curl**, 6.5 cm (`CURL_RADIUS`), for the strip and the print alike. The strip had
13 cm because at anything tighter its end curled in under the printer's base and the
chain's contact could not get it out.

**The room** (`GbPrinter._find_obstacles`): short rays every fifth of a second, kept
in the room and placed against the printer each frame -- down under its back, slot
and front; down from BOTH edges of every 2 cm of the paper; and from each of those
rows to the next -- each hit a patch of surface reaching 1.4 cm round it and only for
paper within 3 cm behind it. So a print hangs over a table's edge and stops against a
wall. `GbPaperSweep` also casts between consecutive rendered positions (every third
row's middle and the free end's corners: a ray a particle was 400 a frame). A crossed
surface stays active beyond the ordinary 3 cm cutoff until the paper has recovered or
moved past the patch.

**The printer's own boxes** are one solid, reaching all the way down (under the printer
is never where paper goes), and a way out of one is taken only if it is clear of all of
them and no deeper into a surface than the point already is; now out through any of a
box's six faces, the paper being free to lie beside the printer. Paper within 8 mm of
the slot's mouth does not meet them (the slot is inside the body's box). **Known
limit:** contact is per particle, so paper falling across the printer's back edge bends
up to ~50 degrees there for a moment (64 at `FEED_MAX`); the edge is not rounded.

**Fingers** (`_place_fingers`): every controller's poke tip within 2 cm of the paper is
a 9 mm sphere, met by each row's RUNG (the edges are 38 mm apart and a finger between
them touched neither particle), so a hand nudges, flicks or holds up the paper; tearing
still needs the trigger.

**The knock and the tear** turn the paper about the slot (`GbThermalRibbon.jolt`, a
velocity to its first 4 cm) and it rings back by its own weight; `jolted` is the wake.

**Drawn** from the same rows (`GbThermalRibbon.mesh_arrays`, the printer's strip and a
print alike): each row's normal from the rows either side of it, where one flat normal
a row drew every row as a fold.

**A tear** takes what is past the slot as a sheet of its own (`torn_state`: the paper
where it hangs with its velocities, its rows evened out, since the stretch at the
mouth is shorter than a row) and the print starts from exactly that. Torn while a
strip is still coming out of the slot, the print starts as a fresh sheet (logged).

**Prints are paper** (`GbPrintoutFlop`, on a Poster marked `printout`, or one
whose picture is in the prints folder): loose, a print is the same sheet. It hangs
from the hand and swings as it moves and stops. Only the row in the hand is pinned:
letting go unpins it and moves nothing. The body's colliders are boxes that follow the
sheet, each over a few rows and no more than 48 of them (a box a row would be 199
shapes on a long print's body). Stuck to something it is the flat sticker it always
was, and so is its stick PREVIEW (`Poster.is_previewing()`): the preview slides the
Poster's `Surface` to the landing, and the bent mesh is a child of that `Surface`, so
it used to show the curled paper still simulating on the wall. While previewing the
flop shows the flat sheet and holds the ribbon still, and the paper picks up exactly
where it was when the wall leaves reach. It sleeps once its points have moved less
than 0.5 mm/s for half a second. `GbPaperMotion` reads how a thing is moving for both
(off the pose it is drawn at, smoothed). The print's own pointer target, a
StaticBody3D round the sheet, is left out of its look at the table: taken for a
surface, it stood half the print up.

**In the DESKTOP hand a print is a flat, still sheet (2026-11-08).** The mouse hand trails the gaze, so a pinned
ribbon swung and curled with every step of it and the print could not be looked at, turned (middle drag) or
sized (Q/E). While a holder in group `desktop_hand` has it (`GbPrintoutFlop._desktop_holds`) the print shows the
flat sheet exactly as a stuck sticker does (`_was_rigid`), the ribbon paused; on release the paper is laid again
at the size it ended with, with its roll's curl. A headset's hands keep the hanging, swinging paper.
`gb_printer_tests --only=desktop_hand` (mutation-tested: the desktop check forced false turns three cases red).
Headset-side feel and the real mouse hand are OWED.

**Dropped prints (2026-10-25):** the rigid body owns falling and impact response;
the loose sheet relaxes its bend without a second acceleration impulse from
the body's collision. Existing penetration is recovered by translating the
whole body (`GbThermalRibbon.body_shift`), with surface patches moved into that
recovered frame. Bending still respects surface contact. Previously each rail
was pushed out separately, its mean correction was discarded to keep the local
centroid fixed, and that positional correction became bending velocity. A
landing therefore buckled the print around its center, then flattened its curl.
Contact-normal velocity is now removed after positional repair, and a supported
body can sleep after its bending, translation and rotation settle. A regression
that puts a curled 24 cm print 4 mm into a table preserves its shape and clears
the table. Real-body drops in three orientations check length, folds,
table clearance and settling. Loose prints retain their roll curl on landing;
this is not a permanent-crease simulation.

**A print on a table SETTLES and is left alone (2026-11-04).** The whole-body recovery
above and Jolt never agree on where a resting print is: Jolt rests its 0.8 mm colliders a
little into the table, the recovery lifts the body back out, Jolt settles it again, every
frame, for ever -- a fraction of a millimetre, or a slight rock (up to ~0.05 rad) of a curled
sheet. Judged by its speeds, the print never went quiet and its body never slept: the flop
ran its full step, about 1 ms a frame, for as long as the room was open (the Starlight
Arcade autosave, measured). Now a loose print whose body STAYS within 3 mm and 0.08 rad of
one pose for half a second, its sheet quiet, is settled: put to sleep and nothing runs. Three
things each undid that sleep and are why the code reads as it does: a collider refit is
committed at Jolt's next step and a moved node's transform reaches the server when
transforms are flushed, and both wake the body (`JoltBody3D::_shapes_committed`,
`_transform_changed`), so it sleeps only on a frame that refits nothing, after
`force_update_transform()`; and Jolt wakes a sleeping body whenever an awake one touches it
(in the room, the printer it came out of), dropping it the ~1 mm it was being lifted, so a
settled print that wakes within the tolerance is put back on its settled pose and to sleep
(one transform write) rather than brought back to life. A hand, a stick, a preview, or a real
move (a knock, its table taken away) brings it back. `gb_printer_tests --only=drop`
checks all three dropped prints settle and sleep; `[GbPrinter] print settled` logs once per
landing, and seeing it repeat with `settled print stirs` means something is waking it again.

**The paper on the printer RESTS too (2026-11-10).** Until then every printer stepped,
swept and redrew its strip every frame for as long as the room was open, standing still
or not. Now `_move_paper` stops once the printer has been drawn at one pose and no point
of the paper has moved faster than `PAPER_SETTLED` (0.5 mm/s, `GbThermalRibbon.move_speed`)
for `PAPER_SETTLE_TIME` (0.5 s). At rest only `_paper_wake` runs, plus
a whole update every `FLOOR_EVERY` so the room is still looked at (a table taken away still
drops the paper). It wakes, saying why in `[GbPrinter] paper stirs: …`, on any of these:
the drawn pose differing from the one it rested at, the pivot turning, the length changing
(a line fed, a tear, or a strip still coming out), the motor running, a knock or a tear's
flick (`jolted`), or a fingertip at the paper. The sweep's exclusions are `_own_rids`,
gathered by `_find_obstacles`. `gb_printer_tests --only=rest` checks a still printer rests
and updates only for the room's look (≤ 7 a second, against every frame without it), and
that each wake brings the paper back. A printer leaves bodies
BESIDE itself (its battery bay's: `BatteryBay` adds cells to `current_scene`, which in a
suite is the suite): a case that makes one must free what it added, or a body left in the
air sits in the next case's stick ray (it previewed `Poster`'s stick and hid the
bent print). A metre of paper printed in the windowed probe rests 1.8 s after the last line.

**paper-godot is the only solver, and it is per platform.** The binaries are gitignored
and `Tools/build.py` builds one platform: a platform left on a build from before
2026-11-12 has no `PaperSheetSolver`, and there the paper **holds its shape and does not
move**, said once at error level (`[GbPrinter] paper-godot has no PaperSheetSolver …`).
`gb_printer_tests` fails on it (`_test_paper_solver_is_loaded`). Rebuild windows AND
android (`python Tools/build.py <platform> --only paper-godot`). The class name is new on
purpose: a stale library is told by `ClassDB.class_exists`, not by a call that fails.

**Cost** (this desktop, the editor's `template_debug` library, a whole frame's steps at
90 Hz, `Tools/perf/paper_sheet_probe.tscn`): 0.06 ms for 4 cm, 0.18 ms for 22 cm,
0.4 ms for 60 cm to a metre (100-170 rows) with the printer and a table to meet. The old
chain was 0.10 ms native on a Quest 3 for 1.2 m and the old 48-row print 0.44; this is
three to four times the rows of either, so expect it dearer there while a long strip
MOVES, and nothing once it rests. **Not measured on a Quest** (the `Quest paper probe`
preset now starts `paper_sheet_probe`, which prints the same lines to logcat).

**Rolls:** `GbPrinterPaper.ROLLS`, the three Nintendo sold: white printing sepia,
yellow printing black (the roll in the printer's box) and blue printing black
(Japanese Wikipedia, ポケットプリンタ). The tones are judged, not measured. Chosen in
the printer's object menu (`options_choices`/`options_choose`, the generic
`ObjectOptionsPanel` choice row) and saved with the room as `"paper"`; a save from
before rolls loads white, the paper the printer always had. A dot is the paper as
far toward the ink as it is dark, blended in sRGB in the shader and in
`GbPrinterPaper.sheet` alike, so a print looks the same torn off as on the strip.
The colors are baked into the print's file at the tear, so a print keeps its roll
whatever the printer is loaded with later. A roll changed mid-session reaches the
other peers with the next snapshot (the printer is not synced live); the prints
themselves travel as files, colors and all.

**Tearing:** TRIGGER on the paper (never a touch, a brush of the hand must not
throw a print away). The room reads the frame NOW, writes it as a print, spawns a
Poster at the paper's size into the tearing hand, and presses TEAR with left stick
X = how many lines it captured, and, on window frames, left stick Y = 1 + the line
its strip ended at, modulo 32767 (a count of a 9 m strip does not fit an axis).
The core tears exactly those off the OLD end, so a line burned between the look
and the press stays on the roll. Switching the printer off tears off whatever is
hanging out first.

## Sound

`src/sound.c` in the core, 32768 Hz (256 ticks a sample, 548.625 samples a
frame), deterministic, in the savestate and in step with the paper. FITTED TO A
RECORDING of a real MGB-007 printing, measured twice, the second time
independently (Codex), which found what the first missed:

- The motor: harmonics of the step rate, the 9th, 10th, 18th, 20th, 24th, 36th,
  39th and 40th standing out (1.2-5.1 kHz), over a rattle across 1-7 kHz that
  rises and falls gently with the steps (four low-pass stages: the first fit's
  bright, even hiss was heard as white noise).
- The gear's turn, 1.1407 s, a few milliseconds longer or shorter each turn: the
  step rate holds near 127.8 Hz for a third of the turn, winds down to 119.5 Hz
  by half way and snaps back past 129 -- the winding heard turn after turn --
  while the tones give way to rattle and the whole stays about as loud; a broad
  swell at 3-6 kHz as it winds down; and a knock as it comes round (a 2.2 ms
  ring near 5 kHz with a burst of noise, about 24 dB over the motor). The first
  fit tracked each harmonic in a window too narrow to follow the pitch down,
  read the harmonics leaving the window as the motor going quiet, and made a
  loudness dip that is not there; a harmonic-comb fit over the turn now puts
  the synth within about 1 Hz of the recording at every point.
- The turn is its own clock, not the lines': the line timing games see is
  unchanged. The gear starts at its knock whenever the motor starts and each
  turn's give or take is a fixed pattern, so the room can count the same turns
  and jolt the paper as each knocks (`GbPrinter.TURN_S`/`TURN_OFFSET_S`, kept
  the same as the core's).
- The head's tick per inked line is kept from the first synthesis (not
  separable in the recording).

`render_wav out.wav` in the core repo renders a print to listen to. The room
poses the core's voices on the printer (VmuCard's standalone pose).

## Netplay

LOCKSTEP only (a Game Boy on a cable is). The printer is never a session's
anchor: it comes in as a member of the Game Boy's group through the lead
(`LinkCable.linked_machines()` names it, because `LinkPort.get_machine()` finds it
by `get_libretro_node()`), boots `{"mode":"no_content"}`, and every peer prints
the same paper from the same agreed inputs.

- Its port is its own (`port_holders() == [self]`), so it participates from the
  start and follows the hand: `object_sync` hands it over on a grab as it does a
  standalone VMU's.
- In a session FEED and TEAR go through `netplay_route` ONLY, never straight into
  the core: a press one peer's printer saw is paper one peer has. A peer that does
  not drive the port is told to pick the printer up; a tear checks
  `NetworkManager.netplay_owns_port` before it writes a file.
- A printout's picture travels: `object_sync._file_desc` now describes a Poster
  (it was listed transferable and never described, so no poster ever reached a
  peer).
- `state_transfer: false`: a late join over a cable is owed for the Game Boy pair
  itself (neither Game Boy core's link clock is in its savestate).

## Checks

- Core: `ctest` in the core repo (32k checks, the protocol on whole packets built
  from an asymmetric image, RLE, checksum, timing, tear/feed, savestates, sound,
  and the whole core against a mock bus playing a Game Boy). Mutation-tested.
- `Tools/link/gb_printer_probe` (windowed, `--core=gambatte|mgba`, `--nocable`):
  `printer.gb` (Tools/gen_gblink_rom.py) prints a known picture; the paper must
  equal `printer_expected.png` dot for dot. 12/12 both cores, 3/3 controls.
- `Tools/link/gb_camera_print_probe` (mGBA, `--sav=` a Camera save, copied
  first): the Game Boy Camera prints a saved photo. The print command is behind
  SELECT on an open photo (radial menu: print up). 208 lines, matching the screen.
  `--rom=` and `--core=` drive any other game: **Super Mario Bros. Deluxe** prints
  its Toy Box calendar from a fresh save on gambatte AND mGBA, the two papers
  identical (`w400,START,w120,DOWNx3,w30,RIGHTx2,w30,A,w120,A,w120,A,w90,RIGHT,w30,A,printed`:
  title, the icon row, TOY BOX, the calendar, A for Mark/Print, RIGHT to Print).
  Its Album is all locked on a fresh save; its pictures need a save with progress
  (no trustworthy complete save was found online).
- `Tools/link/gb_printer_room_probe` (windowed, `--frames` for an mp4): a Game Boy
  stand-in cabled to the printer with the real lead, print, tear. Writes into the
  REAL prints folder and removes it. It reads the paper from the PRINTER
  (`_paper_image`): the core's frame is only the newest window of it, and converting
  that frame in place took its header with it, after which the printer read the next
  one as a whole 129-line strip (found red on both counts 2026-11-12; not checked
  when it went red). 21/21 on gambatte and on mGBA with the one-sheet paper
  (2026-11-12): the print stands out of the slot, tears, and is handed over where it hangs.
- `Tools/netplay/gb_printer_netplay_probe` (headless): two replicated pairs,
  gated, the cable seated with every core held; then only the printers are held at
  each checkpoint while the Game Boys run on (inputs ahead of the cores, as in a
  live session); paper, Game Boy screens and the printer's savestate
  byte-identical across peers at every checkpoint to frame 2400, FEED and TEAR as
  agreed input. 20/20 both cores.
- `Tests/gb_printer_tests` (headless, no core) and the printer's row in
  `link_tests`' socket matrix. `-- --only=paper` is the sheet alone (62 cases, 20 s);
  `--tune=<constant>:<value>` changes one of the solver's constants for the run, which
  is how its cases were mutation-tested (2026-11-12: `min_radius:0.0001` reds the
  creasing cases, `gj:0` the twist bound, `ei:0.000002` seven, `self_gap:0` the
  self-crossing and the wall, `mu_static:0` the tipped table, `iterations:1` six).
- `Tools/room/gb_paper_probe` (windowed, `-- --out=DIR`): a real printer on a real table
  prints a metre, then is carried 20 cm along it; stills and frames for an mp4. How the
  paper LOOKS is this, not the suite. Measured 2026-11-12: 169 rows of 6 mm, sharpest
  turn 50 degrees while printing (across the printer's back edge) and 20 at rest, lying
  on the table (lowest point at the table top), at rest 1.8 s after the last line.
- `Tools/perf/paper_sheet_probe` (headless): how it stands, falls over and feeds, and
  what a step costs; `-- --feed --uneven` for a window's uneven frames.

**OWED:** a pulled lead mid-session on mGBA (above), the headset (how the paper and the tear feel: the one-sheet paper of 2026-11-12 has been seen only in the desktop probe), the paper's cost and look on a Quest, the Quest (the core's
Android build is in its release; never run on device), a real two-headset
session, a late join, other printing games (Pokemon's Pokedex, Zelda DX), and a
recording of the real sound.
