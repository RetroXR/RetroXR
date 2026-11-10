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

## Substeps: a tick is four short steps (2026-11-10)

`substeps` (C++ default 4, no scene sets it). A tick integrates and solves four times
over a quarter of the tick each, with a quarter of `constraint_iterations` a slice (2 of
8), so the constraint work is what it was. The environment is still queried ONCE a tick,
after the last slice, and the self contacts are found once, after the first integration.

- **Why:** what was left after every contact fix was the same thing in different
  places, a two-tick limit cycle: a strand rocking on another, a pile that never agreed
  with itself, a corner's friction sticking on one tick and not the next. One long step
  and eight Gauss-Seidel passes overshoot and come back; short steps do not. Measured
  with `rope_jitter_probe` over five starts each (chattering ticks of 718, worst
  reversal): a hand-wound coil 717 / 24 mm before, 695 / 16 mm with the contact fixes
  alone, 167 / 1.8 mm with substeps; a heap 107 / 11 mm, 8 / 1.3 mm, 2 / 1.0 mm.
- **A stiffness rated as "share of the error per iteration" is rescaled per slice**
  (`SliceStiffness`: bend, end stiffness, the stub). The same share over a step 1/n as
  long is a constraint n² times as stiff: unscaled, a cord rated 0.2 stood up like wire
  (`rope_tests` "the cord lies down", 325 mm tall). Scaled by `full / (now × n²)` a
  hanging loop has the shape it had at one step (0.6 m between sockets 0.1 m apart:
  259 mm deep against 260 rated 0.2, 255 against 256 rated 0.3). `stretch_stiffness`
  1 stays rigid. A rating of 0.1 does not match as well (247 against 284).
- **Pinned ends are carried through the tick**, a quarter of the way per slice
  (`m_pin_from`, `m_pin_fraction`), not thrown to the anchor in the first slice.
- **The sweeps cover the whole tick** (`m_tick_from`): a particle's ray and a segment's
  capsule are cast from where they were when the tick began, not from the last slice.
- **A plug's force is the MEAN over the slices** (`CouplePlug`): the pin reactions are
  summed over the tick and divided by the slice's dt² times the slice count. Taken from
  one slice alone it sent a composite lead's plugs 42 m.
- **`wave_damping` (0.3)**: each slice a particle's velocity is drawn that share toward
  the mean of its two neighbours', a pinned neighbour counting as its ANCHOR's velocity.
  One step of eight iterations damped a cord's fast transverse waves by accident;
  slices of two do not, and a hanging span buzzed after every move of its end. It also
  takes a swing out through the cord's fixed ends. Free fall is untouched.
- `damping` is still per TICK (a slice keeps the root of what a tick keeps).
- **Cost** (desktop debug, `rope_bench`): 207 -> about 220-250 us per awake rope-tick,
  16 settling cables asleep at tick 64 (was 49) at 43 us (was 42). A Quest is OWED.
- **Where a step goes: `XENU_ROPE_PROFILE=1`** prints, every 2000 steps, the time per
  phase over every cord in the process and the queries made. Measured on `rope_bench`
  (16 awake cables on table slabs): the physics QUERIES are over half (about 57 shape
  queries and 25 rays a cord a tick, 2-3 us each: every call returns a Dictionary), bend
  15%, stretch 6%, the self contacts' search 7%. That search was a quarter (85 us)
  until two segments whose middles are too far apart to touch were skipped before the
  closest-point arithmetic (15 us after; exact, the stress table is identical).
- **Tried and backed out: culling the queries by stretch.** One sphere round every eight
  segments, and a stretch's own queries skipped when it touches nothing. It was made
  exactly equivalent (a segment with a near particle has to count as near: a contact
  moves the shared particle out of the far stretch's sphere), and it was SLOWER, 330
  against 269 us on a cord hanging over a table's edge: one big overlap query costs as
  much as six or seven small ones, and in a furnished room most stretches are near
  something. A solve on worker threads would touch only the 35% that is not queries.
- `substeps = 1` is still a working solver (the probe's `--substeps=1` control leg) and
  keeps every contact change below; it is not bit-identical to the solver before.

## A cord that will not lie still in a ROOM: ask it (`XENU_ROPE_DIAG=1`)

Five causes of a cord "twitching about once a second" were found the same afternoon the
substeps shipped, none of them reproducible in a probe with a bare rope, all of them in
the player's own saved room in a minute. Run the app with `XENU_ROPE_DIAG=1` and every
cord that is awake prints, once a second, why (`[Rope] <path> awake 90 ticks: moving N,
anchor moved N, unsettled N, wakes anchor/env/call ...`), its fastest particle, the self
contacts that pushed on two consecutive ticks with their weights, and, for a segment far
past its length, what a ray finds between its two ends. **A cord that reports nothing is
asleep.** What it found:

- **The sleep poll did not know an edge contact** (`EnvironmentChangedWhileSleeping`).
  It asked for a surface along the contact's normal, an edge's normal points out of the
  corner, the face found is turned 45 degrees from it, and that read as "the support
  changed": woken, contacts cleared, re-laid, a 20 mm jolt, asleep again. An edge
  segment is asked `EdgeStillThere` now.
- **A lay that cannot be** (`HOPELESS_FRAMES`): a pad's plug seated in a port on the far
  side of its console from where the cord lay, so the cord's last segment ran through
  21 cm of console, 7.5x its length, for ever. The wrong-side recovery walks a particle
  back to its PREDECESSOR, no help when the far end is the pinned one. A segment past
  `SLEEP_STRETCH_ERROR` for 180 ticks with both ends still gets the cord laid afresh,
  once (logged; not again until an end moves; `InitPoints` must not reset the flag).
- **A rule decided by where on a segment the closest point falls can flip every tick.**
  The exemption for two branches of one breakout asked "is it at an end": a contact
  resting on that line was on one tick and off the next, and a branch lying across
  another dropped 3.4 mm and was put back, for ever (a PS2 A/V lead). It is decided by
  where ALONG THE BRANCH the segments are now (inside `fray_taper_segments`).
- **"Resting on a surface" is within a radius of touching, not 5% over** (`RestingNormal`,
  2.0 x the radius): a strand under another bobs a millimetre, was in and out of the
  test on alternate ticks, and the pair shared the push on one tick and not the next.
- **A segment that ends at a PIN, against a strand that cannot give way, is left alone**
  (`DetectSelfContacts`' `add`): a loose plug lying across its own cord levered its one
  free particle up several millimetres every tick. The plug's body is what is there.

`pad_cord_probe` (a real pad, its own cable, the engine ticking; `--system=genesis` seats
the plug in a real console; `--loose`, `--console`) does NOT show any of them, which is
the point of the paragraph above. `rope_jitter_probe --rest` counts wakes after the first
sleep; `rope_tests` `awake/` has the stay-asleep cases.

## Contact planes are FINITE, and a sharp edge is a line (2026-11-10)

A cached contact plane is infinite and the face it was read from is not. Three rules:

- **A plane is kept only while a ray finds its face under the particle**
  (`PlaneSupported`, on the rest cadence). A particle that slid off a table's edge used
  to stand on the table top's plane in mid air, stuck there by static friction, until it
  was two segment lengths from where it last touched, and then dropped 13 mm in a tick
  (`rope_jitter_probe --case=corner --trace`). The same in reverse: hauled UP over an
  edge it was stopped by the side face's plane, which goes on up for ever.
- **The surface is read with a RAY; the sphere query only says which way it lies**
  (`SurfaceUnder`). Jolt rounds a box's edges by its collision margin for SHAPE queries
  (up to 4 cm, 8% of its thinnest side) and a ray sees the box sharp, so near any edge
  the two disagreed by up to 16 mm and a particle fed planes from both was thrown from
  one to the other. When the sphere reports the plane a slot already holds, that is the
  confirmation and no ray is sent.
- **A segment lying over a sharp edge holds the edge's LINE** (`m_edge_*`,
  `m_mid_contact` bit 4). When a particle runs off a face, `FindEdgeFor` looks back under
  that face for the one it meets, and the segment gets the line the two share. Slot 1 of
  its contact is re-derived from the line every slice (`PlaceEdgeContact`): the point of
  the segment nearest the line stays a radius clear of it, so the contact SLIDES along
  the segment as the cord is pulled round. Near an end of the segment the next segment
  is given the line too (passing ONE contact back and forth left one of the two inside
  the corner every tick). Friction for it acts on that point's velocity, shared to the
  two ends, not on each end's own. With the line known, a plane from either face is
  dropped the moment its particle is past the other face (`UpdateEdgeContacts`, plain
  arithmetic, every slice).
- **The sweep's ray reaches a radius PAST the particle**, and a hit out there is ahead of
  it: the particle is held off that plane where it IS. It used to be snapped to the hit
  point, up to a radius along its own motion.

Still open: over a block's CORNER (three faces) a dragged cord chatters on 7 ticks in 718
by 1.6 mm (34 by 6 mm before), and over a table's edge 11 by 1.2 mm (6 by 3.9 mm before:
fewer but larger). A curved surface is unchanged (the pipe wrap is the control: 0).

## A cord crossing itself: the strand underneath owns the floor

Self contacts are found once a tick (`DetectSelfContacts`) and solved INSIDE the
constraint loop, before the surface planes (`SolveSelfContacts`), since 2026-11-10. Until
then it was one pass after the solve: eight stretch and bend iterations closed a coil
with nothing in their way, the pass pushed it open, and a wound-up cord churned for as
long as it was awake. Also since then:

- **Segment pairs are the closest points of the two SEGMENTS, clamped.** It took the
  closest points of the two lines and kept a pair only when both fell inside, so the end
  of one strand sliding into the middle of another was no contact until it had gone
  through, and was then lifted a cord's thickness over it in one tick (8.5 mm).
  Between two branches of ONE breakout only a true crossing counts, as before (they
  leave it closer than the clearance, and the fan was pushed apart for seconds).
- **Strands found a quarter of their clearance apart or less are parted along the
  perpendicular to both, held for the tick** (`SelfContact::fixed`). Their offset is a
  millimetre of noise that changes sign: parted along it a kink's two segments went
  through each other and back every tick, 6 mm each way, for ever.
- **Strand on strand has friction**, by `ApplyContactFriction`'s rule, on velocity only,
  loaded by how far the solve parted the two (`FinishSelfContacts`). With none, a loop
  lying across itself chattered on 264 ticks of 718 while its end was moved (0 now).

Where a loop crosses over itself on a floor, three rules keep the crossing still
(2026-09-22):

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
  (`floor_ends_probe`). Every particle's history moves with ALL the contacts pushed it
  (`m_self_moved`), not only the part along a contact's normal: a segment lying across
  a strand was otherwise left rocking on it, one end up 2 mm and the other down, which
  is a motion the contact point has no part in. Segment pairs stop the approach too.
- **Nothing ends a tick inside a surface because of a crossing.** That was a lift
  afterwards, of only what the pass had pushed in; the surface planes are solved after
  the crossings in every iteration now, which is the same thing.

A pile forced awake from the moment it lands (`rope_crossing_probe --heap --awake`)
moves 0.84 mm/tick at its worst crossing (4.2 before) and still slumps slowly. Left to
itself the same pile sleeps by tick ~150 (270 before). A loop tighter than about
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

## A ribbon's lay is held by BOTH connectors

A ribbon (`ribbon_count` > 1, the two-wire mains cords) is one simulated chain. Its
cords are laid out sideways in a render-time frame that is parallel-transported
along the curve, seeded from the START connector's `ribbon_axis`. Until 2026-09-22
nothing tied it to the END connector, so the pair entered that plug at whatever
angle the transport arrived at, and visibly rolled about the cord as it moved.
`RenderCord` now measures the roll between the arriving frame and the end
connector's own `ribbon_axis`, and spreads it along the cord by arc length: the lay
leaves both plugs square and takes up the difference as a gradual twist. Where the
cords share a colour it takes the shorter way round (half a turn looks identical),
and otherwise the exact roll. This only applies where the trunk ends AT a plug; a
frayed end is a breakout. A sleeping ribbon also re-meshes (never re-simulates) when
either connector turns more than half a degree (`RibbonEndsTurned`). Rolling a plug
about its own cord axis moves no anchor, so the rope slept on and the wires stayed
put under a turning plug. `ribbon_twist_probe` films it (windowed only: the lay is
drawn, not simulated).

## A taut cord stretches: the solver's known limit

Eight Gauss-Seidel iterations cannot make a long cord inextensible under tension. A lead
held up by one plug with the other on the floor sits a few percent long along its whole
length, and most of that (1.23–1.25×) lands in the first segment past the held plug's
boot (`handling/a yanked lead recovers its length`, bound 1.30). The standard fix is
long-range attachments: every particle constrained to lie within its path length of each
pinned end, which is O(n) per iteration. It is not built.

## A seated plug takes its basis from its SnapGrabPoint -- a captive one too

A snap zone seats a plug at the zone's transform times the plug's grab point's inverse. Every plug carries a
`SnapGrabPoint` turned half about X, so its +Z goes INTO the socket and its -Z (where the rope leaves) out of the
socket's mouth. A plug with none takes the socket's own basis and its cord leaves backwards. The headphones' hidden
captive plug (`PlugA0`, in `Body/LineIn` on the cup's `CordExit`) had none, so the cord rose into the cup before
hanging (2026-11-03); `headphones_tests` `scene/` asserts the plug's -Z along the CordExit's -Z by sign.

Where the plug STOPS is the socket's: a 3.5 mm `TrsPort` zone stands 2 mm proud for the collar a stand-in draws,
and a shell that draws its own PHONES mouth has no collar, so `SystemAvPorts.build_phones` puts the zone ON the
shell face (a seat's optional `face` says where the face is along the normal from `position`, measured off the
mesh). Before, every detailed handheld held the handle 1.8-2.5 mm off its shell (`jack/` in `headphones_tests`).
Measured after, handle face to shell: gb/gbc +0.17 mm, gba 0, gamegear -0.24, n3ds -0.19, nds -1.0 (the xenu.nds
mod's seat is 1 mm inside its shell; the fix is a `face` in that mod), CD player PHONES +0.75 (its zone is
`DeckFace.seat_port`'s `PORT_PROUD` off the model's mouth).

## Probes (`RetroXR/Tools/rope/`)

- `rope_jitter_probe`: does a cord JITTER while it is awake and being handled? Every
  other check asks whether a cord settles, and sleep hides jitter. One bare rope, an
  end moved slowly and smoothly, `--case=` `edge` `corner` `wrap` `wrappipe` (the
  round-bar control: no edges) `loop` `heap` `wound`. Read `chatter`: ticks on which a
  particle's acceleration turned right round from the tick before, by more than 0.5 mm
  both times (a span swaying has second differences as large, but they keep their
  direction). **`--seeds=N` and read the SUMMARY's medians**: a pile lands differently
  for a millimetre's difference in its start, and one layout's number is mostly about
  the landing (the heap read 0, 315, 5 and 112 kicks across four small changes before
  this existed). `--trace` / `--watch=N` print a particle and its neighbours tick by
  tick round the worst chatter with each cached plane (`get_contact_debug`);
  `--disable=` and `--substeps=` are the control legs (`debug_disable`: 1 edge
  contacts, 2 strand friction, 4 the confirming rays); `--sharp` zeroes the boxes'
  collision margin; `--video=` (windowed).

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
- `ribbon_twist_probe`: a two-wire mains cord held at both plugs, the appliance plug
  turned a full 360° about its cord axis; the wires must turn with it.

Headset validation of all of this is OWED: nothing here has been felt in a hand.
