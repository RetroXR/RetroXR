# The Super Scope (SNS-013) and its receiver (SNS-014)

Nintendo's light gun for the Super NES, as three room objects: the cordless
**scope** (`SuperScope`, `Scripts/Objects/peripherals/super_scope/super_scope.gd`,
a `LightGun` with no cord), its infrared **receiver** (`SuperScopeReceiver`, the
thing in the console's port) and its detachable **sight** (`SuperScopeSight`).
All three are primitive stand-ins built in code. Offered on the SNES card:
"Super Scope (SNS-013)", "Super Scope Receiver (SNS-014)" and an AA battery row.
The generic Light Gun row stays on the card, standing in for the Justifier and
the M.A.C.S. rifle.

## The hardware

Sources: the design patents US D344,108 / D353,169 / D353,170 and the utility
patent US 5,310,192 (Nintendo; true orthographic views and the switch
positions), the Super Scope 6 manual, the Wikipedia article and its Wikimedia
Commons photographs
(left, right, receiver, and a cut-away "Bisected" one). Read the photos before
changing the model (memory: stand-ins match real mechanics).

| what | fact | where from |
|---|---|---|
| length | just under 61 cm | Wikipedia |
| layout | orange-ringed lens at the MUZZLE; pistol grip hanging under the barrel near the FRONT; dark curved shoulder rest under the rear stock | photos |
| top controls | midway along the top, front to back: FIRE (purple), PAUSE (grey, round), then the power switch | photos, Wikipedia |
| power switch | OFF at the rear, ON in the centre, TURBO at the front | US 5,310,192 (first position off, second on, third continuous fire); the manual ("slide this switch forward to the center position to turn the power on") |
| CURSOR | on the grip | Wikipedia; the photos show a small button on the grip's back face near the top |
| cells | six AA | Wikipedia, every box |
| battery tray | in the rear stock: two rows of three AA in a tube running diagonally through it, springs and contacts at both ends; the door is the stock's sloped underside (medium confidence) | Bisected photo, a replica battery cover (90.6 x 33.5 mm) |
| infrared out | a small dark window in the hump over the muzzle, looking forward | Bisected photo |
| sight | about 13 cm, a rubber eyepiece at the rear; two clips on EACH side of the barrel, so it mounts left or right | Wikipedia, photos |
| receiver | 6.4 x 6.4 x 2.5 cm, an oval black window across its front, an SNES pad cord out of the back; in controller PORT 2, stood on top of the set | Wikipedia, photo |

**ESTIMATES** (named constants, flagged in the code): every size not in the
table; the cells' layout (the stand-in lays six side by side across the stock,
BatteryBay's way, not two rows of three on the diagonal, door in its underside,
so the shoulder rest is drawn behind it);
the infrared range (0.3-6 m; Nintendo's figure is that it aims best from 3 m),
its beam (30 degrees each way) and the receiver's acceptance (60 degrees off
its face).

## The cores (measured in `~/libretro-cores-retroxr/`)

- **snes9x** lists `SuperScope` (id 260) on its SECOND port only
  (`libretro/libretro.cpp` `port_2`); its first port has no gun. Its lightgun
  mode (`snes9x_lightgun_mode`, default `Lightgun`) reads TRIGGER = Fire,
  AUX_A = Cursor, AUX_B = Turbo, START = Pause, IS_OFFSCREEN = aim off screen.
- **Turbo is a TOGGLE in the core.** snes9x flips `SUPERSCOPE_TURBO` on each
  rising edge of AUX_B (`controls.cpp`, the `S9xButtonSuperscope` case); the
  libretro layer latches the edge (`snes_superscope_turbo_latch`). The toggle
  is in the savestate (`S9xControlPreSaveState` copies `phys_buttons`) and
  resets to off when the core starts (`superscope.phys_buttons = 0`).
- **bsnes reads a Super Scope only as a touchscreen pointer**
  (`target-libretro/program.cpp`, the `SuperScope` case returns 0 unless
  `retro_pointer_enabled`). The scope plays on snes9x, the SNES default core.

`Tools/input/super_scope_device_probe` (windowed, one leg per process) runs the
real snes9x on any SNES ROM (default: a Super Game Boy BIOS, which is what this
machine has): snes9x draws its own crosshair where a port-2 Super Scope points.
`--leg=scope` checks the resolver gives 260 from the core's own list and the
crosshair appears; `--leg=pad` is the control (a joypad draws nothing);
`--leg=port0` checks the first socket is told NONE and draws nothing. All three
PASS (2026-11-04).

## How the room does it

**The receiver is the port.** Its captive cord's plug carries `device_type` 4,
`device_names` ["superscope", "super scope"] and **`strict_device_names`**: when
the running core lists devices for the port and none has that name,
`SystemPorts.core_device_id(..., strict)` announces **NONE** instead of the bare
light gun type. A plug does not copy the flag, so `strict_names_of` asks the
plug's controller. So the receiver seats in either socket, as on the console,
but in socket 1 nothing reads it, and it toasts "works in controller port 2". A
core that lists nothing for a port is still told the bare type.

**The scope pairs** with the nearest seated receiver no other scope has
(`_repair`, on every receiver seat/unseat, once a second and on spawn: the
Satellite's arrangement), and then calls LightGun's own `on_plugged_in` with the
receiver's console and libretro port. Its `get_connected_system()` is null and
`restore_port_connection` does nothing: the port is the receiver's to save.

**The infrared is a gate on what is sent, not on the pairing** (`_link_ok`,
looked at every 6 physics ticks). It is up when the switch is not OFF, the
cells are live (`PowerInput`; with power simulation off they always are), and
the receiver's window is in the scope's beam, the scope in the window's view,
within range, and with a clear ray on `IrBus.SIGHT_MASK` (the room and loose
objects; held things are on layer 17 and do not block). Down, `_set_button`
sends every button released and `_set_aim` sends the gun off the screen: what
a receiver hearing nothing reports. The gate sits before
`NetworkManager.netplay_set_lightgun_*`, so the wire carries the gated input.
Every change is logged with its reason (`[SuperScope] link down: 93 degrees off
the beam (half 30)`).

**Turbo is translated.** The scope `claim_button`s AUX_B, so no hand press
reaches the core. What the core believes is kept on the CONSOLE (meta
`super_scope_core_turbo`: it is the core's, and outlives a receiver pulled and
put back). When the switch and that belief part, and the core is running and
the link up, the scope sends ONE press (`set_external_button` AUX_B down for
60 ms, then up for 60 ms before another may start) and flips the belief. A
stopped core clears it (a new run starts off). The switch at OFF sends nothing,
so the core keeps what it had, as the hardware's would. **Limit:** a savestate
load sets the core's toggle from the state; the belief is not re-read (nothing
exposes it), so it is logged as unverified and corrected only by moving the
switch. Netplay replays the presses as inputs, so peers agree.

**Controls.** Fire is TRIGGER, Cursor AUX_A, Pause START, from the stock
light gun map (trigger, A/X, stick click); the switch is a three-step
`VRSlider`. Fire, Pause and Cursor are `_anim_btns` caps, so a fingertip presses
them too (`ControlPoke`); Cursor presses along its own `dir` (toward the
muzzle), which `LightGun._animate_controls` now honours for any cap.

**One hand.** The grip is the hold, as every gun's. A second-hand grab is not
offered: the fork emits `grabbed` for the second hand and no `dropped` when the
first lets go while the second holds, which breaks LightGun's toggle-hold.

**The sight** clips into `SightClipL` / `SightClipR` (`CoverSlots.make_zone`,
group `super_scope_sight`), seats by its identity grab point, and is lent the
scope's collision (`SeatedCollision`). A fresh scope comes with it on the left
(skipped when the scope is `CoverSlots.RESTORING`, which netplay object sync
also sets). Cosmetic: the game is told where the barrel points.

**Saved:** `super_scope` (pose, `power_switch` set before `_ready`, `sight` ref
and `sight_side`), `super_scope_receiver` (its console and socket, as the
Satellite receiver), `super_scope_sight` (pose only). The cells are the bay's,
saved as any bay's are.

## Tests and probes

- `Tests/super_scope_tests` (73 cases): `port/` (260 in socket 2, NONE in socket
  1, the generic gun still a plain gun there, the bare type for a core that
  lists nothing), `pair/`, `gate/` (OFF, a wall, turned away, out of range,
  behind the receiver), `turbo/` (the hand's AUX_B claimed; one press per
  change, none while left, none at OFF, the stopped core starts off), `sight/`,
  `bay/`, `poke/`, `save/`, `spawn/`. Mutation-tested: the gate removed, the
  belief never updated, the claim dropped, the strict flag unread on a plug.
- `Tools/input/super_scope_device_probe` (above).
- `Tools/models/super_scope_render_probe` (windowed): the scope with its sight
  on each clip, its controls and muzzle, the receiver on a set with its plug in
  port 2; prints the pairing and the link.

## OWED

A real Super Scope game played through (Super Scope 6, Yoshi's Safari, Battle
Clash, T2: none on this machine), which is also the only check of turbo in a
game; a headset (how a 61 cm gun held by its grip sits, the slide under a
fingertip); the Quest; a real two-peer session; the pretty model.
