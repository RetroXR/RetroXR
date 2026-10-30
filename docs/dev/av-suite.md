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

### The RETRO XR television: the set's stock cabinet (2026-10-30)

The spawn menu's **TV** is now `tv:retroxr_crt`: `tv.tscn` wearing the RetroXR-models
`generic/crt-tv` set (380 x 330 x 400 mm, origin at the body centre). The old box is still
**Classic TV** (`tv_model ""`), and every room that places a set keeps it, because the
arcade and den were laid out round that box. The three `tv_mobile*.glb` and
`tv_contract.json` live in `imported-assets/appliances/crt_tv/` (never edit a GLB; after a
re-import, put the extracted textures back to VRAM Compressed and the GLBs back to
`generate_lods=false`).

`RetroXRCrtShell` (`Scripts/Objects/tv/retroxr_crt_shell.gd`,
`Scenes/Objects/tv_models/retroxr_crt.tscn`) is an ordinary `RetroTVShell`. The model's own
ScreenSeat / PortSeat / SpeakerOutSeat / VgaPortSeat / AmbilightSeat place the tube and
sockets through `TvFit`, so the scene carries no hand-measured pose. On top of that:

- **Sockets.** The model marks each socket's mouth with an empty named like the socket.
  The shell renames each one `<name>Mouth`, so a recursive find on the set never meets an
  empty before the real `RcaPort`. It also names `RfPortSeat` from the aerial's mouth.
  `TvFit` now seats `RfPort` (`rf_port_seat()`, which any shell may name): without that it
  stayed at the stock pose, inside this deeper body. Four AV inputs stand in a column
  (`av_group_step` (0, 0.04, 0)).
- **Printing.** The model prints its own legends, so `print_legends = false` on the shell
  stops `TvPanel` printing a second set over them.
- **Keys.** `TvFit` now really calls `on_buttons_built` (it was documented but never
  called). The shell `adopt_button`s all twelve bezel buttons onto the model's keys.
  `VRButton.set_color` leaves a button with `state_tint` off alone, or the set's state
  colours repaint an adopted key.
- **Key door.** It opens and closes on a press of its face (`KeyDoorButton`, depth 0) and
  runs `DoorOpen` / `DoorClose`. While it is shut, the five keys behind it (AUDIO MODE,
  AUDIO OUT, CRT, ASPECT, STEREO) are not interactive. The door is NOT saved or synced: a
  restored or remote set starts shut.
- **Lamp.** `PowerLed` takes a material of its own, lit while `is_on()`.

`Tools/av/tv_model_probe` (windowed, `-- --out=`) checks the twenty sockets on their mouths
with +Z out of the back, the tube on ScreenSeat, the keys, the door, the lamp, a lead in
AV1 and a 1.5x resize. It renders front, open door, back with leads, and resized. Taking
out `RfPort`'s or the tube's seat in `TvFit` turns it red. Headset feel and the Quest are
OWED.

**Where the mains cord leaves (2026-10-30).** The VCR, DVD player, amplifier, record player and RETRO XR television models each carry a `PowerCordExit` empty, on every level, at the tip of the AC cord's strain relief on the back (`ApplianceModel.part("PowerCordExit")`; `power_cord_exit` in each `*_contract.json`). Its basis is identity, so a cord leaves along its local -Z, out of the back, as every cord anchor here does; the socket-mouth empties point the other way (+Z out). Nothing draws a cord from it yet.

### The ray meets what the model draws: no padding (2026-10-30)

Every box the desktop ray (or a hand) meets on the RETRO XR VCR, DVD player, amplifier,
record player and television is what the model draws, with NO margin. Before, bodies and
`PointerArea`s stood 5-20 mm past the models and `adopt_button` padded every key 1.5 mm a
side. The padded shell stood in front of the television's twelve keys and the amplifier's
SURROUND MODE key by more than `InteractionResolver.ENCLOSURE_DEPTH` (5 mm), so the desktop
ray could not press them at all.

- `ApplianceModel.bounds(space, except)` / `node_bounds(node, space)` give what the close
  level (or a part hung under a pivot) draws in a frame. `fit_box` makes a shape exactly a
  box, duplicating it first (scene sub_resources are shared), and `fit_shapes` fits a
  body's and its `PointerArea`'s. `adopt_button` makes a key's box the key.
- **A control deeper than 5 mm needs a pocket.** `carve(box, pocket)` returns the box less
  the pocket (up to six boxes), and `fit_collision` lays them as `<shape>Carve<n>` siblings.
  The television's five door keys sit 7.6 mm into the bezel: the pocket runs from the caps'
  BACKS out through the front. A pocket floor level with the key faces ties with the key,
  and the shell wins the tie (the resolver returns the first of two non-controls). The door
  is left out of the body and is its own box (`KeyDoorButton`, pressed on its face along -Z).
- **The record player's plinth stops under the 33/45 caps.** The model's `Body` also
  carries the tonearm base, 48 mm higher. The dust cover's lever box is the whole cover, the
  body's `CoverShape` is the cover shut, and the tonearm's lever box is the whole arm. With
  the cover shut, the 33/45 keys are taken from the front, and the arm not at all.
- **The DVD player's keys are the remote's (2026-10-30)**: dark rubber caps with a word over an icon,
  and the navigation keys a round four-way RING (25 mm across, `common/applkit/geom.ring_arc`, the
  remote's arcs) round OK, in one round opening. Arcs and OK would overlap as boxes, so
  `adopt_button(..., exact = true)` (`DeckFace.adopt_front_key`'s `exact`, `DVDPlayer.RING_KEYS`)
  gives each its own triangles as its shape and a `footprint_gate`: a fingertip presses a key only
  over its own face, with no reach (the slots are 0.6 mm). `appliance_pointer_tests` `dvd/ring` checks
  that rays and fingertips in the gaps take no key. As boxes, 14 checks fail.
- `appliance_pointer_tests` checks it all: every key's box is its key, no body or pointer box
  is bigger than the model, and the desktop ray along a control's facing takes THAT
  control, with the set's door shut and open and the deck's cover open and shut. Putting
  the 3 mm key margin back fails 39 cases; dropping the television's carve fails the door
  keys. `Tools/av/appliance_ray_probe` prints the same numbers for every direction.

### The RETRO XR remote: a handset with real keys (2026-10-30)

`tv_remote.tscn` wears RetroXR-models' `generic/tv-remote` (`imported-assets/appliances/tv_remote/`,
LOD0 inside 1 m, LOD1 to 2.5 m): a 175 x 50 mm two-AAA handset, keys up (+Y), the window along -Z,
100 mm ahead of the origin (the grip end 75 mm behind it: it was cut 25 mm shorter under the logo and the origin
stayed, so the keys and the tip did not move; `GrabPoint` and the hand poses went to z 0.055).
Its 26 keys are the grid's cells (`TVRemote.KEY_CELLS`; PREV/NEXT are `prev_ch`/`next_ch` on a
DVD); the stick now walks the keys themselves, and the floating grid is an option (below).

- **Every key is a VRButton** under `Keys`, built in `_dress_keys` and dressed by `adopt_button`
  (1.5 mm travel along the key's -Z: the long end of a rubber keypad's 0.8-1.5 mm stroke, Diamond HMI's
  design guide, so a press is seen from arm's length; only the cap moves, the shape stays put). A key does what its cell does on the device the grid is
  showing, or, with no grid up (the remote lying on a table), on whatever `IrTip` points at;
  a cell the grid would grey or leave out does nothing, and the line says which.
  `press_key()` is that path; the grid's highlight moves to the cell pressed.
- **Shapes are what is drawn, with no margin:** each key's is its own triangles (the ring's four arcs and OK
  overlap as boxes), the `PointerArea`'s the shell's triangles, the body's the shell's convex
  hull (186 points from LOD0, made per remote: a shape kept in a static crashed the exit; Jolt takes it, and `simplify` pads it 1.6 mm).
- **A fingertip presses one key:** `press_gate` (`_key_gate`) keeps a touch to the key's
  footprint +1 mm and no higher than 3 mm over its face, and goes by angle round the ring's
  centre for the arcs and OK. `trigger_radius` 12 mm only reaches the widest key's corner.
  **The path that presses is VRButton's own touch** (not ControlPoke): `PokeTip.tip_of` of every
  `XRController3D`, by distance and the gate, with no physics query, so the held layer (17) never
  enters into it, and a cap sinking under the finger cannot pull a collider out from under it.
  The hand HOLDING the remote presses nothing (`PokeTip.is_poking` is false while its pickup holds
  something); the other hand pokes the held remote's keys as it pokes one on a table.
- **A cell pressed on the floating grid sinks its key** for `KEY_FLASH` (0.15 s, `_flash_key`,
  `set_latched_pressed`), DVD chapter cells included, so a press is seen on the handset however it
  was made; a key a finger or the laser is already holding is left alone.
- `IrTip` replaces the scene's `Tip` transform; the cone and the desktop crosshair are unchanged.
- `tv_remote_tests` (67): dress, shapes, the desktop ray at every key from above and tilted
  (and the 2 mm gap and the shell take no key: a 3 mm-padded box took the gap), touch, the
  key-to-cell map on a set, VCR, DVD and record player, aiming with no grid, every key's click
  sinking it alone along its own -Z, `poke/` (a REAL fingertip: an `XRController3D` on an
  `XRPositionalTracker` the suite registers, so VRButton's own path runs) pushed into every key
  lying down and seven held tilted in an active second hand whose thumb on STOP presses nothing,
  and `grid/`. Mutation-tested: travel back to 1.2, no grid flash, no press gate (VOL - fires
  beside POWER), the holding hand poking. `Tools/av/remote_poke_probe` (windowed) records a
  fingertip poking six keys for an mp4.
  `Tools/av/remote_model_probe` (windowed) renders it held at the RETRO XR set, a key down, the handset
  from above and the bay open with its cells. Headset feel and Quest cost (29 draws at LOD0, 3 at LOD1/2)
  are OWED.
- **The battery bay is the room's battery bay** (`_dress_battery_bay`): the model's `BatteryCover` becomes a
  `CoverSlots` cover (`tv_remote_battery_cover`, outer face down), taken off whole by hand, laser or mouse and put
  back, saved and synced as a Game Boy's is. The model's cover is hidden on every level and the slot's cover
  wears LOD0's (`CoverSlots.wear` on seating), so it is drawn at any distance. `BatteryAAA1/2` are `CellSlots`
  seats, shut in while the cover is on. **A remote fresh from the spawn menu comes with two AAA cells in**
  (`_seed_cells`, real `BatteryCell`s that can be taken out); a restored one (`CoverSlots.RESTORING`) has what its
  save says. The cover is left out of the shell's laser shape, so with it off the bay is open to the ray. A cell
  is taken from below through the body's convex hull only because `battery_aaa.tscn`'s pointer cylinder is 5 mm
  proud of the cell (radius 10.1 against 5.1); the model's real motion (press the latch tongue, slide toward the
  grip end, lift off) is documented on the node, not animated. `tv_remote_tests bay/` (10), mutation-tested:
  no seeding, the cover left in the laser shape, the far levels' covers drawn each go red.
  `CoverSlots._refresh` takes a `Variant`: a cover freed before its deferred refresh ran failed the typed parameter.
- **The keys are the menu; the floating grid is off by default** (2026-10-30). Held, the remote lights one of its
  own keys with the laser's hover outline (`VRButton.set_selected`, ORed into `_sync_outline`; starts on OK and
  keeps the last key from hold to hold). The holding hand's stick walks the light (`move_key`): to the nearest
  key in that direction by the keys' real places on the face, no further aside than 1.5x ahead, side distance
  counted 3x, never wrapping; on the ring it goes round the ring while another of its keys lies that way (left
  from the top arc is the left arc, not REW above it) and leaves it past the top and bottom arcs. Keys that do
  nothing on the aimed device are SKIPPED (`key_live`, the grid's own greying), the way the grid skips greyed
  cells; aimed at nothing every key is live. A stick click (or A/X) holds the lit key down while held, at least
  `KEY_FLASH`, and does its cell through `press_key` (a dead key still goes down and does nothing, as a real
  one would). Desktop: the arrows walk it, Enter holds it down. **The remote's own menu** (Tab / pointer
  menu, the generic `ObjectOptionsPanel` through `options_choices`, titled "TV Remote") has a "Floating
  button menu" Off/On row, `AppPrefs.remote_button_menu`, default off: an APP preference, not saved on the
  remote and not synced — how the player likes to drive a remote, kept for every remote and every room, the
  way "Press Controller Buttons by Touch" is. On, the grid is exactly as before (the stick and arrows walk
  it, its presses flash the key) and no key is lit. `tv_remote_tests stick/` (33): the default, the outline,
  ten neighbours (ring, rows, no wrap, dead keys passed on a set), the REAL stick and click through a tracker
  (VOL- one step down, sunk while held, alone, back up), a dead key, a DVD's PREV/MENU, the desktop arrows and
  Enter, the menu row switching the grid on (shown, no key lit, the stick walks the grid) and off, and the
  prefs file written (the player's real file, restored byte for byte). Mutation-tested: default on, no ring
  rule, no dead-key skip, no sink, a key lit under the grid, not saved, no outline each go red.
  `Tools/av/remote_stick_video_probe` (windowed, `--fixed-fps 30`) records it at the RETRO XR set and stills
  the menu.

**Every appliance key is pressed by a fingertip only over its own face (2026-10-30).** VRButton's touch is a
sphere round the key's centre (10 mm by default), so on the DVD's front panel a finger on the up arrow also
pressed MENU above it. `adopt_button` now gives every key `footprint_gate` (the cap's outline + 1 mm, no higher
than 3 mm over its face; the ring's arcs 0 mm), and widens `trigger_radius` to reach a wide key's corners (the
amplifier's 38 mm SURROUND MODE). `footprint_gate(..., face_axis)` takes the axis the face looks along: the record
player's 33/45 lie on the deck and press along -Y. `appliance_pointer_tests` `poke/` pushes a tracked fingertip
into every live key of the VCR, DVD, amplifier, record player and television (and the door keys with the door
open): each sinks its full travel, fires once, alone, and comes back up. Taking the gate off box keys fails it.

### Headphone jacks, and the RETRO XR headphones (2026-10-30)

**The jacks** (commit e744ce16). A handheld with no phono sockets wears a 3.5 mm TRS socket, `PhonesOut` (OUT,
`Channel.AUDIO_STEREO`), where its model's `headphone_jack()` says (`SystemAvPorts.build_phones`); a set's shell
names one with `PhonesSeat` (`TvPanel.seat_phones`). The jack is not in `ports`: a handheld plays from its own body
until the jack's lead reaches a SINK, and only then does `phones_carry_sound()` cut its speaker
(`audio_route()["socketed"]`). A sink is anything `get_device()` finds that answers `get_speaker_positions()`
(SpeakerPair, a set, now the headphones); the SOURCE owns its voices and puts its left channel at speaker 0 and its
right at speaker 1 every frame. A set's jack carries everything the set plays (`RetroTV.get_speaker_positions` hands
over the jack sink's), and the sink's `get_volume()` is folded into the set's level. The SP has no jack: its
`PhonesAdapter` in EXT.2 lends it one.

**The headphones** (`Scenes/Objects/appliances/headphones.tscn`, `Headphones` / `HeadphonesBody` / `HeadphonesPlug`;
model RetroXR-models `generic/headphones-portable`, assets `imported-assets/appliances/headphones/`). Spawned as
`headphones` (Objects, and every card with a jack). A `CompositeCable`, like the Antenna, with the difference that its
captive end HAS a plug: `PlugA0` sits for good in the headset's own hidden IN jack (`Body/LineIn`, on the left cup's
`CordExit`), so a jack's lead resolves to the headset as a sink by the ordinary path, and the whole routing above is
unchanged. `PlugB0` wears the model's plug and is the only connector a player touches.

- **Sound.** The host's two Meta XR voices go to the two pads, left channel left, right channel right. Dry: the game
  never calls `MetaXRAudioServer.set_room`, so no voice has a reverb or reflections send (`headphones_tests` checks no
  script calls it). One level and one law: the headphones push `Headphones.LEVEL` (0.7) at their source as a speaker
  knob does, and answer `get_audio_unit_size()` = 0.12 m, which `SystemAudio`, `MediaTransport` and (through the set)
  `RetroTV.get_audio_unit_size()` use in place of their own: full level within 12 cm of the head, 1/d past it. Worn,
  the cups' middle IS the head's middle, so gain 1.0; a metre off on a desk the same pair plays at 0.084, 0.12 of worn
  (-18 dB), the leak of open foam headphones. `hold_off_head` still holds each voice 25 cm out along its own
  direction, so worn they are hard left and hard right without the HRTF's near-field dulling.
- **Worn** is placement only. VR: let go within 0.28 m of the view point; grab to take off. Desktop: "On your head"
  in the headset's menu (`ObjectOptionsPanel` rows through `HeadphonesBody`), or the PLUG's menu once worn (the camera
  is inside the band, so the pointer cannot reach the headset). Saved (`carried_body_pose()["worn"]`); not sent to
  peers, who would otherwise put the headset on their own heads: they see it where its synced pose is.
- **Band size** (Small / Medium / Large: each ear piece 0 / 8 / 16 mm out of its slider) rides a hidden `VRSlider`
  (`Body/BandSize`), so the articulated-control walk saves and syncs it, as the turntable's SpeedSwitch does.
- **Collision** is what the model draws: boxes along the band's arch (the padded strip in them where it runs), the two
  sliders, and per side the pivot, strip, cup and pad as cylinders, on the body and its PointerArea alike; the open
  middle of the band is empty. The plug's box is its mesh's.
- `headphones_tests` (scene, jack, tv, sound, wear, save, ray; 49 checks). The sound group drives the real
  `SystemAudio.update_position` with a recording stand-in for the SDK (headless has none).
  `Tools/av/headphones_probe` (windowed) renders the headset and records its plug going into a Game Boy Color's jack.
  Listening (the probe runs no core), the Quest and a real session are OWED.
- Not yet: the record/cassette/CD players (`audio_player.gd`) do not read a sink's `get_audio_unit_size`, so through a
  set's jack they are heard at their own law; the CD player's PHONES jack is not a socket yet.
