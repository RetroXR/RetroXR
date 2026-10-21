# The first gamepad, off a headset

**Status: PLAN, nothing built yet (2026-10-21).** The spec is the player's (pasted 2026-10-21); the
decisions marked **ASSUMED** are mine and want a yes or a correction before they are built.

## The spec

Off a headset:

1. **Controller 1 is treated as the keyboard is**: movement and main game control.
2. **Keyboard and controller are interchangeable on the fly.** The help prompts follow the LAST input:
   a key press shows keyboard prompts, a controller press shows controller prompts, instantly.
3. The controller still has its **adapter** (the spawnable `PadReceiver`) for being connected explicitly as
   an EXTERNAL controller, for a player who wants keyboard and controller at once.
4. Spawning the adapter for controller 1 from the menu first shows a **warning**: this treats the
   controller as external, so it stops being the main movement until the item in the game is put away.

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

## Proposed design

One service, `DesktopPad` (autoload, after `AppPrefs`), and everything else asks it.

- `main_device() -> int`: the joypad index of controller 1 (first of `GamepadBindings.usable_pads()`), or -1:
  no pad, a headset session, the pref off, or **an external receiver bound to that pad exists** (the adapter
  rule, point 3-4; one place decides it, so the keyboard-only fallback is automatic when the item is spawned
  and the pad is main again the moment it is put away / freed).
- `last_device` (KEYBOARD_MOUSE | GAMEPAD) from `_input`: a key, mouse button or mouse motion over 2 px is the
  first; a joypad button or an axis past 0.5 on `main_device` is the second. Signal `device_changed`.
- `pad_family` (xbox | playstation | switch | generic) from `Input.get_joy_name`, picks the glyph set.
- It adds/removes the joypad events on the InputMap actions that already exist, so locomotion needs no new
  code path and the "external" rule is one add/remove.

### Mapping  (**ASSUMED** -- Xbox names; PlayStation/Switch glyphs by `pad_family`)

| keyboard / mouse | controller 1 |
|---|---|
| WASD (move) | left stick |
| mouse look | right stick (turn + pitch), same sensitivity pref |
| left click: grab / press a control / drop on release | RT (also A) |
| wheel: push / pull / catch into the hand | D-pad up / down |
| middle-drag: turn the held thing | LT held + right stick |
| Shift: roll / drop modifier | LB |
| Tab: spawn menu | Menu (Start) |
| crouch | B |
| sprint / walk toggle | L3 |
| F11: picture fills the window | View (Back) |
| (holding a handheld or a controller: the game) | the pad drives it, the same way the keyboard does |

Menu navigation by pad (D-pad + A/B over the spawn menu) is **not** in this plan: the menu is a pointer UI.

### Stages  (each leaves the game working)

1. `DesktopPad`: last-device tracking, `main_device`, `pad_family`, the external rule; unit tests with synthetic
   `InputEventJoypad*` events.
2. Locomotion + look + menu + crouch/sprint by pad.
3. The hand by pad: grab / drop-on-release / push / pull / catch / turn (`desktop_pickup.gd`'s input becomes a
   handful of verbs the mouse and the pad both call).
4. Game control: a held handheld / controller is played by the main pad as by the keyboard.
5. Prompts: `HeldHint` and the menu hint rows re-draw on `device_changed`; a table maps each keyboard/mouse
   glyph to its pad glyph per family.
6. The warning when the menu spawns a `PadReceiver` for the main pad.

## Questions

1. **Mapping** above: right as a default? Which of crouch / sprint / jump do you want, and on which buttons?
2. **"Controller 1"** = the first usable pad. With two pads, is the second ONLY ever an external one?
3. **Game control**: should the pad drive the game in your hand even with a PadReceiver spawned elsewhere for
   the SAME pad? (As written, no: that pad is external, the keyboard moves you.)
4. **The warning**: a confirm dialog (Continue / Cancel), or a toast and the spawn goes ahead?
5. **When the pad is external and the item is put away**: main again immediately, or only after a button press?
6. Glyph sets: detect Xbox / PlayStation / Switch from the pad's name, or one set for all?

## Not testable here

No pad is attached to the development machine, and Godot's `Input.get_joy_*` reads the OS state, which a
synthetic event does not move. The service reads InputMap ACTIONS (which synthetic events do drive), so stages
1-3 are tested; stage 4 touches `GamepadBindings.poll`, which is not, and stays OWED a real pad.
