# The welcome page (WelcomePanel)

One page that stands in front of the player when the room is ready, at the start of
every launch until they say not to:
**DO** (open the menu, download the recommended cores, where ROMs go, build it like
the real thing, grab/drop, options, focus) and **DON'T** (games or BIOS files you
don't own), then **MORE HELP**: buttons to the site and the Discord, beside a looping **clip of the menu being used** and, on the headset's
page, **the player's own controllers pressing each button**. A headset and a desk
get different pages, built once by `MenuStyle.is_vr_mode()`: a player in VR has no
Tab key and one at a desk has no left stick.

| file | what |
|---|---|
| `Scripts/UI/panels/welcome_2d.gd` (`Welcome2D`) + `Scenes/UI/welcome_2d.tscn` | the page, built in code from MenuStyle: the copy (consts `DO_VR`, `DO_DESKTOP`, `DONT`) left, the clip (`MENU_CLIP`) right, and on the headset's page the STAGE under it with the step written below (`set_step`) |
| `Scripts/UI/panels/welcome_panel.gd` (`WelcomePanel`) | the run-time `XRToolsViewport2DIn3D` it is drawn on, `due()`; stands the ControllerDemo at the stage |
| `Scripts/UI/panels/controller_demo.gd` (`ControllerDemo`) | the headset page's two controllers and their `STEPS` |
| `Scripts/UI/panels/controller_stand_in.gd` (`ControllerStandIn`) | a primitive controller with Meta's rig shape, for a hand with no runtime model |
| `Scripts/XR/controller_rig.gd` (`ControllerRig`) | how a model's rig moves each input, shared with `ControllerModel` |
| `Textures/welcome/menu_clip.ogv` | page 1's clip: Ogg Theora, 880 x 720, 30 fps, silent, about 20 s |
| `Textures/welcome/hookup_clip.ogv` | page 2's clip: an NES hooked up in the bedroom, 960 x 540, about 30 s |
| `Tools/room/nes_hookup_probe` + `Tools/room/roms/brix.nes` | films page 2's clip; the ROM is BrickBreaker (MIT), credited in ABOUT |
| `Textures/welcome/upload_clip.ogv` | page 3's clip, a Quest's only: a ROM uploaded through the Web File Manager, 960 x 540, about 21 s |
| `Tools/net/web_upload_probe` + `Tools/art/film_web_upload.py` | serve a scratch data folder with the real `WebFileServer`, and film page 3's clip in Chromium against it |
| `SpawnMenuController._offer_welcome` / `_show_welcome` | when, and where it stands; hands over the two `ControllerArt`s |
| `AppPrefs.show_welcome` / `set_show_welcome` / `show_welcome_changed` | whether it comes up at start; the ONE way to change it |
| `SpawnMenuOptionsView._build_welcome_option` | OPTIONS > General > Show Welcome Page at Start |

## When it shows

- Once per launch, at the end of `_connect_menu_signals()` (after
  `notify_scene_content_ready`), then after `LoadingOverlay.overlay_hidden` if the
  curtain is still up — in front of a player who can see it and act on it. Never
  headless. At least `WelcomePanel.MIN_DISTANCE` (1.1 m) off: it is as wide as the menu.
- **Every launch while `AppPrefs.show_welcome` is on** (default on, the missing key
  too). **Done** puts it away for this launch. **Don't Show Again** also switches
  it off; **OPTIONS > General > Show Welcome Page at Start** switches it back on.
  **Both stand on the LAST page only** (with the note saying where the switch is):
  the way out is through every page; Next, green as Done is, stands on every other.
  Opening the menu (which stands where the page does) or a room change puts it away
  and changes nothing.
- Both go through `AppPrefs.set_show_welcome`, which saves and emits
  `show_welcome_changed` only on a real change: the OPTIONS switch is built with the
  menu, before the page is pressed, so it follows that signal, and setting it
  re-enters the setter, which does nothing when nothing changed (no loop).
- ABOUT's "Show the Welcome Page Again" stands it again whatever `due()` says
  (`welcome_requested`, relayed by `SpawnMenu2D`).
- The startup "Menu" HeldHint waits for it (`_hint_waits_for_welcome`): the page says
  the same thing, and two popups at once is how neither gets read. Opening the menu
  over the page drops the held hint, since the player has just done what it teaches.

## The headset page's controllers (ControllerDemo)

- **They are the player's own**: COPIES of what the hands show (`ControllerArt`),
  laid in the controller's AIM frame, so a Quest 2, 3 or Pro player sees that
  controller and nothing is asked of the runtime. Meta's model (`XR_FB_render_model`,
  the `GripAnchor/FbRenderModel` child) is copied whole with its rig; the core tier
  (`XR_EXT_render_model`) animates its own nodes from the runtime, so only its meshes
  are copied and they stand still (the marker still says which button). The copy's
  surface overrides are cleared: they are ControllerArt's FADE materials, which a grab
  turns see-through.
- A hand with no model yet gets `ControllerStandIn` and swaps on `art_changed` (Meta's
  runtime retries for half a minute after a controller wakes). The stand-in is not a
  likeness; it is built like Meta's model (Skeleton3D with Meta's bone names, one
  "All Animations" clip running every input) so it goes through the same code.
- **Presses go through `ControllerRig`**, the reader `ControllerModel` uses for the
  hand's own buttons. A stick's ROTATION track is its lean, so a click passes
  `turn = false` and only moves it.
- `STEPS` name bones in Meta's rig; `welcome_tests demo/` holds every one to a bone
  the rig has AND one `ControllerModel` drives. Each step has a `view`: "top" (as you
  see your own hand, for the stick and face buttons) or "side" (profile, for the
  trigger and grip on the front edge). A cyan marker (no depth test) sits on each
  pressed bone. The demo carries its own small light: a dark model on a dark stage in
  a dark room says nothing.
- **Desktop checks only ever see the stand-in**: OpenXR hands over no model without a
  running headset session. How the real models look on the page is OWED to a headset.

## Page two: hooking up a console

**Next** (page 1) shows `HOOKUP_TITLE`, the hookup clip and `HOOKUP_LINES` beside it,
with the game's credit; **Back** returns. Done and Don't Show Again are under the
last page. Next and Back step one page (`show_page(_page ± 1)`) and stand only where they
lead somewhere: page 2 is the last page off a Quest, so it has no Next there.
`show_page` pauses every hidden page's clip and plays the shown one's;
`page_changed` makes WelcomePanel refit (the pages differ in height) and shows the
3D controllers only on page 1, where their stage is. Both clip pages are built by
`_build_clip_page`, the clip drawn at `HOOKUP_SIZE`.

The clip is FILMED in the real app by `Tools/room/nes_hookup_probe` (windowed):

- **The bedroom without its PlayerRig** (it is what restores the player's saved
  room; no welcome page, no menu), mods off, its own camera in a SubViewport with a
  caption bar drawn over it.
- **A table**, the RETRO XR set and the NES side by side facing the camera, the
  table 0.35 m off the wall so a camera fits behind the set, where its inputs are.
  Both are stood ON the table by what they draw (`_rest_on`): placed by origin the
  set sank half its height into the top.
- **Every step through the calls a hand's own makes**: plugs eased to just off the
  socket, then the zone's `pick_up_object`; the model's `play_open`/`play_close`;
  the cart onto the tray's perch and in, `toggle_cart_tray()`; POWER's VRButton
  `button_pressed`; START through a stand-in fingertip (`PressPoke`, a ControlPoke
  whose poll holds the bit), so the pad's cap moves AND the core reads it.
- **Frames on the WALL clock** (a slow frame is repeated, never stretched): the
  core runs on its own thread in real time, and a game-time film would show the
  game fast or slow. `--layout` places everything connected and saves a still per
  framing, to stage by.
- **Cords on film (the first cut's cables were jumpy; fixed 2026-11-06)**: frames are
  taken by a loop of their own (`_capture`), and a carried plug moves a step every
  PHYSICS tick on the wall clock (moved once a rendered frame, about three ticks at
  the film's rate, the solver got the plug in jumps and the cord swung back and
  forth). The AV lead is LAID on the table, each plug 16 cm out from its own socket
  (`_lay_cable`): dropped anywhere, its B end slid to the floor and was hauled a metre
  up over the table's edge, and its pair lay crossed. Each end's two plugs are
  carried TOGETHER in a lifted arc (`_seat_all`): one at a time, the first seated
  held the lead's short fork while the second was taken away from it, and it snapped
  taut. `_watch_cord` logs the cord's jerk next to each end on every carry; the
  `--old-seat` leg brings back the old carry as the control (mean jerk 4.2/7.6 mm
  then, 0.7/1.9 now, the worst B-end jolt 111 mm then, 10 now), and a film with
  none of its frames flipping back and forth (A-B-A) is the check on the video.
- **Nothing goes through the console or the set (second cut, same day)**: "straight
  out of a jack" is from the middle of the thing it is on through the jack, level
  (`_out_of`), NOT the jack's own Z, which on the console's jacks points up: the AV
  plugs were brought down through the console's lid. Each pair is laid where it is on
  the table AND clear of both bodies (`_lay_offset`: straight out, then along the
  side), and carried on a smooth curve (`_carry_path` + `_along`, Catmull-Rom) up,
  round to a point straight out from the jack, and in, raised over a body only where
  the way would meet one. `_inside_body` tests the bodies' DRAWN parts, each in its
  own frame: their collision reaches far past the shell (a point 16 cm out from a
  jack was "inside" it) and both are turned, so an axis-aligned box lies too. Every
  tick of a carry, the push home included but its last quarter, is tested, and one
  inside fails the film; steering the approach 20 cm into the body fails all five
  carries, which is the check's control.
- **The pad's cord** (`ControllerCable`, a node of its own beside the pad, not under
  it) is laid in ONE circular arc of its own length from the pad to its plug
  (`_lay_pad_cord`, `VerletRope.restore_points`): dropped, it lay in loops over each
  other and twitched all film (such a loop never quite sleeps, `rope.md`). An arc
  crosses itself only past a full circle, so a long cord bends further round, up to
  330 deg, rather than the pad moving (moved out to fit half a circle, it fell off the
  table). `_watch_cord` watches it on every carry too.
- **Checked as it films**: the tray latched and the machine reading the cart, a
  picture on the set, START changing what the set shows. It fails otherwise.
- The NES-001 is the shipped detailed model: there is no primitive NES (the
  Famicom is the primitive), and the NES has no mains inlet, so no power lead.
- Encode: `encode_welcome_clip.py <frames> --name hookup_clip --width 960`.

## Page three, a Quest's only: putting games on

On a Quest (`_is_android()`, or `android_override` / `force_android` for a desk),
Next on page 2 shows `UPLOAD_TITLE`, the upload clip and `UPLOAD_LINES`: OPTIONS >
File Server, the headset's own address, the PIN, media > roms > the system, choose
files, then the system's page under SPAWN, which rescans its folder when opened
(`SpawnMenuSpawnView._populate_cartridges_detail` drops its cached listing), so the game is there. A desktop
has a folder of its own, which page 1 names, so it gets no such page.
`welcome_tests copy/` holds the lines to the server: `headset_url()`, its `media`
root, and the words on its own buttons (`WebFileServer._HTML`'s "choose files" /
"choose folder").

The clip is the REAL server in a real browser, never a mock-up:

- `Tools/net/web_upload_probe` (headless) points the data root at
  `<scratch>/data` through `DataPaths.set_config_path_for_tests`, lays out a few
  `roms/<system>/` folders, and serves it with `WebFileServer` on 8080, PIN 1234, until
  `<scratch>/stop` appears. It refuses to run without `--scratch`: it never serves
  the player's own folder.
- `Tools/art/film_web_upload.py` (Playwright Chromium, 960 x 540) signs in, opens
  media > roms > nes, picks `Tools/room/roms/brix.nes` through the page's own file
  chooser, waits for it in the list, checks it reached the scratch folder, writes
  `stop`. Wait for the probe's `[webprobe] serving` line before starting it: the
  first try started the browser before the server listened (`ERR_CONNECTION_REFUSED`).
- The cursor, the captions and the address bar are drawn BY THE PAGE (an init
  script); a recording has none of them.
- **Frames come from Chromium's screencast** (`Page.startScreencast`, PNG, each
  stamped with its swap time) laid on a 30 fps timeline, each held until the next.
  Playwright's own recorder draws at the page's CSS size whatever the device scale
  (a page zoomed for legibility came out small in a grey frame) and is lossy VP8 on
  top of Theora. The screencast is CSS pixels too, so the page is laid out at 960 x
  540, a phone's width: shown 1280 wide on the welcome page, its 14 px text reads a
  third larger. Its waits go through `page.wait_for_timeout`, never `time.sleep`:
  a frame is sent only once the last is acked, and acks are answered only while
  Playwright has control.
- Inside a folder the list always has its `..` row, so an empty folder never says
  "Empty": wait for the `..` row pointing back up instead.
- Encode: `encode_welcome_clip.py <scratch>/frames --name upload_clip`.

## The menu clip

Recorded from the REAL menu, not drawn: `Tools/room/welcome_clip_probe` (windowed)
builds `spawn_menu.tscn` at its own 2200 x 1800 in a SubViewport and drives it with
real mouse events (hover and press states are the menu's own) under a drawn pointer
dot, saving each frame at 0.4; `Tools/art/encode_welcome_clip.py` makes the `.ogv`
with imageio-ffmpeg's ffmpeg (it has libtheora). Both engines, the Quest's patched
one included, carry the theora module, so it is Godot's own `VideoStreamPlayer` —
no VLC.

- **Nothing of the recording machine in a clip that ships**: `_scrub()` rewrites any
  label holding the home folder to `~`. Look at the frames before committing a new
  clip (the systems grid shows that machine's cores and hidden count).
- It presses views only (CORES, SPAWN, a system's card, TVs); "Download All
  Recommended" and the spawn rows are pointed at, never pressed.
- The pointer aims BESIDE a label (`_aim`), or the clip hides the word it points at.
- `--map` lists every pressable control per stage with its rect, to pick targets.
- Re-record after the menu changes its look; the clip is a picture of the menu.

## Rules

- **The copy must match the real bindings.** `welcome_tests copy/` holds the drops to
  `HeldHint.DESKTOP_DROP_GLYPHS` / `VR_DROP_GLYPHS` (the README had the desktop drop
  on Ctrl + click while the code had Shift). Change a binding, change the page and
  the demo's `STEPS`.
- The ROM folder is `DataPaths.media_root("roms")` at run time, on the desktop.
  **A Quest is told the Web File Manager and nothing else** (`QUEST_ROMS_LINE` in
  place of the folder line, and `DONT_QUEST`): a file a file-manager app, a PC over
  USB or adb puts in the app's folder belongs to that other owner (uid), so RetroXR
  can read it at best and never change or delete it, and may not be let into a folder
  made that way (quest-device.md on `adb push`). The Web File Manager writes as the
  app. The line names `WebFileServer.headset_url()` (localhost:8080), which the
  headset's own browser opens with no other device; OPTIONS > File Server shows it
  beside the LAN address (`address_text`), and `welcome_tests` holds the line to it. `android_override` / `do_lines(vr, android)` / `dont_lines(android)` let the
  suite and the probe build a Quest's page on a desk.
- **The links are held by the suite**: `WEBSITE_URL` is the README's
  (`retroxr.app`, `welcome_tests` reads the README); `DISCORD_URL` is the welcome
  page's OWN invite (`discord.gg/CranAYPfX`), deliberately not the one `release.yml`
  posts in the release notes, so changing one never changes the other; the suite
  pins it by value. A button opens through `open_url` (`OS.shell_open`; the suite
  swaps in a recorder) and writes its address on itself, for typing on a phone. What
  `shell_open` does on a Quest (the headset's browser, presumably) is OWED.
- The quad is **SCISSOR**, not TRANSPARENT: alpha-blended, the bedroom window's
  string lights two metres behind came through the text (measured in the probe).
- The quad is **fitted to the page** a couple of frames after it is built
  (`Welcome2D.content_height()`, bounded by `MIN_PX`/`MAX_PX`), hidden until then; the
  demo is placed a frame after THAT, when the stage has moved to its final place.
- Redrawn throttled (30/s, enough for the clip), never `UPDATE_ALWAYS`; built when
  shown, freed when put away.

## Checks

- `welcome_tests` (headless): the pref's default, `due()`, round trip, the setter
  saying so once; Done leaves it on, Don't Show Again switches it off and saves, a
  double press does nothing, put away changes nothing; `options/` the real General
  row, switched on as a player does, and following the page's Don't Show Again; the copy against the
  bindings and the ROM folder; every line on each page, a height the panel can take,
  the clip on both, the stage on the headset's only; `rig/` the reader on rigs of
  known travel (a click that must not lean); `demo/` the steps' bones, the sequence of
  a combination, and the presses landing on the step's own hand only; `page/` Next
  and Back through two pages off a Quest and three on one, only the shown page's
  clip playing, the ways out on the last page only, the upload page's every step,
  and the links.
- `Tools/room/welcome_probe` (WINDOWED; it writes `user://app_prefs.json`, back it
  up): the page in the bedroom with the clip playing, Next to the last page and Done
  pressed through the quad's own pointer body at the button's real place, ABOUT bringing it back, Don't
  Show Again pressed there and kept, then OPTIONS > General scrolled to the switch,
  showing off, and pressed on through the menu's own body; Next and Back pressed
  the same way, page 2's clip checked playing; the pages flat. `--vr` builds the headset's page and watches a whole loop of the demo
  (every step's own buttons must move); `--menu` walks CORES / SPAWN / TVs with the
  same pointer events and checks each view opened; `--quest` builds a Quest's page
  and presses on to page 3 and back (and fails if page 2 has a Next without it). Record it with Godot's movie
  writer (`--write-movie out.avi --fixed-fps 30`): the probe counts the demo in game
  time, so it holds under the writer's slow frames.

Headset (the real controllers on the page), Quest and a real first launch OWED.
