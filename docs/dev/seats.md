# Seats (§2z-seat)

`Seat` (`Scripts/Objects/room/seat.gd`, extends `XRToolsPickable` like `Table`) is somewhere the player sits: a racing seat, a stool, a chair, a floor cushion, a sofa,
a bed (`Scenes/Objects/furniture/seat_*.tscn`, baked by `Tools/gen/gen_seats.gd`, primitive boxes: sizes are ordinary furniture, none measured). Spawn menu > Objects.

- **Press the cushion to sit, again to get up; HOLD on the seat to carry it** (`grab_hold_seconds` = `HoldToGrab.DEFAULT_SECONDS`). `SeatTrigger` is a pointable
  `Area3D` slab 3 cm proud of the cushion, so it wins the ray over the body's `PointerArea` (the same rule that makes the arcade's panel grip work); it tints when aimed at.
- **A seat is a scene with the script and three markers:** `EyePoint` (where the head goes, -Z is the way it faces), `StandPoint` (a floor point to the side: the front is often a cabinet) and
  `SeatTrigger`. `type_id` names its `ScenePersistence.PLAIN_SCENES` row. A mod's seat is any scene that has them.
- **What sitting does.** The origin is turned about the head to the seat's heading and carried over the eye point, standing on the seat's floor (`Seat.origin_for_eye`, pure, tested on bare
  transforms); the origin is then PINNED there every physics frame. Walking, teleporting and snap-turning are held (`LocomotionManager.set_block`, owner `&"seat"`, channels ALL and DESKTOP_MOVE).
  Standing puts the head over `StandPoint` as the seat IS then (moved while sat on, it still works). One player, one seat (`Seat.current`); picking the seat up, freeing it, or leaving the room
  (`PlayerRig.leave_world` -> `Seat.release_all`) lets the player go.
- **THE PLAYER BODY STAYS ON (a critical bug shipped for a few hours, 2026-10-23).** godot-xr-tools runs every movement provider, the desktop's mouse-look and its mouse capture among them, from inside the
  body's physics step and skips them all when it is disabled: a seat that switched the body off left the player unable to turn, so unable to aim at the seat to get up. The body's collision mask (1019)
  has no pickable layer, so its capsule does not fight the seat. Proof: `Tools/models/seat_look_probe` (the game's real `player_rig.tscn`, injected mouse motion; `-- --oldbug` is the control leg:
  `turned=false`).
- **Height.** On the desktop the camera's own height IS the eye height, so the seat sets it and puts it back (also when the seat goes away mid-sit). In a headset the head's height is the person's: the
  seat puts the floor under itself and leaves the head where it is, so someone really sitting on a chair is already at that height. Not testable here: the headset and the Quest are OWED, and so
  is a bed (lying down changes nothing but the heading and the floor; the horizon is the person's).
- **Saving.** Pose only (`ScenePersistence` branch `node is Seat`, token = `type_id`). That the player is seated is this session's: never saved, never on the wire (the input a seat leads to goes through
  `netplay_route` as any input does).
- **What it is for.** A steering wheel and pedals (not built yet, see arcade.md "The cabinet follows the game") want a player who is held in front of them; a seat is that player. A seat per cabinet
  is wired only for a sit-down driving cabinet (below): elsewhere a seat is a separate object the player puts in front of it.
- **A cockpit's own seat (2026-10-25).** A sit-down driving cabinet (`ArcadeCabinetBuilder._build_cockpit`) is built with a seat you can press and sit in
  (`CockpitSeat`, node `DriverSeat`), where its seat was a decoration. The sitting is not the furniture's: it was lifted out of `Seat` into `SeatSitting`
  (pose, pin, camera height, locomotion block), which a `Seat` and a `CockpitSeat` each own one of; `Seat.current` is now a `Node` (either) and
  one player sits in one seat whichever kind (a chair's `sit()` gets up from the cockpit's). A `CockpitSeat` is part of the cabinet and no object of its
  own: not a pickable, not in the `spawned` or `seat` groups, never saved by itself; the cabinet being picked up, its form changing under the
  player or the room being left lets them go. **The eyes are at the middle of the glass** (`EyePoint` at the `racer` body's glass centre, 1.12 m,
  and 0.72 m above the cushion, the racing seat furniture's `eye_above`); the player gets up on the driver's side (`StandPoint` 0.62 m to the left, on
  the floor). **The cabinet's pointer boxes leave the cushion open**: a box over the whole seat stood between the laser and the trigger that lies
  3 cm proud of it (the base under the cushion and the back behind it are boxes; nothing above). `seat_tests cockpit/`; the view from the seat is
  `arcade_cabinet_probe --forms=daytona` (`formseat_`). A headset and the Quest are OWED, as for the furniture.
- **A seat on a moving base carries the player (2026-10-26).** A cockpit whose game's cabinet moved (After Burner II's, Out Run's: `ArcadeCabinetBuilder._build_cockpit` with `motion`) is built on a
  `MotionPivot` that `ArcadeControlModule` tilts about the platform's centre a few degrees with the stick or the wheel. The seat moves with it, and so does a seated player:
  `CockpitSeat._physics_process` calls `SeatSitting.follow()` before `pin()`, which moves the origin (and the body under it, and the pin) by the eye point's move since the last frame.
  **Position only**: the base turns, the view does not (a rotation of the player's view by a base is the thing that makes people ill in a headset: `AppPrefs.arcade_motion` is automatic = off in a headset,
  on at a desk, or the player's choice). `seat_tests follow/`. A headset and the Quest on a moving seat are OWED, as for every seat.
- Tests: `seat_tests` (groups `pose sit press family cockpit follow save`; mutation-tested: yaw sign and the body switch). Pictures: `Tools/models/seats_probe` (windowed; eyes yellow, stand point green).
