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
  USA then EUR then JAP. Upstream libretro Dolphin cannot start empty at all. The Wii's empty-tray boot is the System Menu in dolphin's NAND,
  chosen by `dolphin_console` — see `wii-menu.md`. The flag is not consulted anywhere; the table records what
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

### The DS and DSi home screens (measured 2026-09-21)

`RetroXR/Tools/cores/ds_boot_probe.tscn` — windowed, one core per process, against a
THROWAWAY root (`--root=`; it writes that root's `core_options/`). `--opt=key=value`
pins options, `--gba=` loads melonDS DS's Slot-2 subsystem beside `--rom=`, `--press=`
takes `12:touch=x:y` (bottom-screen pixels) as well as buttons, `--options` dumps every key.

| core | empty slot | DSi (`console_mode`) | card listed | GBA listed |
|---|---|---|---|---|
| melondsds | no content (NULL) | DSi Menu | DS + DSi menus | yes, Slot-2 subsystem |
| melonds | zero-byte `.nds` (no SET_SUPPORT_NO_GAME) | DSi Menu (touch mode Touch) | DS + DSi menus | no subsystem |
| desmume | refuses both → "no cartridge" | none | DS menu (`desmume_use_external_bios` + `desmume_boot_into_bios`) | no subsystem |

The menu is in `firmware.bin` and runs on `bios7.bin`/`bios9.bin`, so the rows use
`also_needs` (all-of) beside the any-of `boot_rom`. DS vs DSi is the player's core
option and is never pinned. The DSi's first screen is the health warning; a touch
reaches the DSi Menu, whose card-slot icon sits next to System Settings.

Three traps found on a REAL data root that a fresh probe root hides:

- **The NULL no-content flag raced.** `Libretro.SetNoContentPassesNull` wrote a global
  the emulation thread read LATER, after `system.gd` had already put it back to false,
  so every no-content start got a zeroed struct. xemu takes either, which hid it;
  melonDS DS says "Loaded an empty file as content". `Wrapper::StartSubsystemContent`
  now latches it per run.
- **melonDS DS saves `melonds_firmware_nds_path = "/notfound"`** when first run with no
  firmware, and keeps it after the files arrive ("Oh no! melonDS DS couldn't start").
  The row pins both firmware paths to the standard names.
- **`system/melondsds/melonDS DS/wfcsettings.bin`** — the built-in firmware's "melonAP"
  Wi-Fi profile from such a run — is merged into real firmware and the menu dies
  (ARM9 "PC in non executable region 00800204", white screen; control leg: same
  `firmware.bin` boots without it). The row's `retire_files` renames it to
  `.retroxr-retired` before the boot. melonDS DS also REWRITES `firmware.bin` on
  shutdown, so a crashed run leaves the merged state behind — restore the dump.
