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

### Combination sets: a deck built into the cabinet (2026-10-21)

A cabinet carrying a `VcrSeat` / `DvdSeat` marker gets that deck built in (`TvDecks`,
`MediaTransport.build_into`). It is the ordinary `VCRPlayer` / `DVDPlayer`, instanced
under the set as `BuiltInVcr` / `BuiltInDvd`, rather than a second copy. Everything
the player touches is the deck's own code: the slot, the transport, the scan, the
remote and the netplay transport sync. What changes when it is built in:

- **Input.** It takes the composite slot after the cabinet's phono rows, so no
  `RetroTV.Source` value is added. That enum is on disk and on the wire
  (`EV_TV_SOURCE`). `TvPanel._builtin` files the deck there, because
  `_input_for_device` has no lead to find it by. The slot's sockets stay off, since
  `disable_absent_inputs` already turns off everything past the phono rows. SOURCE
  names the input with `RetroTV.source_name()`, which every banner and log now uses
  instead of `SOURCE_NAMES[...]`.
- **Body.** Not pickable, frozen STATIC (kinematic drifts under the host's rotation,
  as MediaSlot found), collision layer and mask 0. Its slot's `host` becomes the
  SET, so the media is collision-excepted against the body it is actually inside.
  Its `PointerArea` stays, so the remote targets it.
- **No lead.** Its A/V outputs are switched off, and `on_av_topology_changed` returns
  early. The feed is fixed: picture plus L/R onto speakers 0/1.
- **Save.** Its media is saved on the TV record as `"decks": {kind: {media, yaw}}`,
  and only when something is in a deck, so every other set writes the same bytes as
  before. The deck is never in `spawned`, and `_serialize_node` also refuses it, so
  ObjectSync cannot register it as an object of its own.
- **Netplay.** A node with no `net_id` but a registered ancestor goes on the wire as
  `{"$id": <set>, "$sub": "BuiltInVcr"}`. The old fallback was the absolute path,
  which named whatever the set happened to be called on the sending peer.
  `_media_state` gained a `sub` argument for the same reason (an RPC signature
  change; peers must be on the same build anyway). The heartbeat walks each
  registered set's decks.
- **Buttons.** The old box decks carried them on top, and `VcrControls` / `DvdControls`
  carry that whole panel, rigidly, from the top face's centre to the marker. The RETRO
  XR decks (below) are FRONT-panel (`MediaTransport._front_panel`): seated flush, their
  keys are already on the cabinet's face beside their own slot and display, and they
  ignore the controls marker (carried to it, they parted from both). Their seat puts the
  deck's front on the cabinet's face: the VCR's is 135 mm along the deck's +Z, the DVD
  player's 145. `_housing()` is the model's `Body` / `BodyPrint` (and the VCR's lamp and
  POWER, which `build_into` takes out of play with `set_active(false)`): the VCR's flap
  and holder and the DVD's tray stay, so media still goes in through them.
  `ButtonRow` (the set's own caps) is different: the caps keep their basis and the
  row walks the marker's axes, so that marker must NOT be turned. A turned one sent
  rows two to four into the cabinet in the first photo.

`combo_tv_tests` (13 cases) uses the reference cabinet
`Tests/fixtures/combo_tv_shell.tscn`, plus a copy with three phono rows written to
`user://` for the "no input left" case. `Tools/av/combo_tv_probe` (windowed,
`--out=`, `--housing` the control that shows the decks' boxes) is the picture.

Headless runs of a set with a VCR and a DVD player sometimes print
`Initializing already initialized RID` and a few dummy `mesh_storage` null errors. A
stock set with LOOSE decks does the same (1 run in 8), so it is not the built-in
path. Not chased further.

### The RETRO XR decks: models, mechanism and display (2026-10-30)

`vcr_player.tscn` and `dvd_player.tscn` wear RetroXR-models' `generic/vcr` and
`generic/dvd-player` (`res://imported-assets/appliances/`, three mobile levels, their
contracts beside them) through an `ApplianceModel` node placed before
`PickableHighlight`. Every node the scripts, saves and netplay name is kept; only what
is drawn changed (`VCRBody` / `DVDBody` and the old clock are hidden, kept as nodes).

- **Keys.** `DeckFace.adopt_front_key` puts each scene `VRButton` on the model's key
  (`ApplianceModel.adopt_button`) and turns its frame a quarter about X, so the cap
  faces its +Y like every other cap and presses along -Y: the combo code and its tests
  read a key's facing off +Y. `set_color` would paint over a model key's own material,
  so the VCR no longer tints its keys and the DVD's box-button refresh skips adopted
  ones (`state_tint`). The VCR gained REC (no recording: a log and an OSD line) and
  POWER (the display and lamp to standby; the deck has no power state).
- **Sockets.** `DeckFace.seat_port` puts each RcaPort 1 mm out from the model's jack
  empty (10 mm proud of the panel, where a seated plug's origin goes) with
  `show_jack` off. The models print their own AV OUT legends: no `AvLegend`.
- **VCR mechanism.** `MediaSlot.ride_driver` lets a host ride the media itself. The
  VCR's `TapeSlot` is at the door where the holder grips a tape (35 mm of spine out),
  and Load runs from frame 24 (after the contract's hand push) with the tape on the
  contract's `tape_center` each frame and the model held at the same time
  (`ApplianceModel.seek`), so door, holder and tape move as one; the cassette's own
  flap follows `tape_door`. A restore is laid seated at once. With nothing in the
  slot, a tape a HAND holds at the mouth, flat and flap first, pushes the deck's flap
  by the contract's `door_vs_tape`, and it falls shut behind (`_follow_hand`).
- **The tape** is the real cassette (`VhsCassette`, ported from the model's demo):
  188 x 104 x 25 mm, wound by where the tape stands on its T-n, its flap, the face
  art on its 80 x 48 label and the spine art and a `SpineTitle` on the spine.
- **DVD tray.** `DiscSlot` is on the tray's `DiscSeat` when it is OUT, and on only
  while the tray is out, still and empty. OPEN/CLOSE opens or closes an empty tray,
  or ejects / reloads a disc (`MediaSlot.toggle_eject` through the ride driver, which
  lays the disc on `DiscSeat` through Open / Close). A disc laid on the open tray
  closes it, as a disc dropped in the old slot rode straight in.
- **Display.** A `VfdDisplay` over each model's `Display` (whose mesh is hidden),
  redrawn only when what it shows changes (the VCR's counter once a second). VCR:
  VIDEO / SP, the cassette (lit with a tape in), the tape counter H:MM:SS in seven
  segments (the time the old clock showed: the recording's, running on into blank
  tape), ST / SAP and REC PLAY PAUSE FF REW lit from `is_playing`, `_paused`,
  `_scan_dir`. DVD: play or pause, TITLE nn CHP nn H:MM:SS from libVLC, or one word:
  OPEN, CLOSE, NO DISC, LOADING (1.5 s after taking a disc in), STOP, MENU.

`deck_model_tests` pins all of it (keys on the model and facing out, sockets on the
jacks, the display, a restored tape seated and its flap open, eject to the mouth, a
load through the door, the flap pushed by a held tape and not by one held spine
first, the DVD tray empty and with a disc, a restored disc at its saved spin, the
words). `Tools/av/deck_model_probe` (windowed, `--out=`, `--combo` for the cabinet
alone) is the picture and writes the mechanism's frames.
