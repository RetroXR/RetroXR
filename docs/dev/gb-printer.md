# The Game Boy Printer (§2e-prt)

A Game Boy Printer (MGB-007) in the room, printing from any Game Boy game on
**gambatte** or **mGBA** over the ordinary Game Boy link lead. Neither Game Boy
core changed.

## The pieces

| Piece | Where | What it is |
|---|---|---|
| The core | `RetroXR/gbprinter-libretro` (MIT, its own repo, `~/libretro-cores-retroxr/gbprinter-libretro`) | No CPU, no game. Joins the link bus (env 94) on `gb-sio`, the wire gambatte and mGBA already speak, and answers as the printer. Its video frame is the paper, its sound the motor and head, its input FEED and TEAR. |
| The room object | `Scripts/Objects/peripherals/gb_printer.gd` (`GbPrinter`), `Scenes/Objects/peripherals/gb_printer.tscn` | A pickable with its own `Libretro` node (VmuCard's arrangement, not a RetroSystem), an EXT.IN `LinkPort` on the back, POWER, FEED, and the strip out of the slot. |
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
8 degrees back by the slot.

**How it bends** is `GbPrinterStrip` (`gb_printer_strip.gd`), pure and stepped by
the printer every frame: a 2D elastica in the printer's YZ plane, up to 48 hinged
segments of about 4 mm. Each hinge springs toward the roll's curl (radius 13 cm,
judged from photographs of long prints, which make a loose, open curve; at 6 cm a
22 cm print closed most of a circle and its end came back to the printer's base
wherever the printer was, pressed there as if stuck) and carries the weight and
inertia of the paper past it; the stiffness (EI 3.2e-5 N m^2) and weight
(5.7 g/m) put the length at which it gives way at about 8 cm. So a short print
stands curling back toward the roll cover, and a long one arcs over it and drops
down behind the printer onto the table. Gravity is taken in the printer's frame
less the slot's acceleration, and the printer's angular acceleration about its X
loads each hinge by the inertia past it. Springs and damping are implicit per
hinge, which keeps it stable however short the tip's segments; damping is
critical, so the bend itself never swings back.

**The flop** is a swing on top of the bend, as `BookFlop` swings a book's pages:
one springy, lightly damped pendulum for the whole strip (`sway`: about a swing a
second for 10 cm of paper, softer for longer, damping 0.3 of critical), pushed by
the slot's smoothed acceleration across the strip and by the printer's turn, its
angle spread along the strip as extra rest bend for the hinges to follow, so
contact still holds. Carried and stopped, the paper lags, swings back past its
rest and settles. Its push is `shove`, the slot's acceleration alone, apart from
the gravity the bend already takes it in.

**Smooth, not jumpy** (the first version was; numbers from a throwaway probe that
moves the printer on physics ticks and takes the strip where it is drawn):
- The printer's motion is read off `get_global_transform_interpolated()`, not
  `global_transform`. A held printer moves only on physics ticks (90 a second);
  a frame at 72, 60 or 120 Hz sees one tick's move or two, so the speed read off
  the ticks stutters, and differenced into an acceleration it shook the paper.
- Speed and acceleration, and the turn rate and its change, are each smoothed
  over 80 ms; faster than 4 m/s or 12 rad/s is a jump (a snap into a hand), not a
  push. The turn used to be dumped into the slot's hinge each frame, which kicked
  the paper with every millimeter of tracking jitter.
- The surface under the slot is found every 0.2 s but kept as it is in the room
  and put against the printer every frame, so a tipping printer never meets it a
  fifth of a second late.
- `TERMINAL_SPEED`, 0.5 m/s: no point of the paper moves faster against the
  printer, a step's whole bend scaled down until none does. The hinges each
  settle almost at once on their own, and together they snapped a long tail from
  lying on the table to curled up the printer's back in two frames (13 cm).
  The limit includes contact correction, and corrected hinges do not turn that
  positional repair into velocity. A regression introducing a finger into the
  strip reached 1.02 m/s before this fix (2026-10-24).
- Contact is follow-the-leader (as for hair): from the slot out, each point is
  carried by its leader's move, pushed out of what it is in, and set back one
  segment from its leader; the hinges are read back off the points. Turning
  hinges to push points out was a lever that threw the free end about, and could
  not lift a point whose segment ran along the push.
- Nonadjacent paper segments also make contact, checking segment crossings as
  well as endpoint clearance. The two halves of a torn print meet each other
  after mirroring into the same frame. Short monotone strips skip self-contact
  searches, and bounds reject segments far from the other half.
  A long strip initialized all at once starts short of a closed loop; its
  springs then recover the roll's curl while respecting contact.
- The printer's boxes are one solid (a way out of one must be clear of all; the
  cover's hump and the body sent a point back and forth between them), and reach
  all the way down: under the printer is never where paper goes (it crept into
  the half millimeter the shell stands off the table, and was pinched there when
  the printer was set down). A way out is never deeper into the table than the
  point already is, and a point in the corner of printer and table goes into the
  corner in one push.
- Measured on that probe, first version against this one: a 10 cm strip on a
  printer held with tracking noise turned its tip back 246 times in 6 s, now 28
  (worst jerk 15 mm, now 5); tipped back and forth, 188 times, now 4. A 22 cm
  strip's worst frame-to-frame jerk, tipped on the table, held, or snapped into a
  hand: 119, 119 and 111 mm, now 10, 12 and 10.

New lines push the strip out keeping its shape from the free end; a tear starts a
fresh end of roll. The mesh, the tear trigger's box and the hover outline are laid
again only once a point has moved 0.05 mm (`VRButton.mesh_changed` drops the
outline's cached copy).

**The room** (`_find_obstacles`): short rays every fifth of a second, kept in
the room and placed against the printer each frame -- down under its back, slot
and front; down from every 2 cm of the paper; and from each of those points to
the next -- each hit a patch of surface reaching 1.2 cm each way and only for
paper within 3 cm behind it (`GbPrinterStrip.patches`). So a print hangs over a
table's edge and stops against a wall. At 4 cm a patch found at the edge reached
past it into the air, and a render caught a print's end lying out on nothing.
`GbPaperSweep` also casts between consecutive rendered positions every frame.
A crossed surface stays active beyond the ordinary 3 cm cutoff until the paper
has recovered or moved past the patch. Recovery ignores the opposite face of
the same collider, so a thin tabletop cannot trap the paper between its top
and underside. The printer and loose printouts both use these sweeps.

**Fingers** (`_place_fingers`): every controller's poke tip (`PokeTip.tip_of`)
across the paper's width and near the slot is a round obstacle, 9 mm, so a hand
nudges, flicks or holds up the paper; tearing still needs the trigger.

**The knock and the tear:** the room counts the gear's turns as the core does
(above, under Sound) and kicks the paper's swing as each knocks; tearing flicks
the stub back.

**Prints are paper** (`GbPrintoutFlop`, on a Poster marked `printout`, or one
whose picture is in the prints folder): loose, a print is one `GbThermalRibbon`,
a sheet of two rails (both edges) held to its length and width, bending toward
the roll's curl and free to bend sideways and twist. It hangs from the hand and
swings as it moves and stops; lying on a table face down its ends lift, face up
it lies flat. Only the row in the hand is pinned: letting go unpins it and moves
nothing (two halves anchored at the grip used to stay anchored there after
release, so where it was last held chose how it lay). A tear hands over the
strip's actual points and velocities, so the print starts exactly as it was on
the printer. The body's colliders are segments that follow the sheet, not a
flat board. Stuck to something it is the flat sticker it always was. It sleeps
once its points have moved less than 0.5 mm/s for half a second -- not on hinge
speeds, which contact repair zeroes: a print once slept 37 mm short of its curl.
`GbPaperMotion` reads how a thing is moving for both (off the pose it is drawn
at, smoothed). The print's own pointer target, a StaticBody3D round the sheet,
is left out of its look at the table: taken for a surface, it stood half the
print up.

**Two curls:** a torn print curls at 6.5 cm (`GbThermalRibbon.CURL_RADIUS`), the
strip still on the printer at 13 cm. At 6.5, 8 and 9 cm a long strip's end curled
in under the printer's base: the gap between the case and the table is half a
millimeter, and contact capped at the air's speed limit cannot get it back out
(uncapped, the paper jumps 24 mm a frame). No radius from 6.5 to 13 passed every
strip check, so the strip keeps the one that did. One curl for both needs the
strip's contact against the case reworked. A strip lying on the case buzzes
about 0.1 mm a frame for ever; `motion()` ignores contact repair below
`REST_SPEED` (12 mm/s).

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
  stand-in cabled to the printer with the real lead, print, tear. 20/20 both
  cores. Writes into the REAL prints folder and removes it.
- `Tools/netplay/gb_printer_netplay_probe` (headless): two replicated pairs,
  gated, the cable seated with every core held; then only the printers are held at
  each checkpoint while the Game Boys run on (inputs ahead of the cores, as in a
  live session); paper, Game Boy screens and the printer's savestate
  byte-identical across peers at every checkpoint to frame 2400, FEED and TEAR as
  agreed input. 20/20 both cores.
- `Tests/gb_printer_tests` (headless, no core) and the printer's row in
  `link_tests`' socket matrix.

**OWED:** a pulled lead mid-session on mGBA (above), the headset (how the strip and the tear feel), the Quest (the core's
Android build is in its release; never run on device), a real two-headset
session, a late join, other printing games (Pokemon's Pokedex, Zelda DX), and a
recording of the real sound.
