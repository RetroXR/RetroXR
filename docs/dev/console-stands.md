# Console stands

A **console stand** is a thing a console is *mounted in*, and it decides how the
console stands: a fat PS2 on its left side in Sony's SCPH-10040, a Wii upright in
the RVL-017 cradle, a Virtual Boy on its bipod. Added 2026-10-30 as the concept,
before any stand has a model: the two shipped stands are primitive stand-ins.

## The pieces

| piece | file | what it is |
|---|---|---|
| `StandCatalog` | `RetroXR/Scripts/Data/systems/stand_catalog.gd` | the rows (`const _ROWS`) + a mod overlay (`static var`); which stands take which console, on which face, where |
| `StandFoot` | `RetroXR/Scripts/Objects/stands/stand_foot.gd` | the grab point a console is held by: one per face a stand rests it on |
| `ConsoleStand` | `RetroXR/Scripts/Objects/stands/console_stand.gd` + `RetroXR/Scenes/Objects/stands/console_stand.tscn` | the stand object: a pickable built from its row, carrying the `StandMount` snap zone |

It is the inverse of the 32X's Model 2 spacer (`AccessoryMount`, §2j′): there the
UNIT holds the accessory; here the STAND holds the console. It is
`SpeakerStand`'s arrangement: the stand records what is on it, and `RetroSystem`
knows nothing about stands. No line of `system.gd` changed.

## How a console is posed

`XRToolsSnapZone` puts the held object's **grab point** on the zone (the object
is posed `zone * grab_point^-1`); with no grab point it keeps the object's own
rotation, which a stand cannot have. So a console grows a `StandFoot`, an
`XRToolsGrabPointSnap`:

- at the middle of one face of its **measured** box (`RetroSystem.body_aabb()`), so
  a stand fits a stand-in and a detailed shell alike;
- with +Y pointing INTO the console (`StandCatalog.foot_transform`), so composed
  inverted the face lies on the seat, outward normal down;
- the front stays the front for bottom/top/left/right; for back/front the top
  faces the player;
- `require_group` = `console_stand_mount_<face>`, which only a `StandMount` for
  that face joins: no other zone sees it, and a stand that stands a console on
  its side cannot take it by its underside;
- weighted ×1000 in `can_grab`, so a plain grab point that happened to be nearer
  never wins.

Feet are built **lazily**: the mount's `snap_filter` (`ConsoleStand._accepts`)
calls `StandFoot.build_for`, and the zone runs its filter before both the ghost
preview and the drop. A console no stand takes grows nothing. Like
`ExpansionFoot`, a foot is pushed onto the pickable's `_grab_points` by hand
(XRToolsPickable collects them in its own `_ready`, before the model is measured).

## A row

```gdscript
"ps2_vertical_stand": {
    "label": "Vertical Stand (SCPH-10040)",   # the spawn card's row
    "fits": ["ps2"],             # systemids and/or model ids (a model id is narrower)
    "face": "left",              # bottom top left right back front, of the console's box
    "seat": Vector3(0, 0.008, 0),   # where that face's middle goes, stand frame
    "seat_rotation_deg": Vector3.ZERO,   # optional: a tilt (Virtual Boy), a lean
    "parts": [ {"box": Vector3(...), "position": Vector3(...)},
               {"cylinder": [radius, height], "position": ...} ],
    "scene": "",                 # optional authored model; empty = primitive
    "color": Color(...), "mass": 0.14,
}
```

`parts` are ALWAYS the collision (and the pointer area), and the look only when
there is no `scene`: an authored model is only the look, so a stand whose GLB is
missing still stands and still holds. **The id is persisted** (`stand_id` in a
save): replace a stand-in with its model by giving the row a `scene` and keeping
the id.

### Which face — measure, do not assume

The face is of the console *as the room holds it*, not as the hardware is drawn.
The Wii was the trap: `wii_primitive.tscn` is AUTHORED upright, and its root turns
it onto its side (rows `0,-1,0 / 1,0,0 / 0,0,1` = authored +Y → host −X), so the
console in the room is 159 × 44 × 216 mm and stands up again on its **right**
face. `bottom` (the first guess) left it lying flat in the cradle. Print
`body_aabb()` and the model's basis from a probe first; `console_stand_tests`
`seat/` asserts the up direction, and goes red on `bottom`.

## The shipped stand-ins

Neither stand's dimensions are published (searched 2026-10-30), so both are
estimates around the consoles' real sizes:

- **`wii_stand`** — RVL-017 trough (170 mm, walls 0.5 mm clear of a 44 mm Wii)
  on the round RVL-019 plate (130 mm, an estimate). Face `right`.
- **`ps2_vertical_stand`** — SCPH-10040, fat PS2 only: in reality it fixes to
  the console's underside with one coin-slot screw (not modelled; seated is held)
  and stands it on its LEFT side, power/reset up, USB and i.LINK at the bottom.
  A foot 110 × 180 mm and an arm up the underside, drawn for the real 78 mm. The
  PS2 has no shipped model: without the `xenu.ps2` pack it is the generic
  300 × 100 × 250 mm box, which the arm sits inside.
- **Virtual Boy: no row.** `virtual_boy_primitive.tscn` authors its own bipod,
  so a stand would double it. A stand for the detailed shell is a row with
  `fits` naming that model's id, `face: "bottom"` and the bipod's tilt in
  `seat_rotation_deg`.

## Save, spawn, netplay, mods

- **Save**: entry type `console_stand` with `stand_id` and `console` (a ref).
  `_load_console_stand` sets the id before `_ready`; a stand nothing defines any
  more (its mod is gone) is skipped with a warning, and its console keeps its own
  saved pose. `restore_console` waits up to 30 frames for the console's body to
  be measured before seating it.
- **Spawn**: token `console_stand:<id>` (`SpawnCatalog.TokenKind.CONSOLE_STAND`),
  offered on the card of every platform it fits (`StandCatalog.stands_for_card`).
- **Netplay**: a seated console follows its carrier on every peer
  (`object_sync` skips a zone-snapped body). The act of seating is NOT announced
  (no `EV_*`), the same as a loudspeaker onto a `SpeakerStand`: a client mounting
  a console is not seen by the others. OWED.
- **Mods**: `ModApi.register_console_stand(id, row)` adds one (id namespaced
  `mod:name`). `ModApi.override_console_stand(shipped_id, changes)` gives a
  SHIPPED stand its model in place: `changes` is MERGED over the row
  (`StandCatalog._overrides`), the id is kept so saves resolve, one mod per stand,
  and the merged row is validated as a whole. Both are withdrawn with the mod
  (`StandCatalog.drop_mod`), which brings the primitive back. Author docs:
  `docs/modding.md` "Console stands".

## Physics

Seated, the console's shapes are lent to the stand (`SeatedCollision.lend`) and
the two are exempt from each other (the console stands IN the cradle): carry the
stand and the console comes with it; reach for the console and it comes off the
stand, taking its lent shapes back.

## Checks

- `Tests/console_stand_tests` (headless): `catalog/`, `override/` (a mod's model for a shipped stand), `foot/` (every face lands
  its middle on the seat, faces down, the box above, front kept, no mirror),
  `seat/` (a real Wii and PS2 mounted at 0 mm, the right way up, refused by the
  wrong stand), `save/`.
- `Tools/room/console_stand_probe` (windowed, `--out=`): stills of both, empty
  and mounted, and the face-to-seat distance.

**OWED**: the real models (RetroXR-models), a headset (lowering a console in by
hand, lifting it off), a seat event for netplay, and the Quest.
