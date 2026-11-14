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
- `pull_face_size` / `pull_face_offset` / `pull_face_centre`: the INSIDE of the front (the drawer's inside front
  wall, from its floor to the front's top). A fingertip that is inside a part-open drawer and moves OUT against it
  pushes the drawer open, following it (2026-11-12: "I can push them in but can't push them out"). Only a tip that was
  inside behind that face starts it; a tip resting there, going back in, or outside moving away pulls nothing.
  `FurnitureDrawers` sets it from each drawer's contract `inner` and `front`; the walnut nightstand from
  `DRAWER_INNER` (`vr_drawer_tests pull/`).
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
  hauled hard. That was answered first by a held-only `Lid` over the drawer, and is now answered by CarryContents
  (below): what is in it is held in place while the piece is carried. The lids (the nightstand's and every
  FurnitureDrawers drawer's) were REMOVED on 2026-11-14; nothing latched can leave.
- **What is in it: `CarryContents`** (`Scripts/Objects/furniture/carry_contents.gd`, both furniture classes,
  `process_physics_priority` 100 so it runs after the grab driver and the laser's pickup). ONE rule (2026-11-14): **the
  whole unit carried, what is in it is HELD IN PLACE; a drawer slid with the unit standing is ordinary physics** (what
  is in it rides and jostles). Each place it carries things (each drawer's inside, the walnut shelf, over the top) is an
  `Area3D` bin (`add_bin`), so Jolt reports what is in it (no per-tick queries; an idle piece costs nothing). The tick
  the carry BEGINS (the hold polled, below), everything in a bin is latched: frozen kinematic, moved to the held layer
  with mask 0 (it passes through what the carried piece passes through and shoves nothing in the room), put where it
  lay in the piece every tick. Put down, each is let go with the piece's velocity at its place, its own freeze mode,
  layer and mask back. A thing let go into or over the piece mid-carry is NOT latched (latched on arrival, one let go
  over the top hung frozen in the air). One a hand or a laser takes out mid-carry is the hold's: its
  `restore_freeze` is set false, because xr-tools gives back the freeze it FOUND (the carry's) and it stayed frozen in
  the air after the hand let go (`again/` "taken out of a carried drawer", red without it). Only a body it froze is
  unfrozen. Why one rule: physics alone cannot carry things in a piece moved as fast as a hand moves it (a pickable
  settles a few mm into a floor with continuous collision on, and a floor lifting past ~1.3 m/s outruns it; a quarter
  swing's walls cut through a box in one tick), and what was built to let it try (a 1 m/s cap on the piece,
  `bffc0c48`; then continuous collision switched off in bins plus a latch above a speed set by each thing's thickness,
  `126c19ad`-`179b7f7d`) was four mechanisms patching each other. Test boxes have `continuous_cd` on as pickables do;
  a test of a hand taking something out uses a plain pickable (the TV remote's own toggle-hold re-grabs it after a
  drop). Test movers must be FREED, not queued, before a let-go. The drawers' held-only lids are GONE (2026-11-14):
  `haul/`, `real/`, `mission/`, `beds/` check what is in a drawer is latched while carried (`carry().is_latched`)
  and let go when put down, instead of a lid. A resting drawer's VRDrawer switches its
  physics tick off (`_update_knob` wakes it).
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
boxes (`collision.case`, named `Case<name>_<n>`), and per drawer a `DrawerBodyN` (front, floor, four walls),
a `DrawerVisualN` the model's `DrawerN` hangs from, and a `DrawerHandleN` VRDrawer at the middle of its pulls with one
handle box across them (a wide drawer's two pulls are one handle). The hold is polled as the nightstand's, and what
is in it is carried by `CarryContents`: a bin per drawer on its body, and a bin per contract `surfaces` row on the
piece (`DrawerFurniture.surface_bins`: the surface's footprint from its top up to the surface over it, or 0.4 m); a
contract with no `surfaces` (the Mission pair's) gets one over its top. `rider_shapes()` is the top (`CaseTop_`), never
the top rail. Saved as `type_id` through `_drawer_furniture_entry`, each drawer through its VRDrawer's path.

Shipped: `mission_nightstand` (2 drawers) and `mission_chest` (6), the owner's Mission bedroom pair modelled from
photos in RetroXR-models `generic/mission-bedroom` (sizes ESTIMATED until measured; its `params.py` holds every
number). `vr_drawer_tests mission/`.

**The drawers are built by `FurnitureDrawers`** (`Scripts/Objects/furniture/furniture_drawers.gd`, 2026-11-12), which
`DrawerFurniture` and a bed (`ContractSeat`, seats.md) share: the same nodes, names and rules. A contract drawer row
may name its `axis` (the way it comes out, default +Z): everything it is built from is turned into the drawer's own
frame (its Z the axis), built there as a +Z drawer always was, and turned back, and the `DrawerHandleN` is turned so
its own Z is the axis (VRDrawer slides along its local Z, and its front push needs that). A +Z drawer is built exactly
as before (`vr_drawer_tests mission/` unchanged). **The beds' drawers come out of the bed's SIDE (+X)**: three in the
captain's bed, two in the waterbed's pedestal, saved as sliders, what is in them held by CarryContents while the bed
is carried (a `DrawerPoll` child polls the hold: a Seat's own physics process runs only while sat on). They sit under the bedding with room to spare
(drawer tops 361 mm under the captain's bedding at 420, 258 under the waterbed's at 330). `vr_drawer_tests beds/` (mutation-tested: a drawer built along +Z goes red).

## The living-room set: sliding doors and hinged doors (2026-11-14)

Fifteen pieces from RetroXR-models `generic/living-room` (`imported-assets/furniture/living-room/`), every one a
`DrawerFurniture` scene: six TV stands (`tv_stand_mission`, `_wall_unit`, `_credenza`, `_bench`, `_corner`, `_cubby`),
five bookcases (`bookshelf_oak`, `_mission`, `_midcentury`, `_cube`, `_pine`) and four coffee tables
(`coffee_table_mission`, `_midcentury`, `_glass`, `_pine`). Their contracts add two moving parts to drawers:

- **Sliding doors** are `drawers` rows with `kind: "sliding_door"`, `axis` ±X, `track` (a depth range) and `opening`.
  `FurnitureDrawers._build_sliding_door` makes each the same VRDrawer as a drawer, sliding along its axis, but its body
  is the door's slab alone (no box or floor, and no carry bin: what is behind a door is its surface's bin), its handle
  a box at the
  finger pull, and no face push or pull (`push_face_size`/`pull_face_size` zero). Two doors that overlap run on two
  tracks at different depths, so they pass one in front of the other as real ones do: the mid-century bookcase's two
  doors each cover half the cabinet, so slid together they only swap halves; the credenza's cover two bays and open
  together. Saved as sliders (`DrawerHandleSlideDoorN`).
- **Hinged doors** are `doors` rows (`side`, `hinge`, `open_deg`, `box`, `pulls`, `glass`, `inset`).
  `DrawerFurniture._build_doors` makes each a `VRDoor` named by the row's node (`DoorN`), at the door box's bottom
  middle, `hinge_side` from `side` (left = -X), swinging toward the front (+Z), with `opener = NONE` and
  `latching = false`: a push door whose leaf is the model's own `DoorN` part (every level, hung on a `Leaf` holder in
  the tree first so `attach_part` keeps it where it stands shut, then put under the door before the door is added, so
  its `_ready` builds the rig once). A hand takes the leaf with the trigger (or the grip at its edge) and swings it, a
  fingertip pushes it, a laser drags it and a desktop press + wheel turns it (VRHinge). Its `LeafBody` is put on the
  piece's own layer with a collision exception both ways, or the piece fought its own doors. Inside a spawned object a
  VRDoor is not a room door (`is_room_door`), so its `DoorHinge` is saved and synced as one of the piece's articulated
  controls (`hinge`, angle + latched). The hinge line VRDoor uses is the leaf's front edge; the contract's overlay
  doors hinge at the back edge, 19 mm in: not visible, and nothing hits the case either way. A VRDoor runs a small
  `_process` (watching its angle for the log and netplay), a few comparisons a door a frame.
- **The wall unit's tower doors are clear glass** (`LIV_ClearGlass`, alpha 0.12), the set's only transparency; the
  import keeps it blended (`living_room_probe` logs the surfaces).

Tops, shelves, cubbies and bays are case collision boxes in the contract, so things stand on them, and each is a
CarryContents bin (`surface_bins`): what stands on it, or in the compartment behind a door, is held in place while
the piece is carried. A coffee table's drawer sits between its shelf and its top, so its shelf's bin covers it as
well as the drawer's own. The corner stand's diagonal back is stepped
boxes; the bookcases carry `wall_back` and `footprint` (no tipping physics). `vr_drawer_tests living/`: every piece
builds what its contract lists and spawns/saves as itself; every drawer and slider opens its travel along its axis and
goes home; overlapping sliders never share a track, shut or open; every hinged door swings OUT on its own side to
`open_deg` (its free edge travelling round, its hinge edge staying) and shuts; a hand slides the credenza's door and
swings the pine bookcase's; a door angle and a slider save and restore; a box set on a top and on a shelf rests there;
and on EVERY piece, a box on every surface and in every drawer is held in place while the piece is carried and moved
(within 5 mm of its place in it) and let go to ordinary physics, moving as the piece did, when it is put down
(`living/carry`). Mutation-tested (a slider built along +Z, a left door hinged on the right, doors swung inward, no
surface bins, no drawer bins each go red).
`Tools/room/living_room_probe` (windowed): all fifteen shut and open, the wall unit's glass with a box behind it, a set
and a VCR on the Mission stand. Headset feel, Quest cost and a two-peer session OWED.
