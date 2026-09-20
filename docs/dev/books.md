# Books (§2v)

`PDFBook` (`RetroXR/Scripts/Objects/books/pdf_book.gd`, scene
`Scenes/Objects/media/pdf_book.tscn`) is a PDF or CBZ you can hold, open and page
through. This doc covers how the paper is built and how it hangs in the hand. Page
grabbing is in the header of `page_grab.gd`; the dead-zone bug is the header of
`Tests/book_tests.gd`.

## The frame everything is written in

Book-local: the **gutter is the line x = 0, running along Y** (the spine axis); pages face
**+Z**. A *side* is `dir = +1` (right) or `-1` (left). Every page surface's centre sits at
`x = ±(_book_width/2 + SPINE_WIDTH/2)`.

There is **no hinge node and no open angle**. `CLOSED` / `OPEN` / `LAST_PAGE` are three
snapped layouts (`_set_state`); covers flip by `rotation_degrees.y = 180`. `_current_leaf` is
the spread index: left page `= leaf*2 + 1`, right page `= (leaf+1)*2`.

## Paper is deformed in the vertex stage, never rebuilt

Every sheet is a subdivided `QuadMesh`; every block a `BoxMesh`. Nothing is an `ArrayMesh`
and no mesh is touched per frame — the CPU only writes uniforms. Three layers, applied in
this order in `Shaders/paper.gdshader`:

1. **Rest shape** — `paper_rest.gdshaderinc`: gutter dive, fore-edge sag, bow, edge curl.
   Shared with `page_edge.gdshader` (the block) so the two cannot disagree.
2. **Fold** — the hand-driven cylinder wrap of the one turning leaf (`_update_fold_from_hand`
   solves the fold line; the shader wraps).
3. **Flop** — `paper_flop.gdshaderinc`: the whole half hanging from the binding. Last,
   because it carries the other two with it.

**The rule that has been broken twice already:** anything that moves a sheet must move the
block under it by the same amount, from the same numbers, or the block surfaces through the
page. That is why each layer is an include shared by both shaders, and why `_push_flop`
writes one side's numbers to all of that side's materials in one place.

Vertex displacement does not move culling bounds. Every paper surface **and both blocks**
carry a `custom_aabb` a full page-width deep (`_set_paper_aabb`, `_refresh_flop`) — a half
hanging off a raised spine swings its fore edge that far. It used to be 16 cm, sized for the
fold alone.

## Flop: how the book hangs

`book_flop.gd` (`BookFlop`, a pure `RefCounted`) is **not a cloth solver**. Per half it is two
damped pendulums about the gutter — a loose **hinge** at the binding and a stiffer **bend**
over the page — and one more per loose leaf of the fan. Its whole output is four numbers
per side, `(angle at the gutter, page curvature, support distance, gutter displacement)`,
which the shader wraps the geometry round as three pieces in series out from the gutter — a
tight arc at the binding, a straight run to the supporting hand, a long shallow arc over the
rest (arcs conserve paper length exactly, the same trick the fold uses) — then moves the half
with the gutter. Angles are **positive toward +Z**: positive is a half closing over the
other, negative is it drooping under a book held face-up.

Why this and not the obvious alternatives:

- **Not `VerletRope`.** It is a world-space, `top_level` 1-D chain that owns a tube mesh and
  has no sheet constraint. A half's droop is an angle, not a chain. (It is the right tool for
  a ribbon bookmark, the `BeadPullCord` way.)
- **Not a CPU mesh rebuild.** That is the cost the rope's C++ port exists to remove
  (~460 µs/tick + ~157 µs/frame per object in GDScript). Doctrine is in
  `blind_slat.gdshader`: motion in the vertex stage costs the CPU nothing.

Things that are easy to get wrong:

- **The body is FROZEN while held** and driven by `XRToolsGrabDriver` (physics priority −80),
  so `linear_velocity` / `angular_velocity` read zero. Motion is differentiated from the pose:
  effective gravity on a half is `basis⁻¹ · (g − a)`, where `a` is the second difference of
  that half's own rest centre — one number that already contains swing, shake and rotation.
  It is low-passed and capped; tracking jitter differentiated twice is loud.
- **Only a hand makes a book hang.** `_flop_holder()` excludes `XRToolsSnapZone`: a book filed
  on a shelf is supported. Not held → no drive at all, the springs ring down to flat.
- **The tick is default-off** (`set_physics_process(false)` in `_ready`), armed by
  `picked_up`, and disarms itself once the book is put down and `is_settled()`. It then
  `reset()`s so the book is *exactly* flat and the shaders take their no-bend branch. A room
  holds many books; one on a shelf costs nothing.
- **Where the hand is matters.** The root is rigidly tied to the hand, so the spine is the
  frame. The half the hand is on is *supported* from the gutter out to the hand
  (`set_support` → `support(dir)`): its hinge locks and it only bends beyond the hand. The
  other half hinges freely. Held within 2 cm of the spine, both flop.
- **A shut book has no free hinge.** It bends as one block (both covers on one side). Hinging
  is opening, opening is a page turn, and that is synced, saved state — physics never changes
  `BookState`.
- **Stiffness is linear in leaf count**, not cubic: leaves slide on each other. A 4-leaf manual
  flops; a 300-leaf book barely moves. `floppiness` (export, 0–1) scales the drive; `0` is the
  old rigid book.
- **A mesh's own frame is not the book's.** Covers are turned 180° about Y (their +Z is the
  book's −Z → `flop_z_sign`); a spread page is the child of a Z-scaled block
  (→ `flop_origin_z` from `_book_xform`, and `z_scale` in the block shader, which also has to
  take the normal through the inverse scale). `s`, the distance from the gutter, comes from
  `spine_sign * VERTEX.x`, which is already rotation-proof.
- **The turning leaf crosses the gutter.** Its flap lies on the far half, so paper materials
  carry `flop_far` as well as `flop_own`, and a negative `s` takes the far side's bend.
- **The fold solver works on the FLAT page.** The hand goes back through the bend first
  (`_leaf_local`), and the grab zones are carried round it (`_seat_page_grab`) — on a
  drooping book a zone left on the flat plane hangs in the air above its page.
- **A LIFTED sheet cannot take the binding's tight bend.** `z` above a bend of radius `R` it
  is on the outside of the curve and has to cover `(R + z) / R` times the paper it has: 5 cm
  over a drooping spine, 3.7×. A page being turned was stretched into a flat tongue longer
  than the page, and the hand carrying it slid centimetres off the paper as it crossed the
  spine. The turning leaf — `flop_cross = 1`, and **only** it, since a sheet lying on its block
  must agree with the block — spreads the same turn over an arc that widens with height
  (`hinge_len_at` / `flop_hinge_len`, `LIFT_SPREAD` × z): 1.26×. On the page plane that is
  `HINGE_LEN` again, so a landed page lies exactly on its block. The two halves' maps meet at
  the gutter (the turn starts from zero there), so nothing is blended — blending
  the two was tried first, on the wrong diagnosis (a seam at the gutter), and left 2.8×. The hand uses `bend_over` /
  `unbend_over`; the inverse is a real Newton step with a measured Jacobian, because this map
  is not a rotation (the arc depends on the point's own height) and the rotate-the-residual
  shortcut `unbend()` gets away with stalled 16 mm off. The leaf's own hinge is undone after
  it, as a plain rotation.
- **Turning a page does not hold the half up.** There used to be a `DRAG_DRIVE` that cut the
  drive on the side being turned to 0.4, to keep hand-tracking error small; the half popped up
  from 50° to 20° the moment a page was touched. The turning hand holds one leaf, not the
  half. With the inverse exact there is nothing for it to paper over, so it is gone.

### The turning page: a bend, a hinge, and the hand

**It bends (`_fold_shape`).** The turn used to be an origami fold: flat sheet, a half-cylinder
of radius `min(up / 2, across / π)` with a 3 mm floor, and a flap flipped a full 180° lying
flat on top. The instant a page was gripped and moved a few millimetres, `across` was tiny, the
radius hit the floor, and a sliver of page **snapped** over into a crease that then slid along.
Now the sheet may wrap *less* than half way round, with the grip still on the curve. A point
carried through an angle φ round radius r moves

    across = r (φ − sin φ),   up = r (1 − cos φ)

— a cycloid, which inverts in closed form up to one scalar solve (`up / across` fixes φ, then
r). A small pull is a huge radius and a barely-lifted sheet; the curl tightens and rolls over
as the hand carries it across. At φ = π it *is* the old rolled-over flap (`up = 2r`,
`across = πr`), so a hand low over the page still gets the flap and the two meet with no seam.
`CURL_MIN` is 9 mm, not 3: paper does not crease by being pulled.

**It hinges (`_leaf_lift`, `_solve_leaf_lift`).** The curl starts from a line on a sheet lying on
the book, and the paper is **bound**: that line cannot be behind the gutter. A hand pulling a
page nearly straight up wants a curl so broad it would have to start there — and then the sheet
is simply an arc that begins *at* the gutter, leaving it at a tilt. That tilt is closed-form:
the arc's length is known (paper from gutter to grip) and so is where it ends (the hand), so
`chord / length = sin h / h` gives the half-angle `h` and the arc leaves the gutter `h` short of
the hand's bearing. Zero or less → the curl fits and the sheet lies on the book: every ordinary
turn, untouched (`page_grab_probe`'s fold-direction cases give the same numbers).
- **Paper cannot stretch.** A hand further from the gutter than there is paper gives `h = 0`:
  the leaf taut, pointing straight at a hand it cannot reach. The gap that remains is real.
  So is the part of a gap that lies *along* the spine: a bound page cannot slide on its binding.
- **The lift is a RIGID hinge on the flat book, with the droop applied on top**
  (`bend_over(point, dir, lift, pivot_z)`, `flop_lift` in the shader, applied before
  `paper_flop`). It was first folded into the droop as one more angle over the widened arc,
  which gave the high parts of the sheet only a fraction of the lift: the "leaf's frame" was
  then not a frame, the solver wanted curls starting 6 cm behind the binding, and the grip sat
  37 mm from the hand. As a true hinge the flat frame is exact for every point — the page on its
  block and a hand 25 cm above it alike — and the grip lands **0.0 mm** from a hand pulled up.
- **Do not search for the lift.** The first version bisected "does the curl fit at this lift?"
  over the whole range, where it is not monotone: it found a different root every frame, the
  page jittered between 90° and 140°, then dropped out into a roll — a snap, again. One smooth
  function of where the hand is, or nothing.
- **Paper is stiff (`LIFT_BOW_STIFFNESS`).** An ideal limp sheet turns its first hair of slack
  into a bow — the half-angle goes as the *square root* of the slack — so where the hand's
  distance from the gutter equals the paper's length, 0.9 mm of hand moved mid-page 11.6 mm.
  `h² / (h + h₀)` is linear near taut. The grip still lands on the hand exactly: the curl is
  solved in the leaf's own frame whatever the lift is, and this only decides how the turn is
  shared between hinge and bow. **Judge continuity by the paper, not the lift angle** — near
  taut the tangent at the binding legitimately turns degrees for a fraction of a millimetre.
- **The lift hands over to the roll** (`LIFT_HANDS_OVER_FROM/TO`, in the hand's bearing about
  the gutter, 90° = straight over it). A leaf up on its hinge is turned about *its own* half, so
  it can never lie on the far one; the rolled-over sheet, whose flap rides the far half's bend,
  can. Bearings run −90°…270°: wrapping at 180° dropped the lift from 105° to nothing in one
  frame once the hand was over the far side of a drooping book.
- A raised leaf is being lifted, not corner-folded: the hand's drift *along* the spine stops
  steering the fold (`LIFT_STEERS_STRAIGHT`). Before, a hand that mostly rose gave an in-plane
  displacement of a few millimetres pointing wherever it drifted, the binding rule refused it,
  and the page did nothing until the hand had travelled.
- **Solve and wrap with the same crease.** The shader loosens the curl toward the spine by
  `curl_taper`; the solver used one radius and the shader another, and the grip sat 11 mm
  short. The solver works with the radius *at the grip* and hands the shader the fore-edge
  figure that tapers to it.
- **Progress is how far the GRIP has been carried** (`_grip_travel`, 0.5 = over the gutter), or
  `lift / π` if larger — not how far the curl line has travelled. A page lifted by its edge
  starts curling from right beside the binding while it has gone nowhere, and would have
  committed on release.

Measured with a marker on the gripped paper (`book_flop_probe` segment 6f): before any of
this the paper was 11 mm from a hand pulling over, 116 mm from one pulling out past the fore
edge and 355 mm from one pulling up and away, lying on the book throughout. Now 0 mm over,
0 mm up, and the two out-of-reach legs sit at what the paper's length allows.

### Hands: where a book is held, and by how many

- **A book is held WHERE it was taken** (`PDFBook.pick_up`, `_grip_point`). pickable.gd's local
  patch pulls a grab-point-less object's *origin* into the hand — right for a cartridge, wrong
  for a book, whose origin is the spine: every hold was a hold by the spine and a hand could
  never be on an end. The override keeps the patch's purpose (nothing dangling at arm's length)
  by flying the book in only until the *nearest point of the book* is in the hand, a little
  in from the edge. A shut book only exists on one side of the gutter, so the clamp uses the
  per-state collision box. Laser (ranged) pickups and snap zones are left to their own rules.
- **Two hands** (`second_hand_grab = SECOND`): GRIP takes hold, TRIGGER is still the page. The
  second grab also **aims** (`drive_aim = 1`): two hands that each merely vote on the pose
  average a raised hand into a half-height lift; aiming tilts the book toward it.
  `set_support` takes both grips — each supports the half it is on, so a hand on each end
  locks both hinges and leaves only the strip beyond each hand to droop. That is the fix for
  "too limp to read", and it is the player's to apply. The sim is fed the **grip points**
  (`_flop_grips`, `grab.transform.origin`), not the hands, which two-handed drift off them.
- **The grip quick-flip is gone.** The other hand's GRIP near a held book used to turn the
  page; that grip is now the second hand taking hold, and every two-handed grab flipped a
  page on the way in. The trigger drag turns a page with the same hand; desktop keeps E / Q.
- **Sag between two hands.** The hands do not move, so the grips stay put and the *gutter*
  drops between them; each half then slopes up from the gutter to its hand by
  `asin(drop / distance to that hand)`. One scalar — `BookFlop._sag`, the gutter's
  displacement along book Z — is the whole degree of freedom, and it is the one number both
  halves share (`params().w`), which is what keeps them joined at the binding when the hands
  are at different distances from it: one drop, two slopes, the nearer hand's half the
  steeper. Live only with a hand supporting **each** half of an open soft-cover spread (boards
  held at both ends hold the joint up). It stiffens with leaf count and with a *shorter*
  span. Two traps: (1) liveness tests the support **targets** as well as the support points —
  a hand that has let go leaves its point sliding home for a fraction of a second, still
  above zero, and dividing the drop by that shrinking distance whipped the slope to 30°;
  the hand distances are *remembered* (`_sag_hand`) so a released sag eases out over what
  it was hanging between. (2) The binding is the one rigid piece, so no shader moves it —
  `_push_flop` moves `_spine_node` by the sag, from `_spine_rest_z`, which the two layout
  functions record. The paper in each hand shortens toward the gutter by `s(1 − cos slope)`
  (~2 mm at 10°); that is left alone rather than opening a gap at the binding.
- No headless suite drives a real grab (none in the project does — see CLAUDE.md on
  godot-xr-tools). `_grip_point`, the flag and the two-grip support are tested; the feel of
  the two-handed pose is a headset check.

### Hardback

`PDFBook.hardback` (export, **default off**, the "Hardback (stiff covers)" row of the book's
options panel, saved as `"hardback"` in the room; **not** sent over netplay — cosmetic and
each player's own, unlike size and half-page mode, which change the shared layout).
`BookFlop.hardback`: the boards do not bend (`bend` is *zeroed*, not stiffened — a spring
stiff enough to look rigid would outrun the step, and switching it on mid-hang must remove
the bend that is already there), and the joint stops them at `HARDBACK_ANGLE_MIN` (−6°), so a
hardback held level by the spine lies open instead of drooping. They still swing toward shut
when the book is turned over, and the pages inside still fan: they are paper. Shut, a
hardback is rigid.

### The fan

Up to 3 loose leaves per side (2 on Quest) lie on each block of an **open** spread. Each is a
light pendulum with **one-sided contact**: it cannot pass the block or the leaf under it.
Face-up, gravity pins the whole fan at *exactly* zero and no leaf is drawn. Tip the book past
vertical and they peel off; each deeper leaf is held a little tighter by the binding
(`FAN_W2_SPREAD`), which is the only reason a fan fans instead of moving as one sheet.

Leaf `k` carries the pages that were on top of the block (`_update_spread_textures`, the one
place spread textures are written), and the block shows the page under the last visible
leaf. `prefetch_pages = 6` covers three leaves either side; `_prefetch_nearby_pages` reaches
**one page further right** than the spread needs, for the page under a fully opened fan —
rendered on demand it was a blank sheet the first time a book was tipped over. Taking a
page (`_spawn_leaf`) shuts that side's fan first: the turning leaf *is* the top of it, and
two things would otherwise drive the block's top sheet.

### What it costs

`Tools/perf/book_flop_bench` (windowed — a real RenderingServer behind
`set_shader_parameter`), one **held** book, per 90 Hz physics tick, timed around the calls
the way `rope_bench` is. Desktop, 2026-09-18:

| held book | sim | push to shaders | total | of one core |
|---|---|---|---|---|
| one hand, hanging | 19 µs | 18 µs | 38 µs | 0.34 % |
| turned over, 6 leaves fanned | 19 µs | 26 µs | 45 µs | 0.40 % |
| two hands, sagging | 20 µs | 17 µs | 37 µs | 0.33 % |
| hardback | 20 µs | 18 µs | 37 µs | 0.34 % |
| shut | 7 µs | 15 µs | 22 µs | 0.19 % |
| **not held** | — | — | **0** | tick is off |

For scale, the GDScript rope this project replaced was ~460 µs/tick + ~157 µs/frame per
cable. At most two books are ever held. **Quest is not measured** — expect a small multiple
of these; run the bench on device before quoting a figure. The GPU side is a sin/cos pair
per vertex over ~600 vertices (Quest grid) and is not visible to a script.

### What a page TURN costs, and why it used to hitch

The flop above is the cheap part. The expensive thing a book does is produce page textures,
and until 2026-09-19 a turn did it on the main thread.

`_get_page_texture()` has always had two branches. A page with no PNG in `user://pdf_cache/`
goes to `WorkerThreadPool` and the caller gets `_loading_texture` until it lands. A page that
IS on disk looked free — no render needed — so it was read **inline**:
`Image.load_from_file()` plus `ImageTexture.create_from_image()`. That is 14 ms for a
1200×1600 page (11 ms decode, 3 ms upload), against an 11 ms frame at 90 Hz. A turn asks for
the two new pages, every raised fan leaf, and then prefetches a fifteen-page window
(`prefetch_pages` 6), and `_trim_texture_cache()` drops the pages behind as it goes — so the
window kept refilling off the disk.

The cache dir outlives the app, which is the trap: **the first read of a book was smooth and
every read after it hitched**, which is the opposite of what a cache is supposed to do.
Measured with `Tools/perf/page_turn_probe` (windowed — `--headless` skips the upload and
shows only the decode), on pages smaller than a 150-DPI Letter page:

| a turn | before | after |
|---|---|---|
| reading straight through | 28–34 ms | 0.2–0.3 ms |
| the book reopened, nothing in RAM | 150–220 ms | 0.3 ms |
| pages already in RAM | 0.3 ms | 0.3 ms |

Both branches go to the pool now, and the disk branch decodes there instead of re-rendering.
What is left on the main thread is the upload alone, which cannot move: `_on_page_rendered`
parks the image in `_upload_queue` and `_drain_uploads()` spends **`UPLOADS_PER_FRAME`** (2)
of them per frame from `_process`, **nearest the open spread first** — a finished prefetch
window is fifteen images, and drained in arrival order the reader would watch the placeholder
while pages they cannot see went up ahead of it. Prioritised, the spread is up **one frame**
after a cold start; the rest of the window fills in over ~16, invisibly.

A page therefore stays in `_pending_renders` until its texture actually exists, not until its
worker finishes. That is deliberate: it keeps `_pending_renders.is_empty()` meaning
"everything asked for is in `_texture_cache`", which is what every suite's `_drain_renders`
waits on.

The cost that remains is real but off the frame: decoding is ~11 ms of worker time per page,
so a book whose pages are 3000×3000 spends proportionally more of the pool. Nobody has
measured this on a Quest, where the storage is slower and the upload is not free.

### The pick-up outline bends with the book

`PickableHighlight` draws its outline from a flat, smoothed **copy** of each source mesh, kept
on the source node's transform. The bend exists only in the page shaders, so the outline
stayed where the flat book would be — an empty rectangle floating in the air — while the book
drooped away under it.

- The book's highlight has `bends_with_parent = true` (`pdf_book.tscn`), which swaps in
  `outline*_bent.gdshader`: the same four shaders with `outline_flop()`
  (`outline_flop.gdshaderinc`, which calls the very same `paper_flop`) run on the vertex before
  the hull is inflated.
- **The four outline shaders are not touched, and not restructured.** Their headers record what
  changing their *shape* has done to a Quest's GPU (VRS + stencil, a constant-folded fragment
  output). Every other object keeps byte-for-byte the shader it had; only the book gets copies,
  **generated** by `Tools/gen_bent_outline_shaders.py` with the additions between two marker
  lines. A copy of a fragile file drifts, so the suite strips the marked lines back out and
  compares each copy with its original to the character — edit an `outline*.gdshader`, rerun
  the tool, or CI goes red. **The copies are untested on a Quest**: filmed on desktop in both
  variants (`book_flop_probe --outline`, and `--hull` for the depth-carved hull a foveated
  session draws).
- The highlight shares ONE material across all of an object's overlays, and each overlay hangs
  by its own side's bend, so the numbers are **per-instance uniforms** (`flop_own`,
  `flop_frame`, `flop_page`), set through `PickableHighlight.set_source_param()`. It *keeps*
  them as well as forwarding them, because overlays are rebuilt from scratch when the meshes
  change and a rebuilt one would come back flat. `_push_flop` sends `flop_own` with the rest;
  `_refresh_flop` sends where each mesh sits (a cover turned 180°, a block scaled on Z).
- The rigid binding's overlay is given nothing (all-zero = no bend) and follows the sag because
  it follows its node. Page sheets, the turning leaf and the fan are `outline_exclude`.

### A page dragged with a pointer

The desktop reticle and the VR laser latch a page with PRESSED and used to move it on MOVED —
and a pointer only reports a position while its ray is on something that takes pointer events.
The grab zone covers the outer 65 % of a page (so the laser can still pick the book up by the
rest), so across the inner strip, the gutter and the far page's inner strip the ray was on the
book's pick-up body, which does not: **the page stood still across the whole middle of the
book**. Now `PageGrab` keeps the latching pointer and, every frame, asks the book where its
ray puts the hand (`drag_point` → `_page_drag_point`): the ray meets the plane of the pages,
and the height is an arch over the gutter (`POINTER_LIFT_EDGE` → `POINTER_LIFT_GUTTER`),
because a ray has no height of its own and a page dragged flat across the book rolls tight
where a hand would lift it over. Worked out on the flat book and taken through the leaf's
bend, so the fold solver sees exactly that point. Both pointers cast along a child
`RayCast3D` named `RayCast`.

Related: turn progress (`_grip_travel`) is measured on the **flat** book (`_hand_across`), not
in the leaf's tilted frame — over the gutter the leaf is up on its hinge, the hand is
foreshortened across it, and the turn read 0.42 and stalled for the width of the gutter.

### Thick books

Everything above was built and filmed on a 24–28 page booklet, a 1.2 mm block, where a
surface's height off the neutral plane is nothing. A 400-page book is a 2 cm block: opened in
the middle its top page and its cover sit **5–6 mm either side** of the plane the bend is
written about, and the turning leaf hinges from 5 mm up (`pivot_z`). Checked, not assumed
(`thick/` in the suite, `book_flop_probe --pages=400`, front and back):

- It droops 14° where the booklet droops 50° (stiffness is linear in leaf count), and the
  two-hand sag is 6 mm rather than 25.
- **The invariant:** the binding turns over an arc `HINGE_LEN` long, so its radius is
  `HINGE_LEN / |gutter angle|`; a surface `z` off the plane on the inside of that turn is on
  radius `R − z`. If the block's half-thickness plus its cover reached `R`, the inside of the
  block would fold through itself. Under 2500 ticks of 60 m/s² shaking the tightest radius is
  15.2 mm against 6.5 mm of block and cover. Thick books are safe *because* they are stiff; if
  `HINGE_W2_PER_LEAF` is ever lowered, this is the case that goes red.
- The fan and the spread take their pages from the middle of the book (leaf 99: pages 200 /
  206 on the right, 199 on the left), and the gripped paper still lands 0.0 mm from the hand.
- CBZ pages must be named so they SORT (`page_%04d`): at 400 pages `page_100` sorts before
  `page_11`.
- Not like a real book: turned over, only `FAN_LEAVES` (3, or 2 on Quest) loose leaves fall
  out of a thick book, where hundreds would. The cap is for cost.

### Look at the BACK of the book

Every view of a book in normal use is of its pages, and two bugs lived on the side nobody
films. `book_flop_probe --only=back` goes round: from underneath a hanging book while pages
turn above, from behind one held up to read, from above one turned over. `--hide=covers|
blocks|tops|fan` takes a family of surfaces out of the picture, which is how to find out what
a patch of white actually *is* — reasoning about it got nowhere; hiding the blocks took one
run.

- **A white band down the fore edge of both covers, in every open pose.** The block takes the
  sheet's fore-edge droop (`REST_DROOP`, 1.5 mm) and the covers were left flat a millimetre
  under it, so over the outer fifth of each half the block's cream underside hung *through*
  its cover. Older than the flop work; invisible from the front. The covers now sag exactly
  as far as the block on them (`_set_cover_droop`, from `_update_gutter_depth`, and zeroed by
  `_set_spine_closed` because a shut book's block does not droop). The rest shape is applied
  along the **book's** +Z (`flop_z_sign`), not the mesh's: a cover turned 180° about Y would
  otherwise sag *up into* its block.
- **One whole side flashes white for a single frame as a page turn lands.** The project runs
  with **physics interpolation on**: a child's transform set from `_process` is eased in over a
  tick, while a shader uniform lands at once. When a turn finishes the blocks change their Z
  scale, and the block shader is told that scale (`z_scale`) to take the bend out through it
  and back. For one frame the shader divided by the new scale and the node applied the old
  one; the error grows with distance from the gutter, so on a drooping book the block splayed
  out from the binding through its cover (or, on the other block, through the page on top).
  `_snap_layout()` calls `reset_physics_interpolation()` on the book's children after every
  layout change — **not** on the book itself, which would snap a held book to its hand.
  **No headless suite can see this one**: it is a render-order fault. The back-view film is
  its only check.

### Covers are printed inside

A cover's inner face carries the page printed on it (`_update_cover_texture` →
`_apply_back_texture`, pages 1 and `count − 2`, both kept out of the cache trim). The sheet
shader's back face otherwise defaults to blank **white**, which a rigid book always hid behind
its block; a book that hangs, fans and is turned over shows its covers from angles it never did.

### Cosmetic and local

Flop changes no collision shape and no `PointerArea`, and puts nothing on the wire — each
peer hangs its own copy from the held pose it is already sent, for the same reason the fold
is never streamed (`_animate_page_step`'s comment). The only thing saved is the `hardback`
choice; the angles themselves never are, and a restored book starts flat.

### Not done

- Bending **along** the spine axis (a magazine held by its bottom edge folding over at the
  top). Paper cannot bend two ways at once, so this needs a stiffness coupling, not a second
  independent bend.
- A book overhanging a table edge does not droop — not held means supported.

## Testing

- `Tests/book_flop_tests` — the sim with a fixed `dt` (signs and orderings, not tuned
  magnitudes), the CPU/GPU bend staying one function (`FLOP_HINGE_LEN` is pinned against
  `BookFlop.HINGE_LEN`; `unbend(bend(p)) = p`; arc length conserved), and the wiring on a
  real book built from a CBZ. The suite's book is frozen and unheld, so it steps
  `book._flop` and calls `_push_flop` itself — the same code the tick runs. Two traps met
  while writing it: **a suite whose script does not parse HANGS** (the scene loads bare, so
  the watchdog inside the script never starts — run new cases under `timeout`), and asking
  `_get_page_texture()` for a page a worker is still rendering races it (the PNG can be on
  disk before the main thread adopts the texture, and a second one is loaded from the file):
  `_drain_renders` first.
- `Tools/perf/book_flop_bench` — the CPU cost table above.
- `Tools/vr/book_flop_probe` — **windowed**, poses one book through nineteen segments (one
  hand, two hands sagging, pages turned on a hanging book through the real
  begin/move/end grab calls, a hand pulling a page over / up / out / away with a RED dot on
  the hand and a GREEN one on the gripped paper and the gap printed per leg, soft cover,
  hardback, shut, put down; `--only=follow` runs just the page-following leg) and writes
  frames; `python Tools/book_flop_video.py <dir>` makes the mp4 and a contact sheet. This,
  and the headset, are the only judges of how it looks and feels.
- `Tools/vr/page_grab_probe` — the fold-direction oracle; needs a real PDF.
