# §2d — the BIOS-boot survey

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### 2d. The BIOS-boot survey — a probe that must stay one core per process

`RetroXR/Tools/cores/bios_boot_probe.tscn` + `Tools/bios_boot_survey.sh` are the provenance
of the `BiosBoot` table, and the only way to refresh it when a core is updated. The
probe reports one core's firmware status, its boot-ROM-ish option keys, and whether it
will start with no content; the survey drives every candidate and prints a table.

```bash
Tools/bios_boot_survey.sh                # every candidate
Tools/bios_boot_survey.sh mgba flycast   # just these
```

**Never loop cores inside one Godot process.** Starting a core with a game info it did
not expect runs code its author may never have exercised, and the extension is built
`-fno-exceptions` with no sandbox: of sixteen cores surveyed 2026-08-20, **six killed the
process** — mgba and parallel_n64 dereference a null `retro_game_info`, and
mednafen_saturn, neocd, dolphin and same_cdi die on a zeroed one. One process per attempt
is what makes a casualty cost one table row instead of the run.

Two things the survey settled that are easy to re-derive wrongly:

- **`supports_no_game` in the `.info` is useless here** — all sixteen candidates declare
  it `false`, yet flycast, pcsx2 (LRPS2) and the Dolphin fork's `retroxr` branch start
  with no content and draw their BIOS menus (measured 2026-09-15). Dolphin's core option
  `dolphin_gc_bios_region` picks which GameCube IPL: `auto` boots the first installed,
  USA then EUR then JAP. Upstream libretro Dolphin cannot start empty at all. The flag is not consulted anywhere; the table records what
  was measured. The installed pcee2 is refused before it is asked, because it does not
  declare `SET_SUPPORT_NO_GAME` to the bridge.
- **The usual mechanism is empty MEDIA, not an empty path.** Only pcsx_rearmed accepts a
  zero-byte image, and it gives the real PS1 BIOS. flycast (gdi/cdi/chd),
  mednafen_saturn, mednafen_pce and neocd all refuse one. mednafen_saturn takes a cue
  over one silent audio track instead (`BiosBoot` `empty_media_track`), which lands in
  the Saturn's CD player; a blank data track gets "Disc unsuitable for this system".

A disc console boots what its drive would read: the disc under a SHUT lid. An open lid,
or a disc taken out while the game ran, boots the BIOS where the table says the core can,
and otherwise refuses with "Lid open" / "No game inserted". Shutting a disc into a BIOS
run restarts the machine on it rather than swapping it in: measured 2026-09-15, neither
pcsx_rearmed's nor mednafen_saturn's BIOS boots a disc swapped in under it (20 s later,
still "Please insert PlayStation CD-ROM" / the CD player), and a core started with no
content has no disc list at all — flycast indexes that empty list when its tray shuts —
so those runs send the core no tray ops.

It **writes the player's real `core_options/`** — a core serialises its whole option set
on shutdown, and a crashed run can leave a key moved (a crashed mgba run flipped
`mgba_skip_bios` to `ON`). The survey snapshots the directory up front and restores it on
exit, including on failure. A probe run by hand does not, so restore by hand or re-run the
survey afterwards.
