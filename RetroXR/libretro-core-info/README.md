# libretro core info

Vendored copy of the libretro core `.info` files — one per core, giving its
display name, the systemid it serves, its supported extensions and its licence.
`CoreInfoDatabase.load_from_project()` parses every `*.info` here.

  Source repo : https://github.com/libretro/libretro-super
  Path        : `dist/info/`
  Last merged : `b90a4ee4f89aa7e227a4aa14aae533936b955b5a` (2026-11-05) — the
                `--base` of the next merge; update it after every one.
  Licence     : MIT — `COPYING`, copied from the same repo.

These files used to be the `libretro/libretro-core-info` submodule, which is a
mirror of libretro-super and lags it by days. They were first vendored on
2026-08-07 from the XenuIsWatching/libretro-super fork (libretro-super
`4e1d67c1` plus the fork's systemid fixes, most of which upstream has since
taken); the fork is now well behind, and the 2026-11-05 refresh came from
libretro-super itself.

**This is not a copy of upstream: RetroXR's own lines live in it**, and upstream
has none of them:

- `secondary_systemids`, a **format addition** in some 70 files. It is what
  gives Game Gear, Sega CD, Satellaview... systemids of their own rather than
  leaving them buried in a multi-system core's `database` field.
  `00_example_libretro.info` documents it.
- the **systemids themselves**. RetroXR's are ES-DE's folder names (`n64`,
  `snes`, `gb`), not libretro's (`nintendo_64`, `super_nes`, `game_boy`); the
  table is `SystemIds.LEGACY` in `Scripts/Data/systems/system_ids.gd`, applied by
  `Tools/rename_systemids.py`. `systems_data_tests` fails while any `.info` here
  still declares an old id.
- a primary core's `systemname` names ITS OWN machine (`0ad3d330`): the first
  core whose own systemid a tile is names it, so BlastEm's upstream "Sega 8/16-bit
  (Various)" would label the Genesis tile. A multi-system core upstream files
  under `multi` (jgenesis) gets a real primary and secondaries instead.
- fixes for cores RetroXR builds itself (extensions, flags).

`RetroXR/libretro-core-info-retroxr/` is the other half: a file there REPLACES
the entry of the same name whole, so an upstream change to one of its cores
does not reach the app through this directory. For an overlay that is upstream
plus one line (gearboy, nSide), merge the upstream change into it
(`git merge-file overlay base upstream`); one that describes RetroXR's own build
(dolphin, flycast, Beetle Saturn, LRPS2, Virtual Jaguar, xemu) follows that
build, not upstream.

`rpcs3_libretro.info`, `xenia_edge_libretro.info` and `parallel_xbox360_libretro.info`
(the PlayStation 3 and the Xbox 360, `docs/dev/seventh-gen.md`) were copied in by hand
on 2026-11-05 from libretro-super `dist/info` and renamed (`playstation3`, `xbox_360`);
all three are in `b90a4ee4`, so the merge tool treats them as ordinary upstream files.
`parallel_xbox360` was copied in AFTER that merge: should a later run report it
"kept (deleted here)", it went missing from this directory, not from upstream.

**To refresh, MERGE — never `cp`**, which throws every line above away:

    git clone --filter=blob:none --sparse https://github.com/libretro/libretro-super.git ../libretro-super
    git -C ../libretro-super sparse-checkout set dist/info
    python Tools/merge_core_info.py --repo ../libretro-super --base <Last merged>            # report
    python Tools/merge_core_info.py --repo ../libretro-super --base <Last merged> --write    # do it

It three-way merges each file (base = upstream at the last merge, ours = this
directory, theirs = upstream now, both upstream sides renamed first), follows a
renamed file by its content, deletes a file only if RetroXR never touched it,
and lists conflicts and every systemid new to RetroXR. Then: resolve the
conflicts, give a new id whose ES-DE folder differs a `SystemIds.LEGACY` entry
(ES-DE's `resources/systems/linux/es_systems.xml` names them), check the
`systemname` of any new or widened multi-system core, hide a non-machine id in
`SystemFilter`, look at the overlay files upstream changed, update **Last
merged**, and run `systems_data_tests`.

The 2026-11-05 merge (`4e1d67c1` -> `b90a4ee4`): 34 files merged, 2 conflicts
(geargrafx kept "PC Engine"; Virtual Jaguar took upstream's, which matches
RetroXR's own v3.6.1-based build), 40 new cores, `higan_sfc_balanced` became
`nside_sfc_balanced` (the buildbot ships only the new name), `radio` came back
(SystemFilter hides `internet_radio`). `parallel_xbox360` was left out of the merge and
added with the Xbox 360 work.
