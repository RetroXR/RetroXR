# The Wii System Menu

A Wii's "BIOS" is the System Menu installed in dolphin's NAND. With one installed,
a Wii switched on with an empty drive boots to it, and a Wii switched on with a
disc boots to it with the disc in the drive: the player starts the game from the
Disc Channel, as on the hardware. With none installed, a Wii with a disc boots the
disc directly and an empty Wii is refused (it never falls back to the GameCube IPL).

## Where it lives

- The NAND is in the core's SAVE dir: the fork's User dir is `<save>/User`, so the
  menu is `<root>/save/dolphin/User/Wii/title/00000001/00000002/`. No `.info`
  declares it, so it is not a firmware row.
- "Installed" is `WiiSystemMenu.is_installed()`: the menu's `title.tmd` AND the
  IOS it names (u64 at 0x184 of that TMD, IOS80 for 4.3). The TMD alone is not
  enough: Dolphin's updater installs the menu SECOND of 58 titles, so an update
  cancelled early leaves a menu with no IOS, which boots to a black screen
  (measured with `wii_menu_update_probe --cancel-after=3`).
- `BiosBoot` row `dolphin/wii` gates on it with `wii_menu: true` instead of
  `boot_rom`, because `boot_rom` means files in the SYSTEM dir.

## Which console dolphin is: `dolphin_console`

One core and one `dolphin.opt` serve both the GameCube and the Wii. A disc says
which console it wants, an empty drive cannot, and Dolphin's own
`dolphin_disc_based_games_boot_to_wii_menu` also applies to GameCube discs. So the
fork has `dolphin_console` (`auto` | `gamecube` | `wii`):

| value | empty drive | disc-to-menu option |
|---|---|---|
| `auto` (default, upstream behaviour) | GameCube IPL | honoured for any disc |
| `gamecube` | GameCube IPL | ignored |
| `wii` | System Menu (refused if none) | honoured |

`ForcedCoreOptions.dolphin_console` pins it on EVERY run of both machines, not
only empty ones: without it, a GameCube loaded after a Wii read the Wii's
disc-to-menu option and booted a Wii menu (measured: `auto` + a GameCube disc
shows the Wii health screen, `gamecube` shows the game).

The Wii row's `splash` pins `dolphin_disc_based_games_boot_to_wii_menu=enabled`,
which `splash_options` only applies when the menu is installed. The player's
**BIOS boot override** preference hands it back as an ordinary option (seeded
on), which is how one switches disc-through-menu off.

A menu of another region does not list the disc; the core logs it and the Disc
Channel stays empty. The region is the player's choice on the download row.

## Installing it: the core does it, never RetroXR

Installing a title means decrypting it with the **Wii common key**. That is a
circumvention key (DMCA §1201; it is what Nintendo's 2023 notice against Dolphin's
Steam release named), so RetroXR must not carry it. Dolphin already does, so the
fork exports Dolphin's own *Tools > Perform Online System Update*:

```c
int retroxr_wii_system_update(const char* user_dir, const char* sys_dir,
                              const char* region, progress_cb, void* userdata);
```

(`Source/Core/DolphinLibretro/WiiUpdate.cpp`, returns `WiiUtils::UpdateResult`.)
libretro-godot's static `Libretro.RunWiiSystemUpdate(root, core, user_dir,
sys_dir, region, progress: Callable)` dlopens the core in place (like
`PeekCoreOptions`) and calls it; -1 = no core, -2 = a core without the export.
It blocks for the whole install, so `FirmwareInstaller`'s `WII_MENU` job runs it
on its worker thread; progress is in titles, and a cancel lands between titles.
The job is refused while any dolphin machine is switched on (same NAND).

Nintendo's Wii update service itself is offline: Dolphin's
`fakenus.dolphin-emu.org` answers the title list and Nintendo's Wii U CDN serves
the files, so the download depends on both staying up.

UI: BIOS / Extras → Wii → "Wii System Menu" row, with a region button that
cycles USA → EUR → JPN → KOR (defaulted from the OS locale, or the installed
menu's region). No `OptionButton`: popups do not work in the headset menus.

## Measured (2026-09-21, Windows)

- `Tools/cores/wii_menu_update_probe` into a scratch NAND: 58 titles, result 0,
  7.5 s. Its `title/`, `ticket/` and `shared1/` are byte-identical to what
  standalone Dolphin's online update installed. `--cancel-after=3` → result 8.
- `bios_boot_probe` (windowed, `--opt=`): empty + `wii` → the menu's health
  screen; empty + `gamecube` → the GameCube IPL; Wii Sports + disc-to-menu on →
  the menu, off → Wii Sports' own wrist-strap screen; a GameCube disc with the
  option on → the game under `gamecube`, the Wii menu under `auto`.

## Owed

- An **Android** build of the fork and a fork release (CoreSources still names
  v12, which has neither the export nor `dolphin_console`: the row then reports
  "core too old"). Dolphin's curl on Android has not fetched over HTTPS here yet.
- The headset: the row, the install and booting the menu on a Quest.
- Driving the menu into the Disc Channel with a Wii Remote in the room.
