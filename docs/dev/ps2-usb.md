# PlayStation 2 USB sockets and the GunCon 2

The PlayStation 2 has two USB-A sockets on its front, and the GunCon 2 plugs into
one of them, not into a controller port. The room models it that way.

## How it is wired

- **Sockets.** `RetroSystem._build_usb_ports()` builds `UsbPort1`/`UsbPort2` for a
  console with USB (`Connectors.USB_PORTS`: `ps2` has 2; a model can override with
  `get_usb_port_count()`). They are snap zones taking a plug whose connector is
  `usb_a` (`Connectors.USB_A`) and nothing else; the controller ports refuse one.
  On the stand-in box they sit on the front face below ports 3/4 with a dark
  `UsbRecess`; a model moves them onto its own shell in `configure_usb_ports()` and
  hides the recess (the PS2 mods use the GLB's `USBPort1`/`USBPort2` markers, rolled
  180 degrees about Z like the controller ports so the plug sits the right way up).
- **The core.** RetroXR's PS2 core (LRPS2 fork) offers "GunCon 2" on each of its two
  input ports. Choosing it on port k plugs an emulated GunCon 2 into its USB port k
  and KEEPS the emulated DualShock 2 on that port's SIO slot ("The GunCon is a USB
  peripheral, so it does not displace the emulated SIO DualShock 2",
  `PAD.cpp` `retro_set_controller_port_device`). Pad and gun read the same frontend
  port, one as joypad, one as light gun; libretro-godot's `InputHandler` answers by
  the device QUERIED, so the two never overwrite each other.
- **So USB socket k is core port k.** `_on_usb_snapped` announces the plug's device
  on port k (`core_device_id` finds the core's "GunCon 2" by the gun's
  `device_names`) and the gun sends its aim and buttons as port k's light gun input.
  A device in USB socket k wins the port's announcement over the pad in controller
  port k, whichever went in first (`_bind_port`, `_unbind_port`, `_announce_port`,
  `_reannounce_port_devices`); taking the gun out announces the pad again.
- **No extra ports.** An earlier idea gave USB its own frontend ports 3/4; that
  collides with how a multitap numbers ports. Not needed: the core's own split
  above does it.
- **Saved and sent as `USB_SLOT_BASE + k` (16 + k).** `cabinet_port_of`,
  `restore_controller_plug` and `net_release_controller_port` all take that number,
  so a room restores the gun into its USB socket and a netplay peer sees it seated
  there. Netplay hands a port to whoever HOLDS its pad; a USB gun's number maps to
  no netplay port, so its input follows whoever owns core port k. Not validated.

## What a game does with it (measured)

`Tools/input/guncon2_usb_probe` boots a disc with no pad in any controller port and
a gun in USB socket `--usb=1|2` (or none, `--usb=0`, the control), aims at the centre
and presses buttons, writing the picture every 5 s. Run windowed.

Time Crisis II (USA), 2026-10-17:

| gun | at boot |
|---|---|
| none | skips calibration, goes to the memory card screen |
| USB socket 1 | GunCon 2 calibration, "calibrate **2P** side" |
| USB socket 2 | GunCon 2 calibration, "calibrate **1P** side" |

So which player a gun is, is the GAME's decision by USB port, as on the hardware --
here USB 2 is player 1 (PCSX2 reports Endgame doing the same). With the calibration
shot the game showed "Is the gun sight aligned correctly?" with the shot dead centre:
aim and trigger reach the game through its USB port.

## The calibration shot

The core takes a GunCon 2's calibration as START + SELECT held together
(`usb-guncon2-input.cpp`: frontends read the old LIGHTGUN_PAUSE through Start, so the
chord stands in for it, and is withheld from the game). The trigger alone does not
calibrate: a run without the chord sat on the calibration screen. On desktop the
START and SELECT keys make the chord. **In VR it is stick click + grip**: the
default light gun map (`ControllerBindings.DEFAULT_LIGHTGUN_MAP`) has Start on the
stick click and Select on the grip. A held gun stays held without the grip, and the
drop combo is grip + trigger + stick click, so the chord neither fires nor drops it
(`binding_tests` `calibrate/`). It had no Select at all until 2026-10-17. A player
whose bindings file was saved before then keeps the grip unassigned until they
press Reset on the Controls page (a saved map is written whole and shadows the
defaults).

## The gun's other buttons

The light gun ids are libretro.h's (`binding_tests` `ids/` reads them out of the
header). Until 2026-10-17 they were numbered by hand straight on from Start, so
Aux C went as the retired PAUSE (5) and the thumbstick d-pad was one button askew:
up sent Aux C, down sent up, left sent down, right sent left and nothing sent
right. The GunCon 2 reads all of them (`usb-guncon2-input.cpp`): Trigger, A, B, C,
Start, Select, the d-pad and RELOAD.

RELOAD (id 16) is an off-screen shot: the core sends the trigger with the position
(0, 0). The extension used to answer it with its bit, which an `int16_t` truncates
to 0, so no core was ever told a reload (`ButtonFromMask`, libretro-godot
`tests/button_mask_test.cpp`; the joypad's R3, bit 15, came back as -32768 the same
way). Nothing binds it by default: aiming off the glass and firing does the same.
The Controls page offers it, and on desktop the pad's Y key is Reload and X is Aux C.

Measured 2026-10-17 with `guncon2_usb_probe --usb=2 --then=trigger|offscreen|reload`
(calibrate at 30 s, then hold that button to the end). Time Crisis II's "Is the gun
sight aligned correctly?" screen draws the gun's live cursor: the trigger leg keeps it
centred, the offscreen leg has none, and RELOAD held at the middle takes it away as
the offscreen leg does. The same RELOAD leg on the extension before the fix keeps it
centred. The calibration screen comes up at about 24 s: a chord before it is lost,
which is why `--then` calibrates at 30.
