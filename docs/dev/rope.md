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
  segment cannot carry a 50–100 g plug through a PBD reaction. The owner's hard tether
  (`PlugTether`, below) does that. `plug_hang_probe` runs the same tether for that
  reason. Without it the plug simply falls to the floor.
- The velocity change the coupling can make in one step is capped (`MAX_COUPLE_DV`,
  `MAX_COUPLE_DW`). Normal handling never reaches the caps. They exist for a whipping
  cord.
- Sign check: `plug_hang_probe` hangs a plug turned 90° off its cord. Coupled, it
  settles about 2° from the cord and stays there. With `--no-couple` it stays at about
  130°. A sign error shows as the angle growing.
- **Known:** in that probe the coupled plug hangs against the table's side face with
  the cord's pull pressing it there. Its pose is still to under 1 mm, but Jolt keeps
  a 0.03 rad/s velocity into the contact, the plug never sleeps, and so neither does
  the rope (measured for 30 s; `--dbg` prints it). It is invisible and costs one
  awake rope. Dropping the torque's component along the cord did not change it (it
  is a pitch into the face, not a roll). The uncoupled control sleeps.

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

## A cord crossing itself: the strand underneath owns the floor

`SolveSelfCollision` runs after the solve. Where a loop crosses over itself on a floor,
three rules keep the crossing still (2026-09-22):

- **A particle resting on a surface is never pushed into it** (`PushesIntoRest`: a
  push with more than a glancing share into the plane it touches). The strand on top
  takes the whole separation. Split evenly, the lower strand was driven into the
  floor, the floor threw it back out on the next tick, and a loop unbending across
  itself popped a strand a full cord's thickness over or under the other in one tick.
  `rope_crossing_probe` at 70% loop size measured the loop never sleeping, 209 mm of
  creep, 11 mm single-tick jumps, and the strands swapping places. After the fix it
  sleeps at tick about 70, with no creep.
- **A contact is INELASTIC.** Parting two strands creates no velocity (the history
  moves with the push), and any velocity they had toward each other stops.
  Both halves matter. The particle pass used to leave the push as velocity, which
  bounced a heap (2.1 mm/tick held awake with the history left alone). Moving the
  history alone kept the approach, so strands pressed together were pushed again
  every tick, and a composite lead's breakout knot crept 22 mm across the floor
  (`floor_ends_probe`). The segment pass moves the history but does not yet stop
  the approach.
- **Only what the pass pushed into a surface is lifted back out**, with the history
  (`m_self_moved`). Re-projecting EVERY resting particle instead also lifted ones that
  were low for other reasons: a heap churned at 0.63 mm/tick held awake. Lifting
  without moving the history pumped the loops, which then never slept. Both were
  measured and backed out.

The heap case measures 0.035 mm/tick held awake (0.35 before). Strand on strand has NO
friction, only strand on surface: a pile forced awake from the moment it lands (`--heap
--awake`) slumps slowly, and a strand now and then slides off another (a 4 mm drop).
Left to itself the same pile sleeps by tick ~270 without creeping. A loop tighter than about
10 cm across (40% in the probe) still springs open against friction: at the shipped
bend stiffness a cord is stiffer than its grip on the floor. Holding it would need
bend memory (a rest shape that yields to where the cord has lain), which is not built.
Two separate cables do not collide with each other at all. A rope has no
CollisionObject, only queries, so crossing leads pass through each other.

## A loose plug is reeled in by ONE helper: `PlugTether.reel_in`

Every owner of a lead keeps its loose plug within the cord's reach with a hard tether
(the rope cannot carry a plug's weight). That used to be written sixteen times, twelve
near-identical copies in the consoles, controllers and peripherals and four variants
(RfSwitch, Antenna, PowerStrip, CompositeCable), and the copies disagreed. Since
2026-09-22 they all call `Scripts/Objects/cables/plug_tether.gd`, which:

- **moves the plug SWEPT** (`move_and_collide` plus a slide), never by writing
  `global_position`. A write bypasses collision and could carry a plug through a
  partition.
- **kills the outward velocity it undoes.** RfSwitch, Antenna and PowerStrip did not.
  A plug hanging past its reach fell a tick's worth, was hauled back, and fell again
  for ever, so neither it nor its cord slept.
- **leaves `SLACK` (5 mm) and holds the plug AT the slack's edge.** The solver leaves
  a taut cord a few millimetres long. A clamp at exactly the reach dragged a floor
  plug 2.4 mm back into its neighbour every tick, inside the rope's 0.5 mm wake
  threshold, under a cord that never woke: the plug jostled for ever (193 mm of travel
  in `rope_tests`). Hauling a hanging plug all the way back to the reach instead
  bounced it 5 mm a tick.

Callers still decide which end is loose (a held plug is somebody else's) and which point
the reach is measured from: the cord boss for the leads, the plug origin for the
controllers, as each always did. A body that must be HAULED on its cord (a switch box, a
speaker cabinet) is `CableHaul`'s job, not this. A new owner of a lead calls
`PlugTether`; it never writes its own clamp.

## A taut cord stretches: the solver's known limit

Eight Gauss-Seidel iterations cannot make a long cord inextensible under tension. A lead
held up by one plug with the other on the floor sits a few percent long along its whole
length, and most of that (1.23–1.25×) lands in the first segment past the held plug's
boot (`handling/a yanked lead recovers its length`, bound 1.30). The standard fix is
long-range attachments: every particle constrained to lie within its path length of each
pinned end, which is O(n) per iteration. It is not built.

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
- `rope_crossing_probe`: a cord laid in a loop crossing itself on a floor (`--scale=`
  for tighter loops, `--heap` to drop 2 m in a pile, `--awake` to measure jitter
  rather than sleep, `--video=`). Reports the strands' heights at the crossing, the
  peak single-tick jump of any stacked particle, creep, and sleep/wake flips.
- `rope_ledge` (older): gained `--no-couple`, `--legacy` and `--trace`. Its composite
  lead hangs off BOTH table edges with no host, three plugs dangling from each
  breakout and pressing into each other. That still wakes now and then (plug jitter
  2.0 mm, was 4.1). It is a bundle-on-a-hard-clamp problem, not the rope's.
- `plug_shape_probe`: lists any plug still resting on a sphere, with its mesh bounds.

Headset validation of all of this is OWED: nothing here has been felt in a hand.
