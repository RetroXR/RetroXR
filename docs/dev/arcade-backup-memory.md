# §2z-arc-mem — An arcade game's own memory: "Backup Data Error", NVRAM, and what the room does about it

(2026-10-26.) Silent Scope (`sscope`) and Silent Scope 2 (`sscope2`) show **BACKUP DATA ERROR** at start. This is what is known of why, which other games
are the same kind of thing, how libretro-mame stores the memory, and what the room does about it. Every claim is tagged: **VERIFIED** (read in source, file and line
given; `T:` is the `mame0289` tag of mamedev/mame, `L:` libretro/mame master, which is byte-identical to the tag for the files named), **INFERRED** (deduced from
verified facts), **SECONDARY** (a web-search summary of a page that could not be opened: a strong hint, no proof) and **OWED** (needs a real core and ROM, which the
sandbox never had). The long form, with the census scripts and every excerpt, is `research/nvram_backup_error.md` in the session notes; this is the part worth keeping.

## 1. What the message is

- **It is Konami's own message, not MAME's** (SECONDARY: the operator's manual, ManualsLib p. 26 and 63). The game checks its Timekeeper (M48T58, 8 KB, battery RAM
  and clock in one chip) **block by block** and names the failing blocks: option settings, ranking data, bookkeeping income data, **scope screen adjust data** and **gun
  volume data**. TEST at the error screen puts the first three back to factory values; the last two are the machine's calibration and are set again in the test menu
  (SCOPE SCREEN ADJUST, then SAVE AND EXIT; the gun by shooting the lower left and the upper right).
- **It is not the region mismatch.** A Timekeeper that disagrees with the 93C46 serial EEPROM and the DS2401 LAN ID gives `HARDWARE ERROR(-8B)` after POST, on Silent
  Scope 2 only (VERIFIED, `T:konami/hornet.cpp:395-396,411-412`); the original has neither chip. **Nor the LAN board's ROMs:** they are a required region, so a missing
  one stops MAME before the game (`T:src/emu/romload.cpp:564-571,667-672`) and a wrong checksum only warns. A missing board is a black screen (`hornet.cpp:407-409`).
- **Why it is expected under MAME** (VERIFIED/INFERRED): all 20 `sscope` sets (the first game's) ship a `BAD_DUMP` Timekeeper image marked "hand built" (`hornet.cpp:1661-1662` and the
  other regions), which cannot hold this machine's calibration, as do 18 of Silent Scope 2's (`sscope2a` and the other regions; the parent `sscope2` and `sscope2ub` ship a `good` dump, which the
  `-listxml` of 0.289 says and the table's `b` carries); and **every one of the 44 Silent Scope sets is `MACHINE_NOT_WORKING` in 0.289** (`hornet.cpp:3718-3764`).
  Clearing the memory will not by itself make the game playable.
- **Why it can look permanent** (INFERRED, OWED): MAME seeds the chip from the ROM image only when **no NVRAM file exists** (`T:src/devices/machine/timekpr.cpp:455-469`)
  and any file that opens wins for ever, a short one only logging `Error reading NVRAM file` (`T:src/emu/machine.cpp:1216-1230`). libretro-mame writes the file **only at
  `retro_deinit`** (a clean teardown) or a hard reset, not at `retro_unload_game`, not at a soft reset, not if the process is killed (`L:src/emu/machine.cpp:1486-1494`,
  `L:libretro.cpp:877-882,990-1000`). So a core that is not torn down cleanly makes every launch a first launch, and one torn down while the game was half
  initialised leaves a file that is loaded for ever. Savestates carry the NVRAM too (`timekpr.cpp:227`): a loaded state re-imposes it.
- The host date is a weak suspect: the M48T58 has no century register, 2026 is stored as BCD `0x26`, and the visible clock bytes are zero for the first emulated second
  (VERIFIED, `timekpr.cpp:245-255,283-354`, `machine.cpp:379-382`); Gradius 4 and NBA Play by Play boot on the same device.

## 2. Where the memory lives (libretro-mame 0.289, VERIFIED unless said)

`<save dir>/mame/nvram/<romset>/<device tag>`, no extension (`L:osd/libretro/libretro-internal/retro_init.cpp:109-154,550-578`; `machine.cpp:1179-1210`). `<romset>` is the zip's
stem, so **a clone has a folder of its own**. In RetroXR the save dir is `<libretro root>/save/<core>` (`SramPaths.core_save_dir`), so on desktop
`…/libretro/save/mame/mame/nvram/sscope/m48t58` and on the Quest `…/files/libretro/save/mamearcade/mame/nvram/sscope/m48t58` (the core name is from the docs; the build was not
inspected). Silent Scope is `m48t58` (8192 bytes); Silent Scope 2 adds `lan_eeprom` (128 bytes), and the two must stay a pair. No core option resets NVRAM or sets the
clock; a `.cmd` content file can pass `-rtc` (not used). The core's memory API exposes no `SAVE_RAM`, so the bridge cannot read or flush NVRAM; the files are MAME's own.
FinalBurn Neo keeps `<save>/fbneo/<romset>.fs`, another file and another layout (hence `arcade` being per-core in `SramPaths`).

## 3. Which other games are the same kind of thing

Census over MAME 0.289's `-listxml` (28,713 coin-op romsets) and the driver sources, by `Tools/arcade/gen_game_index.py`'s `b` attribute (the table carries it; `ArcadeGameProfile.backup_class`):

| class (`b`) | meaning | romsets (families) |
|---|---|---|
| `bh` | a Timekeeper-class chip (`m48t02 m48t35 m48t37 m48t58 mk48t08 mk48t12 ds1643`) whose default image is **hand built or missing** (`baddump`/`nodump`): the first run starts from a synthesised memory | 82 (14) |
| `bg` | the chip, with a real-dump default image | 296 (48) |
| `bn` | the chip, no default image at all: the game builds its own memory, some ask for a TEST/F2 step | 423 (133) |

801 coin-op machines (171 families) carry such a chip, in 19 arcade driver files (System 573 69 families, Igrosoft Multi Fish 35, Viper 16, Hornet 6...). Only **82 machines in
14 families** ship a synthesised default, 13 of the 14 Konami: `sscope gradius4 nbapbp terabrst` (Hornet), `thrilld` (NWK-TR), `gticlub2 mfightc p911 thrild2 tsurugi`
(Viper), `bujutsu` (Cobra), `dstage` (System 573), and Capcom's `pmonster`. **Silent Scope 2's own set (`sscope2`) ships a REAL dump of the chip** (`m48t58y-70pc1`, `good`: `bg`),
while its clones for other regions (`sscope2a`...) and every `sscope` set ship a `baddump` one (`bh`): so the first-start hint is told for the original and for the Asia set of the
sequel, and a Reset is offered for every game that has a folder. At least 24 drivers say in their notes that the game validates or needs initialising (VERIFIED):
Viper "hold TEST while booting from the very start" (`viper.cpp:100`), chunk checksums that sum to 0xFFFF (`viper.cpp:255-267`), System 573's "press F2 to skip the RTC cleared note"
(`ksys573.cpp:22`), Sega Model 2 `hpyagu98`'s magic and checksum (`model2.cpp:7522-7530`), Final Lap 3's bootleg that poisons its NVRAM (`namcos2.cpp:5594-5598`), the PGM sets that expect
"magic values" (`pgm.cpp:5359-5411`), Atomiswave's "zap NVRAM" (`dc_atomiswave.cpp:878-879`), Midway Y-unit's FULL FACTORY RESTORE, Namco System 22's SERVICE+TEST at power-on.
Namco System 11/12/23, Sega Chihiro/Lindbergh, Taito F3/Type X and Capcom CPS3 carry no such note.

## 4. What the room does (implemented 2026-10-26)

Rules that came out of the constraints: **never destroy a valid file** (everything is a reversible move, never a delete, and only of a whole `nvram/<romset>/` folder, so Silent
Scope 2's pair never separates), **generic first** (the action needs no table; the table only adds hints), **no ROM data shipped**, **the same code on desktop and Quest** (plain
`DirAccess`), and **never while a core holds the game** (MAME writes at teardown).

- **`ArcadeBackupMemory`** (`Scripts/Data/systems/arcade_backup_memory.gd`), pure file operations on a core's save directory (`SramPaths.core_save_dir`), for the two MAME 0.289 builds
  (`mame`, `mamearcade`; FinalBurn Neo keeps one `.fs` file a game and the old MAMEs another layout: not managed):
  - `describe` (files, sizes, newest time) and `summary` (words: "2 files, 8.1 KB, saved 3 days ago"), `is_first_run`;
  - `quarantine` moves the whole `mame/nvram/<romset>/` folder to `nvram_quarantine/<romset>/<UTC stamp>/nvram/` with a `manifest.json` (romset, when, reason, each file's name, size and
    SHA-1); a second set aside in the same second gets `-2`; **the newest 20 copies of a game are kept** (`prune`, the one place anything is deleted, and only what it set aside itself);
  - `restore` is the exact inverse, byte for byte, and **itself reversible**: the folder that is there goes into quarantine first ("before restoring ..."), so the swap can be undone by restoring
    that; `list_quarantines` newest first;
  - `damaged` (the **size rule**): a file named after a Timekeeper chip (`m48t58`, `m48t35`...) whose size is not the chip's (`m48t02` and `mk48t12` 2 KB, `m48t58`, `mk48t08` and `ds1643`
    8 KB, `m48t35` and `m48t37` 32 KB: timekpr.cpp's own sizes) is already corrupt (MAME would read it, print `Error reading NVRAM file`, and run on the part it got: **an empty or short file left by a
    write that never finished is the plausible reason a BACKUP DATA ERROR comes back for ever**, since a file that is there wins over the default image). A file of the right size is never touched,
    whatever it holds; an EEPROM or a chip this does not know is not judged;
  - `prepare_launch` is what a start does: set the folder aside if (and only if) a file is damaged, and say whether it was a first start.
- **At launch** (`RetroSystem.power_on`, before the core starts, through `_game_memory_before_start`): the size rule; a card says "Game memory reset" when it fired (and where to get the memory back); for a
  game of class `bh` with nothing saved yet, **a first-start hint** ("the game may say BACKUP DATA ERROR; press TEST (the red button in the compartment) and follow its menu, then switch the cabinet
  off with its power switch so the game's memory is saved"). Not in a netplay start.
- **The DIP Switch tab has a "Game memory" section** for a cabinet with a MAME game in it (`RetroSystem.game_memory_state`, drawn by `CoreOptions2D._dip_memory_rows`): what is saved, the first-start
  note for `bh` games, **Reset game memory** (**asks twice**: the first press changes the button to "Press again: set aside this game's memory" for six seconds), and up to five **Put back <time>
  (<why>)** buttons for the copies set aside. It says what is lost (settings, high scores, bookkeeping and, for a gun game, calibration) and that **saved states keep their own copy of the memory** (they
  are not touched: loading one brings it back). Everything is greyed, with the reason, while: the game is running, or stopped less than **8 seconds** ago (MAME writes at teardown, on the emulation
  thread, after `StopContent` has returned: `RetroSystem._game_memory_stopped_ms`), or **another cabinet runs the same game** (they share one folder, as on real hardware), or a netplay session is running.
- **TEST and SERVICE start the game** and wait for it as a coin does, and the cabinet has an operator's **selector** (UP, DOWN, LEFT, RIGHT, ENTER = the first player's stick and button 1)
  beside them for the test menus of cabinets that have no stick: `arcade.md` "Service switches".
- Tests: `arcade_memory_tests` (groups `paths describe damaged quarantine restore prune launch table system ui`; 81 checks, 33 deliberate breakages each turn one red; the start's two cards are observed on the cabinet's own notice card).

What it does **not** do, on purpose: **generate or ship NVRAM images** (option D of the research): the format is documented only for the 16-byte identifier chunk and its complement checksum
(`nwk-tr.cpp:1741`, `viper.cpp:255-267`, `cobra.cpp:3106-3131`); the game's own chunks (settings, rankings, scope, gun) are not, and Python/Viper memories are "not possible to hand-create"
(`kpython.cpp:105-107`). MAME already seeds the chip from the hand-built image in the player's own zip. **Script the test menu** (option C): a recipe is a timed key schedule that wipes data if it
misfires (TEST held at power-on is a factory initialisation), and not one has been measured on a core. **Pin the date** (option F): no game is proven date-sensitive. **Judge a file by its content**: an
all-zero memory of the right size is not "damaged" (the game may call it an error; the player has Reset).

## 5. What a player can do today (OWED: from the manual's summary, not run)

Start the game, press TEST at the error screen, open the test menu (UP, DOWN, ENTER on the selector), run SCOPE SCREEN ADJUST then SAVE AND EXIT and the gun adjustment, leave through GAME
MODE, and **switch the cabinet off with its power switch** so the core is torn down and `…/nvram/sscope/m48t58` is written. If the error still comes back, Reset game memory and repeat.

## 6. Not verified

The on-screen text and triggers of the error (manual summary only); whether the hand-built images hold valid scope and gun blocks, and which byte ranges the game checks; whether POST reads the
clock inside the first emulated second and how it takes a 2026 year; that the files really land where the source says on a running core and on the Quest build; that RetroXR's every stop path reaches
`retro_deinit` (app pause, headset removed, crash: `WrapperEmuThread.cpp:165-173` is the normal one); that F2 reaches Silent Scope's TEST input through libretro-mame; which FinalBurn Neo drivers use
its own Timekeeper. **Option G of the research** (make sure every stop path ends the core cleanly, and read MAME's `Error reading/writing NVRAM file` lines out of `LogHandler::RecentErrors`
to tell the player the memory could not be saved) wants an accessor in the C++ extension (two platform rebuilds) and is the next step; the file's mtime not moving after a run would also tell.
