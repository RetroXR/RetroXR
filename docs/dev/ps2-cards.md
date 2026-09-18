# §2k — PlayStation 2 memory cards

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### 2k. PlayStation 2 memory cards — a filesystem, and two cores that own it

The `playstation2` card family, added 2026-09-09. Every other family here is a
flat table; the PS2's card is a real filesystem — a superblock, a doubly-indirect
FAT, and 512-byte directory entries two to a 1024-byte cluster, with 16 bytes of
ECC in every page's spare area (528 raw, 512 to the filesystem). Each save is a
DIRECTORY at the root, so a save's name is a folder name and its size is what its
whole subtree occupies. `PS2Card` is correspondingly larger than its siblings.

**Where the format came from, since none of it can be trusted on paper.** Upstream
PCSX2's `pcsx2/SIO/Memcard/MemoryCardFolder.cpp` synthesises a card image from a
host directory, which makes it a WRITING reference and not only a reading one —
geometry, FAT construction, directory layout and the ECC table are transliterated
from it. **PCSX2 has no formatter**: it creates a card as 8,650,752 bytes of 0xFF
and leaves the BIOS to format it, so `blank_image()` had to be written from the
Ross Ridge specification PCSX2 vendors alongside the code.

**The specification is wrong about `card_flags`**, and four fills with it. Measured
against a real 44-save PCSX2 card backup: `card_flags` is **0x2B**
(`CF_USE_ECC | CF_BAD_BLOCK`), not the 0x52 the spec calls the default — a value
with `CF_USE_ECC` clear, on a card whose every page carries ECC. Also measured:
an unused indirect-FAT slot is **0** while an unused bad-block slot is
**0xFFFFFFFF** (the two 32-entry lists are adjacent and filled differently), the
superblock page is zeroed past `card_flags` rather than 0xFF-filled, and a page's
spare area ends in four NULs rather than 0xFF.

**The check that settles all of it is one assertion.** A formatted card's
superblock never changes as saves come and go, so a blank card's first raw page
must equal the same page of ANY console-formatted card. It does, byte for byte,
and `card_tests` pins the SHA-256 (`5cf22726…`). That one case covers magic,
version, card_type, card_flags, every geometry field, both fill conventions and
the ECC algorithm together. The card itself is not committed — 8 MB of somebody
else's saves — so the digest stands in for it.

Four things a reading of the spec alone gets wrong, all with cases:

- A directory's `length` is a **SLOT count**, including `.`, `..` and every DEAD
  slot. It is a capacity, never a file count, and the append path decides where
  the next entry goes from `length % 2`.
- The root's `..` is **0xA426** — it drops `MODE_READ` and carries 0x2000, unlike
  every subdirectory's. Confirmed on the real card, not just in PCSX2.
- "Deleted" and "erased" are different tests: `mode != 0xFFFFFFFF` is valid,
  `mode & 0x8000` is used. A deleted file is valid-but-unused.
- Usable clusters are truncated to `(alloc_end/1000)*1000 - 1` = **7999**, not
  the 8135 the superblock allows, to match what the console reports. `total_blocks`
  is 7998 of those, because the root directory always holds one and a save can
  never have it — the same reason the PlayStation's card excludes its directory
  block.

**Icons are 3-D models**, not sprites: `icon.sys` names the save and three `.icn`
files (normal, copying, deleting — note Play!'s own accessor enum lists them in a
different order, so the file is the authority). `PS2Icon` parses them as data and
`PS2IconView` renders one per row in a SubViewport. Three traps, none of which
appears in a log:

- The PS2 authors icons with **+Y pointing DOWN**, so a straight read stands every
  one on its head. Caught on Indiana Jones' hat — the medallions and rings in the
  same card could not have shown it. Render something ASYMMETRIC.
- **A vertex color's scale depends on whether a texture modulates it.** Textured:
  the GS shifts the product down by 7, so 0x80 is NEUTRAL and the texture shows
  through unchanged — every textured icon on the test card reads a flat 127/128,
  which is what that looks like. Untextured: the color IS the surface, an
  ordinary 0-255. Divide by the wrong one and half the card is twice as bright as
  it should be. Indy's hat is `(35, 14, 5)` on the card and `(35, 14, 5)` in an
  independent rip of the same model.
- **A vertex color is sRGB and a renderer wants linear.** Handing the byte over
  as-is both brightens a color and flattens it toward gray — `(35, 14, 5)` is a
  7:3:1 ratio and comes out 1.6:1.2:1. That desaturation is the signature; look
  for it rather than for brightness. The TEXTURE is the opposite case: an albedo
  texture is already taken for display-referred, so converting it here too drops
  a textured icon to near-black.
- **Icons are drawn UNSHADED, with no lights at all.** The artist baked the
  shading into the vertex colors — Tekken's trophy has a bright top and a dark
  base with nothing shining on it — so lighting them again shades them twice.
  icon.sys does carry three directional lights and an ambient, and they are
  deliberately not read: several saves ship a placeholder the developer never set,
  and Indiana Jones has ambient pure RED with three lights that are pure red,
  green and blue down X, Y and Z, which renders his hat green.
- Judge this by MEASURING the output, not by eye. Unshaded, Tekken 5 renders
  `(255,253,61)`, `(93,69,50)`, `(91,56,56)` against an independent rip's
  `(255,253,61)`, `(94,68,48)`, `(92,55,55)`, and Indy renders the exact vertex
  bytes his card holds. Every wrong version above also *looked* plausible.

An `.icn` whose texture encoding or animation header is unrecognized costs the
texture or the animation rather than the whole model; five saves on the test card
showed nothing at all before that.

**Neither core takes a card through SAVE_RAM.** Both open files of their own, so
`MemcardMounts` describes where, and `memory_card_controller` copies a seated card
in before the core loads and drains it back on the poll that already exists for
Dolphin.

| | `pcsx2` (LRPS2) | `pcee2` (upstream port) |
|---|---|---|
| directory | `<system>/pcsx2/pcsx2/memcards` | `<system>/pcee2/pcsx2/memcards` |
| slot names | fixed `Mcd001.ps2` / `Mcd002.ps2` | the card's own id |
| empty slot | **phantom card** — unavoidable | `slot{1,2}_enable = disabled` |
| swap while running | next power cycle | re-opens live |

LRPS2's libretro build defaults to shared cards, which is the only mode with two
slots at all — its per-game branch names slot 1 after the ROM and DISABLES slot 2.
It keeps settings in memory and reads no ini, so those names cannot be redirected,
and it creates a card for any enabled slot whose file is missing.

**The mirror must land before the core loads, and this is load-bearing rather than
tidy.** pcee2 builds the list of cards it will offer by scanning that directory as
it registers its options — which is before the core has run any code that would
create the directory. So RetroXR creates it and fills it. A late mirror leaves the
two slot options unregistered, and `OptionsHandler::SetVariable` drops a key the
core never declared without failing, so the card would silently not be selected.

```bash
"$godot" --headless --path RetroXR res://Tests/card_tests.tscn -- --only=ps2
"$godot" --path RetroXR --resolution 900x760 --position 20,20 \
  res://Tools/input/ps2_card_probe.tscn -- --card=/path/to/card.ps2
```

The probe is **windowed, never `--headless`** — the icons are SubViewports, and
the dummy renderer returns a blank image while the size oracle happily reports the
right one. Without `--card` it generates its own saves, which proves the pipeline
and nothing about any real game's artwork.

**Both halves of the mount hang off one predicate.** `_core_owns_card_files`
decides whether a card is staged into the directory the core reads AND whether
the poller that drains the core's writes back is started. A core missing from it
loses both: the core invents a card of its own, the player saves into it, and the
save lives in a file RetroXR never reads — with the game's own LOAD screen
listing it perfectly, which is what makes the report confusing. That shipped once,
when a refactor lifted the old slot-count test into a named predicate that said
Dolphin alone. It asks `MemcardMounts` now, and `system_tests` pins it against
that table rather than a second list.

**A card can be swapped mid-game on pcee2 and cannot on pcsx2, and the reason is
the core rather than RetroXR.** LRPS2 has the whole machinery —
`VMManager::CheckForMemoryCardConfigChanges` does `FileMcd_EmuClose/EmuOpen` then
`AutoEject::Set`, a real eject the guest sees, and the libretro layer reaches
`ApplySettings()` on any option change. But it fires only when `Mcd[i].Enabled`,
`.Filename` or `McdEnableEjection` differ, all three of which come from an
in-memory settings interface, and LRPS2 declares exactly ONE memcard core option:
`pcsx2_shared_memory_cards`. So no key a frontend can set reaches any trigger. It
holds the card it opened at boot until the next power cycle, and nothing here can
change that without forking the core. `_set_card_presence` is no help either —
it is `pcsx_rearmed` only, because that is the core with a presence option.

Two things follow for a non-live core, both of which cost a bug. **A pull while
it runs must not delete the staged file or forget which card it belongs to**: the
core is still holding that card and flushes it on the way out, so the file is the
only route those writes have home. And **a staged copy belongs to the card that
FILLED it, not to whatever is in the slot now** (`_scratch_owners`) — swap a card
on one of these and the core goes on flushing the old one, so draining by the
seated card would overwrite a card the console never read with another card's
contents.

**pcee2 hot-swaps, but only because the directory is seeded.** It registers
`pcsx2_memcard_slot{1,2}_file` only when its scan found at least one card, and
that scan runs once, before the core loads — so a console powered on with both
slots empty leaves those keys unregistered for the whole session, and
`OptionsHandler::SetVariable` drops an undeclared key without failing, so every
later insert would be accepted and reach nothing. `_seed_card_directory` writes a
placeholder card to prevent that. The value need not be one of the candidates:
pcee2 says so in as many words — *"Runtime reads must not be gated by the
registration-time candidate list"* — and queries both keys every frame, so a card
first seated mid-game selects correctly though its name was never enumerated.

**Every card event prints a line**, `[MemoryCard] <machine>: …` — a card seated
or pulled, the route a mount took and what each slot resolved to, bytes staged
into a core's directory, bytes drained back out, and an image seen to change.
Events only; a poll tick that found nothing is silent. That is a direct answer to
the bug above: a drain that was never running and a drain that ran and found
nothing looked identical from outside, so every line names a slot, a file and a
byte count, which is what tells those two apart.

**LRPS2 runs on VULKAN here, and blanks fields through a null image.** Its
renderer option defaults to `Auto`, which asks the frontend what it prefers, and
RetroXR answers Vulkan (`g_preferred_hw_render`) — so the D3D11/OpenGL line in the
vendored `.info` describes neither what the core can do nor what it does here. The
overlay `pcsx2_libretro.info` says so. What follows from it: when the PS2's PCRTC
has nothing to merge, `GSDeviceVK::PresentRect` calls `set_image(nullptr)` and
then refreshes anyway, expecting the frontend to paint black. That is ordinary
traffic around every video-mode change — Ace Combat 04 does it on about 7% of
frames — and `ReadbackToPixels` used to log an error on each one. It now
distinguishes a RETRACTED image from one the core never published: the first is
silent and keeps the last frame, the second is a protocol error worth one line.

**Still owed:** netplay does not carry a PS2 card — `net_sram_file_bytes` is
slot-A-and-SAVE_RAM only, which is the same gap Dolphin has.
