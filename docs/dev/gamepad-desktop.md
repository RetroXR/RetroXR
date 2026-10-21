# The first gamepad, off a headset

**Status: BUILT (2026-10-21), no real pad tried.** `DesktopPad` (autoload, `Scripts/Desktop/desktop_pad.gd`,
class `DesktopPadService`) makes the first pad the player's input. The spec is the player's; the mapping
below is the ASSUMED default I chose, so a correction is cheap. Tested with synthetic events only
(`Tests/desktop_pad_tests`, 72 cases; `Tools/room/pad_hand_probe`, windowed, through the real hand): **no
real pad has been plugged into this work**, so feel (look speed, dead zones, the trigger thresholds) and
the real `Input.get_joy_*` path (`held_state` -> `GamepadBindings.poll`) are OWED.

## The spec

Off a headset:

1. **Controller 1 is treated as the keyboard is**: movement and main game control.
2. **Keyboard and controller are interchangeable on the fly.** The help prompts follow the LAST input:
   a key press shows keyboard prompts, a controller press shows controller prompts, instantly.
3. The controller still has its **adapter** (the spawnable `PadReceiver`) for being connected explicitly as
   an EXTERNAL controller, for a player who wants keyboard and controller at once.
4. Spawning the adapter for controller 1 from the menu first shows a **warning**: this treats the
   controller as external, so it stops being the main movement until the item in the game is put away.

## How it works

The pad is made into the input the game already reads, not given code paths of its own.

- **`main_device`**: the first of `GamepadBindings.usable_pads()`, or -1 when a headset is on, there is
  no pad, or **a `PadReceiver` for that pad is in the room** (the adapter rule, 3-4: one place decides it,
  so the keyboard-only fallback is automatic while the item exists, and the pad is the player's again the
  moment it is freed). `would_go_external(guid, ordinal)` is what the menu asks.
- **`last_is_pad`** / `device_changed(pad)`: a key, mouse button or mouse move over 2 px is the keyboard; a
  joypad button or an axis past 0.5 on `main_device` is the pad. The events the pad makes itself carry
  `SYNTH_DEVICE` and are skipped, or the pad would read as the mouse. No main pad: always the keyboard.
- **InputMap actions** get the pad's events ADDED while a pad is main and taken off after: the left stick
  walks (`desktop_move_*`), Start `desktop_spawn_menu`, Back `desktop_tv_fullscreen`, B `action_crouch`, L3
  `action_walk`. Everything in the engine that already reads these needs no change.
- **The hand and looking round read the MOUSE**, so the pad sends mouse events: RT = left button (grab,
  press a control, drop on release, left-drag turns), LT = middle button (turn the held thing), D-pad up /
  down = wheel up / down (push / pull / catch; held, it repeats), the right stick = mouse motion
  (`LOOK_SPEED` 750 px/s, ~150 deg/s; `TURN_SCALE` 0.4 while LT), LB = Shift on all of it (roll; LB + RT
  drops a gun). `MovementDesktopTurn` already ignores the mouse while a button is held; it reads mouse
  motion, so the look and the turn needed nothing either.
- **R3 sends F3**, the keyboard's own "this device has my keys" (`ScrollLockCapture`). While a held device
  has them (`ScrollLockCapture.any_active()`, which asks each capture whether it is still eligible) the pad
  stops sending hand events AND its InputMap events come off (Start would otherwise open the spawn menu
  over the game it pauses, B crouch, A jump), **the pad is the game's**:
  `handheld_input.gd` and `retro_controller.gd` merge `DesktopPad.held_state(...)` (the same
  `GamepadBindings.poll` a `PadReceiver` uses, the machine's own pad map) into what the keyboard drives, the
  left stick not walking because capture already blocks locomotion.
- **Prompts**: `HeldHint` draws its desktop rows again in the pad's glyphs on `device_changed`
  (`DesktopPadService.pad_row`: `PAD_ROWS` rewrites a row whole -- rotate, hand hold, capture, drop -- and
  `PAD_GLYPHS` maps any other keyboard / mouse glyph one for one). **Only the Xbox set is whole** in
  `Textures/InputPrompts` (PlayStation lacks the face buttons, Switch the triggers and sticks), so one set
  serves every pad; `pad_family` from `Input.get_joy_name` is for when those fill in.
- **The warning**: `spawn_view._pad_receiver_row`. The first press on the main pad's receiver row swaps it
  for the explanation and Continue / Cancel; a row for any other pad spawns at once.

### Mapping

| keyboard / mouse | controller 1 |
|---|---|
| WASD | left stick |
| mouse look | right stick |
| left click: grab / press a control / drop on release | RT |
| wheel: push / pull / catch | D-pad up / down |
| middle button: turn the held thing (with mouse motion) | LT + right stick |
| Shift: roll / drop a gun | LB |
| F3 / Scroll Lock: the held device has the keys | R3 |
| Tab: spawn menu | Start |
| crouch | B |
| walk | L3 |
| F11: TV full screen | Back |
| a held handheld / controller, captured | the pad plays it (A is NOT the left button: it is a game button) |

Not mapped: jump (`ui_accept` is also the GUI's accept), menu navigation by pad (the menu is a pointer UI,
RT works it), a second pad (any other pad stays external: only a `PadReceiver` takes it to a console).

### Known limits

- Godot's `InputMap` does not tell two pads apart for an action, so with TWO pads the second also walks
  the player and presses crouch (the mouse events and the capture merge ARE per device).
- A wheel notch is sent as a press AND its release, as a real wheel's is (a press alone left the wheel's
  bit in `Input`'s button mask).

## What there is now

| piece | where | what it does today |
|---|---|---|
| `PadReceiver` | `Scripts/Objects/controllers/pad_receiver.gd` | a spawned object plugged into a console port; drives that port from ONE named physical pad (`pad_guid` + `pad_ordinal`). The spec's "adapter". |
| `GamepadBindings` | `Scripts/Data/bindings/gamepad_bindings.gd` | the physical-pad -> RetroPad map, `poll(map, stick_map, device)`, `usable_pads()`, `resolve_device(guid, ordinal)`, `identify_device`. Reads raw `Input.get_joy_*`. |
| keyboard for a game | `DesktopBindings`, `ScrollLockCapture`, `RetroController` | the keyboard drives ONE controller at a time, the one that took the capture; handhelds take it while held (`HandheldInput._desktop_held`). |
| locomotion | `xr-tools` `MovementDesktopDirect` (actions `desktop_move_*`), `MovementDesktopTurn` (mouse motion), crouch/sprint/jump nodes | keyboard + mouse only. No joypad event is bound to any action. |
| the hand | `desktop_pickup.gd` | mouse only: left = grab/click, release = drop, wheel = push/pull/catch, middle-drag = turn, shift = roll. |
| menu | `spawn_menu_controller.gd` | Tab / mouse; a joypad press is read only while capturing a rebind. |
| prompts | `HeldHint` rows with `PLATFORM_DESKTOP` or `PLATFORM_VR` and Kenney `InputPrompts` glyph names; `Textures/InputPrompts/` already holds `xbox_*` (32), `playstation_*`, `switch_*`. | keyboard/mouse glyphs on desktop; no gamepad set is ever chosen. |

The old "merge the pad into whatever you hold" is gone on purpose (`pad_receiver.gd` header): both hands were
occupied and two pads could not be two players. This is a different thing -- the pad as the PLAYER's input, not
a prop's -- and must not bring that merge back.

## Not testable here

No pad is attached to the development machine, and Godot's `Input.get_joy_*` reads the OS state, which a
synthetic event does not move. The service reads events and InputMap actions (which synthetic events do
drive), so the main pad, the last device, the map, the mouse events it sends, the prompts and the merge are
all tested; `held_state` -> `GamepadBindings.poll` (the held game actually reading a real pad) and the feel
of the sticks are not, and stay OWED a real pad.
