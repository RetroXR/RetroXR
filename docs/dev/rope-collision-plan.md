# Plan: the cord's own collision (replacing the query-and-remember layer)

Status: PROPOSED, 2026-11-17. Nothing here is built. `rope.md` describes what ships.

## Why

A cord does not collide with anything today. A few times a second each particle and
segment asks the physics engine one question at a time (29 call sites in
`VerletRopeSim.cpp`: `intersect_ray`, `get_rest_info`, `cast_motion`,
`intersect_point`), and what comes back is kept as an infinite plane fixed in the
room. Every fix since 2026-11-10 corrects that memory being wrong:

| the memory is wrong because | what was added to cope |
|---|---|
| a plane is infinite, a face is not | `PlaneSupported`, `SurfaceUnder`, the taut hold's face search |
| a plane is fixed in the room, a table is not | the sleeping poll, its two-poll confirmation, the far poll, the stride |
| a plane cannot say "corner" | `FindEdgeFor`, `PlaceEdgeContact`, `UpdateEdgeContacts`, `EdgeStillThere` |
| nothing keeps a segment's middle out of a solid | `KeepTautOutside`, its put-back, its holds (bit 8) |
| and when all of that loses | `RecoverWrongSideParticles`, `DepenetrateLay`, the walk-out (removed 2026-11-17) |

It is also the cost. On a Quest 3 (simpleperf, 109 cords, 2026-11-13) the solve is
about 5% of the main thread and the queries about 20%, each one a `Dictionary`
through godot-cpp.

## What the rooms are made of

Authored collision on the layers a cord sees (1-3), counted from the scenes:

| room | shapes |
|---|---|
| arcade | 13 boxes |
| bedroom | 16 boxes |
| passthrough | 1 box (the real room's surfaces are built at run time, `real_room_surface.gd`: concave) |
| Starlight Arcade (mod) | 12 spheres authored; its walls are not in the scene file |

Across every shipped scene: 476 boxes, 37 spheres, 24 cylinders, 3 capsules, and no
authored convex or concave shape. Made in code: 123 boxes, 8 spheres, 6 cylinders,
6 capsules, 5 convex hulls, 9 trimesh or convex-from-mesh calls (appliance key
pockets, the arcade cabinet model, the Atari 2600, two adapters, cover slots, the CD
and DVD players).

### Counted in a running room (stage 0, 2026-11-17)

`XENU_ROPE_CENSUS=1` (`debug.xenu.rope_census` on a Quest) makes every cord say
what `GatherShapes` finds near it. The Starlight Arcade as saved, 69 cords:

| | |
|---|---|
| shapes near a cord | median 9, most 48 (the cap; two cords reached it), 8 cords over 24 |
| boxes | near 141 of 145 reports, 948 in all |
| convex hulls | near 47 reports, 250 in all |
| cylinders | near 26 reports, 45 in all |
| trimeshes | near 3 cords only, but 22 to 44 shapes each, 16,720 to 47,696 triangles |
| spheres, capsules | none near any cord |

What that settles:

- **Boxes first, convex hulls with them.** A third of the reports have a hull.
- **Trimeshes cannot be skipped and cannot be tested naively.** The three cords
  are mains leads beside appliances whose key pockets are carved trimeshes
  (`ApplianceModel.fit_shapes`): tens of thousands of triangles within a cord's
  box. They need a grid or tree per shape, built once, and are their own stage.
- **The cap of 48 is too low** beside an appliance. Raised with the trimesh work.

## The design

One rule, enforced in one place: **no part of a cord's jacket is inside a solid.**

1. **Snapshot (main thread, once a tick per awake cord).** One
   `intersect_shape` with a box round the cord (its bounds plus a tick's travel)
   returns the bodies near it. For each, the shape's type, data and transform are
   read from `PhysicsServer3D` (`body_get_shape`, `shape_get_type`, `shape_get_data`,
   `body_get_shape_transform`, the body's transform). Shape DATA is cached by shape
   RID and read once; only transforms are read each tick. The snapshot is a flat
   array of primitives in world space, each with the body it belongs to.
2. **Narrow phase (worker thread, inside the solve).** Each segment is a capsule.
   Closed-form tests against box, sphere, capsule and cylinder; convex hulls as
   plane sets (built once per shape RID); trimeshes as triangles in a small grid
   (built once per shape RID). The result is a contact: body, point and normal IN
   THE BODY'S FRAME, depth.
3. **Contacts are solved where they are now**, last in each iteration, and friction
   is unchanged. What changes is where they come from and that they are re-derived
   every substep from the shapes, not remembered.
4. **A moved body carries its contacts.** The cord keeps the transforms of the
   bodies it rests on. A sleeping cord compares those transforms (no query); a
   changed one wakes it. A cord on a carried table rides it or falls off it, and is
   never left standing on where the table was.
5. **Tunnelling** is closed by the shapes being solid (a point inside a box knows
   which face it is nearest and, from where it was last tick, which face it came in
   by), with the substeps bounding how far anything travels between tests.

Because the snapshot is plain data, the whole narrow phase runs on the solve
workers. Today every query is on the main thread.

## What goes, what stays

Goes: `SweepParticleContacts`, `SolveSegmentCollision`, the cached planes and their
slots (`m_c_*`, `m_mid_contact*`), `PlaneValid`, `PlaneSupported`, `SurfaceUnder`,
the edge system (four functions), `KeepTautOutside` and its holds,
`RecoverWrongSideParticles`, `DepenetrateLay`, `EnvironmentChangedWhileSleeping` and
its poll cadence, far poll and stride. Roughly 1,500 of `VerletRopeSim.cpp`'s 4,195
lines.

Stays: integration and substeps, stretch and bend, the strain-relief stubs,
self-collision, friction (`ApplyContactFriction`), plug coupling, the solve
threading, the hand hold, rendering, and every test and probe.

## Risks

- **Two answers to "where is the surface".** Jolt rounds a box by its margin for
  its own bodies; this would not. A plug (Jolt's) and its cord (ours) could rest a
  few millimetres apart on the same edge. To be measured in stage 1, not assumed.
- **Trimeshes.** The passthrough room's real surfaces and some models. The riskiest
  code, and the one whose need the stage 0 count decides.
- **Scaled and compound shapes**, and cylinders (no simple closed form with a
  capsule; an approximation is likely).
- **A crowded cord.** Inside an arcade cabinet a cord may have dozens of shapes in
  its box. The snapshot is capped, and says so in the log when it is.
- **Everything moves.** `rope_bench`, all 22 `rope_stress` rows and every jitter
  median get re-measured. That is the point at which a regression can hide, so the
  old path stays selectable until the new one has matched or beaten it case by case.

## Stages

Each ends with something measured, and the old path stays the default until stage 4.

0. **Count and baseline.** DONE for the count (above). Still to record: today's
   numbers for every `rope_jitter_probe` case, the `taut/` and `through/` tests, and
   a Quest capture.
1. **Snapshot plus box, sphere, capsule, cylinder**, behind a `collision_mode`
   property (default: old). `rope_tests` run in both modes; a probe draws both
   cords in one scene. Target: the `taut/` cases pass with `KeepTautOutside` off.
2. **Convex hulls and trimeshes**, if stage 0 says they are needed where cords go.
3. **Sleep from body transforms.** The carried-table case as a test: the cord rides
   or falls, and never hangs.
4. **Switch the default, delete the old layer, re-baseline** the oracles and
   `testing.md`. Rebuild windows and android together.
5. **Measure on the Quest** against the stage 0 capture.

Sizes, as estimates and not measurements: stage 1 is the bulk (several days), 2
depends on stage 0 (a day to several), 3 and 4 about a day each, 5 an afternoon with
the headset.

## Stage 1 so far (2026-11-17)

Built, and OFF by default: `collision_mode` (0 old, 1 shapes) on a cord, or
`XENU_ROPE_SHAPES=1` (`debug.xenu.rope_shapes`) for every cord in the room.

- `RopeShapes.hpp`, `VerletRopeShapes.cpp`: the gather, a cache of shape data by
  RID (hull faces found once, by brute force, up to 96 points; over that a
  bounding box stands in), nearest-point tests for box, sphere, capsule,
  cylinder and convex hull, and `ContactsFromShapes`, which writes the SAME
  plane arrays the solver, the friction and the resting tests already read. So
  the solve is untouched; only where its planes come from changes.
- Planes are made for surfaces up to 2 cm past touching (a plane costs nothing
  until it is met, and a cord pulled hard travels more than its radius a slice).
- A point found inside a shape goes out by the face it CAME IN by
  (`rope_way_in`, walked from where it began the tick), not the nearest one.
- A segment through a box or hull goes out by the face that frees the whole
  piece inside with the least travel (`segment_through`).
- A segment may bear on one shape in two places (asked again toward each end).
- A sleeping cord keeps the shapes it bore on and compares their transforms
  (`RememberSupports`, `ShapesChangedWhileSleeping`): one gather, no rays.
- In this mode none of these run: the sweeps, the cached planes' upkeep, the
  edge system, `KeepTautOutside`, the wrong-side recovery, `DepenetrateLay`.

`rope_tests` with `XENU_ROPE_SHAPES=1`: **116 of 117** (117 of 117 in the
default mode). What got it from 109 to there, 2026-11-17:

- **The bounds were tighter than the reach.** A shape's bounds were grown by two
  radii and a contact reaches 1.3 radii plus 2 cm, so a point 13 mm over a
  panel's top was skipped before it was asked and had no plane at all
  (`ContactReach()` is the one figure now).
- **The surfaces have the last word of a tick.** A slice's planes are made where
  the cord was when the slice began, and a particle rounding a corner under a
  hard pull goes 14 mm in a slice: its segment ended the tick cut 10 mm into the
  block. One more `ContactsFromShapes` after the last slice, answered alone.
- **A lay is still freed by `DepenetrateLay`**, in both modes: once a lay, on the
  main thread, with rays. A lift written for this mode could not go round a
  table's edge and was removed.
- **`contact/a bridged cord does sag into the gap` runs with no friction.** With
  it the spare cord stays on a support (7 mm of sag) or slides in (461 mm) by
  which way the lay folded; sliding freely it is 487 mm in both modes, and the
  case asks what it meant to: that nothing but the supports holds the cord up.

Still failing: **`taut/` thin panel, yanked** (a 2 cm panel, the cord pulled to
twice its length at 44 mm a tick). The same panel at a hand's speed holds, but
on a narrow margin: a segment lying across a top narrower than itself has to be
held at BOTH top edges, and it gets its second contact from two fixed samples
toward its ends. Two more principled versions were tried and were worse (second
contacts only where they face the way the first does: the slow pull failed;
each of a box's twelve edges asked for itself: four `taut/` cases failed). What
is likely needed is contacts remade between solver iterations for a segment
that bears in two places, not once a slice.

Not done: trimeshes (stage 2; a cord beside an appliance sees them and tests
nothing), jitter medians in this mode, a look at it in a room, the Quest.

## Decisions

Answered 2026-11-17: cords must work on the passthrough room's real surfaces
(so trimeshes are needed before the switch); a few millimetres between where a
plug and its cord rest is acceptable; the Quest performance session is finished,
so nothing else is rewriting these functions.
