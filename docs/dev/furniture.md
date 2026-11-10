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

## The nightstand (`Scenes/Objects/furniture/nightstand.tscn`, `Nightstand`)

RetroXR-models `generic/nightstand` (Blender 5.3, its own level loop on applkit geometry; real walnut/birch textures,
not the swatch atlas; 1.6 k / 0.9 k / 0.6 k triangles, five draws a level), copied into
`imported-assets/furniture/nightstand/`. Spawn token `nightstand` (Objects tab), save row `[Nightstand, "nightstand"]`:
pose only, the drawer rides `articulated`. `nightstand.gd` builds the collision from consts copied from the contract
(JSON is not exported): the case's six boxes and four leg cylinders on the body, the drawer's front, floor and four
walls on `DrawerBody`, which never collides with the case (an exception both ways). `vr_drawer_tests contract/` fails
if the consts and the contract part.

Tests: `vr_drawer_tests` (`rig contract latch grip coast soft push save carry`; every mechanism mutation-tested: the
mute, the grab offset, the stale re-arm, the physics follow, the inward push, keep-awake, the restore snap). Look:
`Tools/room/nightstand_probe` (windowed; `--out=`, `--frames`, use `--fixed-fps 72` to record). Headset feel, the Quest's
cost and a two-peer session OWED.
