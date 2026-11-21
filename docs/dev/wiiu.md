# The Wii U (`wiiu`, Cemu)

The Wii U runs on RetroXR's Cemu fork: RetroXR/cemu-libretro, branch `retroxr`, row `cemu` in `CoreSources`. The console and its pads are primitive stand-ins in the base game. The detailed models (RetroXR-models `nintendo/wiiu/{console,gamepad,pro-controller,psu}`) can take their place later; the console is built in those models' frame and uses their marker names.

## Content

A NUS dump is a folder of encrypted `.app`/`.h3` files beside `title.tmd`, `title.tik` and `title.cert`. Cemu boots it from `title.tmd`, and needs no keys for it (only `.wud`/`.wux` need keys).

`wiiu.tres` has `folder_content`, so the library shows one row per folder. `RomLibrary.content_stem()` names a `title.tmd` by its folder, and `_MARKER_PREFERENCE` puts `tmd` last.

An update or DLC goes into `system/cemu/Cemu/titles/` and is installed from there by Cemu. Saves go to the core's own `save/cemu/Cemu/mlc01/`, and nothing is staged.

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
- **Touch:** a `TVTouchSurface` on the glass (one implementation for the DS on a TV and the GamePad). Its `uv_rect` follows the view, and touches go to `feed_touch` on port 0.
- **Motion:** `MotionSampler` derives accel and gyro from the pad's pose on the physics clock. `android_axes` maps them to Android's axes (+X right, +Y the top edge, +Z out of the screen), which is what Cemu reads for the GamePad.
- **Speaker:** the fork pushes the GamePad's sound through the controller audio interface (location 0, port 0, index 0) when the frontend takes it, so it is posed at `Speaker`. Otherwise it is mixed into the TV.

The Pro Controller lights its player lamp (port N is player N).

The GamePad's speaker was measured in the room: its sound gets a voice of its own, `controller 0.0 plays on voice 2`, beside the TV's voices 0 and 1, but only once the game plays something on it. At Nintendo Land's title it is silent, so no voice exists yet.

## The GamePad cradle and its adapter

`WiiUGamePadCradle` (WUP-014) is a black primitive at `Scenes/Objects/peripherals/wiiu/`; another session is making the real model.

- **Seating:** the GamePad drops into its `PadSeat` (snap zone, group `wiiu_gamepad`) on its bottom edge, screen forward, leaning back 15°.
- **Contacts:** the two tabs and two contacts sit where the GamePad's support slots and charging terminals are (RetroXR-models gamepad: x ±37 and ±10 mm). The cradle's size is ESTIMATED; nothing publishes it.
- **Power:** the GamePad AC Adapter (WUP-011, `wiiu_gamepad_ac_adapter`, a grey inline brick, plug `wiiu_gamepad_dc_plug`, size ESTIMATED) goes into the cradle's back (`PowerInlet`) or straight into the GamePad's top (`ACAdapterPort`, x -54 mm).
- **Charging:** the GamePad charges (`is_charging()`, its orange lamp) while its cradle has the adapter's plug in, or its own port does, under the room's power rule. No charge is modelled; the GamePad runs either way.
- **Saving:** the cradle saves its pose. Which GamePad stands in it is not saved yet (OWED).

## Power and AV

- **Power:** DC from the WUP-002 brick (`wiiu_ac_adapter`, plug `wiiu_dc_plug`, sizes from RetroXR-models' `psu/asset_stats.json`), into the console's `DCIn` mouth.
- **AV:** the AV MULTI OUT is the Wii's own socket and lead (`wii_av_cable`), and the HDMI OUT (`HdmiOut`, an `HdmiPort` built in `configure_av_ports` on the `HdmiAnchor` marker, `rf_feed`) takes the HDMI Cable to a set's HDMI IN, picture and sound on one plug (av-suite.md "HDMI").
- **Not modelled:** the front USB and SD.

## Checks

- **`Tests/wiiu_tests.gd`** (no core): model, views, pairing, ids, touch, axes and cradle. Its slot rule and its axes were mutation-tested.
- **`DevTools/cores/wiiu_boot_probe`** (windowed, real Cemu):
  - `--leg=views` (default): two views, both lit.
  - `--leg=noviews` with `XENU_NO_VIDEO_VIEWS=1`: the control (no map, a 1280 x 720 frame).
  - Measured 2026-11-20 with Nintendo Land and Wind Waker HD (NUS, US).
- **`DevTools/models/wiiu_room_probe`** (windowed): a console, a set on the AV lead, the GamePad and a Pro Controller paired, a disc in and POWER. The set shows the TV view and the GamePad its own.
  - With no save, Nintendo Land waits at its title ("Touch the Wii U GamePad to start", a red curtain) for as long as nobody touches it. With a save it plays an attract loop instead. So the probe sets the save aside and puts it back afterwards (`--keep-save` to skip that).
  - `--touch=tap` touches the GamePad's glass: the curtain must go, and the GamePad's speaker must then have a voice.
  - `--touch=none` is the control: the curtain must stay.
- **Nintendo Land sometimes sticks on its green loading screen**, at boot or after the first-run box, for minutes. That is open; it could be Cemu or the missing shared fonts (`OSGetSharedData` uses a placeholder). Re-run when a leg never reaches the title.
- **`DevTools/models/wiiu_render_probe`** (windowed, no core): stills of the console, the GamePad standing in its cradle with the WUP-011 plugged in, the Pro Controller and both adapters.

**OWED:** a headset, the Quest (the fork's Android build has never run a game), netplay (Cemu has no savestates), a Wii U on HDMI and AV Multi to two sets at once (only the first video sink gets `on_tv_connected`), the detailed models, the GamePad's microphone and camera, and the remotes' speakers (Cemu does not emulate them).
