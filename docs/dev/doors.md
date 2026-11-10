# Doors — `VRDoor`

A door that opens: a leaf on a vertical hinge, held shut by its latch until its knob is
turned. First used on the 90s bedroom's closet (`BedroomScene.tscn`
`Furniture/ClosetDoor`, 2026-11-11), built to be dropped into any room or mod.

| file | what |
|---|---|
| `Scripts/Objects/room/vr_door.gd` | `VRDoor`: one node builds the whole rig, decides the latch, saves/syncs |
| `Scripts/Objects/widgets/door_hinge.gd` | `DoorHinge extends VRSpringLatchedHinge`: the leaf, latched, no spring |
| `Scripts/Objects/widgets/door_knob.gd` | `DoorKnob extends VRKnob`: turns either way, follows the wrist, springs back |
| `Scripts/Objects/room/door_model_split.gd` | `DoorModelSplit`: takes leaf and knob out of a one-mesh door model |
| `Tests/door_tests.gd` | the suite (65 cases) |

## Using one

Put a `Node3D` with `vr_door.gd` at the **bottom middle of the doorway**: +Y up, X across
the opening, Z through it. Set `hinge_side` (±X) and `swing` (the face it opens toward).
That is all; `_ready` builds the rig. The leaf comes from, in order:

1. **A one-mesh model under the node** (`door.glb` is one mesh of five surfaces): name
   the leaf and knob surfaces in `leaf_surfaces` / `knob_surfaces` (surface or material
   name). The leaf's own bounds then size everything and the knob sits where the model
   has it; `width`/`height`/`thickness` are ignored. A name the mesh lacks is logged with
   the names it has.
2. **Authored children `Leaf` and `Knob`** (any Node3D, placed shut), sized by the exports.
3. **Nothing**: a plain box leaf and a brass ball knob from the exports.

The bedroom closet: `leaf_surfaces = ["Trim_Door"]`,
`knob_surfaces = ["Knob_Metal", "Knob_Metal_2"]`, hinge +X, swings +Z (into the room),
`open_deg` 105 (the leaf meets the west wall at about 128°).

## How a hand works it

- **Shut, the leaf cannot be taken**: `_can_engage` is false and the grab box is off.
  Only the knob lets it go.
- **The trigger at the knob takes the knob, never the leaf**: `DoorHinge` refuses any
  fingertip in the knob's reach (`DoorKnob.in_reach`). The knob's reach is a capsule
  along its axle on both faces, so one spindle serves both sides, as on a real door.
- **The knob follows the wrist** (`follow_roll`), either way, ±60°. Past `unlatch_turn`
  (0.6 of that) the latch lets go and **the same hand is handed on to the leaf**
  (`DoorHinge.grab_with`, which skips VRHinge's re-arm guard). One pull turns and swings.
  The knob springs back when let go and keeps itself awake until it is home, because
  PokeWake would otherwise freeze it half-turned.
- **Unlatched, the leaf stays where it is left** (no spring). It can be taken anywhere:
  with the trigger, with the grip at its edge, or pushed with a fingertip on either
  face (torque faces, with release momentum).
- **The bolt drops back in by itself:**
  - Let go within `close_latch_deg` (3°), it latches (the parent's `_on_released`).
  - Swung home on its own momentum, it latches once armed (opened past 3° since it was
    unlatched).
  - Knob let go with the door still at the strike, it latches (VRDoor).
- **A leaf swung into a fingertip stops on it.** A finger in the way is a poke, as a
  real door stops on a hand.
- **Desktop or a laser:** a press on the knob is `toggle()`. A shut door opens to
  `desktop_open_deg` (80°) on a tween; an open one swings shut and latches.

**The hinge axis cannot be a rolled pivot.** VRHinge writes `target.rotation.x`, which is
the middle term of a Y-X-Z Euler, so its axis is the parent's yawed X: always
horizontal. VRDoor therefore builds a `HingeFrame` whose basis maps X to the vertical,
`X = Y × Z` with `Y` = swing normal and `-Z` = hinge→latch. The `HingePivot` under it
turns at an otherwise identity rotation. `door_tests geometry/` checks every
side × swing pair on a door yawed 30°, by where the knob ends up.

## Saved and synced

- **A room's door** (no `"spawned"` ancestor; `is_room_door()`):
  - **Slot:** `ScenePersistence` writes `"doors": [{path, deg, latched}]` beside
    `"switches"`. It is omitted for a room with none, so old slots keep their bytes,
    and it is restored with them.
  - **Netplay:** `NetEvents.EV_DOOR {door, deg, latched}` (appended), sent at most
    every 125 ms while it swings, once when it stops, and on every latch change. A
    receiver eases toward the angle at 360°/s. A late joiner gets a `"door"` record in
    `_capture_room_state`.
  - A hand on the door wins over a remote update. A remote update is never echoed
    back: the reported state is synced as it is applied.
- **A door inside a spawned object or mod prop** reports none of that. Its `DoorHinge`
  (a `VRSpringLatchedHinge`, latch included) and `DoorKnob` are articulated controls
  that the object's own entry already saves and syncs. `DoorHinge.drive_to` emits
  `rotation_changed` for that reason.

## The model split

`DoorModelSplit` copies the named surfaces into new ArrayMeshes and rebuilds the frame's
mesh without them. The GLB is never edited.

- **The knob surfaces are split again by triangle.** Triangles wholly outside the leaf's
  two faces turn with the knob; the rest (the latch bolt in the edge, the spindle
  through the bore) stay on the leaf. door.glb's `Knob_*` materials are the whole
  lockset.
- **A copied surface must carry its custom-channel format bits** (`surface_get_format`
  into `add_surface_from_arrays`'s flags), or the surface is refused with
  `p_arrays[ai].get_type() != PACKED_BYTE_ARRAY`.
- door.glb result: 3 leaf, 2 knob and 2 frame surfaces (`split/`).

## The bedroom closet

`SouthWallCol` used to be one solid slab across the opening. It is now three pieces,
W, E and Head, matching the wall meshes. The closet now collides: back, sides, top,
base, the **shelf** (things can be set on it) and a **threshold** strip. The strip
fills the 7.5 cm gap between the room floor (ends at z 2.2) and the closet base (starts
at 2.275), which the shut door used to hide and the open one showed as a black seam.

## Checks

- `door_tests` (headless): geometry, latch, turning and pulling with one hand, a short
  turn (the control leg), release, swinging home, the pointer toggle, the split, save and
  netplay.
- Mutations that go red (checked 2026-11-11):
  - the latch gate off;
  - every door counted as a room door;
  - no hand-off from the knob;
  - no knob spring.
- How it looks: `bedroom_probe -- --mode=stills --stills=closet --empty-room --door=95`,
  or `--door-sweep=48` for the frames of an mp4 (`bedroom-probe.md`).
- **OWED:** headset feel (the turn-and-pull above all; the 60° turn and 0.6 threshold
  are guesses), the Quest, a real two-peer session, a door in a mod room, and the
  baked shell lighting on the open leaf.
