# Power: devices run only when plugged in

The room has had the mains side for a long time: wall outlets (`WallOutlet`, a plate per
region from `MainsRegions`), power strips (`PowerStrip`), travel adapters (`TravelAdapter`),
the regional cords (`PowerCord`, seventeen baked `*_cord.tscn`, C7/C13 appliance ends) and
`MainsSplice` keeping plugs seated through a change of region. Since 2026-11-01 something
CONSUMES it: a console, a handheld, a set, a deck or a cabinet switches on only when a live
supply reaches it, and pulling the plug switches it off.

**The rule is opt-in.** Options > General > **Enable Power Simulation**
(`AppPrefs.power_simulation`) ships OFF, which is exactly the old behaviour: everything
powers whatever its cords do. Switching it ON turns on the rule, and cuts at once whatever
is running with no supply. A room with **no wall outlet at all** (the den, the test hallway,
passthrough, most mod rooms) powers everything either way (`MainsPower.room_has_mains`),
because nothing in it could ever be plugged in. The Arcade Room and the bedroom have outlets.

## The pieces

| piece | file | what it is |
|---|---|---|
| `MainsPower` | `Scripts/Objects/cables/power/mains_power.gd` | Static resolver, no autoload (IrBus's arrangement). `socket_live(port)`, `plug_live(plug)`, `seated_live(plug)`, `room_has_mains`, `changed(tree)`. |
| `PowerInput` | `Scripts/Objects/cables/power/power_input.gd` | A device's intake, a child named `PowerInput` (`PowerInput.on(host)`). Live when ANY source is: an inlet holding a live plug, its own cord's plug in a live socket (or the cord hidden), every cell bay filled, a built-in battery, a deck it is built into (`follow`). `evaluate()` gives `{live, supplied, supply}`; `describe()`/`why_not()` are the words the menu and the toast say. |
| `SystemPower` | `Scripts/Objects/systems/system_power.gd` | RetroSystem's component: builds the PowerInput with the model, the inlet from `PowerProfiles`, a handheld's battery bay; reacts to the supply coming or going. |
| `PowerProfiles` | `Scripts/Data/power_profiles.gd` | Per model id, then systemid: `inlet` (c8 / c8p / c14 / dc / dock), the DC `plug`, `brick`, `internal`, `bay`. No row = no supply modelled = always on. |
| `CaptiveMainsCord` | `Scripts/Objects/cables/power/captive_mains_cord.gd` | A deck's or the amplifier's own cord from its `PowerCordExit`, plug in the region's two-pin (or, grounded, three-pin) shape. Child of the current scene, freed with its host, never `spawned`. |
| `ApplianceMains` | `Scripts/Objects/power/appliance_mains.gd` | `hook_up(host)` gives a deck or the amplifier its PowerInput and its own cord; `hook_up_inlet(host, search, "c8"/"c14")` gives a set (C8) its inlet where the model's cord would leave; `follow(deck, set_input)` for a built-in deck. |
| `PowerBrickCatalog` / `PowerBrick` | `Scripts/Data/power_brick_catalog.gd`, `Scripts/Objects/power/power_brick.gd`, `Scenes/Objects/power/power_brick.tscn` | Every AC adapter as a primitive built from its row: wall wart, in-line, inlet, dock (N64), battery pack (DMG-03). |
| `BatteryBay` | `Scripts/Objects/power/battery_bay.gd` | A primitive handheld's compartment from its `bay` row, CUT INTO the body (2026-11-01): the body's box becomes the same box with a pocket in its back (`pocketed_box`), the cells inside, contacts, `BatteryAA<n>` seats (CellSlots) and a lift-off cover per compartment (CoverSlots) flush with the back, in the shell's colour. A seated cover is aimed at by a box of its own width standing `POINTER_REACH` (7 mm) out of the back, past the console's grab box (body + 5 mm), or the desktop ray and the laser took the console instead (`Tools/room/battery_bay_probe`, which checks both). |
| `PowerMenuRows` | `Scripts/UI/panels/power_menu_rows.gd` | The Power section of a device's System tab: status, supply line, Show Power Cord. |
| `VbPowerUnit` | `Scripts/Objects/power/vb_power_unit.gd`, `Scenes/Objects/power/vb_battery_pack.tscn`, `vb_ac_tap.tscn` | The Virtual Boy's VUE-007 battery pack (six AA behind an end lid) and VUE-011 AC adapter tap (a DC jack), each a primitive of the pack's measured outline that clips onto the controller's `PackMount`. |

## Rules

- **Power flows one way, wall to appliance.** A wall plug never carries power out; a
  strip plugged into one of its own sockets is dead (the walk keeps a `seen` set). Any
  lead, fixture or brick takes part by answering `mains_live_at(at, seen)` (and
  `mains_noun()`, `mains_wall_plug()` for the words).
- **Every change goes through `MainsPower.changed()`**, coalesced to one
  `call_group("mains_consumer", "on_mains_changed")` at the end of the frame: a seat or pull
  on any `PowerPort` or `DcPort` (`Port._mains_moved`), a cell in or out (`CellSlots`), the
  option (`AppPrefs.set_power_simulation`), a cord shown or hidden. A PowerInput emits
  `power_changed` only when its answer moves.
- **The gate is the machine's own power path, never a second one.** `RetroSystem.power_on()`
  asks `SystemPower.allows_power_on()` right after its early return and BEFORE the attract
  branch (an unplugged cabinet shows no attract either); `toggle_power()` asks too, because a
  host starting lockstep goes `netplay_start_host` -> `net_start_core` and never reaches
  `power_on`. `net_start_core` is not gated (that would desync peers). A client's press is
  not gated locally; it reaches the host, whose cords decide. A refusal says why on the
  machine's notice card ("No power").
- **A supply lost under a running machine switches it off** through the same path a press
  takes (`netplay_stop("unplugged")` for the session's machine, else `power_off()` and
  `EV_SYS_POWER_STATE`). Saves drain as on any stop.
- **A latched switch stays where the hand left it.** A slide (`latching_power_switch()`:
  a handheld's authored `PowerSwitch`, a console's `build_power_slider`) left ON with no
  supply brings the machine on when the supply arrives, and after a pull it is still ON. A
  push button and a spring-return slide never latch.
- **Inlets.** A model's own `PowerPort`/`DcPort` is its inlet (the PC tower's C14, a
  handheld's `DcInPort`). Otherwise `SystemPower` builds `PowerInlet` (never renamed: saves
  name the socket) on the back of the body from the profile: a C8 for an internal supply
  (`iec_c8_port.tscn` / `iec_c8_polarized_port.tscn`; a plain C7 also fits the polarized
  inlet, `Connectors.ALSO_FITS`), a barrel jack (`barrel_dc_port.tscn`, connector set at run
  time) for an adapter. A model can place its real one with `power_inlet_transform()`.
  **A detailed model's own inlet wins** (2026-11-01, `SystemPower.seat_on_model_inlet`):
  RetroXR-models marks each mouth with an empty whose name differs by model (`ACIn`,
  `ACInPort`, `AcInAnchor`, `DCIn`, `DCInPort`, `DCPort`, `DcInAnchor`, `PowerInPort`,
  `AcAdapterAnchor`: `SystemPower.MODEL_INLETS`); the socket goes there, facing out of the
  nearest face of the body, set in as deep as the stand-in's inlet is, and the stand-in's
  drawing of it is hidden. A mod's shell for a handheld that drops the stand-in's DC IN gets
  it back from the profile's `dc_jack`, in the model's inlet. The N64's mouth is its
  `PsuSeat` (`MOUTH_OUT` -Z: the bay's open back, the module's back face ends there), on
  the xenu.n64 model AND the stand-in, which has the real rear bay cut into its base
  (113.6 x 42.7 x 73.4, 70 mm left of the middle seen from the front, open underneath) --
  before 2026-11-02 the stand-in had none and the module stood off the back. The
  primitive module (`PowerBrick._make_dock`) reaches +Z from the plug's origin: a seated
  plug's +Z points INTO its socket, and built toward -Z it hung 73 mm off any back. The
  shipped Dreamcast GLB draws its AC IN (C8P, above SERIAL) with no empty, so
  `dreamcast_model.gd` adds `ACIn` at the pins' middle, measured off an orthographic render
  (move it into `prepare_dreamcast.py` at the next export). A model without an empty (the
  shipped NES and PlayStation GLBs predate theirs) keeps the built inlet.
  **Every built inlet is set in flush** (`ApplianceMains.inlet_proud`: the C8's drawn body
  stands 6 mm out of its socket point; its face is left 0.5 mm proud so it does not
  z-fight), and on a model with no `PowerCordExit` it goes on the drawn surface, found by
  a ray into the model's own triangles (`ApplianceMains.back_surface`: a CRT's back tapers,
  so the bounds' back is the tube's hump; a steep face such as a stand's rim moves the
  search toward the middle). The Panasonic set's inlet floated behind its corner before.
- **DC connectors are the plug's STANDARD** (`barrel_5_5x2_1`, `barrel_5_5x2_5`, `eiaj_03`,
  RetroXR-models `common/powerkit.py`), so consoles that take the same barrel take each
  other's adapter. Voltage is not modelled. Proprietary plugs have their own names
  (`snes_dc_plug`, `gc_dc_plug`, `wii_dc_plug`, `n64_psu_dock`); the five handheld names
  stay. A 5.5 x 2.5 plug goes over a 2.1 pin (loosely), not the reverse.
- **Handhelds.** Cells in EVERY bay, or a live DC adapter where the hardware runs off one,
  or a built-in pack (GBA SP, DS, 3DS, PSP: treated as always charged, so the machine is
  always powered; their jack only charges, so it is not an inlet).
  An object with bays counts only its cells; cells carry no charge level (a drain model is a
  follow-up). Base-game primitives get their bay from `PowerProfiles` `bay`
  (`BatteryBay`); a mod's shell that builds its own seats (xenu.gb) keeps them. A fresh
  spawn's bay is empty with its cover on: cells are the Power tab's AA/AAA rows.
- **A set has a cord of its own, as the decks do** (the user's call, REVERSED 2026-11-01:
  it was a C8 inlet): `ApplianceMains.hook_up(tv, shell)` from the RETRO XR model's
  `PowerCordExit`; a model with none (the Classic box, a mod's set like the Panasonic) gets
  an exit on the back it really has (`ApplianceMains._exit` -> `back_surface`), never the
  bounds' rearmost point, where a CRT's tapered back left the cord hanging in the air. A
  save from before has the set's plug recorded in a `PowerInlet` that is gone; the cord
  comes back loose. **Arcade cabinets keep a C14 inlet** (`PowerProfiles` row "c14", built
  by `SystemPower` on the back of the body and re-placed when the cabinet changes form) for
  the spawnable Power Cord (C13), which the arcade card offers. The TV's `_tv_enabled` is its switch position (a push-push switch latches):
  `is_on()` is switch AND power, so a pull darkens it and a replug brings it back.
- **Decks and the amplifier** (VCR, DVD, CD, cassette, record player, surround amp) have a
  cord of their own from their model's `PowerCordExit`. They go dead (nothing plays, display
  dark, amp silent) and come back. One a room AUTHORS (not `spawned`) starts with its cord
  hidden: furnished, plugged in behind the furniture.
- **A cord carried past its reach lets go of the outlet cleanly** (`CaptiveMainsCord`): a
  plug carried by hand past its cord's reach and seated was pulled out every tick and
  dropped AT the outlet, where the duplex's other socket took it back, so it traded sockets
  every frame. The pull goes through `MainsSync.release` (clear of the socket, which is shut
  for two ticks) and the tether reels it toward the appliance.
- **The spawn menu says where a model was sold and what its plug is**: a power row and its
  region tiles show the region's flag and the outlet of the variant's REAL wall plug
  (`MainsRegions.PLUG_OUTLETS`, `plug_glyph`, `flag_of`; `PowerSpawnRows.mark_of`), with
  "Type A" etc. on the tile and tooltip. It showed the region's own outlet, so a North
  American adapter (a Type A plug) wore North America's Type B.
- **Show Power Cord** (the device's System tab, devices with a cord of their own only): off
  puts the cord away, the plug out of its socket, and the device counts as plugged in out of
  sight. Saved on the host's `mains_cord` record and sent as `EV_MAINS_CORD_HIDDEN`.
- **The Virtual Boy runs on what is on its controller** (2026-11-01). The console has
  neither a switch nor a supply: its `PowerProfiles` row says `through: "controller"`, so
  its PowerInput reads (`PowerInput.through`) the intake of the controller in its port,
  which reads the unit on its back (`VbController.PackMount`), which reads its six cells or
  its jack. A supply line says the chain ("Controller: Battery pack: Batteries (6 AA)").
  The pack is the real one's outline (RetroXR-models `nintendo/virtual-boy/controller`
  MEASUREMENTS.md `pack`, 56.4 x 34.2 x 64 mm) in that model's `BatteryPackPivot` frame,
  its cells loaded end-on through the lid end in three columns of two exactly where the
  model's `BatteryAA1-6` are (front layer + toward the lid, back layer + away, as the lid's
  plates and springs have them), the lid a CoverSlots cover. The tap is the same box split
  as the model splits it: a base with a channel, the gray jack standing in it 19.8 mm
  toward the cord end with its socket facing the lid, and the lid (the box's back) a
  CoverSlots cover. **While the tap's lid is on, its jack takes no plug and the plug in it
  cannot be pulled** (CellSlots' rule for a bay, `VbPowerUnit._refresh_jack`); it goes
  back on over a plug, as the real one closes over the SNS-002's (a longer universal plug
  keeps a real one from closing; ours goes through it). The US tap takes the Super NES SNS-002's `snes_dc_plug`, the Japanese one the
  Famicom HVC-002's `barrel_5_5x2_1` (by the outlet region at spawn, saved as `variant`).
  The controller's POWER slide is the machine's latching switch (`SystemPower._latch`
  falls back to a port controller's `latching_power_switch()`). A fresh controller comes
  with its pack on, empty and shut, as one did out of the box; the card and the Power tab
  offer a second pack and the tap, and the card the SNES and Famicom adapters.
- **Bricks keep the region they were bought in.** A spawned brick is the Options region's
  variant (or the row's MAKE DEFAULT); a later region change does not re-form it, and
  `MainsSplice` splices a travel adapter in for its prongs as for any wall plug.

## Netplay

- Every mains lead (`PowerCord`, `PowerStrip`, `TravelAdapter`, `PowerBrick`) announces its
  seats as `CompositeCable` does, diffed against the last seating it reported
  (`MainsSync.report`, `EV_RCA_PLUG` / `EV_RCA_UNPLUG`, its own `net_seat_plug` /
  `net_release_plug`). Before 2026-11-01 mains plugs had no live event at all.
- An appliance's own cord is not an object on the wire: it is named by its appliance
  (`EV_MAINS_CORD_PLUG`, `EV_MAINS_CORD_UNPLUG`, `EV_MAINS_CORD_HIDDEN`, appended to
  `NetEvents.Event`, never renumber).
- Power itself is the host's: only the host (or an offline machine) gates and cuts
  (`SystemPower._on_power_changed` does nothing on a client). The mains region is a local
  preference, so a client may see a plug that does not fit its wall; the host decides.

## Saves

- A brick is a `composite_cable` entry, `kind` "power_brick", with `brick`, `variant`, its
  plugs and its body's pose.
- An appliance's cord is the `mains_cord` field of its OWN entry (`hidden`, the plug's pose,
  `device` + `port`), restored in pass 2 (`_restore_mains_cord`). An entry without it is from
  before appliances had cords: the cord comes back loose behind it.
- Bays and covers are CellSlots' and CoverSlots' fields, as for every object with them.
- A Virtual Boy pack is a `vb_battery_pack` entry and a tap a `vb_ac_tap` with its
  `variant` (PLAIN_SCENES: a pose, and their cells and lid as above). Which controller one
  is on is the CONTROLLER's `power_unit`, written even when null; a controller entry with no
  `power_unit` key is from before packs were their own and gets a fresh pack.

## Tests and probes

- `Tests/power_tests` (headless, no core): the graph (wall, strip, a strip in itself,
  travel adapter), PowerInput's answer and words, cells, the option and a room with no
  outlets, a console's built inlet / gate / pull / push button, a handheld's latching
  slide, the Arcade Room's plates read off the scene, the TV's cord (plug, pull, remote,
  hide, menu, region), the decks' and amp's gates, a Game Boy's bay (seats, cover, cells,
  a cell pulled while running), the bricks (wall wart, in-line PAL with its 2.5 mm plug,
  inlet brick fed by a C7 cord, battery pack), a save round trip, the Power tab's rows and
  token, the cabinet's cord and an authored set's hidden cord, and the Virtual Boy (`vb/`:
  no controller, an empty pack, the lid, five cells and six under a switch left ON, the
  pack pulled, the tap and the SNES adapter, the controller unplugged, a save round trip
  and an old save, Japan's tap).
- `Tools/room/power_probe` (windowed): unplugged / plugged in / the outlet close up / the
  set's plug pulled (frames for an mp4) / the cord hidden / a Game Boy's bay shut, open and
  full / the set's System tab. With mods mounted, a Game Boy may wear a mod's shell and its
  own bay; the primitives' bays render under `res://Tests/` (no mods).
- `Tools/room/vb_power_probe` (windowed): a Virtual Boy controller face down with its pack
  on, the pack off with its lid off and six cells in (front layer's + ends at the lid),
  and the tap on the controller with the SNS-002's plug in its jack.

## The pretty models (mods)

The primitives stay the game's; RetroXR-models' adapters dress them as MODS
(`ModApi.override_power_brick`, docs/modding.md "AC adapters"): a GLB per region the
adapter was sold in (`model`), the plug's (`plug_model`), and for the N64's module a
`model_offset`. `PowerBrickCatalog.override_brick` validates and holds them per mod
(`drop_mod` on withdraw); `PowerBrick` wears them: the box (or a wall wart's blades
and box) gives way to the model, its collision and pointer boxes are fitted to what it
draws (a wall wart's stop at its face), the cords leave from the model's
`DCCordAnchor` / `ACCordAnchor`, an inlet brick's C8 sits at its `ACInAnchor` with the
model's pocket as its look, and the DC plug's lead leaves at its `CordExit`. The
mods are generated in RetroXR-models by `mods/tools/make_power_mods.py` (sixteen,
`xenu.nesadapter` ... `xenu.3dsadapter`), checked and thumbnailed by
`mods/probes/powerbrick_probe` through `mods/tools/build_power_mods.sh`.
`power_tests models/` covers the game side with stand-in scenes.

## Not done / OWED

- A headset, the Quest and a real two-peer session: nobody has played with the rule on.
- The pretty models ship as mods (above); without them a brick is its primitive box. The
  N64 module's `model_offset` is read off its README (ConsoleSeat), not measured on a
  console with the model.
- The AGB-008 (a module IN the GBA's bay with a DC jack of its own) has no working form
  yet: the GBA runs on cells. The N64's NUS-002 docks into the console's rear bay (the
  module IS the plug); the stand-in's bay and module are primitives.
- The Virtual Boy's pack and tap are primitives in the base game; `xenu.vbpad`
  (RetroXR-models) dresses the controller, both units and both lids in the model's. Seating
  one is not announced in netplay (as the N64 paks are not). Both lids lift off where the
  real ones swing on hinges. Holding the model's controller (its hands on its grips, which
  run back from the pads where the stand-in's hang down) is OWED in a headset.
- No ModApi call registers a mod's `PowerProfiles` row or `PowerBrickCatalog` row yet (both
  have a static `extra` table to layer over the shipped one).
- Not gated: loading a tape or a disc, the CD tray, the cassette door (mechanical on some
  decks, motorised on others). Cells carry no charge level.
- The bay's walls take the shell's colour; the covers are CoverSlots' plain blocks.
- Consoles with no `PowerProfiles` row (no facts looked up yet) are always on.
