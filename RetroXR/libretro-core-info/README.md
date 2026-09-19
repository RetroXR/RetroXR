# libretro core info

Vendored copy of the libretro core `.info` files — one per core, giving its
display name, the systemid it serves, its supported extensions and its licence.
`CoreInfoDatabase.load_from_project()` parses every `*.info` here.

  Source repo : https://github.com/XenuIsWatching/libretro-super
  Path        : `dist/info/`
  Licence     : MIT — `COPYING`, copied from the same repo.

These files used to be the `libretro/libretro-core-info` submodule, which is a
mirror of the above and lags it. They are vendored rather than submoduled
because the fork carries fixes not yet upstream.

One of those is a **format addition**, `secondary_systemids`, which RetroXR
depends on — it is what gives Game Gear and Sega CD systemids of their own
rather than leaving them buried in a multi-system core's `database` field.
`00_example_libretro.info` documents it. It exists only in the fork, so
resyncing from anywhere else drops it.

The other is the **systemids themselves**. RetroXR's are ES-DE's folder names
(`n64`, `snes`, `gb`), not libretro's (`nintendo_64`, `super_nes`, `game_boy`);
the table is `SystemIds.LEGACY` in `Scripts/Data/systems/system_ids.gd`. Until the
fork's `dist/info` is renamed too, a resync brings every old id back, so rename
after one:

    python Tools/rename_systemids.py RetroXR/libretro-core-info RetroXR/libretro-core-info-retroxr

The same script takes the fork's `dist/info` as its directory. `systems_data_tests`
fails while any `.info` here still declares an old id.

To resync: `cp <libretro-super>/dist/info/*.info RetroXR/libretro-core-info/`.
That is a mirror, not a merge — a file only the old submodule had is not
restored by it. Two such files were dropped at the switch: `boom3_xp` (deleted
upstream) and `radio` (`internet_radio`, which SystemFilter hides anyway).
