# Modding RetroXR

A mod is **one file** dropped in a folder. It can add consoles, whole platforms,
rooms, props, television cabinets and controllers — geometry, procedural animation
and code — or replace something RetroXR ships.

**Nothing here is frozen.** See [Stability](#stability) before you build anything
you intend to maintain.

## Installing one

**From inside RetroXR:** open the menu's **MODS** tab. The first time, it shows
mod.io's terms and asks nothing of mod.io until you agree to them. **Browse** then
lists the mods published for RetroXR on [mod.io](https://mod.io/g/retroxr); pick
one and press Download. It is fetched and checked, and you are shown what it
replaces before you install it. It then appears under **Installed**, where you
enable it and press **Apply now**.

**Packs** lists mod packs: lists of mods somebody put together on mod.io. One
press downloads a pack's mods and one answer installs them. Removing a pack
removes the mods it brought, and leaves any you had installed on its own.

**By hand:** put the file in the mods folder:

| platform | folder |
|---|---|
| Windows | `%USERPROFILE%\retroxr\mods\` |
| Linux, macOS | `~/retroxr/mods/` |
| Quest / Android | `/sdcard/Android/data/com.xenu.retroxr/files/mods/` (`adb push`-able) |

Then open **MODS → Installed** (it looks in the folder again each time it is
shown), enable it, and press **Apply now**.

**Apply now** loads a newly enabled mod without a restart. The room you are
standing in is rebuilt behind the loading screen, with everything in it put back
where it was, so your mod's hooks see the room being built just as they do at
launch. Switching off, updating or removing a mod that is already running cannot
happen in place (see [Limits](#limits)), nor can loading one that replaces a file
RetroXR ships; for those the button reads **Restart now**, and RetroXR restarts
itself and comes back to the same room. Neither works during a netplay session.

Mods are **disabled when they arrive**. A mod runs with the app's full
permissions — your ROMs, your saves, your RomM credentials, the network — and
Godot has no sandbox to put one in, so nothing loads until you say so. Enabling
is the whole of the trust decision, and it is yours.

RetroXR does not make or host mods. The Browse tab shows what authors have
published on mod.io, which scans what it hosts; a file you copy in by hand has
been through nothing but RetroXR's own checks. Either way the contents are
between you and whoever made it, and RetroXR never sends a mod from one player to
another.

Updating or removing a mod that is currently running, like enabling one, takes
effect the next time RetroXR starts.

## What a mod looks like

```
xenu.snes.zip
    res://mods/xenu.snes/mod.json        the manifest
    res://mods/xenu.snes/thumbnail.png   the preview image: 16:9, at least 512x288
    res://mods/xenu.snes/mod_main.gd     the entry script
    res://mods/xenu.snes/...             everything else it ships
```

`.zip` is the recommended format. Godot mounts a zip resource pack exactly as it
does a `.pck`, and a zip can be read member-by-member *without being mounted* —
which is how RetroXR shows you a mod's name, version and thumbnail while it is
still disabled. `.pck` works too, with one limit: its `mod.json` and thumbnail
must be stored uncompressed, or the pack is refused with a message saying so.

### mod.json

```json
{
  "id": "xenu.snes",
  "name": "Super Nintendo",
  "version": "1.0.0",
  "author": "Someone",
  "description": "An SNES, its pad and a cartridge.",
  "api_version": 1,
  "entry": "res://mods/xenu.snes/mod_main.gd",
  "priority": 0,
  "claims": [],
  "platforms": ["Windows", "Linux", "macOS", "Android"],
  "dependencies": ["xenu.usba>=0.1.0"]
}
```

- **`id`** — lower-case, `a-z 0-9 . _ -`. Must match the single `res://mods/<id>/`
  folder your pack contains; the loader takes the id from the file list rather
  than trusting the manifest.
- **`api_version`** — see [Stability](#stability).
- **`priority`** — load order, low first; ties broken by id. Only matters when two
  mods touch the same thing.
- **`claims`** — paths **outside** `res://mods/<id>/` your pack writes. Empty is
  the normal case and the safe one.
- **`platforms`** — omit for "everywhere".
- **`dependencies`** — other mods yours needs, by id: `"xenu.usba"`, or
  `"xenu.usba>=0.1.0"` for at least that version. Omit for none. See
  [Mods that need other mods](#mods-that-need-other-mods).

There is no field naming the pack file: the manifest is *inside* it.

### Mods that need other mods

A part many mods share, a plug model say, can be a mod of its own that the others
list in `dependencies`, rather than a copy in each. The GunCon 2 does this: its
USB-A plug is `xenu.usba`'s, and its `.tscn` names
`plug_mesh_path = "res://mods/xenu.usba/model/usb_a_plug.glb"`. What a dependency
guarantees:

- **It is mounted first**, whatever either mod's `priority`, so its files are there
  when your entry script runs and when your scenes load.
- **Without it, your mod is not mounted at all.** Missing, too old, switched off,
  refused, or failed to load: your mod's page in the Mods tab says which, and
  nothing of yours runs half-dressed. (A path into another mod that is not there
  loads nothing, silently, so this is what keeps a plug from quietly turning into
  the generic one.)
- **Switching your mod on switches on what it needs**, and switching a dependency
  off switches off what needs it; the page says so beside the switch.
- **The in-game Mods tab downloads what your mod needs with it**, in the same
  review, from mod.io's own dependency list. So on mod.io, also add the mods it
  needs as **dependencies of your mod page** (Edit mod → Dependencies): the game
  asks mod.io, not your `mod.json`, what to fetch. The two lists should agree.
- A pack (collection) need not list them: installing it fetches what its mods need
  as well.

A mod that only carries parts for others registers nothing: its page says what
needs it. Two mods that need each other never load. Use another mod's files only
by the paths it documents: they are its, and it may move them in a new major
version, which is what `>=` in your `dependencies` is for.

### The namespace rule

Everything your pack ships lives under `res://mods/<id>/`. A pack containing
anything else is **refused outright** unless that path is in `claims`.

This exists because a resource pack can silently replace any file in the game. A
mod that claims nothing is mounted with replacement switched off and provably
cannot touch a shipped file.

You need a claim only when a subsystem resolves by convention path — system icon
art is the usual case, since `SystemIcons` looks for
`res://Textures/SystemIcons/<systemid>.svg`. The Mods page splits your claims into
those that *add* a new file and those that *shadow* a shipped one, and shows the
second as a warning.

Three files can never be shipped, claimed or not: `project.binary`,
`project.godot` and `.godot/global_script_class_cache.cfg`. A mod exported from
its own Godot project picks these up automatically and any of them would replace
the running game's own — the class cache decides what every `class_name` in
RetroXR resolves to. Strip them, or use the packer below, which excludes them.

## The entry script

```gdscript
extends RetroMod

func register(api: ModApi) -> void:
    api.register_model({
        "id": "xenu.snes:snes",
        "platform": "snes",
        "label": "Super Nintendo",
        "scene": "res://mods/xenu.snes/snes.tscn",
        "requires": ["res://mods/xenu.snes/snes.glb"],
    })
```

`register()` is called once, while the room is still being built. A mod that
needs to act later asks for a hook rather than staying resident.

**Ids you introduce must carry your mod's prefix** — `xenu.snes:snes`, not `snes`.
Model ids, room ids and prop types are flat global namespaces that end up written
into save files, so an unprefixed id could collide with a shipped one or with
another mod, and the collision would surface as a save restoring the wrong object.
Registration refuses an unprefixed id.

Every call returns `false` and records a problem rather than throwing. Problems
appear on the Mods page against your mod's name.

## Adding a console

A row is `{id, platform, label, scene | script, handheld?, requires?}` — exactly
one of `scene` or `script`. `requires` lists assets that must be present for the
row to be offered; a row whose assets are missing is hidden rather than broken.

Your model script extends **`RetroSystemModel`**, which is the console extension
point: about forty-five optional virtual methods that `RetroSystem` calls in a
fixed order as it builds the machine. Override what you need and ignore the rest.

The reference implementation is `Scripts/Objects/system_models/nes_model.gd`. It
shows the shape of a detailed console: a GLB instanced as a child named `Shell`,
`Marker3D` seats for ports and cartridges, `VRHinge` / `VRSpringLatchedHinge` /
`VRSlider` for anything that moves, `create_tween()` for scripted travel, a
`PcmOneShot` pool for switch sounds, and `prep_power_light()` for the LED.

Two things you get free by using the shipped widgets rather than animating by
hand: your lid, flap and switches **save and restore automatically** (persistence
walks any spawned object for `VRHinge`/`VRKnob`/`VRSlider` and records them by
node path), and they replicate correctly in a shared room.

### Replacing a shipped console

```gdscript
api.override_model("nes", {...})
```

Replaces the row in place, keeping its id so existing saves still resolve to it.
No file replacement and no claim needed. This is the recommended route.

The alternative — claim a shipped asset path and ship a replacement, e.g. a new
`nes_console.glb` — keeps the shipped logic and swaps only the geometry.

A row you replace brings its own working parts: whatever the shipped scene had
that the room talks to is gone unless your scene has it too. Most are plain to
see (a link socket, a cartridge slot). One is not: **the Game Boy Color's
infrared port.** The shipped model carries an `IrPort` node
(`res://Scripts/Objects/cables/ir_port.gd`) on its window, and it is the only
thing that lets two of them link by pointing at each other. A replacement
without one has no infrared at all, and nothing says so. Put one on your
model's window, looking out of the top end along its own **-Z**, and light the
window from its `link_changed(live)` signal if you want the glow: `live` is
true only while both cores are on the bus. The Game Boy Color in RetroXR-models
(`xenu.gbc`, `_seat_ir_port`) seats it on its GLB's `IRWindow`, and lays its glow
OVER the window (`material_overlay`) because its own paint code owns the window's
material.

### Colors and editions on one row

A machine sold in ten colors is one row, not ten. Give the row a `variants` list
and the player holds the row to pick from a panel of swatches; pressing it spawns
the first, as before:

```gdscript
row["variants"] = [
    {"id": "indigo", "label": "Indigo", "color": Color8(56, 46, 118)},      # as it comes
    {"id": "jet_black", "label": "Jet Black", "color": Color8(40, 41, 45)},
]
```

`id` is what is saved, so it is permanent; `label` and `color` are the swatch. The
first entry is your model as it comes, and is saved as a row with no variant at all.

The game only carries the id to what it spawns. What it MEANS is yours, and there
are three places to read it, by what the row is:

- **Your console** (`register_model`, `override_model`): override
  `apply_variant(id)` on your model script. It is called once, after the model is
  in the tree, and only when a variant was asked for. Paint the WHOLE model, not
  the shell alone: a lid you hung on a hinge is no longer under the shell.
- **A row you add** (`add_peripherals`): put `variants` on the item. Your object
  has it as metadata before it enters the room: `get_meta(&"model_variant", "")`,
  readable from `_ready()`.
- **A row of the game's that you only dress** (`api.dress`): offer it the list by
  its spawn token, `api.offer_variants("n64_controller", variants)`, and read the
  same metadata in your hook.

An id you do not recognize is a save that has outlived your list: leave the thing
as it comes. A variant can be more than paint. One that is a different shell (a
regional pad, a special edition with its own print) swaps the shell before your
script looks for its parts on it. One that is a different machine says so to the
game: a shell that makes the Wii Remote a Wii Remote Plus sets
`motion_plus_inside` on it, and the remote is announced to a console as one with
a MotionPlus whether or not the dongle is in its socket.

To retire rows you once shipped one per color, keep them registered with
`"unlisted": true`: old saves still resolve, and the card stops listing them.

## Adding a whole platform

A console model alone is not a usable platform. `api.register_platform()` takes
the lot and tells you which pieces are missing, because a platform assembled from
four of the six fails much later and far from the cause:

```gdscript
api.register_platform({
    "systemid": "my_console",
    "system_info": load("res://mods/xenu.mod/my_console.tres"),   # SystemInfo
    "models": [ {...} ],
    "pad_art": {...},          # or the Controls remap page has no anchors
    "media": {"cart_size": Vector3(0.09, 0.08, 0.01)},
    "scraper_id": 75,          # or its carts never get art — see below
})
```

Tile art needs no call: ship `res://Textures/SystemIcons/<systemid>.svg` as a
claim and `SystemIcons` finds it.

## Cartridges, discs and scraped art

Three separate things, and only two are yours.

**Sizing** is `api.register_media(systemid, {...})`: `cart_size`, `floppy`,
`disc_diameter`, `disc_finish`, `slot_load`, `front_tray`. The *presence* of
`disc_diameter` is what makes a platform a disc system. Without this your carts
come out a default size and your discs do not exist.

**A real cart model** is optional — with none, the cart is a procedural box sized
from `cart_size`. If you ship a GLB, two rules: the body runs **+Y from the
connector with the label on +Z**, and the swappable label face **must be named
`media_label`** or scraped art never lands on it.

**Scraped art is not yours to ship.** Box, wheel, label and manual art is the
player's own per-ROM data, living outside the game entirely under
`<roms>/<systemid>/media/`, fetched by the in-app scraper. What your platform
needs is to be **mapped**: `api.register_scraper_system(systemid, systemeid)`
against a screenscraper.fr system id. A platform with no mapping can never be
scraped, and the symptom is silent — the carts are simply blank, for ever.

### Cartridge shells, by game and region

The game gives its own cartridges the body and colour each game shipped in: a
Japanese N64 ROM gets the Japanese shell, the gold Zelda gets gold. A mod can do
the same for a system, with its own models:

```gdscript
func register(api: ModApi) -> void:
    api.register_cart_shell("n64", {
        "bodies": [
            {"id": "xenu.n64cart:usa", "label": "USA / PAL",
             "model": "res://mods/xenu.n64cart/usa.glb", "size": Vector3(0.116, 0.0754, 0.0186)},
            {"id": "xenu.n64cart:jpn", "label": "Japan",
             "model": "res://mods/xenu.n64cart/jpn.glb", "size": Vector3(0.116, 0.0754, 0.0186)},
        ],
        "tint": ["Shell_Front", "Shell_Back"],
        "palette": "res://mods/xenu.n64cart/shells.tres",
        "choose": _choose,
    })

static func _choose(info: Dictionary) -> Dictionary:
    var body := "xenu.n64cart:jpn" if info["market"] == "jp" else "xenu.n64cart:usa"
    return {"body": body, "preset": "xenu.n64cart:grey"}
```

- **`bodies`** are the shapes. The first is what a ROM gets when nothing chooses.
  `size` is the model's **true bounds** in metres: the fit is per axis, so a
  rounded number stretches the shell. A body's `id` is saved with a cartridge the
  player forced it on, so it is namespaced and permanent.
- **`choose`** is asked once per ROM and returns its body id and shell colour;
  leave either out, or return `{}`, for the default. It is handed
  `{systemid, rom_path, file, region, market}`: `region` is what the scraper
  wrote, `market` is `"us"`, `"eu"`, `"au"`, `"jp"` or `""` (for an N64 ROM the
  header is read when the scraper said nothing). Anything else, a header title
  say, read from `rom_path` yourself. **It must be a `static func`**: your entry
  object is not kept after `register()`.
- **`tint`** names the materials on your bodies that are shell plastic. Those, and
  only those, are what a colour is painted on: labels, contacts and screws keep
  their own. It is what makes your shells colourable at all. With it a held ROM row
  offers the colour mixer (and the metal flake switch); without it your models
  always wear their own materials and no colours are offered for them.
- **`palette`** is a `CartridgeShellPalette` resource: named colours, shown as
  swatches beside the mixer, and what `preset` names. It needs `tint`.
- **`uv_label`**: your label mesh is UV-mapped as the sticker itself (UV 0-1 is
  the art). Without it the art is laid over the mesh as a quad. Either way the
  mesh is called `Label`.

The model is in the game's cartridge frame: connector toward -Y, label on +Z.

With that the game does for your shells what it does for its own: fits each body
to its size, loads it before the cartridge spawns, puts the scraped label on it,
offers a **Body** row and your colours when a ROM row is held, and saves a body
or colour the player forced. A colour the player picks wins over the one
`choose` gave: a mixed colour first, then a swatch, then yours.

Two rules. It **replaces** the game's own shells for that system, all of them: a
mod for the N64 answers for every N64 cartridge. And **one mod holds a system**;
a second is told who has it on its page in the MODS tab and is not used. A
console seats a cartridge by the system's size, so bodies much larger than the
real cartridge will not sit in the slot.

## Rooms, props, cabinets and controllers

```gdscript
api.register_room({"id": "xenu.mod:attic", "path": "res://mods/xenu.mod/attic.tscn",
    "menu_title": "The Attic", "has_slots": true})
api.register_object("xenu.mod:crate", "res://mods/xenu.mod/crate.tscn",
    {"label": "Crate"})
api.register_tv_shell("xenu.mod:portable", "res://mods/xenu.mod/portable.tscn",
    "Portable TV")
api.add_peripherals("nes", [{"label": "My Pad", "spawn": "retro_controller"}])
```

A **room**'s own `.tscn` must set its `XRInit.scene_id` to the same namespaced id.
`has_slots` should be true for a room the player furnishes and false for one whose
contents you authored, or a save slot will restore spawned objects into a room
that already has its own.

A **prop**'s type string is written into save files — permanent once anyone has
used it. Renaming it orphans every copy in every slot.

A prop can **snap onto** another: give the host an `XRToolsSnapZone`
(`res://addons/godot-xr-tools/objects/snap_zone.tscn`) and the prop a group its
`snap_require` names, and a prop released over it is held there and moves with
it. A save records which zone holds each prop -- the host and the zone's path
inside it, or the zone's own path for one that is part of a room -- and a load
puts it back in that zone, so a stack of props comes back a stack.

The game's own objects work the same way in **your** zones: a console in your
stand, a pad on your rack. A zone counts as yours when it is inside a prop you
registered, or when it is in the `mod_zone` group -- put it there for a zone your
hook hangs on one of the game's objects, or one authored in your room. The
game's own sockets are not yours, and what sits in them saves as it always did.
A zone's `snap_filter` (`func(obj) -> bool`) narrows what it takes, e.g.
`func(o): return o is RetroSystem and o.systemid == "wii"`.

The zone's **path is part of the save**: rename or move it and what it held comes
back loose where it was left. So does anything whose host's mod is gone. Live
netplay does not yet send a snap as it happens; a player joining later gets it
from the room's snapshot.

A **cabinet** extends `RetroTVShell`: geometry plus `Marker3D` seats, while every
functional part stays on the television. Two optional overrides, both defaulting
to doing nothing:

- `screen_shader()` — **null means the stock CRT**, which is what you want unless
  your set genuinely looks different. A shader of your own should be `cull_back`,
  as the stock ones are: drawn double-sided, the far half of a curved tube shows
  through the near half to anyone standing at the side.
- `on_buttons_built(buttons)` — the bezel buttons, so you can adorn them or hang
  your own sounds off them. The stock sets have no button audio at all, so this is
  adding rather than overriding.

A cabinet can seed the stock CRT shader from its `_ready()` using
`(get_parent() as RetroTV).set_crt_defaults({"crt_mask_mode": 2})`.
Only known CRT keys are merged; saved picture values and player edits take
priority, even when restored before the cabinet enters the tree. Use this instead
of `set_crt_params()` for defaults so loading a room cannot reset its picture.
Registered cabinets appear in **SPAWN > TVs** under their registration label.

A cabinet that puts its own tube on the set (`screen_mesh().mesh`, recentred on
the `ScreenSeat`) gets the picture on that mesh's FRONT faces only. Leave it
wound facing out of the cabinet, the way an exporter writes it; wound the other
way it is not drawn at all.

#### A TV/VCR or TV/DVD combination

A cabinet can have the VCR, the DVD player or both **built in**. Add a `Marker3D`
named `VcrSeat` and/or `DvdSeat` to the shell scene. Nothing else needs a script.

- The marker is where the deck's body goes: the centre of the stock deck's box,
  with its tape slot or disc tray 125 mm along +Z and its buttons on top. Put it
  where that box would sit inside your cabinet, its front flush with yours.
- The deck takes the composite input after your phono row: VCR first, then DVD.
  `av_inputs = 1` with both decks gives COMPOSITE 1, VCR, DVD. SOURCE shows the
  deck's name, and the back panel prints no sockets for a deck's input. Phono rows
  and decks share four inputs; a deck with none left is not built, and the log
  says so.
- The deck's grey box is hidden, because your cabinet is its housing. Its slot,
  buttons and the VCR's clock stay. Set `deck_housing = true` while laying out, to
  see where the boxes land.
- The stock decks keep their buttons on **top**, which is buried inside a
  cabinet. Add `VcrControls` / `DvdControls` to carry the panel out. The marker is
  the centre of the deck's top face, and its +Y is the way the caps face. Turned
  `R_x(+90)` (`.tscn` rows `1,0,0, 0,0,-1, 0,1,0`), it stands the panel up on
  the front, with the row nearest the deck's front edge lowest.
- The deck is part of the set. It cannot be picked up, carries no lead, is saved
  with the set and follows it over netplay. What is in its slot or tray is saved
  too. The remote and the options menu reach it by pointing at it, as they would
  a loose deck.

`res://Tests/fixtures/combo_tv_shell.tscn` is a complete example with both decks
and both control panels.

A **controller** is a scene rooted at `RetroController`, and a **light gun** one
rooted at `LightGun`. Persistence already records its scene path and falls back
to the generic pad if your mod is gone; nothing extra is needed. What it plugs
into is below.

### Sockets, plugs and what fits

Every socket and every plug in the room has a **connector**, and a plug goes into
a socket when the two name the same one. That string is the whole agreement: the
game does not have to have heard of it. You set it on the **node, in the scene**,
with no script of your own:

```
; a console's AV socket (in your console's port scene)
[node name="AvMultiOut" instance=ExtResource("snap_zone")]
script = ExtResource("multi_av_port.gd")   ; the game's class: picture + stereo
connector = "ps2_av_multi"

; the console end of a lead (in your lead's scene); the far ends are left as
; they come, "composite_plug", phono plugs for the set
[node name="PlugA0" type="RigidBody3D" parent="."]
script = ExtResource("rca_plug.gd")
connector = "ps2_av_multi"
```

The connector decides only **what fits**. What travels through it is the class
you use: `MultiAvPort` carries a picture and both audio channels through one
hole, `RcaPort` one signal, `LinkPort`/`PsxLinkPort` a link cable, and the plugs
are `RcaPlug` (an A/V lead) and `LinkPlug` (a link lead).

**The game's own connectors** -- use these to fit what the game ships:

| connector | what it is |
|---|---|
| `composite_plug` | a phono jack or plug (the default) |
| `coax_plug`, `vga_plug`, `trs_plug` | RF, VGA, 3.5 mm stereo |
| `n64_av_plug` | Nintendo Multi Out (Super NES, Nintendo 64, GameCube) |
| `wii_av_plug` | the Wii's AV Multi Out (the same shell, other pins) |
| `dc_av_plug`, `genesis_av_plug` | Dreamcast AV OUT; Genesis Model 2 A/V OUT (a Saturn mod uses it too) |
| `ps2_av_multi` | PlayStation and PlayStation 2 AV MULTI OUT |
| `link_plug`, `gg_link_plug`, `ws_link_plug`, `comlynx_plug`, `ngp_link_plug`, `vb_link_plug` | handheld link sockets |
| `psx_link_plug`, `saturn_link_plug`, `jag_link_plug`, `ilink_plug` | console link sockets |
| `nema_5_15_plug`, `iec_c13_plug`, `iec_c7_plug`, ... | power |
| `<systemid>_controller` | a console's controller port, except those shared below |
| `playstation_controller` | PlayStation and PlayStation 2 |
| `gamecube_controller` | GameCube, and the Wii's GameCube ports |
| `de9_controller` | Atari's DE-9: Atari 2600, Master System, Genesis |
| `wii_extension` | a Wii Remote's expansion port |
| `usb_a` | a USB-A socket: the PlayStation 2's two on its front take a GunCon 2 |

A connector names an interchangeable family -- plugs that fit AND work -- not a
machine: a Super NES lead works on an N64, so they share one; a Wii lead fits the
same shell and gives no picture, so it has its own.

**Naming your own.** Inside one mod the name can be anything. Between two it has
to be the same, and nobody hands it out: if you model a console and somebody else
models its lead, you each derive it from the hardware the same way,
`<systemid>_<socket>` in lower case (letters, digits and `_ . : -`):
`saturn_av_out`, `neogeo_av_out`. A socket only your own mod should ever fit is
namespaced, `"<mod id>:<name>"`. Never rename one you have published: it is
inside every lead that fits it.

**A pad or a light gun** names the console it was made for with `systemid` on its
root node, and its plug is that console's controller port -- so it also goes into
every console that shares the port: a pad for `"ps2"` into a PlayStation, a
Genesis pad into a Master System. One whose plug is something else says so with
`connector` (`"wii_extension"` for a Wii Remote extension). A gun that names
neither fits every console's port, as the game's own does.

**A console** lists the cable sockets on its back panel on its row, by connector.
The spawn card reads the list, because it cannot build the console to look:

```gdscript
api.register_model({"id": "xenu.ps2:scph30001r", "platform": "ps2", ...,
    "sockets": ["ps2_av_multi"]})
```

`"composite_plug"` in the list means phono jacks; a row with no `sockets` at all is
taken to wear them, as the stand-in box does. Its controller port is its
platform's and is not listed (a model whose ports are not overrides
`get_controller_connector()`). The first time the console is built, its mod's page
in the MODS tab says if the list and the console disagree.

### What the spawn card offers

Nothing above is said to the menu separately. The game reads each object a mod
registers -- its scene file, not its scripts -- and offers it on a card, whichever
mod brought the console:

- a pad or gun on the card of the console it was made for (its `systemid`). Only
  that one: a DualShock 2 still plugs into a PlayStation, but the PlayStation's
  card lists the PlayStation's own pads, and a Genesis pad is not listed on the
  Master System's;
- a lead on the card of every console that lists its connector among its
  sockets. A phono end fits every console with jacks, so it says nothing of which
  and is never matched; the Composite Cable is the game's answer to those.

`add_peripherals` still lists something on a card, for a label of your choosing,
colors (`variants`), or an accessory that plugs into nothing a card can see. The
card shows each object once.

**The stand-ins go by themselves**, as soon as something installed does their job:

- the **Primitive System** box leaves while a mod's console is on the card;
- the **Primitive Controller**, while a pad made for this console is installed;
- the generic **Light Gun**, while a gun made for it is;
- the **Composite Cable**, while no console on the card has phono jacks;
- the game's own lead for a socket (the table below), while an installed lead fits it.

| socket | the game's lead |
|---|---|
| `ps2_av_multi` | Primitive AV Cable |
| `n64_av_plug` | Stereo Composite Cable |
| `genesis_av_plug` | A/V Cable |
| `wii_av_plug` | AV Cable |
| `dc_av_plug` | Stereo AV Cable |

If nothing installed fits a console's socket -- no mod's lead and none of the
game's, its link cables included -- the console mod's page says so (`nothing installed fits its socket
'...'`). That is also how a misspelt connector shows up: test your console with
your lead mod enabled.

This is the **menu**. A room saved with a stand-in in it still loads one.

Until 2026-10-17 all of this was declared to the API (`av_connector`,
`replaces_standin`, a list of the socket names a mod could use). None of those
exist any more; a row with `av_connector` is refused with a pointer here.

## Attaching to existing code

```gdscript
api.on_node_added(&"RetroSystem", func(sys): ...)   # every console, as it spawns
api.on_scene_content_ready(func(scene_id): ...)     # a room, once it has restored
```

`on_node_added` matches engine classes, `class_name` scripts and connectors (a
plug or socket whose `connector` is the name given), and is how you decorate
something without editing it. It is connected only if a mod asks.

A mod that **dresses** a shipped object -- hides its stand-in mesh and hangs a
real shell on it -- uses `dress` instead, because only one mod can do that to one
thing:

```gdscript
api.dress(&"MemoryCard", "playstation2", _dress)   # false if another mod has it
```

The key says which of that class's objects you mean (a card's family, a pad's
systemid). A plug the game has no class of its own for is dressed by its
connector: `api.dress(&"n64_av_plug", "shell", _dress)`. The first mod to ask gets it, in priority order, and its callback is
called for every node of the class exactly as with `on_node_added`. A later mod
is told who has it on its own page in the MODS tab, and its callback is never
connected -- two shells are not drawn one inside the other.

Also available and needing nothing from this API: the `"spawned"` group (join it
or your object is not saved), `LoadingOverlay.begin(&"my_mod", ...)` for progress,
`QualityManager.configure_light()` so your lights obey the player's quality
settings, and `JsonStore` with `api.store()` for your own settings file.

## Authoring: work inside a checkout of RetroXR

Clone RetroXR, scaffold your mod inside it, and edit it there:

```bash
python Tools/mods/new_mod.py xenu.snes --name "Super Nintendo" --author "You"
# creates RetroXR/mods/xenu.snes/{mod.json,mod_main.gd}
```

This is not a convenience. It is the only arrangement in which a mod's scenes
resolve correctly, for two reasons:

- **Scenes record a `uid` as well as a `path`** for every script they reference. A
  uid minted in a separate project does not exist in RetroXR, so the reference
  survives only by falling back to the path — and working-by-fallback is not a
  foundation.
- **Copied stubs cannot resolve autoloads.** `RetroSystemModel`, the one class a
  console mod must extend, references `AvLegend`, `ProceduralDiscBay`, `VRButton`,
  `VRSlider` and the `NetworkManager` **autoload**. Autoloads come from
  `project.godot`, which a mod pack cannot add — so a stub tree resolves
  everything except the part that makes it work.

Working in the real project makes both problems vanish by construction: every
class, autoload, shader include and `.uid` is the genuine one.

`RetroXR/mods/` is gitignored and excluded from the app's export presets, so a mod
you are developing cannot end up inside a build of the game.

## Building a pack

```bash
# code, scenes and resources
godot --headless --path RetroXR --script res://Tools/mods/pack_mod.gd -- --id=xenu.snes
```

That writes straight into your mods folder and then **reads the result back
through the loader's own reader**, refusing to finish if the manifest cannot be
found — so a pack that would silently fail to appear in the Mods list fails at
build time instead.

**A mod carrying textures, meshes or audio must go through a real export**, because
those load via `res://.godot/imported/*` artifacts that only an export produces.
Add an export preset whose include filter is `mods/<id>/*` and:

```bash
godot --headless --path RetroXR --export-pack "YourModPreset" xenu.snes.zip
```

`pack_mod.gd` tells you which files it skipped for this reason rather than
producing a pack that is quietly missing its art.

### The preview image

Every pack needs `thumbnail.png` in its folder: **16:9, at least 512x288**
(1280x720 is the usual size). It is the tile RetroXR shows for your mod once it is
installed, and the same file is the logo you upload to its mod.io page, so the two
match. `pack_mod.gd` refuses to write a pack without one.

If you build with `--export-pack`, set the PNG's import type to **Keep File** in
Godot's Import dock first. Imported as a texture, the export ships a compressed
copy in its place and RetroXR — which reads the thumbnail without loading the mod —
finds nothing. Check the finished pack either way:

```bash
godot --headless --path RetroXR --script res://Tools/mods/pack_mod.gd -- --check=xenu.snes.zip
```

## Publishing on mod.io

RetroXR's mod browser lists what is published at <https://mod.io/g/retroxr>.

- Upload a **`.zip`** — the pack itself, not a zip with a pack inside it. A `.pck`
  works when installed by hand but is not accepted from the browser.
- Use your `thumbnail.png` as the mod's logo.
- The name, summary and logo on your mod.io page are what players see before they
  download; your `mod.json` is what they see after.
- The file in the pack decides the mod's id and version. Keep the `id` the same
  across uploads and RetroXR treats a new file as an update to the one installed.
- If your mod is not for every platform, say so in `mod.json`'s `platforms`: a
  player on another one is told it was not built for theirs.
- If it has `dependencies`, add the same mods as dependencies on its mod.io page:
  that list is what the game downloads with it.

## Stability

**There is none yet, and that is deliberate.** RetroXR is young and moves fast;
the freedom to change internals is currently worth more than a stable mod ABI.
`RetroSystemModel`'s virtuals will keep growing, row shapes may gain fields, and
the classes under `Scripts/Objects/` are fair game.

`api_version` is a **break marker, not a compatibility promise**. It is bumped
whenever something a mod could depend on changes, and the loader refuses a mod
declaring an older one with a message naming what moved. Breakage is loud and
specific rather than silent.

**Expect your mod to break when RetroXR updates.** A mod that stops loading after
an update is the system working as intended, not a bug.

## Limits

- A mod **cannot add a GDExtension**. Mounting a pack does not register native
  code. Mods are GDScript and assets.
- A mod **cannot add an autoload** — `project.godot` is read before any pack is
  mounted.
- A pack **cannot be unmounted**, so disabling, updating or removing a running
  mod takes effect on the next launch (the Installed page's **Restart now** does
  it for you). A newly enabled mod loads in place with **Apply now**, unless it
  replaces a shipped file.
- A mod loaded with **Apply now** registers after every mod loaded at launch,
  whatever its `priority`. Where two mods claim the same thing (`api.dress`, an
  overridden model row, a cartridge or expansion shell — first come, first
  served) the next launch may settle it the other way.
- Overriding a `preload`ed path is load-order dependent and unsupported.
- Two copies of the same mod are refused, both of them, rather than resolved by a
  rule you cannot see.
- On Quest, remember the mobile renderer: `RetroSystemModel.lamp_glow_supported()`
  is false there, and a tiny light close to a surface renders black or as a flat
  disc. Test on the device.

## One upload, more than one build

mod.io keeps one zip per mod. That zip is normally your pack. It can instead be a
**bundle**: a zip with no `mods/<id>/mod.json` of its own and your packs at its top
level, one per platform, each naming its platforms in its manifest. RetroXR opens
it and installs the one that runs on the device, so a desktop build and a Quest
build can each carry only its own texture formats. A `.pck`, which mod.io does
not accept on its own, is uploaded the same way: inside a zip.

Exactly one pack in a bundle must run on any given platform. None, or two, and
the download is refused with the reason.

## What a mod on mod.io may not contain

RetroXR will not install a download that carries a game or a program: any file
with an extension an emulator core loads as content (`.iso`, `.nes`, `.sfc`,
`.bin`, `.zip`, `.chd` and several hundred more), or native code (`.dll`, `.so`,
`.exe`). Text, pictures and sound are fine. **`.md` is refused**, because it is a
Mega Drive ROM as well as Markdown: ship your notes as `.txt`. RetroXR also waits
for mod.io's scan of your file to finish before offering it, so a new upload
shows as "Being scanned by mod.io" for a while.

## What you are responsible for

Everything in your pack is yours. RetroXR does not make or endorse mods. What is
listed on mod.io is subject to mod.io's terms and to moderation there, and a mod
can be reported from its page in RetroXR's browser.

If you intend to share a mod, ship only what you have the right to ship. Console
shells in particular carry wordmarks, logos and trade dress belonging to their
manufacturers. A practical warning from this project's own experience: a mark can
hide in a **normal map** with nothing in the albedo, so open every texture and
render every side before you publish.
