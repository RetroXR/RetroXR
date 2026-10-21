# The Game Boy Printer (§2e-prt)

A Game Boy Printer (MGB-007) in the room, printing from any Game Boy game on
**gambatte** or **mGBA** over the ordinary Game Boy link lead. Neither Game Boy
core changed.

## The pieces

| Piece | Where | What it is |
|---|---|---|
| The core | `RetroXR/gbprinter-libretro` (MIT, its own repo, `~/libretro-cores-retroxr/gbprinter-libretro`) | No CPU, no game. Joins the link bus (env 94) on `gb-sio-1`, the wire gambatte and mGBA already speak, and answers as the printer. Its video frame is the paper, its sound the motor and head, its input FEED and TEAR. |
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

The core's video frame is the strip hanging out of the slot: 160 dots wide, one
row a line, oldest at the top, the newest at the head; no paper is a 1x1 frame,
and a frame is sent only when the strip changes. `GbPrinter` draws it on a quad
standing out of the slot (`gb_printer_paper.gdshader`), as long as the lines times
the dot pitch, leaning 8 degrees back.

**Tearing:** TRIGGER on the paper (never a touch, a brush of the hand must not
throw a print away). The room reads the frame NOW, writes it as a print, spawns a
Poster at the paper's size into the tearing hand, and presses TEAR with left stick
X = how many lines it captured. The core tears exactly those off the OLD end, so a
line burned between the look and the press stays on the roll. Switching the
printer off tears off whatever is hanging out first.

## Sound

`src/sound.c` in the core, 32768 Hz (256 ticks a sample, 548.625 samples a
frame), driven by the line events the printer records, so it is deterministic,
in the savestate and in step with the paper: a stepper buzz at four steps a line
with a ringing strike on each, and a head click per inked line scaled by its ink.
SYNTHESISED: nothing published describes the MGB-007's sound and there was no
unit to record. `render_wav out.wav` in the core repo renders a print to listen
to. The room poses the core's voices on the printer (VmuCard's standalone pose).
A recording of a real unit (the hardware-sfx skill) should replace it.

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
