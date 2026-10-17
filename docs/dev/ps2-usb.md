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
START and SELECT keys make the chord. **In VR the default light gun map has no
SELECT** (`ControllerBindings.DEFAULT_LIGHTGUN_MAP`: Start is the stick click, grip
is unassigned), so a player cannot calibrate without remapping. Open.
