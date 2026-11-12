# Furniture: VRDrawer and the nightstand

## VRDrawer (`Scripts/Objects/widgets/vr_drawer.gd`)

A drawer, or a flat pull-out tray, taken by its HANDLE and slid straight out to `travel` metres along `axis_local`
(+Z, out of the front), then pushed back in. **It extends VRSlider on purpose**: ScenePersistence saves every VRSlider's
`value` (`kind: "slider"`, `_serialize_articulated_controls`) and ObjectSync sends every VRSlider's `value_changed`,
so a drawer's open amount is saved and synced with no code of its own. `value` 0 = shut, 1 = fully out.

Rig (the nightstand is the worked example):
- The VRDrawer Area3D stays FIXED on the furniture, its origin at the handle with the drawer SHUT. Its child
  CollisionShape3D (a BoxShape3D) is the handle's grab box and rides out with the drawer.
- `target` is the drawer. A drawer that is to carry things is an `AnimatableBody3D` (`sync_to_physics` OFF, see below) with a floor
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

**`sync_to_physics` is OFF (2026-11-12) and must stay off.** Everything below about "a synced body" is why: a synced
body keeps its own WORLD pose when its parent moves and hands its node the previous tick's pose. That is what turned
a dropped piece's drawer collision out of its drawers, made the collision trail the drawing and needed the follow's own
bookkeeping. Off, the body is a plain child of the furniture; the drawer suite passed 102/102 with it (the three
`haul/` box checks that sat at 30-33 mm against a 30 mm limit too), contents still ride (197 / 200 mm, Mission
245 / 252 and 268 / 277), and even the old position-only write passes the angled drop. The `visual` node, the
follow's own `_follow` and the full-transform write are kept for now but are no longer load-bearing.

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
  hauled hard. While the nightstand is HELD the drawer body gets a `Lid` just under the case top over the WHOLE drawer
  (sized once at build and only switched on and off); what is in the drawer stays ordinary physics, sliding and
  knocking about, and cannot leave through the top. Off whenever it is not held. (It used to cover only the part
  still inside the case, refitted every tick; a pulled-out drawer was then open at the front while carried.)
- **What is in it: `CarryContents`** (`Scripts/Objects/furniture/carry_contents.gd`, both furniture classes,
  `process_physics_priority` 100 so it runs after the grab driver and the laser's pickup). Each place it carries
  things (each drawer's inside, the walnut shelf, over the top) is an `Area3D` "bin" (`add_bin`), so Jolt reports what
  arrives and leaves; an idle piece runs no queries. Two mechanisms, both measured (`again/`):
  - **Continuous collision OFF while a thing lies in a bin** (from the tick it arrives, before it settles; given back
    the tick it leaves, including when a hand picks it up, which moves it to the held layer out of the bin's mask).
    Every pickable has it on (HeldObjectPhysics, against throws through the floor), and a body that SETTLES with it
    on rests 3-5 mm into the floor and is outrun by a floor lifting past ~1.3 m/s (a TV remote dropped through).
    Switching it off once settled does not help; lowering Jolt's `penetration_slop` (2 cm by default) to 2 mm does not
    either; cancelling damping, a deeper floor and waking it did not.
  - **Latched while the piece moves faster than physics carries it**: frozen kinematic, put where it lay in the piece
    every tick, let go with the piece's velocity at its place once every bin has been under 0.3 m/s for 0.2 s or the
    piece is put down. Each thing at its own speed: its bin moving its THINNEST extent in a tick (a 7.5 mm Game Boy
    cartridge ~0.68 m/s: it fell through a 2.5 m/s lift a 30 mm box rode), between 0.4 and 3 m/s.
  Only a body it froze is unfrozen, only one whose continuous collision it took gets it back. `CC_NOCCD=1` /
  `CC_LATCH=<m/s>` switch the two for testing. Holding the PIECE to 1 m/s instead (HeavyHold, `bffc0c48`) made
  furniture that cannot keep up with a walk: removed. Test boxes have `continuous_cd` on as pickables do; without it
  they rode where a real thing fell. Test movers must be FREED, not queued, before a let-go.
  Cost (20 Mission chests idle, desktop, noisy): the per-tick queries and drawer writes this replaced cost several
  times more (+5.0 against +1.4 ms a tick); removing the bins changes nothing measurable; the rest is Jolt's own
  bodies. A resting drawer's VRDrawer switches its physics tick off (`_update_knob` wakes it).
- **The hold is POLLED** (`freeze` and the held layer), never `picked_up` / `dropped`: a RAY grab emits neither on the
  pickable (the addon restores the body itself; SurfaceStick's header). A first version froze the drawer's contents
  for the hold on those signals: it read as frozen in a headset, and a ray release left them frozen, solid obstacles
  in the drawer ("an invisible object in there"). `vr_drawer_tests real/` drives xr-tools' own `pick_up`/`let_go`
  with a real `XRToolsFunctionPickup`, and a ray-style hold with no signals at all.

**"The collision is off after I carried it" (2026-11-12): the drawer body kept its old ROTATION.** The follow wrote
back `target.position` only. A synced body keeps its own WORLD pose when its parent moves, so when the furniture TURNED
under physics (the owner's repro: let go at an angle, it hits the floor tipped and settles) the drawer body stayed
turned in the case for good: the drawn drawer was right and its collision swung out of it (517 mm at the handle, 58
deg, on the walnut nightstand; 1.1 m on the chest). Now the WHOLE local transform is written every tick
(`Transform3D(_target_rest_basis, _follow)`); `vr_drawer_tests again/` drops both pieces tipped 35 deg. Measure such a
thing AT THE HANDLE: the body's origin is the furniture's floor centre, so a body turned about it reads 0 mm there.
A carry that only translates or yaws by setting the node (every first probe) never showed it.

Two things about LOOKING at it, both in the collision view (OPTIONS > Collision Debug, `CollisionDebug`, coloured by
layer, depth test off), not Godot's "Visible Collision Shapes":
- it drew a shape once and kept it: a drawer's LID (on only while carried, resized every tick) stayed drawn after it
  was switched off, as a box in the drawer. Switched-off shapes are hidden now, and a resized or re-layered shape is
  redrawn on the next scan.
- it rode each body's node, and a synced body's node reads the previous tick: a drawer's boxes trailed a pull by twice
  what the collision does (7 against 3-5 mm at 0.6 m/s). Synced bodies are drawn from the physics engine's pose now.
  The collision itself trails the drawn drawer by under a physics tick (the drawing is interpolated); `again/` checks it.

Each piece logs, half a second after it is put down, `collision against the nodes:` with every drawer's handle area,
handle box and body offset at the handle (`VRDrawer.collision_report`), and a handle logs laser/crosshair presses and
refused presses.

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
over the whole drawer; the hold is polled as the nightstand's, and what is in it is carried by `CarryContents`. `rider_shapes()` is the top (`CaseTop_`), never
the top rail. Saved as `type_id` through `_drawer_furniture_entry`, each drawer through its VRDrawer's path.

Shipped: `mission_nightstand` (2 drawers) and `mission_chest` (6), the owner's Mission bedroom pair modelled from
photos in RetroXR-models `generic/mission-bedroom` (sizes ESTIMATED until measured; its `params.py` holds every
number). `vr_drawer_tests mission/`.
