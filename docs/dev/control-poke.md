# Pressing a controller's buttons with a fingertip (ControlPoke)

Every button on every pad, handheld, the VMU, the Nunchuk and the light gun can
be pressed with a PokeTip, as well as from the bindings of the hand holding it.
Options > General > "Press Controller Buttons by Touch" (`AppPrefs.poke_controls`,
default ON, read every frame) switches it off, the Wii Remote's face VRButtons
with it (not its POWER key).

## How it works

`Scripts/Objects/widgets/control_poke.gd` is a RefCounted per owner holding
TARGETS — the caps the owner already animates — and hit-tests the player's two
PokeTips against each cap's REST-pose box once a frame (`poll()`, cached per
process frame). The owner ORs the result into the state it sends:

| owner | where the poke joins | targets from |
|---|---|---|
| `AnimatedController` (every pad, pack pads too) | `_send_joypad` (so core, netplay and the animation all see it); unplugged, `_process` animates from it | `add_animator(_anim)` + `_extra_poke_targets()` |
| `RetroSystemModelHandheld` | `HandheldInput._send_joypad` → `model.poke_merge()`, before the unsupported-button mask | stand-in animator + `_poke_targets()` + `_extra_poke_targets()` |
| `VmuCard` | `VmuInput._process` (held or not) → `set_input` | its animator |
| `Nunchuk` | `get_state()` C / Z, on two private bits | its two caps, along each cap's own -Y |
| `LightGun` | `_pressed_now()`, bits are LIGHTGUN ids | `_anim_btns` + `_extra_poke_targets()` (the trigger is left out: the holding hand pulls it) |

Not a VRButton per cap: a pad button is a HELD bit polled every frame, the caps
are 3-5 mm apart, and they already have an animator moving them. One test
against the animator's own entries keeps the two from disagreeing.

The TV remote is the other way round: its 26 keys each fire ONE action (a cell of
the remote grid), and the desktop ray and the laser must reach them too, so each is
a VRButton whose `press_gate` keeps a fingertip to that key alone (`av-suite.md`,
"The RETRO XR remote").

## Rules that cost a bug each

- **A target from an animator keeps the entry as `src` and reads bit/mask/
  stick_dir LIVE.** The Saturn pads re-assign C and Z's bits to the plugged-in
  core at run time.
- **A rocker's arms are DERIVED, never restated**: the arm a turn sinks is
  `dir × turn`, so a model passes the axes its own animation turns about for UP
  and RIGHT. Every model has its own convention (parent vs own frame, sign); the
  stand-ins, SP, 3DS and PSP each differ.
- **`AnimatedController` hands the animator `_dpad_pitch_sign()` only in
  `_animate`** — the poke binds in `_ready`, so `_bind_poke` copies it first. Bound
  without it, UP and DOWN came out swapped on the Famicom, VB and RetroPad pads.
- **The into-the-shell reach (20 mm) only KEEPS a press.** Applied to engaging
  too, a shoulder's reach ran under the face caps and pushing X or Y in pressed R.
- **A cap with no input behind it** (3DS/PSP HOME, the SP's light button) is a
  target with a `depth` and no bit: ControlPoke moves it itself.
- Sticks (thumbsticks, the 3DS circle pad and C-Stick, the PSP nub) are pushed,
  not pressed, and are not targets. The N64's C buttons are: they push the RIGHT
  STICK (`stick_dir`), never their L/R-aliased bits.
- **A shell pack must not call `super()` into anything new**: it still loads in
  older builds. That is why the hooks are `_extra_poke_targets()` (no super
  needed) and why the packs return plain dictionaries, never `ControlPoke.*`.
  The handheld default reads the detailed-shell rows by NAME and only rows of the
  `[node, rest, bit, …]` shape — the 3DS XL packs keep dictionaries under the
  same names.
- **A switched-off handheld's caps still go in** (`HandheldInput._animate_powered_off`):
  the poke and the cap animation run, nothing reaches the core or the wire. It
  animates for `OFF_SETTLE` (1 s) after the last poke or after switching off and
  is idle otherwise, so a room of handhelds that are off costs one poll each.
  Before, `_process` returned on power-off and a cap would not move at all.
- The hand holding the object never pokes it (`PokeTip.is_poking`), and nothing
  is tested unless a tip is within 0.35 m of the owner.

- **A fingertip gate on a VRButton judges the finger against where the cap RESTS, never the sunk cap, and holds a
  press for as long as the finger stays in the key's column** (`ApplianceModel.footprint_gate` + `cap_rest`,
  `VRButton.gate_holds`, 2026-11-08). Measured from the sunk cap, a finger backing off let go and pressed again, and
  a finger pushed through the key was dropped at the release radius and pressed again on the way out: every key of
  the RETRO XR appliances fired twice in a headset (the set's POWER switched itself back off). A suite's poke must
  push THROUGH the key and hold there past `CONTACT_GRACE`, or it cannot see either fault (av-suite.md).

## Widgets out of reach sleep (PokeWake, 2026-11-04)

`VRButton`, `VRSlider` and `VRKnob` each asked `PokeTip.any_tip_within` every frame,
in reach or not: 168 polling in the Starlight Arcade autosave (137 buttons, 18
sliders, 13 knobs), 0.44 ms a frame timed directly; the scanner costs 0.0055 ms. A
small saving: the room's on/off frame A/B (one process) cannot see it under ~17 ms,
and the 0.5-1.3 ms an earlier single-script A/B suggested was noise. They are Area3Ds on the pointable
layer (bit 20), so Jolt's broadphase already indexes them and follows every carried
console. `PokeWake` (`Scripts/Objects/widgets/poke_wake.gd`, a root child made on
first use, not an autoload) runs one `intersect_shape` sphere a fingertip a frame
(`WAKE_RADIUS` = `WIDGET_NEAR` + 0.1 m, areas only, mask bit 20) and switches on the
widgets it finds; each widget, idle for `SLEEP_AFTER` (30) frames, switches its own
`_process` off (`PokeWake.tick` at the end of its `_process`). Their code is
unchanged while they run.

- **A widget the query cannot find never sleeps** (`can_sleep`: pointable bit set, a
  shape owner with a shape and not disabled, the scanner's World3D). Otherwise it is
  a button that ignores a finger.
- **Busy keeps it awake**: a press, an armed trigger, a laser hovering
  (`pointer_event` wakes it first thing), `set_selected(true)`, a drag.
- **Something that switches a widget off must say so**, or a fingertip switches it
  back on: `VRButton.set_interactive(false)` sets `PokeWake.META_OFF`, focus mode's
  `_suspend` sets `META_SUSPENDED`, and `PokeWake.wake` refuses either. A bare
  `set_process(false)` is only safe with the pointable layer cleared too (the TV's
  hidden stereo key does both).
- New controllers are picked up from `node_added`, so a hand made after the widgets
  (a late rig, a test's tracked finger) is scanned from its first frame. A widget
  woken this frame runs from the next: a finger put straight onto a sleeping key
  still presses it once (`poke_wake_tests press/`).
- `PokeWake.enabled = false` is the kill switch and the control leg: nothing sleeps.
- `ControlPoke.poll` itself returns at once with no hand within `NEAR` and nothing held, once
  `SETTLE_FRAMES` (45) have let a released cap ease back: it walked every cap of every handheld
  for nobody, 1.63 ms a frame in the Starlight Arcade, 0.26 ms after (`control_poke_tests` `idle_*`).
  `poke_wake_tests` (20 cases; the wake and can-sleep paths mutation-tested).

## Testing

`Tests/control_poke_tests.tscn` (no mods): per object, `cover/` (every cap-like
mesh is a target, a widget's, or in `SKIP` with a reason), `press/` `push/`
`clear/` `off/` per cap, per handheld `powered_off/` (through a real HandheldInput), and per d-pad `pivot/` plus `arm_*` — the model's OWN
animation is driven with one bit, the arm it sank is found, and a tip there must
give that bit back. `--extra=key|kind|res://mods/<id>/<scene>.tscn` runs the
same on a staged shell pack (`RetroXR-models/mods/build_mod.py <id> --keep-stage
--project <checkout>`). Packs dressed onto the game's own scenes at run time
(NES, N64, PS1, DualShock/DS2, Wiimote, Nunchuk, VMU) have no scene of their own
to load this way.

How it feels in a headset — margins (2 mm engage, 6 mm release), the 0.05 s grace
and the d-pad dead zone — is OWED.

## Knobs: thumbwheels and haptics (`VRKnob`, 2026-11-08)

A `VRKnob` follows the hand ROUND ITS AXLE by default: the fingertip's angle about
the axle (`_angle_at`), right for a dial on a panel. That is wrong for a handheld's
edge THUMBWHEEL, whose axle is inside the shell with only a sliver of rim showing:
a straight swipe from an 8 mm rim can never pass 90 degrees (atan of distance over
radius), turns about 7 degrees per mm near the rim and next to nothing a few cm out,
so a 270-degree volume wheel took three strokes or more. `rim_drag` turns the cap by
the distance moved along the rim's TANGENT instead (Z x the radial to the knob's
first CollisionShape3D, so the box must sit over the showing rim, as every handheld
model script puts it), geared so `rim_travel` (4 cm) is the whole sweep whatever its
degrees. Incremental against the clamped cap, so there is no dead travel coming back
off an end. Laser drags use it too. `follow_roll` (the blinds' wand) is the third mode.

`haptics` (off by default) adds: a `Haptics.click` on latch and release, a tick
(`detent_magnitude`) per detent crossed (`detents` across the sweep), a bump
(`end_magnitude`) on ARRIVING at either end, never for pushing on and never for
coming off, and an optional stronger centre detent (`center_magnitude`, the DMG's
contrast). Every pulse is one 10 ms event and detent ticks closer than 30 ms are
dropped: the rumble manager holds the motor ~0.1 s per frame an event lives, so
more smears a swipe into a buzz. Only a holding controller rumbles: `set_value`
(netplay, restore) and the desktop wheel never do. `detent_felt` is emitted with
each pulse.

On: the game's GBA volume wheel, and in RetroXR-models the DMG's volume and contrast,
GBC, GBA, Pocket and Game Gear volume, and the Lynx's volume and brightness (all
`rim_drag`, `haptics`, 16 detents). Panel dials (speakers, decks, the camera's ball,
the WaveBird channel) keep the angle mode and no haptics. `knob_tests`.
