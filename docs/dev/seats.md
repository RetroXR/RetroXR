# Seats (§2z-seat)

`Seat` (`Scripts/Objects/room/seat.gd`, extends `XRToolsPickable` like `Table`) is somewhere the player sits. **The seats in the room are the RETRO XR furniture (2026-11-12),
built from their models' contracts by `ContractSeat`** (`Scripts/Objects/room/contract_seat.gd`): three sofas (`sofa_midcentury`, `sofa_overstuffed`, `sofa_futon`), two stools
(`stool_mission`, `stool_midcentury`), `chair_desk`, `chair_papasan`, `pouf`, five beds (`bed_captain`, `bed_brass`, `bed_waterbed` queens; `bed_wooden`, `bed_racecar` twins),
and six FLOOR seats (2026-11-14: `floor_cushion_square`, `floor_cushion_round`, `zabuton`, `flip_chair`, `floor_pillow`, `floor_rocker`), modelled in RetroXR-models
`generic/seating` and `generic/beds` (`imported-assets/furniture/{seating,beds}/`, sizes estimated). Spawn menu > Objects. `ScenePersistence.SEAT_FURNITURE_IDS` lists them. The six primitive seats
(racing seat, stool, chair, floor cushion, sofa, bed) were taken out the same day; the chair and sofa are TEST FIXTURES (`Tests/fixtures/seat_{chair,sofa}.tscn`, baked by
`Tools/gen/gen_seats.gd`), and a room saved with any of the six loads without it (`unknown object type`).

- **Built from the contract, at run time** (as `DrawerFurniture`; a `.json` ships with the export): the scene is only the `Model` (`ApplianceModel`, three levels by distance;
  sofas and beds switch farther out, 2.5-3 / 6-7 m, so a sitter never sees the swap) and the highlight. `ContractSeat` adds the collision boxes (every list under `collision`), the
  same boxes as the `PointerArea`, the places and stand points below, and a bed's drawers (`FurnitureDrawers`, furniture.md).
- **PLACES: a seat can have several.** Each place is an eye marker (`EyePoint`, `EyePoint2`, ...; the contract's `z_axis` is its +Z, so -Z looks out of the front) and a
  `SeatTrigger` that NAMES it (`SeatTrigger.eye_point` / `stand_point`). A press on a trigger sits at THAT place (`Seat.toggle_at` -> `sit_place`); seated, any press on the seat
  stands you up, wherever on it (the laser slabs grow while seated and overlap, so a press meant for the next cushion must not move you along it: get up, press again).
  A trigger that names nothing is the old single place (`EyePoint` / `StandPoint`, `Seat.toggle`), which the fixtures and `CockpitSeat` still use. The FIRST place is the
  seat's own `EyePoint` / `SeatTrigger` (the facing arrow, a plain `sit()`): a sofa's middle cushion.
- **A sofa** has its contract's three `seats`, one cushion each. **A bed** is split along its length: the head end (from the head of the mattress to 0.25 m past
  `lie_eye_point`) LIES you down, the head on the pillow looking toward the foot (no pitch is forced: the head or the mouse looks up); the rest SITS you on the +X edge
  (`eye_point`, looking out of the side). Eyes: sitting 1.2-1.5 m (a bed's mattress is high), lying 0.65-0.93 m.
- **A FLOOR seat** (`ContractSeat.is_floor_seat()`: its contract's `seat_top` under 0.3 m, `FLOOR_SEAT_TOP`) is sat on as the floor is: the eyes a floor-sitter's, 0.86-1.04 m over
  the floor and about 0.78 m over its top (0.76 in the reclined rocker), where a chair's are 1.2 m or more. `seat_tests contract/` holds each piece to the range its OWN contract
  puts it in (mutation-tested both ways: no floor seats, every seat a floor seat), never one range wide enough for both. The round and curved ones (round cushion, floor pillow,
  rocker) switch detail levels at 3 / 6 m, the papasan's, so their edges stay round from a seat beside them; the square ones at 2.5 / 5 m.
- **Stand points:** the contract's `StandPoint` (0.3 m clear of one side) and its mirror on the other side (`StandPoint2`); each place gets up onto the one nearer it, so the
  left end of a sofa gets up on the left.
- **Every trigger is TURNED to its place's heading.** Seated, the laser's slab grows toward the sitter's knees, which is the trigger's -Z (`SeatTrigger.stand_zone`); the
  fixtures face -Z, these face +Z (a bed's edge +X), so an unturned slab grew BEHIND the sitter. `seat_tests contract/` checks each place's slab against its eyes.
- `seat_tests contract/` builds all nineteen (places, eye heights, facing, stand points beside the piece, a press on every place sitting there and getting up onto its stand
  point; mutation-tested: an unturned trigger, a place ignored, a stand point not the nearer one); `save/` that they spawn and save as themselves. How they look, sitting on
  the sofa, lying on the captain's bed and sitting on a floor cushion: `Tools/room/furniture_probe` (windowed). A headset (the feel, the laser reaching each cushion) and the Quest's cost OWED.

- **Press the cushion to sit, again to get up; HOLD on the seat to carry it** (`grab_hold_seconds` = `HoldToGrab.DEFAULT_SECONDS`). `SeatTrigger` is a pointable
  `Area3D` slab 3 cm proud of the cushion, so it wins the ray over the body's `PointerArea` (the same rule that makes the arcade's panel grip work); it tints when aimed at.
- **THE VR LASER HITS NO AREA3D (2026-10-27: no seat could be sat on in a headset).** `XRToolsFunctionPointer`'s RayCast leaves `collide_with_areas` off; only the desktop pointer turns it on. A
  `SeatTrigger` is an `Area3D`, so it took a desktop click and was invisible to the laser. It now makes `LaserBody`, a `StaticBody3D` of the same shape and pose on the same layer
  that forwards `pointer_event`, as the seat's SIBLING and not the trigger's child (a laser's pickup takes a collider's PARENT for the pickable, so a hold on the cushion still
  carries the seat). Anything else pointable that is an `Area3D` is in the same case (`ArcadePanelGrip` has the squeeze to make up for it). The tint is yellow
  (`WidgetOutline.SELECT_COLOR`). `seat_tests press/`; a real headset OWED.
- **SEATED, THE LASER FINDS NOTHING TO PRESS (2026-10-27, VR).** The cushion is under the sitter and a laser leaves the hand pointing forward: a probe with the real rig put a seated hand in 45 poses (beside the hips, in the lap,
  a little forward) with the laser forward and 40 degrees down, and it hit the trigger in 3 of them on the chair, 2 on the racing seat, 3 on the cushion, 0 on the bed (the racing seat's `PointerArea` boxes took most of the rest); aimed
  straight down at the lap it always hit. So while the host is occupied the laser's slab (`SeatTrigger.stand_zone`, the `LaserBody`'s own box; the desktop's Area3D keeps its size) reaches 0.6 m toward the knees and 0.2 m to each side,
  on the same 3 cm, and the seat's `PointerArea` carries `SeatPointerArea`: a press on any part of the body of the seat you sit on stands you up (and does nothing to anyone else; carrying is still a hold on it). Put on by `Seat._ready`,
  so a mod's seat has it. `seat_tests press/` (mutation-tested). A headset OWED.
- **A seated player's menu keeps clear of what is in front (2026-10-29).** `SpawnMenuController._menu_distance` stood the menu 0.9 m ahead of the head whatever was there, and a seated player cannot step back, so
  one sitting in front of a cabinet (what a seat is for) had the menu open INSIDE it. Seated, the ray out to it takes the pickables (a cabinet) and the pointable boxes as well as the world and the menu stops
  `MENU_WALL_GAP` short of the first, no nearer than `MENU_SEATED_MIN` 0.45 m (its own bodies and the player's seat left out); it logs `[Menu] seated: <what> stands N m ahead ...`. **Reported, "I can open the menu but cannot
  use it (typing to search, spawning a game)", and NOT reproduced**: with the real rig, a stand-in slab for the menu at its place and each of the six furniture seats, the desktop pointer reaches it every time and its
  suppress area (radius 0.2, layer 23) touches nothing; the pointer boxes of a cockpit leave the centre of the menu clear. So this is the one seated defect found, not proven to be the one reported; a press that the
  seat's own body takes (`SeatPointerArea`) now logs `[Seat] a press on ... stood the sitter up`. The real menu cannot be loaded without the native extensions: a headset and a desktop run OWED.
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
- **Height.** On the desktop the camera's own height IS the eye height, so the seat sets it and puts it back (also when the seat goes away mid-sit). **In a headset the head is brought to the seat's eye point, once, as
  the player sits** (`Seat.origin_at_eye_height`; `stand()` puts the origin back on the floor): the first version put the floor under the seat and left the head where it was, "somebody sitting on a real chair is already at
  that height", and a person sitting low (a low chair, the floor, a crouch) sat on the floor beside a stool whose top was at their eyes (2026-10-29). Someone who really sits at the seat's height moves a few centimetres;
  the log says how far (`[Seat] ...: head from .. m to the seat's eyes at .. m`). A bed (lying down) was never measured, and the headset is OWED.
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
  and 0.72 m above the cushion, the racing seat furniture's `eye_above`) and 0.96 m from the picture (`SEAT_Z`, the monitor's hood: `arcade.md`); the player gets up on the driver's side (`StandPoint` 0.62 m to the left, on
  the floor). **The cabinet's pointer boxes leave the cushion open**: a box over the whole seat stood between the laser and the trigger that lies
  3 cm proud of it (the base under the cushion and the back behind it are boxes; nothing above). `seat_tests cockpit/`; the view from the seat is
  `arcade_cabinet_probe --forms=daytona` (`formseat_`). A headset and the Quest are OWED, as for the furniture.
- **A seat on a moving base carries the player (2026-10-26).** A cockpit whose game's cabinet moved (After Burner II's, Out Run's: `ArcadeCabinetBuilder._build_cockpit` with `motion`) is built on a
  `MotionPivot` that `ArcadeControlModule` tilts about the platform's centre a few degrees with the stick or the wheel. The seat moves with it, and so does a seated player:
  `CockpitSeat._physics_process` calls `SeatSitting.follow()` before `pin()`, which moves the origin (and the body under it, and the pin) by the eye point's move since the last frame.
  **Position only**: the base turns, the view does not (a rotation of the player's view by a base is the thing that makes people ill in a headset: `AppPrefs.arcade_motion` is automatic = off in a headset,
  on at a desk, or the player's choice). `seat_tests follow/`. A headset and the Quest on a moving seat are OWED, as for every seat.
- **A bike's and a bicycle's saddle is a seat (2026-10-26).** `RiderSeat` (`ArcadeCabinetBuilder._build_rider_seat`, a `CockpitSeat` with no drawn seat of its own: the saddle is the machine's):
  the cushion to press on the saddle's top, `EyePoint` 0.68 m (bike) or 0.72 m (bicycle) above it and a little toward the bars, `StandPoint` on the floor beside the stand. Its `floor_y` is the floor the
  rider's feet are taken to be on (the bike's stand, the bicycle's pedals): a headset adds its person's height to it, so a person on a real chair has their eyes about where a rider's are. **It is NOT
  on the part that leans** (a bike at full lean would swing a head 30 cm; the rider's body does the leaning) and **no pointer box of the cabinet stands over the saddle**. `seat_tests rider/`.
- **A cockpit of TWO seats (2026-10-26, Lucky & Wild).** `DriverSeat` and `GunnerSeat`, each a `CockpitSeat` 0.40 m wide, 0.21 m to a side of the middle with their own eye point at the middle of the glass and their own
  `StandPoint` on the OUTSIDE (the driver gets up to the left, the gunner to the right: the other seat is never in the way). They share the one `Seat.current` rule, so sitting in one while in the other gets up first. No pointer
  box of the cabinet stands over either cushion (the same boxes under and behind the cushion, one pair a seat). `seat_tests pair/`.
- Tests: `seat_tests` (groups `pose sit press family cockpit follow rider pair save`; mutation-tested: yaw sign and the body switch). Pictures: `Tools/models/seats_probe` (windowed; eyes yellow, stand point green).
