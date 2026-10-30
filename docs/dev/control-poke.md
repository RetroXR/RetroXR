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
