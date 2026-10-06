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
enable it and restart.

**Packs** lists mod packs: lists of mods somebody put together on mod.io. One
press downloads a pack's mods and one answer installs them. Removing a pack
removes the mods it brought, and leaves any you had installed on its own.

**By hand:** put the file in the mods folder and restart:

| platform | folder |
|---|---|
| Windows | `%USERPROFILE%\retroxr\mods\` |
| Linux, macOS | `~/retroxr/mods/` |
| Quest / Android | `/sdcard/Android/data/com.xenu.retroxr/files/mods/` (`adb push`-able) |

Then **MODS → Installed**, enable it, and restart again.

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
  "platforms": ["Windows", "Linux", "macOS", "Android"]
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

There is no field naming the pack file: the manifest is *inside* it.

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

A **cabinet** extends `RetroTVShell`: geometry plus `Marker3D` seats, while every
functional part stays on the television. Two optional overrides, both defaulting
to doing nothing:

- `screen_shader()` — **null means the stock CRT**, which is what you want unless
  your set genuinely looks different.
- `on_buttons_built(buttons)` — the bezel buttons, so you can adorn them or hang
  your own sounds off them. The stock sets have no button audio at all, so this is
  adding rather than overriding.

A **controller** is simply a scene rooted at `RetroController`. Persistence
already records its scene path and falls back to the generic pad if your mod is
gone; nothing extra is needed.

### Taking a stand-in off the card

A console the game ships no model of gets three stand-ins on its spawn card: the
**Primitive System** box, the **Primitive Controller** and the **Composite
Cable**. A mod that brings the real thing says so, and the stand-in stops being
offered beside it:

```gdscript
api.replaces_standin("ps2", "console")      # the box
api.replaces_standin("ps2", "controller")   # the stand-in pad
```

Say it from the mod that brings the replacement, and only for what that mod
brings: a console mod claims `console`, a pad mod claims `controller`. Then any
subset of them a player installs still leaves a card that works. Several mods
may claim the same stand-in; it goes while any of them is enabled and comes back
with the last. The box only goes while a console for that platform is really on
the card, so a model that failed to load cannot leave a card with no console.

There is no claim for the Composite Cable. It goes by itself once no console on
the card has phono jacks, which a console says by naming its socket (below).

This changes the **menu**. A room saved with a stand-in in it still loads one.

Both calls arrived on 2026-10-06. A mod that should still load in an older build
asks first: `if api.has_method("replaces_standin"): ...`.

### Sockets two mods have to agree on

A lead goes into a socket because both name the same **plug group**, and that
string is the whole agreement. Inside one mod it can be anything. Between two it
cannot: if you model a PlayStation 2 and somebody else models its AV lead, and
you each invent a name, their lead does not go into your console.

So the names that cross between mods are the game's, in
`Scripts/Mods/mod_connectors.gd`:

| name | what it is |
|---|---|
| `ps2_av_multi` | PlayStation 2 AV MULTI OUT |

Use the listed name, verbatim, as the `plug_group()` of both the socket script
and the plug script, and name it on the console's row:

```gdscript
api.register_model({"id": "xenu.ps2:scph30001r", "platform": "ps2", ...,
    "av_connector": "ps2_av_multi"})
```

`av_connector` is what tells the card this console has no phono jacks. A
connector that is your mod's own business is namespaced like any other id,
`"<mod id>:<name>"`; a bare name that is not in the table is refused. If you
need one that is not listed yet, ask for it to be added before you publish: the
name ends up inside every mod that uses it and cannot be changed afterwards.

## Audio and shaders

Ship audio for **your own** hardware and load it yourself — `nes_model.gd` shows
the pattern (a `PcmOneShot` pool and a round-robin voice). There is no mechanism
for replacing a shipped console's sounds, deliberately.

A custom shader is opt-in and never required. Three ways to land:

1. **Do nothing.** Your cabinet gets the same picture every other set has.
2. **Ask for a built-in by name** — `api.shader("crt")`, and likewise `vcr`,
   `static`, `window`, `gameboy_lcd`, `vb_stereo`, `phosphor_decay`,
   `screen_pixel_aa`. You get the resource the game already has loaded, so it
   costs no second compile. Ask by name rather than by path: the shader files are
   free to move.
3. **Write one, reusing ours.** `#include "res://Shaders/crt_filter.gdshaderinc"`
   and `pixel_aa.gdshaderinc` are the tube and pixel-AA stages every shipped
   display shader is built from. Note a `.gdshaderinc` parameter cannot shadow a
   uniform.

Replacing `res://Shaders/crt_effect.gdshader` wholesale is unsupported — it is
`preload`ed, so whether your copy wins depends on load order.

## Attaching to existing code

```gdscript
api.on_node_added(&"RetroSystem", func(sys): ...)   # every console, as it spawns
api.on_scene_content_ready(func(scene_id): ...)     # a room, once it has restored
```

`on_node_added` matches engine classes and `class_name` scripts, and is how you
decorate something without editing it. It is connected only if a mod asks.

A mod that **dresses** a shipped object -- hides its stand-in mesh and hangs a
real shell on it -- uses `dress` instead, because only one mod can do that to one
thing:

```gdscript
api.dress(&"MemoryCard", "playstation2", _dress)   # false if another mod has it
```

The key says which of that class's objects you mean (a card's family, a pad's
systemid). The first mod to ask gets it, in priority order, and its callback is
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
- A pack **cannot be unmounted**, so enabling or disabling takes effect on the
  next launch.
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
