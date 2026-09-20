# Headless testing, suites and probes

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

## Headless Testing & Validation

There is no unit-test framework in the xUnit sense, but there **is** a runner and it
gates CI. `Tools/run_tests.py` runs every `RetroXR/Tests/*.tscn` that has a `.gd` beside
it, in a stable order, and `.github/workflows/tests.yml` builds the six extensions and
runs it on every push. Beyond that the project is validated by running the Godot editor
**headless** for compile/scene checks, plus small "probe" scenes for functional tests.
All of it works without a VR headset (desktop fallback) and without a display.

```bash
python Tools/run_tests.py            # every suite
python Tools/run_tests.py --list     # name them and exit
python Tools/run_tests.py --update-baseline   # after deliberately adding cases
```

**A case count that DROPS fails the run.** `Tools/test_baseline.json` records each
suite's count, and the runner compares against it — because a suite whose group
quietly stops running still passes every case it did run and still exits 0,
which is the same blind spot as a suite nested in a subfolder. Only a drop
fails: a rise is how the suites grow, and a suite missing from the file is new
rather than broken, so adding cases never needs a second commit. A filtered run
(`--only`, or a forwarded `--only=<group>`) skips the check, since a lower count
there is the point. When a drop is deliberate, re-run with `--update-baseline`
and commit the JSON with the change that caused it.

Because the runner globs `Tests/*.tscn` **non-recursively**, `Tests/` stays flat. Do not
nest it into subfolders — a suite in a subdirectory is silently never run, which is the
one failure mode a green CI cannot show you. (`RetroXR/Tools/` is the opposite: it is
foldered by topic, see below.)

**The bar for living in `RetroXR/Tests/` is exact:** a scene that checks itself, runs
unattended with no ROM, core, headset or device, and **exits non-zero on failure**, so it
can gate a commit. The suites, with their measured case counts and runtimes (Windows,
debug build, 2026-08-27 — all passing):

| suite | cases | time | covers |
|---|---|---|---|
| `netplay_tests` | 685 | 32 s | the whole lockstep stack, two NetworkManagers deep (§2f) |
| `romm_tests` | 312 | 17 s | the pure-logic half of the RomM stack |
| `binding_tests` | 176 | 12 s | which control map a platform resolves to |
| `object_sync_tests` | 127 | 8 s | the shared-room network layer, 2–3 real ENet peers |
| `scene_tests` | 120 | 10 s | SceneManager and the save gates around it |
| `poster_tests` | 112 | 11 s | the posters feature, stick/peel/conform |
| `rope_tests` | 82 | 69 s | what a cable does when it meets furniture |
| `av_tests` | 41 | 35 s | what reaches a television's inputs (§2c) |
| `system_tests` | — | — | the machine controller's port, pad, save and disc rules |
| `link_tests` | — | — | which socket each end of a link lead belongs in |
| `state_tests` | — | — | savestate capture/restore rules |
| `expansion_tests` | — | — | the expansion units and their catalog |
| `bay_tests` | — | — | cartridge bays |
| `card_tests` / `deck_tests` | — | — | memory cards; the video decks |
| `motion_tests` | — | — | accel/gyro/IR device frames |
| `screen_cast_light_tests` | — | — | light the screen throws into the room |
| `book_tests` | 22 | 3 s | a book answers the pointer only where it IS: dead page-grab zones and the `PointerArea` outline are checked per state (unloadable, closed, open, last page, failed reload) with a real ray on the pointer layer (the `disabled` flag is what the fix sets, the ray is what the reticle does). Builds its own CBZ, so no PDF or godot-pdfium. Writes one file under the REAL roms root for the manual-follows-its-folder case and removes exactly what it made. **Its exit code is a case too**: a book whose `WorkerThreadPool` render tasks are never waited on segfaults the process at quit, after every case has passed |
| `book_flop_tests` | 163 | 8 s | a soft-cover book hangs from the hand (`docs/dev/books.md`). `sim/` steps `BookFlop` alone with a fixed `dt` and asserts SIGNS and orderings, never tuned magnitudes — face-up droops negative, face-down positive, gravity along the spine bends nothing, the thin half is the floppy one, a fan is pinned at EXACTLY zero face-up and peels in order face-down, 3000 ticks of seeded shaking never reach 90°, a second hand supports the half IT is on (one on each end locks both hinges), a spread held at both ends SAGS (`sag/`: the gutter drops, the paper in each hand does not move, the halves still meet at the binding, unequal hands give one drop and two slopes, a released hand never whips the slope — that one shipped red first), a page LIFTED over a drooping spine is carried across nearly unstretched (`leaf/`, with a control showing the halves' own bend stretches it 3.7×) and the turning hand is still found on the flat page, the page being turned BENDS instead of snapping into a crease (`bend/`: a small pull is a broad curve, the cycloid carries the grip exactly, the curl becomes the roll with no seam) and FOLLOWS the hand (`follow/`: no lift for a low pull so the old roll-over is untouched, 0.0 mm from a hand pulling up, taut and POINTING at a hand out of reach with the paper still its own length, handed over to the roll on the far half, and — judged by a point on the PAPER, not the lift angle — never leaping as the hand is carried over the spine), and `hardback` boards do not bend, open barely past flat, still swing shut and still fan. `bend/` keeps the CPU and GPU halves one function: the shader's `FLOP_HINGE_LEN` is read out of the include and pinned to the script's, `unbend(bend(p)) = p`, arc length is conserved. `book/` is the wiring on a real CBZ book: **every surface on a side carries ONE bend** (a block bent differently from its sheet comes through the page — that class shipped twice), a cover turned 180° bends toward the book's +Z, the grab zone goes down with the page, the fan hands its pages to the right faces, the tick disarms with the book EXACTLY flat, a hand takes hold at the nearest point ON the book (`_grip_point`, per state), and `hardback` round-trips through `ScenePersistence` with old saves defaulting to soft covers. **No case drives a real grab** — the two-handed pose itself is a headset check. The suite's book is frozen and unheld so its tick is off; the suite steps `book._flop` and calls `_push_flop` itself. A check that can ERROR instead of failing is not a check: `float(null)` on a missing uniform aborted the rest of the book cases and the suite still exited 0 on fewer of them — keep such reads null-safe. `thick/` loads a 400-page CBZ (a 2 cm block) and opens it in the middle: surfaces still agree per side, the binding's bend radius stays well clear of the block's half-thickness under violent shaking, the fan takes its pages from the middle of the book, and the grip still lands on the hand with the leaf hinging 5 mm off the neutral plane. `outline/` pins each generated `outline*_bent.gdshader` to its original (strip the marked lines and it must be the original, to the character) and checks each cover's and block's outline overlay carries its own side's bend, rebuilt overlays included; `pointer/` sweeps a pointer that sends NO events across the book and the latched page follows its ray all the way, half turned over the gutter. Mutation-tested 2026-09-19, 59 breaks. How it LOOKS is `Tools/vr/book_flop_probe`, not this |
| `time_of_day_tests` | — | — | the day/night cycle |
| `tv_resize_tests` | — | — | the TV's own geometry |
| `web_server_tests` | — | — | the built-in file server |
| `prop_lighting_tests` | 17 | 1 s | which of a room's meshes go on the baked prop shader, late spawns and despawns included |
| `scrape_tests` | 76 | 10 s | the ScreenScraper queue over a fake client: thread allowance, accept vs review, media wait, quota stop, the AutoScraper gate |
| `microphone_tests` | 55 | 25 s | the capture service: when the device opens, one read fanned out, the distance gain, a seated microphone's position, the DS pins, the DOL-022's slot value and its save round trip, and the HKT-7200 in a pad's slot |
| `famicom_tests` | 101 | 16 s | the Controller II microphone: the volume slider's threshold curve, the gate and its hysteresis, the level measured in C++, the service's one-measurement fan-out, which port the bit may reach, both pads, the captive pair's cords and wells, and the `famicom` systemid's table rows |
| `n64_vru_tests` | 37 | 30 s | the Voice Recognition Unit: no two coplanar faces on the dongle or the microphone, the device id a socket announces through the unit's own plug, seating in socket 4, the microphone in and out of the 3.5 mm jack, which way both cords leave, and the save round trip |
| `n64_cart_tests` | 107 | 10 s | the N64 cartridge: regional bodies, that they carry no mark and no unmapped normal-mapped triangle, which half each moulded part belongs to, per-instance and per-half shell materials, flake parameters and normal maps, repeated switch and reset, the label helper, the coloured-cartridge lookup by header and MD5, the scraped region, and a spawned cartridge |
| `speaker_tests` | 130 | 38 s | the surround rig (§2r): both cabinets' facing, the cabinet's own socket, a lead on each of the set's six outputs, the fold-down and its gains, the AUDIO OUTPUT key, the 1.2 m and 1 m stands, and the save round trip |

Counts are what the suite printed, not a target — they drift upward as cases are added,
so re-measure rather than trusting this table, and treat an unexplained DROP as a signal.

**Everything else is a probe and lives under `RetroXR/Tools/<topic>/`**, including the
ones that assert: they want real cores and ROMs (`cores/azahar_probe`, `cores/sram_probe`,
`cores/vb_probe`, `cores/nds_probe`, `cores/handheld_probe`, `cores/gl_video_probe`), a
headset or a Quest (`netplay/netplay_spike`), or they are reproductions of open bugs and
report failures BY DESIGN (`rope/three_plug_probe`). Moving one of those into `Tests/`
would make a red run meaningless.

### Where the probes live

`RetroXR/Tools/` is foldered by topic. A probe's scene, script and `.uid` sit together,
and a scene refers to its script by literal path, so a probe moved between folders needs
its `.tscn` rewritten too.

| folder | what it holds |
|---|---|
| `av/` | TVs, tuners, phosphor, decks, spatial audio |
| `cores/` | core behaviour, BIOS boot, options, dual-screen, GL video |
| `gen/` | mesh/material generators run with `--script` (no scene); `gen/plug_materials.gd` is the shared one |
| `input/` | controllers, bindings, mice, lightguns, memory cards |
| `link/` | link cables and two-core buses (§2e, §2g) |
| `models/` | geometry authoring, shell audits, model registry, room renders |
| `netplay/` | sessions, rollback, determinism, state transfer (§2f) |
| `perf/` | Quest device probes, spawn/menu cost, VRAM census |
| `room/` | tables, spawn menus, furniture placement |
| `rope/` | cables — the bit-exact oracles `rope/rope_bench` and `rope/rope_stress` |
| `state/` | save/restore, persistence, scene soak |
| `vr/` | grabs, pokes, pointers, sliders, capsense |

Three data directories sit beside them and are deliberately not foldered by topic:
`gblink/` (the ROMs `Tools/gen_gblink_rom.py` writes), `scan/` and
`azahar_stereo_homebrew/`.

`RetroXR/Tests/rope_tests.tscn` is the behaviour half of the rope's cover. Two kinds of
case: where a cord LIES (contact/ — table, over a corner to a floor socket, round a pipe,
on a ledge, heaped, bridging a gap; loose/ — a whole lead dropped flat, across an edge,
from height) and what a player DOES to one (handling/ — a real lead's plug yanked at
5 m/s, towed 2.5 m across the floor, pulled out through a 100 mm slot, carried over a
partition, a cord wrapped round a post and hauled tight), plus inextensibility,
determinism, anchor pinning, teleport re-lay, `set_rope_length` and sleep/wake. 82 cases,
~70 s, no GPU. It complements rather than replaces the two BIT-EXACT oracles in `Tools/`
(`rope_bench --settle` prints `still_awake=12`, `rope_stress` diffs a 22-row table): those
catch arithmetic drift, this catches a cord that jitters, tunnels or will not settle.
(The bench printed 15 until 2026-08-17: DepenetrateLay freed wedged lays and three more
bench ropes settle; the stress rows that moved are the two impossible lays. Re-baselined
deliberately — an UNINTENDED move in these numbers is still a stop-everything signal.)
Two defects this suite caught and got fixed the same day: `AlignAnchorPlug` used to apply
uncapped rotation steps about the cable anchor, a per-tick transform teleport that carried
a dropped lead's plug through a 100 mm floor (now capped at MAX_ALIGN_STEP); and a cord
laid straight through furniture — every restore/teleport re-lay can do this — left
particles wedged inside it for ever (now freed by `DepenetrateLay` on the first tick after
a lay). `Tools/rope/rope_video_probe.tscn` renders the same cases to PNG frames (windowed, not
`--headless`) for when a case has to be WATCHED — most of the traps below were caught on
its footage, not by an assertion.
```bash
"$godot" --headless --path RetroXR res://Tests/rope_tests.tscn
"$godot" --headless --path RetroXR res://Tests/rope_tests.tscn -- --only=contact
```
Four traps it already hit. **Measuring jitter after a rope sleeps measures nothing** —
`step()` on a sleeping rope is a no-op, so the answer is a confident 0.000 mm however
badly it chattered; the cases hold the cord awake with `wake()` and measure the tail
window of the hold (the first wakes just finish a slump sleep froze mid-way). **A rope
built with `VerletRope.new()` takes the C++ defaults**, which are softer than anything
that ships — these mirror `cable.tscn` (8 iterations, `collision_radius` 0.0045,
self-collision on) or every threshold describes a cord the room does not contain.
**Never initialise a cord in a state no hand can produce**: a straight lay from a
table-top socket to a floor socket passes through the slab and wedges particles 11 mm
inside it (a particle born inside a solid has no contact plane), and a lay pre-compressed
between close sockets buckles into a 318 mm standing arch and sleeps there — the cases
lay the cord clear and `_carry()` the end to its socket the way a hand does. And **a
long free-hanging span cannot be held awake at all**: `wake()` every tick feeds the edge
contact's chatter into the span's pendulum mode and pumps a 0.4 m swing the room cannot
reach, because the sleep system cuts that loop off — the corner case asserts what the
room actually does (brushed awake once, asleep again in 30 ticks, 8 mm of drift).
Everything else measures 0.0003–0.07 mm/tick held awake, heaps included.

`RetroXR/Tests/romm_tests.tscn` asserts the pure-logic half of the RomM stack — pair-QR
parsing, slug mapping and systemid collision, the sync fingerprint, cache path safety,
and the `scan_roms` disk walk. 312 cases, ~17 s, no server, no headset, no network.
```bash
"$godot" --headless --path RetroXR res://Tests/romm_tests.tscn 2>&1 | grep -a "\[test\]"
```
Every case in it is a bug that actually shipped, so it doubles as the regression record —
add to it when you fix something in that layer rather than starting a new probe. It uses a
scratch `__romm_selftest` system folder under the real roms root (the path is derived from
the systemid and cannot be pointed elsewhere) and removes it at both ends.

`RetroXR/Tests/scene_tests.tscn` covers SceneManager and the save gates around it — which
rooms keep slots, the per-room active slot and its prefs round-trip (including the legacy
single-room key), which room a launch opens in, the `is_room_ready` / `is_scene_content_ready` boundaries, the transition
state machine's coalescing, the periodic autosave, clearing and reloading the room you are
standing in, two restores racing into one room, a machine's core outliving its machine, the room's own
movable furniture, the video decks' teardown contract, and slot-manifest CRUD.
120 cases, ~10 s.
```bash
"$godot" --headless --path RetroXR res://Tests/scene_tests.tscn
"$godot" --headless --path RetroXR res://Tests/scene_tests.tscn -- --only=autosave
```
It deliberately does **not** drive a real transition: `change_scene()` loads MainScene.tscn,
whose SubViewports render every frame, and a headless run has no GPU to service them — that
hangs rather than fails (see the SubViewport gotcha below). The cases drive `_transitioning`
and `_pending_scene_id` directly and assert the decisions made from them.

Two traps it hit that the next case will hit too. A spawned system also registers its
captive cable in the `"spawned"` group, so the group is always bigger than the entry list —
measure a baseline rather than hardcoding a count. And tear a group's room down with
`clear_scene()`, not by freeing the systems: freeing only those leaves the cables standing
in the next group's room.

It writes to the player's real `user://scenes` — the slot dir is derived from the room id
and cannot be pointed elsewhere — so it snapshots `prefs.json`, the arcade manifest and the
active slots up front and restores them byte-for-byte at the end. Restoring the manifest
matters beyond deleting the test's own entry: any rewrite round-trips it through JSON, which
turns its version int into `1.0`.

`RetroXR/Tests/poster_tests.tscn` covers the posters feature — the image load and the
sheet it sizes (alpha scissor vs opaque, mipmaps, aspect, per-instance sub-resources),
sticking to a surface on release, riding the object it stuck to, peeling, conforming to
a curved shell, the options-menu contract, and the save/restore round trip. 112 cases, ~11 s.
```bash
"$godot" --headless --path RetroXR res://Tests/poster_tests.tscn
"$godot" --headless --path RetroXR res://Tests/poster_tests.tscn -- --only=conform
```
Physics runs fine headless — the dummy renderer stubs RENDERING, not Jolt — so the stick
and conform cases are real raycasts against real bodies. It writes its own PNG into the
player's posters folder (`scan_posters` derives that path) and removes it at both ends.

Two traps worth knowing before adding a case. A stuck poster is REPARENTED under its
host, so anything that walks the host's meshes sees the poster's own sheet — that is what
made the first conform sample every interior ray at depth zero. And a poster is placed by
RAY as often as by hand, where `dropped` never fires; a release has to be detected from
`freeze`, so a test that only simulates a hand grab proves nothing about the real gesture.

`RetroXR/Tests/binding_tests.tscn` covers the resolution rules behind per-platform
control overrides. Both stores — `ControllerBindings` (VR controllers) and
`GamepadBindings` (a real pad) — merge default → global → per-system, and a platform's
stored profile IS its override switch; there is no separate flag. So three rules are
load-bearing and each has cases here: a platform with no profile is indistinguishable
from global, a profile shadows global completely INCLUDING global edits made after it
(which is why a profile is always written whole), and clearing one puts that platform
back on global without touching anyone else's. DesktopBindings is the odd one
and has its own cases: its consumers all read the process-global InputMap, so a
platform's keys cannot be looked up per system — they are APPLIED, and the Scroll
Lock capture decides when (RetroController._sync_desktop_scope). Its legacy flat
file is read as the global layer, which is covered too, because losing it would
wipe every desktop player's key map on first launch. It also covers ConsolePadArt, the
table a platform's own controller is drawn from — that a control key's index in
GamepadBindings.TARGET_ORDER really is its RetroPad bit (the trick that lets one
table serve both the XR and the physical-pad sections), and that every control
has an anchor and a row. 176 cases, ~12 s.
```bash
"$godot" --headless --path RetroXR res://Tests/binding_tests.tscn
```
It writes the player's real `user://controller_bindings.json` and
`user://gamepad_bindings.json` — the paths are consts on the two classes and cannot be
pointed elsewhere — so both are snapshotted up front and restored at the end.

`RetroXR/Tests/object_sync_tests.tscn` covers the shared-room network layer with
two and three real in-process ENet peers: initial and replacement snapshots,
host/client spawning and despawning, rigid-body transform flow, grab arbitration,
release velocities, disconnect cleanup, event relay, plain + spring-latched
hinge mechanics (including push-push trays), knobs, plain + spring-return
sliders, levers, and remote head/hand avatars. Momentary button depression is
deliberately not replicated;
the semantic action it triggers is. The event cases cover platform power/reset,
tray/eject and media insertion, every TV bezel/remote action (power, volume,
mute, CRT, stereo/audio modes, aspect, source and channel), deck transports,
cables/ports, book controls, wall and pull-chain lights, blinds and time of day.
Late-join snapshots also carry the TV control state and those fixed room controls,
not only spawned objects. Articulated updates are capped at 64 per reliable
packet, with overflow retained for following packets rather than discarded. It
has no ROM, headset or display dependency.
Each group is independently runnable.
```bash
"$godot" --headless --path RetroXR res://Tests/object_sync_tests.tscn
"$godot" --headless --path RetroXR res://Tests/object_sync_tests.tscn -- --only=hinges
```

That a binding reaches a RUNNING core is deliberately not here: it needs a real system,
a real controller and the `binding_consumers` fan-out, and lives in
`Tools/input/binding_live_probe.tscn`. Drive that probe through the view's OWN
`_global_editor` rather than a fresh `ControlsBindingEditor` — a detached editor writes
to disk and reaches nobody, so every "applies immediately" case fails for a reason the
player never sees.

**For anything visual, a photo (or a VIDEO if it's animated — mp4 preferred over
animated GIF) is the preferred proof of validation, delivered inline in the chat.**
Headless runs catch parse/scene/shader errors but cannot confirm how something *looks*
(glyphs, layout, colors, animation). When a change is visual, capture a screenshot or
short recording and surface it inline — don't just report that the headless import
passed. To encode mp4 from probe PNG frames: `imageio` + `imageio-ffmpeg` are pip-installed
(`imageio.get_writer("out.mp4", fps=15, codec="libx264", pixelformat="yuv420p")`).

Godot binary (Windows) — use **Godot 4.7.2** (the project targets 4.7):
```
C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
```
**The doubled name is real** — the 4.7.2 download unpacked into a FOLDER called
`Godot_v4.7.2-stable_win64.exe` holding the exe and its `_console.exe`. The old
`Godot_v4.7-stable_win64\` folder is still installed beside it and is NOT the one to
use: `android/build` is stamped 4.7.2 (`android/.build_version`), so a 4.7 binary
fails every Quest export with `Android build version mismatch: Template installed:
4.7.2.stable / Requested version: 4.7.stable` — and that error names the template,
not the editor, so it reads as a broken template rather than the wrong exe.
Use the `_console.exe` variant so stdout/stderr is captured. `$proj` below is the
`RetroXR/` folder inside your checkout.

Godot binary (Linux): `~/Godot/Godot_v4.7.2-stable_linux.x86_64`
(the project targets Godot 4.7 — see `project.godot config/features`; `Godot_v4.6.3` also
sits in that dir). `$proj` on Linux is `<checkout>/RetroXR`. Note Godot
4.7 promoted "Not all code paths return a value" to a hard parse error for `Variant`-returning
virtual overrides (bit two `_property_get_revert` overrides in godot-xr-tools — fixed with a
trailing `return null`).

### 1. Compile / import check (catches parse, shader & scene-load errors)
```bash
"$godot" --headless --path "$proj" --editor --quit
```
This reimports resources, recompiles every GDScript, compiles shaders, and (critically)
**regenerates the global `class_name` cache**. Run it after adding or renaming any
`class_name`, or a probe that references the new class will fail with
`Could not find type "X" in the current scope`. Filter output for
`SCRIPT ERROR|Parse Error|SHADER ERROR|Failed to load|Failed to instantiate`.

### 2. Functional probe (exercises real code paths)
Write a tiny `probe.gd` (`extends Node`) + `probe.tscn`, run it, print `[probe] ...`
lines, then `get_tree().quit(0)`:
```bash
"$godot" --headless --path "$proj" res://probe.tscn 2>&1 | grep -a "\[probe\]"
```
Always **delete the probe `.gd`/`.tscn` (and generated `.uid`/`.import`) when done.**
Include a `get_tree().create_timer(5.0).timeout.connect(...quit)` safety net so a probe
can never hang the run.

### Gotchas
- **Warnings are treated as errors** for some warnings — notably inferring a `:=`
  variable from a `Variant` (e.g. `var x := ClassDB.instantiate(...)`). Use an explicit
  type (`var x: Object = ...`). `unsafe_method_access` (calling a method not on the
  static type, i.e. duck typing) is **not** an error, so it's fine.
- **A `SubViewport` with `render_target_update_mode = ALWAYS` hangs a headless run**
  (no GPU to service the render target). It renders fine in a real session — just don't
  drive extra `await process_frame`s over such a viewport in a headless probe; test the
  logic/wiring instead and eyeball the visual on-device.
- **Known headless noise to filter out** (pre-existing, not your change): OpenXR
  `xrCreateInstance failed`, missing GDExtension DLLs in the `template_debug` path
  (`libgodotopenxrvendors`, `godot-pdfium`, `libretro_godot`), `.NET Sdk not found`, and
  `xr_staging_shim.gd ... is_xr_class ... placeholder instance`. Grep these out.
- **A renamed/deleted source texture can leave the editor filesystem cache
  pointing at a dead `.godot/imported/*.ctex`.** Re-running an ordinary import
  may keep trusting that stale entry. Move/delete
  `RetroXR/.godot/editor/filesystem_cache*`, then run `--editor --import --quit`;
  Godot rebuilds the class cache and replacement texture imports. This is
  generated local state, not a file to commit.
- **A `.tscn` `Transform3D` lists the basis by ROWS**, not the columns the
  `Transform3D(x_axis, y_axis, z_axis, origin)` constructor takes. For a rotation the
  two differ by a transpose — an inverse — so a hand-written rotation comes out
  backwards. Copyable forms: `R_y(+90)`, local +Z → world +X, is
  `0, 0, 1, 0, 1, 0, -1, 0, 0`; `R_y(-90)` is `0, 0, -1, 0, 1, 0, 1, 0, 0`;
  `R_x(-90)` is `1, 0, 0, 0, -4.371139e-08, 1, 0, -1, -4.371139e-08`. **Never check one
  against a 180° or an otherwise symmetric matrix** — those read the same under both
  conventions and confirm whichever reading you already had, which is how the Wii
  ports and then the Game Boy link socket were both authored inside out. Print
  `node.transform.basis.x/.y/.z` from a throwaway probe and compare it with what you
  meant, before rendering anything.
- **PowerShell buffers `& $godot ... | Out-String` until the process exits**, so a
  backgrounded run shows an empty output file until it finishes. The Bash tool with
  `timeout 90 "$godot" ... 2>&1 | grep` streams and bounds the run — prefer it.

### Verify with a check that can fail

**A green check that cannot tell the two outcomes apart is not a check.** Ask what
the WRONG version would look like before believing the right one; if the answer is
"the same", that is not the check to use.

Two of them in a row cost the Game Boy link socket a whole round trip. It was
authored facing INTO the shell, and the render looked identical because a
rectangular port recess is symmetric, while the room probe passed either way because
a snap zone does not care which way round a plug goes in. Both were green and
neither could have gone red. What settles a facing is a printed basis, or a render
of something ASYMMETRIC — a seated lead, not an empty socket.

**And read the note before authoring, not after the bug.** The gotchas above and the
session memory are each one line in an index, which is enough to recognise a topic
and not enough to act on; acting from the summary is how the same mistake arrives a
second time. `.tscn` transforms, a model's facing and a port's seat all have notes,
and all three were sitting in the index while that socket was written backwards.

`libretro-godot/tests/run_tests.py` is the small Godot-free C++ harness for the
link coordinator and sensor-id encoding.

**`RetroXR/Tests/archive_tests.tscn` is the one GDExtension with a self-checking
suite**, because `RommArchiveExtractor` is the one that needs no display, codec,
core or server. 83 checks over a well-formed archive, the plan validation, a
damaged/truncated/non-ZIP/missing one, cancellation, `FirmwareInstaller`'s unpack of
a support archive (`firmware/`) and of a speech pack's remapped parts (`pack/`); every
fixture is built under `user://` at run time, so it carries no binary.

Two of its cases are hand-built STORED archives, and that is not fussiness.
**For a DEFLATED member the declared CRC is handed to `StreamPeerGZIP` as a gzip
trailer**, so a corrupt payload dies inside decompression and
`RommArchiveExtractor`'s own `crc != entry.crc32` comparison is never reached — a
"bad CRC" case built by flipping payload bytes passes with that check compiled
out. Only a STORED member isolates it. `ZIPPacker` always deflates, hence the
hand-rolled fixture.

The other four extensions stay probes and rebuild-plus-load: `verlet-rope` has
the bit-exact oracles in `Tools/rope/`, and `vlc-godot`, `godot-pdfium` and
`metaxr-audio` all need a display, a codec or Meta's blob. Adding a suite for
one of those would mean a red run that depends on the machine it ran on.


### 3. Capturing a real screenshot on Linux (for visual validation)
`--headless` uses the dummy renderer — it **cannot** produce a screenshot (a probe that awaits
`RenderingServer.frame_post_draw` just hangs; `get_image()` is blank). To actually render a
RetroXR scene on this box, run Godot **on the real display** (`DISPLAY=:0`,
Vulkan Forward+ — a window briefly appears on the desktop, ok'd for validation) and draw into a
**`SubViewport`**, not the window viewport (the uncomposited window swapchain reads back as
clear-colour only). Xvfb does not work here (bwrap/glycin abort in the sandbox). Recipe:
```gdscript
var sv := SubViewport.new()
sv.size = Vector2i(1000, 750)
sv.own_world_3d = true
sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
add_child(sv)   # add WorldEnvironment + DirectionalLight3D + your scene + Camera3D as children
cam.current = true              # make_current() does NOT work inside a SubViewport
for i in range(8): await get_tree().process_frame
await RenderingServer.frame_post_draw
await get_tree().process_frame
sv.get_texture().get_image().save_png("res://shot.png")
```
Run `DISPLAY=:0 "$godot" --path "$proj" res://shot.tscn` (import first with `--headless … --import`).
Then **surface the PNG inline via the Read tool** — the user sees it through the Claude app (the
terminal itself doesn't paint it). Don't save renders to a folder; delete the probe + PNG when done.
