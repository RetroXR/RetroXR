# Record player (RETRO XR turntable)

`Scenes/Objects/appliances/record_player.tscn` wears the RETRO XR turntable model
(RetroXR-models `generic/turntable`; GLBs + `turntable_contract.json` in
`imported-assets/appliances/turntable/`). The scene keeps every node name the base
(`audio_player.gd`), the room save, netplay and the tests use; `record_player.gd`
dresses them with the model at `_ready` (`_dress_model`).

## Layout

- `Model` is an `ApplianceModel` with the three mobile levels, at y +0.0525 so the
  model's feet stand on y -0.03 (where the old primitive plinth's underside was; saved
  decks stay on their tables). Deck plate y 0.06, record seat (mat top) y 0.083.
- The model's moving parts are hung, all three levels each, under the scene's own
  pivots (`ApplianceModel.attach_part`), with the pivot set to the angle the model was
  built in first (`_hang`): `Platter` (spun by `_update_platter`), `ArmMount/ArmPivot`
  (turned by `TonearmLever`), `CoverPivot` (turned by `CoverLever`). Godot renames the
  second and third copies under one pivot; only LOD0's keeps the part's name.
- LOD1/LOD2 meshes join `outline_exclude`, or the highlight draws three outlines.
- `MediaSlot` (still a DIRECT child) sits on the mat plus half a record; `PlatterPoke`
  1 mm over it.

## Controls

| Model key | Scene node | Does |
|---|---|---|
| ButtonStartStop (front band) | `PlayButton` | START/STOP toggle of the motor (`_on_start_stop_pressed`). Only the deck's key toggles: `remote_play`/`remote_stop` still mean play/stop. |
| Button33 / Button45 (deck plate) | `Speed33Button` / `Speed45Button` | Set `SpeedSwitch` (pressed DOWN: `depress_axis` -Y). |
| — | `PauseButton`, `StopButton` | Switched off and hidden (the base resolves both; the deck has neither key). The remote keeps PAUSE and STOP. |
| — | `SpeedSwitch` | No longer reachable: hidden, collision layer 0, `PROCESS_MODE_DISABLED` (a hidden slider still engages by fingertip proximity). Kept because its value is what the save and netplay already carry for the speed. |

`Lamp33`/`Lamp45`: the selected speed's lamp is lit (an emission copy of its material,
per level) while the MOTOR runs; both dark when stopped (`_update_lamps`, on change only).

## Tonearm calibration

The model's yaws (contract, glTF +Y) plus a half turn are the lever's angles: rest
+3.739 deg, lead-in groove (146 mm) -24.161, run-out (60 mm) -47.261. So
`TonearmLever` throws `max_deg 3.739 .. min_deg -47.261` (51 deg) and, from the
bearing (x 0.135, z -0.1), the 230 mm arm and the spindle (x -0.055):

| value | angle | needle radius | export |
|---|---|---|---|
| 0 | +3.739 | on the rest, off the platter | |
| 0.5135 | -22.45 | 152 mm, the record's edge | `arm_park` |
| 0.5471 | -24.161 | 146 mm, lead-in | `arm_lead_in` |
| 1.0 | -47.261 | 60 mm, run-out | `arm_lead_out` |

`deck_tests model/` measures the MODEL's `Stylus` at each value (to 1 mm) and its
height on a record; the old deck's lead-in (0.557) is 2 mm off and fails it. Move the
model, the bearing or the platter and these must be recomputed.

## Dust cover

New with the model. `CoverPivot` on the hinge (y 0.061, z -0.197), `CoverLever` (a
VRLever on the front lip, 0 shut .. 1 open = -80 deg about local X) — a lever rather
than the GLB's `CoverOpen`/`CoverClose` animations, because a hand drags it and the
room save and netplay already carry every VRLever by path (`CoverPivot/CoverLever`).
`set_cover_open()` drives it from code. Authored OPEN.

Shut (value under 0.6, about 48 deg): the well closes even with the arm parked
(`_update_gate`: arm parked AND cover up), the tonearm goes off the pointable layer and
stops processing, and `CoverShape` (the closed cover's box on the body) is enabled so a
thing set on the cover rests on it; it is disabled once the cover moves.

## Line out

`AudioLOut` (white, AUDIO_L) and `AudioROut` (red, AUDIO_R) are RcaPorts (OUT), seated on
the model's jack mouths in `_dress_model` (`DeckFace.seat_port`). The routing is the
base's (`audio_player.gd`, "Line out"), so a CD or cassette deck gains it by adding the
two ports: a deck with them answers `on_av_topology_changed` (what `RcaPort.get_device`
walks up for), resolves its sockets through `AvSource` on a plug or unplug, and tells the
sink it gains (`on_av_source_found`) and the one it loses. The sink pushes its level back
through `set_audio_volume` -- a set its input's volume, the surround amplifier its knob,
and silence while the amplifier has no speaker on its back -- and each frame the deck's
two voices stand on the sink's `get_speaker_positions()` (the amplifier's FL / FR, folded
wherever those have no cabinet). The deck has no FreeSurround of its own, so through the
amplifier a record plays in stereo on the front pair and is not matrix-decoded. With no
lead it plays from the deck as before, at the level it had when the first lead went in.
The ground post stays the model's: the room has no ground lead. `NameLabel` is hidden
(the model carries the brand; the base still writes its text). Cases: `speaker_tests`
`amp/the turntable's line out ...`, `amp/a turntable cabled into AUDIO IN ...`; probe
`Tools/av/turntable_line_out_probe` (windowed) renders it cabled into the amplifier.

## Not done

- The arm does not lift (the model's `ArmLift`, cue_up 3.5 deg, is unused).

Probe: `Tools/av/turntable_model_probe.tscn` (windowed: `--resolution 1280x720
--position 20,20 -- --out=<dir>`) renders it playing with the cover up, a tonearm
close-up, the cover down, and frames of the cover opening and the arm swinging in.
