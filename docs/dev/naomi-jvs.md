# NAOMI, JVS and JAMMA hookup (plan 2026-11-11, built 2026-11-12)

The owner's calls: a **full physical hookup** (the board is an object on the cabinet's tray; power, JVS, VGA and RCA cords are
plugged by the player; a cart, or the DIMM board with its key and a cabled GD-ROM drive with a disc, sits on the board); **cords are
RetroXR's, never a mod's**; every Sega cabinet takes **NAOMI and JAMMA**; a NAOMI in a JAMMA cabinet goes through a **modeled
JVS-to-JAMMA converter**, as on real hardware. The models are in RetroXR-models (`sega/naomi/*`, `sega/arcade/*`); the mods carry the
models and register them; the JVS and JAMMA logic lives here.

## Real hardware, in one paragraph

JAMMA (1985): one 56-way edge carries power, RGB video, mono audio, both players' controls and the coin switches. JVS (1996, the NAOMI):
each job its own lead: power from the cabinet's supply, VGA to the monitor, RCA L/R to the amplifier, and the controls through a JVS I/O
board (wired to the panel and the coin mechs) that talks to the board over a USB-shaped cable (RS-485, not USB). A NAOMI in a JAMMA
cabinet sits behind a JVS-to-JAMMA I/O board on the cabinet's harness.

## Design

- **Typed ports** on every device (`Port` subclasses): `power_in`, `vga_out`/`vga_in`, `rca_out`/`rca_in` L and R, `jvs_host`
  (USB-A, on the board), `jvs_device` (USB-B, on an I/O board), `jamma_edge`/`jamma_harness`, `gd_data` (the 50-pin half-pitch, DIMM
  board to drive).
- **A cabinet is devices with fixed internal wiring**: the monitor (VGA in, or video from the harness), the amplifier (RCA in, or audio
  from the harness), the supply (outputs), the JVS I/O board (wired to the control and coin modules), and in a JAMMA cabinet the harness.
- **One hookup resolver per cabinet** (`ArcadeHookup`), run whenever a plug changes: power reaches the board -> it boots; video reaches the
  monitor -> a picture; audio reaches the amplifier -> sound (else silent); the controls reach the board (the JVS chain or the JAMMA
  edge) -> input. Each degrades the way hardware does: no VGA is a black screen, not a refusal.
- **The board's game comes from its own media**: a cart on the board; or the DIMM board with its key, a drive cabled to it and powered,
  and a disc in the drive. The cabinet asks the board for its game and system (`naomi`, `naomi2`), and the core follows the system.
- **The connection graph is data** (which port to which): it saves with the room and replicates like any other state.

## Gaps this closes (from the code survey)

1. A cabinet's system comes from its bay kind's first system (`system.gd` `link_bay`, `_resolve_core`; `arcade_cabinet_model.gd`
   `own_system`): a cabinet taking JAMMA and NAOMI would start a NAOMI on MAME. -> the system comes from the seated board.
2. Bay units are a fixed list (`arcade_bay_unit.gd` `SCENES`, `LABELS`; `scene_persistence.gd`; `spawn_catalog.gd`). -> a NAOMI board
   unit, and a way for a mod's unit to be saved and spawned.
3. No media on media (a cart on a board in a bay; a key on the DIMM board). -> nested slots on the board unit and the DIMM board.
4. `ArcadeDiscs` covers `arcade` CHDs only. -> NAOMI GD-ROM games (GDI/CHD) through the DIMM board and the drive.
5. No USB-B, no JVS cord, no gd_data cord (`connectors.gd`); nothing requires a cord. -> the connectors, a `JvsCable` (from
   `JammaCable`'s `_resolve`), and the resolver above.
6. The cabinet models' node names differ from the module contract (`Stick1Pivot`/`StickPivot`, `P1Button1`/`Btn1`,
   `Screen`/`CabinetScreen`, `CoinSlot1`/`CoinSlot` per module): the mods' scenes map them.

## Phases (each playable before the next)

1. **Board-driven system**: a cabinet's systemid and core come from the media in its bay; a bay kind may list several systems. A NAOMI
   cart in a cabinet runs on flycast, a JAMMA board in the same cabinet on MAME.
2. **NAOMI board unit and cart**: the board as a bay unit on the tray (VRDrawer), its CartSeat; the cart as NAOMI media; the cabinet mods
   (Blast City, New Net City, NAOMI Universal, Aero City) with their modules mapped; JAMMA boards still go in.
3. **Ports, cords and the resolver**: power, VGA, RCA, JVS on the board and the cabinet; the resolver gating picture, sound and input.
4. **JVS-to-JAMMA converter** for the JAMMA cabinets; the JVS I/O board model in the JVS cabinets.
5. **GD-ROM**: the DIMM board on the board's CartSeat, its key seat, the drive (lid, disc seat, data and power ports), GD-ROM games.

## As built (2026-11-12)

Every phase is in. The game ships a stand-in for each part, playable with no mod; a mod only swaps a part's look.

1. **Board-driven system**: `RetroSystem._bay_systems` / `_follow_media_system`; bay kinds `naomi` and `sega_jvs` (ArcadeProfiles).
2. **The NAOMI board and cart**: the `naomi` ArcadeBayUnit (baked by `Tools/gen/gen_arcade_bay.gd --kind=naomi`): its CartSeat turned
   for the flat cart (`CART_SIZES` naomi/naomi2 0.2546 x 0.1258 x 0.020, the models repo's cart frame); markers named as the model's
   anchors. **`ArcadeBayShells`** + `ModApi.override_arcade_bay_shell(kind, {shell, size, shell_lods, shell_offset | origin, turn})`:
   a mod's model over a stand-in, its same-name anchors moving the markers (CartSeat <- CartAnchor). **`ArcadeCabinetFromModel`**: a
   mod's cabinet GLB (the models repo's part names, `sega/arcade/common/candy.py`) built into modules: two panels, the screen, the coin
   doors, the bay with its door's hinge and its BayMount (on a VRDrawer tray where the model has one).
3. **Ports, cords, the resolver**: the board's sockets (`ArcadeBayUnit._build_naomi_ports`: VGA and phono out, the JVS USB-A, the JST
   power header) and the cabinet's at its leads (`ArcadeCabinetFromModel._build_leads`); cords `vga_cable`, `composite_cable`,
   `jvs_cable` (usb_a to usb_b; End A wears the game's USB-A plug model, `imported-assets/connectors/usb_a_plug`, in the scene), `naomi_power_cable` (jst_vl8). **`NaomiHookup.state`**, polled by the cabinet 4 times a second, gates
   the picture (`host_picture`), each audio channel (`RetroSystem.audio_speakers`) and the controls and coins (`ArcadeInput._send`); no
   power takes all of them. A cabinet without the NAOMI leads (the Morphing Arcade Cabinet) is not gated. A fresh cabinet's NAOMI comes
   wired (`NaomiHookup.seed_cords`); a restored room keeps its own cords.
4. **The JVS boards**: a JVS cabinet's I/O board is a stand-in at its JvsLead carrying its USB-B (dressable, kind `jvs_io_board`); a
   JAMMA cabinet (it has a JammaLead, so no I/O board) takes a **`JvsJammaConverter`** (`jvs_jamma_converter`): the harness's JAMMA
   Cable on its edge, the NAOMI's JVS and VGA into it. A fresh JAMMA cabinet comes with one wired in.
5. **GD-ROM**: **`NaomiDimm`** (the DIMM board, the NAOMI's media in the cartridge's place), **`NaomiKey`** (a game's key chip, saved
   with its game), **`NaomiGdDrive`** (the drive: its lid a hinge, the disc on its spindle only while the lid is open), the `gd_cable`.
   `NaomiGdRom.resolve` gives the DIMM board its game once the key, the cable, the disc and a shut lid are there; the wrong key is
   ERROR 33. A NAOMI romset with a GD-ROM image beside it (`ArcadeDiscs.needs_disc`) spawns as its disc and its key.

Tests: `arcade_bay_tests` groups `naomi`, `hookup`, `converter`, `gdrom`. The models repo's mods (`xenu.naomi`, `xenu.blastcity`,
`xenu.newnetcity`, `xenu.naomiuniversal`, `xenu.aerocity`, `xenu.jvsjamma`, `xenu.jvsio`, `xenu.naomigd`) are checked by its probes
(`naomi_probe`, `cabinets_probe`, `gdrom_probe`).

Since: the NAOMI 2 has its own board kind (`naomi2`, it takes NAOMI cartridges too, dressed by `xenu.naomi2`); the GD-ROM drive has a
power socket, and in a cabinet with the NAOMI leads it needs the supply's second lead (`DrivePowerLeadIn`) before the DIMM board loads a
game (the hookup test checks it); the new cords have plugs of their own size (boxes, until a mod draws them).

The Atomiswave (the Atomiswave session, 2026-11-12): its own bay kind `atomiswave` (a JAMMA edge, its JammaPort on a
`JammaEdgeAnchor` marker the board's model moves) and the AWSD cabinet built by ArcadeCabinetFromModel, whose new field
`bay_roll_deg` turns the mount for a board standing on edge (-90 for the AWSD); mods `xenu.awsd`, `xenu.atomiswave`.

Open: a real GD-ROM game through flycast on this chain (this machine has no NAOMI romsets or BIOS in its roms folders); the cords'
plugs are plain boxes.
