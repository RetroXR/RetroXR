# The Wii U (`wiiu`, parallel-gx2)

The Wii U runs on **libretro's parallel-gx2** (Cemu rewritten for libretro by its maintainer: no host locks or allocations in play, shader and pipeline work made ahead; the core RetroArch ships) **with RetroXR's branch on top**: `~/libretro-cores-retroxr/parallel-gx2`, branch `retroxr` off `libretro`, row `parallel_gx2` in `CoreSources` (RetroXR/parallel-gx2, pushed, `retroxr` its default branch; NOT YET RELEASED, so until then the core is built locally). It replaced RetroXR's own Cemu fork (RetroXR/cemu-libretro, row `cemu`, kept for a player who has it) on 2026-11-22: both started from WizzardSK/cemu-libretro, and the fork's features were ported as one commit each, written to parallel-gx2's rules (its AGENTS.md: changelog and README in the same commit, `tools/check_host_locks.sh` and `check_play_allocs.sh` green):

- GamePad: `VPADSetGyroDirection` applied (Ninja Castle's second star), and the **Exact Sensors** motion filter (`cemu_gamepad_motion_filter`).
- Wii Remotes: motion, MotionPlus, Nunchuk and IR pointer (`cemu_wiimote_motion`, `cemu_wiimote_pointer`), their state handed to padscore through a `SeqlockValue` per port, not the fork's mutex.
- Amiibo through the NFC reader (113), its save handed back through a `mailbox_t` and fixed buffers.
- The GamePad's speaker through the controller audio interface (110), kept apart by `TvPadMixer::PadGroupApart`, so parallel-gx2's same-frames pairing (its 12 ms comb fix) holds.
- HOME on joypad id 16, **asked for** (`RETRO_ENVIRONMENT_GET_JOYPAD_ID_COUNT`, 114): RetroArch reads joypad ids from 16 up as its own binds (16 = left stick X+), so the core reads id 16 only from a frontend that answers it.
- No content boots the Wii U Menu.

Not ported: the fork's Android-to-SDL axis turn (parallel-gx2 reads SDL's controller axes, so the GamePad now SENDS them, below), its audio backlog fix (parallel-gx2's FlushAudio already does one frame a run), the startup timing log. **Toy-base figures** were brought back on parallel-gx2 (`1c4f79b5`): its portals are lock-free (one command runner) and figure placement had gone with the desktop UI (`9e155f4a`), so placement is now a `FigureMail` per spot (`nsyshid/FigureMail.h`: a mailbox in for place/remove, one out for a game's write, fixed buffers) applied by the runner at every command, `hid_portal_submit_host` making one run at once; upstream's LoadSkylander/LoadFigure/RemoveFigure on the runner, the portal's status one word a status report advances with an atomic AND. `test/toy_bases` (the core's own objects, mutation-tested) and `wiiu_boot_probe --toys` (the real core publishes 32 spots, 16/9/7, and takes a Skylander dump on and off). Its two screens are its own: **Both Screens** goes out as two video views (TV over GamePad), which `RetroSystemModelWiiU.get_forced_core_options` pins (`cemu_screen_layout1`, one layout). The option keys kept their `cemu_` names. **`WiiUCoreMigration`** (boot, after `SaveMigration`) moves the old core's `save/cemu/Cemu/mlc01` to `save/parallel_gx2/Cemu/mlc01` where the new core has none (a rename), and copies `system/cemu/Cemu/{cafeLibs,keys.txt,titles}` where it lacks them; never overwrites (`wiiu_tests migrate/`). The console and its pads are primitive stand-ins in the base game. The detailed models (RetroXR-models `nintendo/wiiu/{console,gamepad,pro-controller,psu}`) can take their place later; the console is built in those models' frame and uses their marker names.

## Content

A NUS dump is a folder of encrypted `.app`/`.h3` files beside `title.tmd`, `title.tik` and `title.cert`. Cemu boots it from `title.tmd`, and needs no keys for it (only `.wud`/`.wux` need keys).

`wiiu.tres` has `folder_content`, so the library shows one row per folder. `RomLibrary.content_stem()` names a `title.tmd` by its folder, and `_MARKER_PREFERENCE` puts `tmd` last.

An update or DLC goes into `system/parallel_gx2/Cemu/titles/`, found there by title id. Saves go to the core's own `save/parallel_gx2/Cemu/mlc01/`, and nothing is staged.

## Two pictures, one frame: video views

Cemu draws the TV and the GamePad into ONE hardware frame. When the frontend says it presents views (`GET_VIDEO_VIEWS_STATUS`, `RETRO_VIDEO_VIEWS_STATUS_PRESENTS`), the fork packs them side by side in its `Views` layout:

- the TV at `(0, 0, W, H)`;
- the GamePad at `(W, 0, ⅔W, ⅔H)`, so 853 x 480 beside 1280 x 720 in a 2133 x 720 frame.

It sends `SET_VIDEO_VIEWS` before every `video_cb`: screen 0 is the TV, screen 1 is the GamePad.

Without views it uses the player's screen layout option, as it always has, and clears any map it sent. Touch stays in packed-frame coordinates, as the spec says, so Cemu's own sub-rect touch mapping is unchanged.

**libretro-godot** (`VideoViews.hpp`, `VideoHandler::SetVideoViews`):

- It validates and keeps the map beside the geometry, on the same mutex and serial.
- `Libretro.GetVideoViews()` gives `{rect (0..1 of the frame), screen, eye, aspect}` for the views that fit the latest frame. A rotated frame, or one a view does not fit, gets none.
- `XENU_NO_VIDEO_VIEWS=1` answers "not presented"; that is the probe's control leg.
- `tests/video_views_test.cpp` covers the map rules.

**RetroXR:**

- `RetroSystemModelWiiU.live_video_rect(0)` is the TV's view. `RetroSystem.video_window(ch)` prefers a model's live rect over the channel's own, so a set on the AV lead shows only the TV.
- `gamepad_rect()` is the GamePad's view. Before any views arrive the whole frame shows on both.

## Two traps the first boot hit

- **A frame-rate change is not a resize.** Wind Waker HD runs at 30 fps, and Cemu announces that through `SET_SYSTEM_AV_INFO`.
  - Cemu used to put its CURRENT output size into that call. The packed frame had already grown, so libretro-godot saw a new base size and rebuilt the Vulkan context. Cemu reads losing its context as the close, so the title shut down 1.5 s in with no frame.
  - Fixed on both sides. Cemu's `libretro_update_output_fps` now sends the size the frontend was last told; a new size goes over as `SET_GEOMETRY`. And `Wrapper::SetGeometry` now records the base size from `SET_GEOMETRY`.
- **Cemu's audio is made on the host's clock, not per frame**, and the fork handed a backlog over with the next frame. RetroXR's brake waits until the sink is back to its target, so a backlog put the core to sleep for as long as it lasted while another as long built up. After one slow boot frame the game settled at 10 fps in the room, for good (the room itself stayed smooth; `GetPacingStats`: 17.5 s of 20 asleep on the brake). The bare boot probe has no sink, so it read 60. Fixed in the fork: exactly one frame of audio a run, and a backlog past four frames is DROPPED back to two. Even a quarter frame of catch-up let the brake run it at only 48 (48 x 1.25 = 60). Measured with `wiiu_room_probe --perf=30` (`--nopair` the pairing control): Nintendo Land 10 -> 60, Wind Waker HD 30.
- **Cemu still crashes in `VulkanRenderer::DeleteNullTexture` when it unloads after its context has gone** (upstream; seen once, on the bad path above).

## Ports and pairing (WiiLink)

Every Wii U pad is wireless (`has_controller_sockets()` is false, so no cabinet sockets are shown). They pair as Wii Remotes do: SYNC on the console opens the window, then SYNC on the pad.

| libretro port | what | device |
|---|---|---|
| 0 | the GamePad (`WiiUGamePad`, `wants_gamepad_port()`) | `JOYPAD` (1) |
| 1-3 | a Pro Controller (`WiiUProController`) | Cemu's PRO, `SUBCLASS(JOYPAD, 1)` = 513 |
| 1-3 | a Wii Remote | Cemu's ids (below) |

A Wii Remote keeps Dolphin's ids as its kind. `WiiLink.wireless_device_id` turns them into Cemu's on a Wii U:

| Dolphin id | Cemu id |
|---|---|
| 1 | 257 |
| 513 | 1281 (sideways) |
| 769 | 1793 (Nunchuk) |
| 1793 | 2049 (MotionPlus) |
| 2049 | 2305 |
| 2305 | 2561 |

Any other extension becomes Classic, 769.

The remote is told apart by method (`get_nunchuk`), not by class: naming `Wiimote` in `wii_link.gd` closed a load cycle through `ScenePersistence`, and the GamePad's scripts failed to parse. A Wii is untouched: slots 0-3 and Dolphin's ids.

The console's forced options:

- `cemu_wiimote_pointer=ir`: the remote's aim is the sensor bar seen by its camera, as on the Wii.
- `cemu_wiimote_motion=enabled`
- `cemu_gamepad_motion=enabled`

## The GamePad

`WiiUGamePad` is a cordless `RetroPadController` (`WiiUWirelessPad`), built in code at its measured 255.7 x 133.9 mm. Its controls sit at the RETRO XR pad's node paths, so animation, pokes, bindings and the desktop pad all work unchanged. On top of that:

- **Screen:** the 137.3 x 77.2 mm glass shows the console's frame through `screen_window` with `source_rect = gamepad_rect()`.
- **Touch feel:** the console's System tab has a Touch Screen section (`TouchMenuRows`, `TouchFeel`), as a DS's and a 3DS's do: how close to the glass a fingertip touches and how far off it lifts (mm; lift-off is never closer than touch, each slider carries the other), and a light haptic on the hand that touches (0 is off). Saved on the machine (`touch_mm`, `lift_mm`, `touch_haptic`, only once changed). The GamePad's own menu (the generic object menu, `ObjectOptionsPanel`) shows the same section for the console it is paired with (`touch_feel_system()`), none while unpaired. Unset, each screen keeps its own distances (the GamePad and a DS on a TV 8 / 12.8 mm, the DS and 3DS handhelds 10 / 16). `touch_feel_tests`.
- **Touch:** a `TVTouchSurface` on the glass (one implementation for the DS on a TV and the GamePad). Its `uv_rect` follows the view, and touches go to `feed_touch` on port 0.
- **Motion:** `MotionSampler` derives accel and gyro from the pad's pose on the physics clock. **parallel-gx2 reads libretro's sensor axes as SDL's GAME CONTROLLER axes** (+X right, +Y out of the face, +Z toward the player; what a DualSense gives on RetroArch's udev driver), which ARE the pad's own frame, so they go out as they are (`WiiUGamePad.core_reads_android_axes`: false). Only the old fork read Android's (`android_axes`: +X right, +Y the top edge, +Z out of the screen) and turned them into SDL's itself (+Y out of the face, +Z toward the player: `sdl = (x, z, -y)`) before upstream's own conversion, which is written for SDL. Until fork v3 it fed Android's axes in as SDL's, a quarter turn about X: a GamePad lying flat read as one stood on its edge facing away, so Nintendo Land, calibrated with the GamePad put down, showed its picture upside down once it was held up. **And it is EXACT** (`cemu_gamepad_motion_filter=exact`, forced by the model): standalone's IMU gates out turns under 0.015 rad/s and learns the average of every reading under 0.35 rad/s as bias, both for real gyroscopes. On a pose-derived gyro they only lose motion, measured on Cemu's own `Mahony.h`: a slow 5.7° turn registered as 0° ("small movements don't count"), a 23° one as 20.7°, and a GamePad held still after 10 s of slow turning drifted 39.7° in 10 s. Exact: 5.7°, 22.7°, 0°.
- **A slow turn is not thrown away in RetroXR either** (`MotionSampler.tick_rotation`). The sampler took each tick's rotation from `Quaternion.get_angle()`, which is `2·acos(w)`; for one tick's rotation `w` rounds to 1 in 32-bit floats, so every turn up to 0.05° a tick read as exactly 0 (0.1° as 0.0885). Measured in the headset with a temporary motion trace: 1.1-1.5° of real turning a second sent 0.0°, while a 38° turn sent 40.3°. The quick part of a movement got through and the slow part did not, so slow turns did not count and the pointer went off in odd directions. Now `2·atan2(|xyz|, w)`, exact at any size (`wiiu_tests axes/`, mutation-tested).
- **`VPADSetGyroDirection` is applied** (fork; upstream only stores it). Nintendo Land's Ninja Castle sets the GamePad's attitude on its first throw, to say where the TV is. Unapplied, the first star hit the drum and no later one did, the GamePad lying still on a table included. Now the reported attitude is the game's at the set and follows the real turns from there (fork log: `the game set its attitude to …`). Verified in the headset: the second star hits.
- **Speaker:** the core pushes the GamePad's sound through the controller audio interface (location 0, port 0, index 0) when the frontend takes it. Otherwise it is mixed into the TV. It is STEREO (Cemu sets the DRC to stereo, `AVMGetDRCSystemAudioMode`), and the GamePad asks libretro-godot for it in stereo (`SetControllerAudioStereo`, controller-audio.md): the left voice at `SpeakerL`, the right at `SpeakerR`, the two slots by the bottom corners (RetroXR-models params `smalls`: x +-84.4 mm, 54.1 below the middle; left the D-pad's side). An older libretro-godot folds it to one voice, played between them. `wiiu_tests speakers/`.

The Pro Controller lights its player lamp (port N is player N).

The GamePad's speaker was measured in the room: its sound gets a voice of its own, `controller 0.0 plays on voice 2`, beside the TV's voices 0 and 1, but only once the game plays something on it. At Nintendo Land's title it is silent, so no voice exists yet.

## HOME

Every Wii U controller with a HOME to press sends it, but not on one bit:

- **GamePad and Pro Controller:** the RetroPad's sixteen ids are all taken, so HOME is **joypad id 16**, RetroXR's own numbering. libretro-godot's button word is 32 bits (ids 16-31 answered past the RetroPad's; `RETRO_DEVICE_ID_JOYPAD_MASK` still the sixteen), and the core reads id 16 (`RETROXR_JOYPAD_ID_HOME`), only after libretro-godot answers `RETRO_ENVIRONMENT_GET_JOYPAD_ID_COUNT` with 32 (`JoypadIdCount.hpp`; `XENU_NO_JOYPAD_ID_COUNT=1` refuses it, the control: the press is sent and never read), into `VPAD_HOME` (0x0002, both in `VPADController`'s table and the libretro read in `vpad.cpp`) and `kProButton_Home`; upstream Cemu had HOME in neither table. RetroArch does not answer the call, so there they still have none, and its left stick does not press HOME. In RetroXR it is the `Model/Home` cap (`WiiUWirelessPad.HOME_BIT`), pressed with a fingertip like the caps beside it; press and release are logged on both sides (`[WiiU] ... HOME pressed`, the core's `[libretro] GamePad HOME pressed`).
- **Wii Remote:** HOME is on **L**, the fork's remote layout (`libretro_map_wiimote`), which is not Dolphin's: on a Wii U `wiimote.gd` sends `Wiimote.cemu_bits()` (A on B, B on A, 1 on Y, 2 on X, HOME on L; with a Nunchuk 1/2 on L2/R2; no "shake", Cemu reads it off the accelerometer), and Dolphin's table on a Wii. Before, a remote on a Wii U sent Dolphin's bits, so A/B and 1/2 were crossed and HOME (R3) reached nothing.

What HOME does is the title's business: Cemu has no HOME Menu overlay (the OS switching to it is not emulated; `OSEnableHomeButtonMenu` only stores a flag). `wiiu_tests home/`.

## The Wii U Menu

Cemu runs the system menu from an installed system title: a dump laid into the core's `mlc01` (the US menu is `sys/title/00050010/10040100`), started as content by its executable, `code/men.rpx`. Measured with `wiiu_boot_probe` (2026-11-22): 60 fps, both screens; the EULA notice, A to its agreement, a TAP on the GamePad's Agree (A does not press it), then the home screen, the Mii plaza on the TV and the app grid on the GamePad. HOME reaches the core there and nothing opens.

**A Wii U with no disc boots it** (2026-11-22, both cores; on parallel-gx2 in the room from the migrated mlc01): `BiosBoot` rows `parallel_gx2/wiiu` and `cemu/wiiu` (`no_content`, gated by `wiiu_menu` on `WiiUSystemMenu.is_installed()`: a `men.rpx` in `<save>/parallel_gx2/Cemu/mlc01/sys/title/00050010/1004{0100,0200,0000}`), and the fork, given no content, boots the first of those it finds (`libretro_wiiu_menu_path`, the same order; `supports_no_game` true) and refuses the load without one. No menu in mlc01, no row: the console says no game inserted, as before. Nothing installs it: the player lays their console's mlc01 dump in. `wiiu_tests menu/`; in the room, `wiiu_room_probe --nodisc` (POWER on an empty slot, OK and Agree tapped on the GamePad's glass, the home screen on both screens; its check, that the TV left the agreement, passed at 0.21 against a 0.2 bar, so read the stills too). Starting a game from the menu is untested.

    "$godot" --path RetroXR --resolution 320x240 --position 20,20 res://DevTools/cores/wiiu_boot_probe.tscn --       --rom="$HOME/retroxr/libretro/save/parallel_gx2/Cemu/mlc01/sys/title/00050010/10040100/code/men.rpx" --seconds=170       --press="8@35,8@45,8@55,16@150" --touch="0.7843:0.5944@70" --shots="85,145,168" --shot=menu.png

## The GamePad cradle and its adapter

`WiiUGamePadCradle` (WUP-014) is a black primitive at `Scenes/Objects/peripherals/wiiu/`; another session is making the real model.

- **Seating:** the GamePad drops into its `PadSeat` (snap zone, group `wiiu_gamepad`) on its bottom edge, screen forward, leaning back 15°.
- **Contacts:** the two tabs and two contacts sit where the GamePad's support slots and charging terminals are (RetroXR-models gamepad: x ±37 and ±10 mm). The cradle's size is ESTIMATED; nothing publishes it.
- **Power:** the GamePad AC Adapter (WUP-011, `wiiu_gamepad_ac_adapter`, a grey inline brick, plug `wiiu_gamepad_dc_plug`, size ESTIMATED) goes into the cradle's back (`PowerInlet`) or straight into the GamePad's top (`ACAdapterPort`, x -54 mm).
- **Charging:** the GamePad charges (`is_charging()`, its orange lamp) while its cradle has the adapter's plug in, or its own port does, under the room's power rule. No charge is modelled; the GamePad runs either way.
- **Saving:** the CRADLE records the GamePad in it (`gamepad`, a reference field, written only while one stands there), as a stand records its console; a restore seats it again through `restore_pad` (`wiiu_tests` `cradle/`, mutation-tested).

## Amiibo

The GamePad's NFC touchpoint is an `NfcTouchZone` (`NfcZone`), below the D-pad. The real mark is at x -85, 24 mm toward the bottom edge (RetroXR-models params `nfc`); the primitive puts it lower, clear of its own D-pad, and xenu.wiiugamepad moves it onto the shell.

- **Files:** dumps go in `<roms>/amiibo/` with any subfolders. `FigureShelves` takes a `.bin` when its lock, capability container and CFG bytes are an NTAG215's (540 bytes, or 572 with the signature). Cemu makes the same test. The 2048-byte Switch 2 dumps fail it and are left off. A figure's series is its folder, so "Donkey Kong" in two series makes two rows. A dump under a folder named for cards spawns as a card.
- **No key:** the fork decrypts with its own built-in keys, so `key_retail.bin` is never asked for and the BIOS page has no row for it.
- **Shelf:** the Games tile `amiibo` (art `amiibo.svg` / `amiibo-content.svg`) shows when Cemu is installed or the folder has something in it. A row spawns a `ToyFigure`: a 40 mm base with a standee and the name, or a 54 x 85.6 mm card. A save keeps its dump's path (`rom`).
- **Touch:** a figure whose underside, or a card whose middle, is within 2 cm of the mark and 3 cm across it is handed over with `SetNfcTag(<absolute path>)`, with a short tick on the hand holding it. Taking it away calls `ClearNfcTag()`. Cemu keeps a touch for about 2 s and only reacts to a tag arriving, so a figure is set down again for a game that asks later. A new core (the console power-cycled) is touched afresh. A dump the reader refuses is offered once until it is taken away. The core writes a game's saves back into the `.bin`.
- **Not yet:** netplay. The zone stays inert in a session, because `SetNfcTag` reaches only the local core. No other core reads NFC: Azahar has `LoadAmiibo` but its libretro build has no NFC interface.

## Toy bases: Skylanders, Disney Infinity, Lego Dimensions

Each base is a primitive `ToyBase` with a captive 2 m lead ending in a USB-A plug (`toy_base_cable.tscn`, the game's USB-A plug model). The plug goes in any of the Wii U's four USB sockets (`SystemPorts.build_usb`; passive, so nothing is announced on a libretro port). They spawn from the Wii U's card.

| Base | Scene | Spots (Cemu's readers, in order) | Shelf (`roms/<id>`) | Dump |
|---|---|---|---|---|
| Portal of Power | `toys/skylanders_portal` | one top, 16 figures | `skylanders` | 1024 bytes, UID check byte right; `.sky .bin .dump .dmp` |
| Infinity Base | `toys/infinity_base` | hexagon 0-2, player one 3-5 (left), player two 6-8 (right) | `disneyinfinity` | 320 bytes |
| Toy Pad | `toys/dimensions_toypad` | left 0, 3, 4; centre 1; right 2, 5, 6 | `legodimensions` | 180 bytes, NXP 0x04 first |

- **The core:** parallel-gx2 (RetroXR's branch, `FigureMail`, above), as the old Cemu fork (branch `toy-bases`) did before it, publishes each spot of a base it emulates as an accessory reader (`AccessoryInterface.hpp` kinds 1-3, appended to the shared block). Inserting a reader opens the dump writable, so a game's save goes back into the file. The bases attach when the title starts, so `ForcedCoreOptions.toy_bases` pins `cemu_emulate_skylander_portal` / `_infinity_base` / `_dimensions_toypad` to the bases on that Wii U's sockets. A base plugged in while a game runs is found at the next start (`RetroSystem.refresh_toy_base_option`), and its ring stays dark until then.
- **The room:** `ToyBase` finds its Wii U from the socket its plug is in, then asks for the core's readers (`RequestAccessoryReaders`, `accessory_readers_changed`). A figure of its own line whose tag is over a spot goes on that spot's first free reader (`InsertAccessoryMedia`, absolute path); taking it off calls `RemoveAccessoryMedia`. The readers come again after every insert. A figure the core no longer has (`present` false, after a reset) is handed over again, and a different set of readers starts the base afresh.
- **Figures:** `ToyFigure` takes its look from its shelf (a round base and standee; a thin toy tag for Dimensions). Any Infinity dump stands as a figure, since telling a Power Disc apart needs the figure decrypted. The three shelves have no Systematic art, so they use the default icon.
- **Saving:** a base saves its kind, plus the console and the socket its lead is in (`_toy_base_entry`, `ToyBase.restore_connection`).
- **Not yet:** netplay (local only, inert in a session), a real game test (no Skylanders, Infinity or Dimensions title here), Dolphin's emulated bases (its libretro build reaches none), and the release of the Cemu build.

## Power and AV

- **Power:** DC from the WUP-002 brick (`wiiu_ac_adapter`, plug `wiiu_dc_plug`, sizes from RetroXR-models' `psu/asset_stats.json`), into the console's `DCIn` mouth.
- **AV:** the AV MULTI OUT is the Wii's own socket and lead (`wii_av_cable`), and the HDMI OUT (`HdmiOut`, an `HdmiPort` built in `configure_av_ports` on the `HdmiAnchor` marker, `rf_feed`) takes the HDMI Cable to a set's HDMI IN, picture and sound on one plug (av-suite.md "HDMI").
- **Not modelled:** the front USB and SD.

## Checks

- **`Tests/wiiu_tests.gd`** (no core): model, views, pairing, ids, touch, axes and cradle. Its slot rule and its axes were mutation-tested.
- **`Tests/figure_tests.gd`** (no core, dumps written by the suite): each shelf's file test; the shelves; an amiibo on a real zone being set, lifted, set again and refused; a base's lead seated in a socket, with figures going on and off its spots and resent after a reset; and the pinned options.
- **`DevTools/cores/wiiu_boot_probe`** (windowed, real Cemu):
  - `--leg=views` (default): two views, both lit.
  - `--leg=noviews` with `XENU_NO_VIDEO_VIEWS=1`: the control (no map, a 1280 x 720 frame).
  - Measured 2026-11-20 with Nintendo Land and Wind Waker HD (NUS, US).
- **`DevTools/models/wiiu_room_probe`** (windowed): a console, a set on the AV lead, the GamePad and a Pro Controller paired, a disc in and POWER. The set shows the TV view and the GamePad its own.
  - With no save, Nintendo Land waits at its title ("Touch the Wii U GamePad to start", a red curtain) for as long as nobody touches it. With a save it plays an attract loop instead. So the probe sets the save aside and puts it back afterwards (`--keep-save` to skip that).
  - `--touch=tap` touches the GamePad's glass: the curtain must go, and the GamePad's speaker must then have a voice.
  - `--touch=none` is the control: the curtain must stay.
  - `--perf=N` times the room's frames, the core's frames and its pacing for N seconds from POWER; `--nopair` leaves the pads unpaired. The boot probe prints the core's fps every second too.
- **Nintendo Land sometimes sticks on its green loading screen**, at boot or after the first-run box, for minutes. That is open; it could be Cemu or the missing shared fonts (`OSGetSharedData` uses a placeholder). Re-run when a leg never reaches the title.
- **`DevTools/models/wiiu_render_probe`** (windowed, no core): stills of the console, the GamePad standing in its cradle with the WUP-011 plugged in, the Pro Controller and both adapters.

## On the Quest

parallel-gx2 has an AArch64 PowerPC recompiler (upstream's, `BackendAArch64.cpp`, on xbyak_aarch64) beside the x64 one, hardware AES on ARM and a NEON index path; the rest of its SIMD is x86 only. **Measured 2026-11-22, Quest 3, core alone (no room):** Nintendo Land to its title, both screens as two views, median **60 fps** (51.7-64.5 over 139 one-second samples after boot), first views 10 s in. The title screen is light; gameplay and the VR room on top are not measured.

How: the `Quest wiiu probe` preset (package `com.xenu.retroxr.wuprobe`, main scene `wiiu_boot_probe`) reads its arguments from `wiiu_probe_args.txt` in its external files dir. The core goes into its INTERNAL `files/libretro/cores/` through `run-as` (`adb push` to `/data/local/tmp`, then `cat | run-as … sh -c 'cat > …'`), the game into its external `files/roms/wiiu/`. A folder `adb push` makes there is `shell`-owned 2770, which the app could not list here (`--rom must name a file that exists`), so the test content got `chmod -R o+rX` (read-only content only; never for files the app writes). Build the core with the NDK's Windows toolchain: `make platform=android-arm64 NDK_ROOT=… ANDROID_NDK_LLVM=…/prebuilt/windows-x86_64` (the Makefile assumes linux-x86_64). A first launch stops on the permission dialog and Horizon drops the launch; grant the runtime permissions (`pm grant`) or accept it in the headset, then launch again.

**OWED:** the release of RetroXR/parallel-gx2 (pushed, branch `retroxr` its default; CoreSources names `retroxr-parallel-gx2-v1`, not tagged yet), a game's own test of the toy-base figures (no Skylanders, Infinity or Dimensions title here), a headset, the Quest (no Android build of the branch yet; parallel-gx2's own buildbot builds Android), netplay (Cemu has no savestates), a Wii U on HDMI and AV Multi to two sets at once (only the first video sink gets `on_tv_connected`), the detailed models, the GamePad's microphone and camera, and the remotes' speakers (Cemu does not emulate them).
