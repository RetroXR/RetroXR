# Furniture: VRDrawer and the nightstand

## VRDrawer (`Scripts/Objects/widgets/vr_drawer.gd`)

A drawer, or a flat pull-out tray, taken by its HANDLE and slid straight out to `travel` metres along `axis_local`
(+Z, out of the front), then pushed back in. **It extends VRSlider on purpose**: ScenePersistence saves every VRSlider's
`value` (`kind: "slider"`, `_serialize_articulated_controls`) and ObjectSync sends every VRSlider's `value_changed`,
so a drawer's open amount is saved and synced with no code of its own. `value` 0 = shut, 1 = fully out.

Rig (the nightstand is the worked example):
- The VRDrawer Area3D stays FIXED on the furniture, its origin at the handle with the drawer SHUT. Its child
  CollisionShape3D (a BoxShape3D) is the handle's grab box and rides out with the drawer.
- `target` is the drawer. A drawer that is to carry things is an `AnimatableBody3D` (`sync_to_physics` on) with a floor
  box and wall boxes; a tray is the same with the floor only. **A hand-written `.tscn` must list the export in the
  node header, `node_paths=PackedStringArray("target")`, or `target` is silently null** (the first build's drawer
  moved nothing).
- `handle_mesh` / `set_handle_mesh()`: the handle as drawn (outline, desktop crosshair). A model's part is not there yet
  when the VRDrawer readies (children ready first), so the owner hands it over after.

Interaction:
- TRIGGER or GRIP (`grip_engages`, default on) in the handle box latches; the drawer follows the hand RELATIVE to where
  it was taken (VRSlider's plain trigger mode tracks absolutely and would jump it). A hand holding nothing with its tip
  in the box has its `FunctionPickup` muted (VRHinge's arrangement), so the squeeze never lifts the furniture.
- **A trigger already down when the hand arrives is not a press**: after any gap in polling (the widget asleep) the
  re-arm is re-read from the buttons. VRSlider and VRHinge re-arm only while a hand is near, so a squeeze carried in
  from elsewhere took hold.
- Let go moving, it coasts (`release_momentum`, `friction`, `restitution` off the stops); the last `soft_close_zone`
  eases shut; a haptic tick at each stop while held.
- `push_face_size` / `push_face_offset`: a bare fingertip pressing the FRONT pushes it in. Only a tip that came from in
  front of the face AND is moving in pushes: a hand reaching into the open drawer never shuts it, and neither does a
  drawer sliding out onto a still fingertip.
- `_reach_point()` / `_keep_awake()` are VRSlider hooks it overrides: the handle box can be 25 cm from the origin, and
  a coasting drawer must not fall asleep (PokeWake) mid-slide.

**A body target moves on the PHYSICS tick, never from `_process`** (`_physics_process`, a critically damped follow,
`FOLLOW_TAU` 20 ms). Measured with a TV remote in the drawer (`Tools/room/nightstand_probe`, `--fixed-fps`):
- set from `_process`, the drawer stood still one 90 Hz tick and jumped the next, and the remote slipped (162 / 200 mm);
- a first-order follow still stepped the SPEED each render frame: 223 / 250 mm at 60 fps;
- second order: 249 / 250 mm at 60, 72 and 90 fps, back to within 0.2 mm.

Two traps of `sync_to_physics`: the node reads back its PREVIOUS physics pose until the tick has run (so the follow
keeps its own `_follow`, never `target.position`), and a synced body keeps its own pose when its PARENT moves (the
nightstand settling left the drawer 1.75 mm off), so the pose is written every tick. A restore or
`set_value_no_signal` SNAPS (contents laid back by the save must not have the drawer slide out under them).

**Draw a body target from a plain node (`visual`)**: physics interpolation is on, and a synced body's pose is
written back by the physics sync a tick late, so a drawer drawn from the body trailed its case by up to 13.7 mm while
the furniture was carried. The model's drawer hangs from `DrawerVisual`, which the VRDrawer moves with the same
smoothed position: 0.0 mm (`vr_drawer_tests haul/`).

## Carrying furniture with things in it

A picked-up pickable goes on the held layer (17) that nothing loose collides with. Three consequences, measured with
a mover at the grab driver's priority (`vr_drawer_tests haul/`) and in the windowed `nightstand_probe --carry`:
- **The shelf**: `HeldObjectPhysics` couples the RIDERS of a held body, but found them on its FIRST shape only (the
  top), so a box on the shelf hung in the air 1.1 m behind. A body may now name its support shapes,
  `rider_shapes()`; the nightstand answers its top and its shelf floor. Nothing else implements it, so no other
  pickable changed.
- **The drawer**: a shut drawer is no longer a closed box (the case is intangible), and two of three boxes left one
  hauled hard. While the nightstand is HELD the drawer body gets a `Lid` just under the case top, over the part of the
  drawer still inside the case (so a pulled-out drawer stays open at the front); what is in the drawer stays ordinary
  physics, sliding and knocking about, and cannot leave through the top. Off whenever it is not held.
- **The hold is POLLED** (`freeze` and the held layer), never `picked_up` / `dropped`: a RAY grab emits neither on the
  pickable (the addon restores the body itself; SurfaceStick's header). A first version froze the drawer's contents
  for the hold on those signals: it read as frozen in a headset, and a ray release left them frozen, solid obstacles
  in the drawer ("an invisible object in there"). `vr_drawer_tests real/` drives xr-tools' own `pick_up`/`let_go`
  with a real `XRToolsFunctionPickup`, and a ray-style hold with no signals at all.

**"The collision is off after I carried it"** (reported 2026-11-12 on PC, laser carry, any drawer; NOT reproduced: a
real ray grab with a quarter turn, a hand grab and the real buttons all leave every handle area, handle box and drawer
body where the drawer is drawn, 0.0 mm, headless and windowed at 144 fps; `vr_drawer_tests again/`). So the pieces
now say it themselves: half a second after being put down each logs `put down at ..., collision against the nodes:`
with every drawer's handle area, handle box and body (`VRDrawer.collision_report`: the body against its parent times
the drawn `_follow`, never against its own node, which reads the physics pose back and would be wrong WITH it; the
`node` figure trails by a tick while the piece is still falling, 17 mm at 1.5 m/s, and means nothing). A laser or
crosshair press on a handle logs whether it met the box, and a press in the box that is refused logs why.

## The nightstand (`Scenes/Objects/furniture/nightstand.tscn`, `Nightstand`)

RetroXR-models `generic/nightstand` (Blender 5.3, its own level loop on applkit geometry; real walnut/birch textures,
not the swatch atlas; 1.6 k / 0.9 k / 0.6 k triangles, five draws a level), copied into
`imported-assets/furniture/nightstand/`. Spawn token `nightstand` (Objects tab), save row `[Nightstand, "nightstand"]`:
pose only, the drawer rides `articulated`. `nightstand.gd` builds the collision from consts copied from the contract
(JSON is not exported): the case's six boxes and four leg cylinders on the body, the drawer's front, floor and four
walls on `DrawerBody`, which never collides with the case (an exception both ways). `vr_drawer_tests contract/` fails
if the consts and the contract part.

Tests: `vr_drawer_tests` (`rig contract latch grip coast soft push save carry haul`; every mechanism mutation-tested: the
mute, the grab offset, the stale re-arm, the physics follow, the inward push, keep-awake, the restore snap). Look:
`Tools/room/nightstand_probe` (windowed; `--out=`, `--frames`, `--carry`, use `--fixed-fps 72` to record). Headset feel, the Quest's
cost and a two-peer session OWED.

## Furniture built from its contract: `DrawerFurniture` (the Mission pair)

`Scripts/Objects/furniture/drawer_furniture.gd` builds a piece with any number of drawers from its model's contract,
read at RUN TIME (`DeckFace.contract`: a `.json` is a JSON resource and ships with the export, as `vcr_contract.json`
does on a Quest; the walnut nightstand's copied consts were over-cautious). From the contract: the case's collision
boxes (`collision.case`, named `Case<name>_<n>`), and per drawer a `DrawerBodyN` (front, floor, four walls, the lid),
a `DrawerVisualN` the model's `DrawerN` hangs from, and a `DrawerHandleN` VRDrawer at the middle of its pulls with one
handle box across them (a wide drawer's two pulls are one handle). The lid sits under `row_top_y` (the rail above)
and stops at `case_front_z`; the hold is polled as the nightstand's. `rider_shapes()` is the top (`CaseTop_`), never
the top rail. Saved as `type_id` through `_drawer_furniture_entry`, each drawer through its VRDrawer's path.

Shipped: `mission_nightstand` (2 drawers) and `mission_chest` (6), the owner's Mission bedroom pair modelled from
photos in RetroXR-models `generic/mission-bedroom` (sizes ESTIMATED until measured; its `params.py` holds every
number). `vr_drawer_tests mission/`.
