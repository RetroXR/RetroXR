# Cables: the rope, its plugs, and what makes a lead lie still

`Xenu::VerletRope` (`verlet-rope/src/`) is a PBD chain between two anchors. The
anchors are usually the plug BODIES at the ends of a lead (`RigidBody3D`s the physics
server owns) or a plain `Node3D` bolted to a device. This doc is about how the two
halves meet, and about friction. Build notes are in `extensions.md`, the suites and
oracles in `testing.md`.

## A loose plug is Jolt's, and the cord pushes it with FORCES

The pinned end particle follows the plug's cord boss every tick (`PinAnchors`). The
plug is never moved by a transform write from the rope. Instead the solver measures
what it did against each pinned end (`AddPinReaction`: the last segment's stretch
correction, and the boot pulling the first few particles onto the plug's exit axis,
with its moment arm). `CouplePlug` turns that into a force at the boss plus a torque,
scaled by `linear_density` (kg/m) over dt², and hands both to the physics server. The
plug's own contacts, friction, damping and sleep decide where it ends up.

- **Why:** until 2026-09-22 `AlignAnchorPlug` rotated a loose plug onto the cord's
  tangent with `set_global_transform` every tick. On a floor the turn swung the body
  into the surface, the server pushed it out, the pinned cord end moved with it, and
  the next turn started over. The ends of a lead lying on the floor squirmed for
  seconds, and the lead never stayed asleep. Measured with `floor_ends_probe`:
  330–590 mm of plug travel after landing, before; 0 mm and asleep by tick ~150, after.
- **The switch is still `end_align_stiffness`.** The name was kept so the scenes that
  set it need no edit. Any value above zero couples a loose `RigidBody3D` plug (the
  cord leaves along its exit axis and pushes back). Zero leaves the plug alone. The
  value itself no longer scales anything.
- **The coupling cannot hold a plug's weight up.** A rope with a few grams per
  segment cannot carry a 50–100 g plug through a PBD reaction. The host's hard tether
  clamp (`RetroSystem._clamp_plug`, CompositeCable's branch clamps, the controllers'
  `_clamp_*`) still does that, exactly as before. `plug_hang_probe` runs the same
  clamp for that reason. Without it the plug simply falls to the floor.
- The velocity change the coupling can make in one step is capped (`MAX_COUPLE_DV`,
  `MAX_COUPLE_DW`). Normal handling never reaches the caps. They exist for a whipping
  cord.
- Sign check: `plug_hang_probe` hangs a plug turned 90° off its cord. Coupled, it
  settles about 2° from the cord with no spin. With `--no-couple` it stays at about
  129°. A sign error shows as the angle growing, or as spin.

## Plug colliders are FITTED boxes, never spheres

Every loose plug's physics collider is a box sized to the connector mesh (measured by
`Tools/rope/plug_shape_probe`). The RCA family used to rest on spheres of radius
28–35 mm, two to five times the 14 mm barrel. They rolled under any torque and held
the plug 27–30 mm off the floor with nothing visible under it. With the coupling
pushing a plug, a sphere rolls: new code on old spheres travelled 629 mm. The Multi
Out keeps its "sized to the shroud, not the tongue" rule, now as a box. The pointer
target stays a separate, deliberately larger shape. A fitted box reaches about 20 mm
less than the old sphere did, so a plug has to come that much closer before a port's
snap zone (60 mm, coax 35 mm) sees it. The link and power plugs have always worked
that way. Confirm the feel in the headset.

## Friction is Coulomb, on VELOCITY only

`static_friction` / `kinetic_friction` (0.7 / 0.5, PVC on wood or carpet). The load on
a contact is the push the contact solve applied this step (the XPBD multipliers,
summed over every plane and segment midpoint bearing on a particle). A resting point
is pushed back by one step of gravity, so "step < μ × load" is exactly
"force < μ × weight". After the solve, along the plane bearing hardest: a slow
tangential velocity is zeroed outright (static), a fast one loses μk × load per step,
never past zero (kinetic). With both coefficients at zero, the old viscous
`surface_friction` damping comes back.

**Do not move friction onto positions.** Three position-level versions were built and
measured, and each one broke something:

| version | what broke |
|---|---|
| stick applied once, after the solve | stuck points left stretch/bend unsatisfied, the solver hauled their neighbours every tick, and a composite lead's breakout loop crawled 110 mm on the floor |
| stick inside the iteration loop | held points against pulls the stretch constraint re-applied in small steps: a cord hauled round a post went to 2.07× rest (`rope_tests` failed), and a ledge wrap jittered 2.9 mm and never slept |
| stick in the loop with a per-step grip budget (XPBD \|λt\| ≤ μ λn) | the rigid stretch constraints spent the budget at rest, points slipped and re-stuck, and a lead on the floor never slept (208 mm of creep) |

Velocity friction cannot hold a point against a steady pull (a cord on a slope
creeps), but the creep is a crawl the sleep system parks within a second.

- **Stable range, measured on the floor probe:** static up to about 1.5× kinetic,
  kinetic non-zero. 0.4/0.3, 0.7/0.2, 0.7/0.5 and 1.0/0.8 all settle with no creep.
  0.7/0 and 1.2/0.3 stick-slip and keep crawling. No scene sets them yet.
- `rope_stress` "dragged through wall" now reads a 30.8× worst segment (was 6.9×):
  an anchor teleported 1.2 m through a slab leaves a segment straddling it, and
  friction holds the snag harder. Jitter there fell from 81 to 3.7 mm. It is one of
  the two impossible lays, and it was accepted deliberately.

## Host clamps need slack, and must kill the velocity they undo

`CompositeCable._clamp_move` (branch and one-cord pair clamps):

- **It removes the outward velocity**, as `RetroSystem._clamp_plug` always did. A plug
  hanging past its reach used to fall a tick's worth, get hauled back, and fall again,
  so neither it nor its cord ever slept.
- **`CLAMP_SLACK` (5 mm).** The solver leaves a taut branch a few millimetres long. A
  clamp at exactly the reach dragged a floor plug 2.4 mm back into its neighbour every
  tick, which kept it inside the rope's 0.5 mm wake threshold under a cord that never
  woke. The plug jostled for ever (193 mm of travel in `rope_tests`). The clamp holds
  a plug AT the slack's edge rather than hauling it back to the reach: a hanging plug
  dropped 5 mm and yanked up every tick bounced.
- Other owners' clamps (`rf_switch`, `antenna`, `power_strip`, the controllers) were
  left as they were. If one of those leads' ends squirm, look for the same pattern:
  a blocked `move_and_collide` repeated every tick under a sleeping rope.

## Probes (`RetroXR/Tools/rope/`)

- `floor_ends_probe`: a plain lead and a composite lead dropped on a floor, ticked by
  the ENGINE (real plug bodies). Prints per-plug travel after landing, peak per-tick
  motion, resting height and tilt, and each rope's first sleep and `creep` (mean
  particle travel). Switches: `--legacy` (sphere colliders back), `--no-couple`,
  `--no-friction`, `--mu-s=`/`--mu-k=`, `--straight`, `--ticks=`, and
  `--video=<dir>` (windowed only) with `--low` for a floor-level camera. The app's
  boot `LoadingOverlay` curtain is a 44 m panel standing in the world, so a windowed
  probe must `suspend()` it or it renders straight into the camera.
- `plug_hang_probe`: the coupling's sign and settle check (above).
- `rope_ledge` (older): gained `--no-couple`, `--legacy` and `--trace`. Its composite
  lead hangs off BOTH table edges with no host, three plugs dangling from each
  breakout and pressing into each other. That still wakes now and then (plug jitter
  2.0 mm, was 4.1). It is a bundle-on-a-hard-clamp problem, not the rope's.
- `plug_shape_probe`: lists any plug still resting on a sphere, with its mesh bounds.

Headset validation of all of this is OWED: nothing here has been felt in a hand.
