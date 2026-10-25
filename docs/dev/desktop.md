# Desktop: the window, and updating

Windows, Linux and macOS builds only; a headset has neither. Source:
`RetroXR/Scripts/Desktop/desktop_window.gd`, `Scripts/Data/update_plan.gd`,
`Scripts/Data/app_update.gd`, `Scripts/UI/spawn_menu/views/update_banner.gd`.

## The window (`DesktopWindow`)

- **Restored once per process**, from `xr_init.gd` (desktop branch) through
  `QualityManager.begin_window_tracking()`. It used to be restored when the spawn menu was
  BUILT, which re-centred the window on every room change; `restore()` has a once-guard now and
  `SpawnMenuGraphicsView.restore_window_state()` only forwards to it.
- **The size goes first, then the mode**, so leaving fullscreen or maximised returns to the size
  the player chose. With nothing saved the window is still `fit()` to the screen: the project's
  2560x1440 default hung off a 1080p monitor.
- **Free resizing**: `Window.min_size` is 800x450 and the tracker (a child of `QualityManager`)
  listens to `size_changed`, waits 0.5 s for the window to hold still, and saves the settled mode
  and size. Only a `windowed`/`borderless` size is saved -- a maximised or fullscreen window
  reports the screen's size, which is not a choice. `settled(key)` is what the GRAPHICS tab's
  Window Mode / Resolution rows follow (skipped while one of their lists is open).
- Modes: windowed, **maximized** (new), borderless, fullscreen (borderless fullscreen, not
  exclusive). `fit()` keeps the shape: a too-wide window is scaled down, never squeezed.
- **Resize through `Window`, never `DisplayServer.window_set_size`.** On X11 the latter resizes
  the real window AND records the new size, so the X server's ConfigureNotify then reports
  "no change" and the `Window` node (the viewport) never hears: a bigger window drawing the old
  picture, cropped, crosshair off to one side (measured 2026-10-20 under GNOME/XWayland: X window
  1500x700, `Window.size` 960x600, no `size_changed`). `apply_size`/`apply_mode` use the root
  `Window`. (A tracker that compared the two every 0.5 s and "healed" a gap was tried and removed:
  a window manager that clamps a size, as GNOME does to the 2560x1440 default on a short screen,
  would have been asked again at every tick -- a resize and a new swapchain each half second.)
  `window_resize_probe`'s "drag" steps call DisplayServer directly to show the desync.
- **A window that fills the screen along one axis may be held maximised on that axis alone**
  (GNOME does it when an edge is dragged to the top), a state the engine neither reports nor clears
  -- it only undoes a full maximise. Asking such a window for 640x480 got 640x1108. So
  `apply_size(key, strict, unstick=true)` (the Resolution row) first maximises and restores a
  window that `fills_screen`, then sizes it; it is a coroutine for that reason. Restore at launch
  does not (a fresh window is clean, and it would flicker at every start). Reproduced with
  `_NET_WM_STATE_MAXIMIZED_VERT` sent from outside: real height 1108 before, 480 after.
- **The window OPENS small** (`display/window/size/window_width_override`/`height_override` =
  1280x720 in project.godot) and `restore()` sizes it afterwards. Opened at the project's
  2560x1440 on a shorter screen, the window manager clamps it and GNOME holds it maximised along
  that axis: the saved width was applied, the height stuck at the screen's, and that wrong height
  was saved back (a launch opened bigger than the one left; the prefs read `1600x1108`).
  `restore()` also unsticks (`apply_size(.., unstick=true)`). With nothing saved the target is
  `DEFAULT_KEY` (2560x1440), fitted to the screen. Verified by watching the window's real X
  geometry: 1280x720 at creation, 1100x700 once restored, saved value unchanged.
- The Resolution row lists the usual sizes of every common shape (4:3, 5:4, 16:10, 16:9, 21:9)
  with the shape beside each (`ratio_label`, tolerance 1.2%, 1366x768 is 16:9).
- **Zoom** (OPTIONS, next to Field of View, desktop only, 1.00-4.00x, starts at 1x, saved as `zoom` in
  graphics_prefs.json): the camera's vertical fov is `zoomed_fov(fov, zoom)`, the TANGENT divided
  by the zoom, so 2x shows half the height and width. Applied by `SpawnMenuController` at start and
  on both sliders; never in a headset.
- **The spawn menu stands further off when zoomed** (`_menu_distance` in the controller): 0.9 m x
  `DesktopWindow.menu_distance_factor(zoom)` = 1 + 0.5 per extra 1x (2x = 1.35 m, 4x = 2.25 m),
  cut short by a ray against layer 1 so it never goes into a wall (the bedroom's nearest wall
  ahead is ~2 m: the probe measured 1.78 m at the first, too-large factors). Desktop only. Tried
  and rejected as too far: 3x at 2x, and the full zoom (2x = 1.8 m).
  `Tools/room/menu_zoom_probe`.
- **Rotating a held object is the REVERSE of aircraft controls**, on the desktop (middle-mouse
  drag, `desktop_pickup.gd`) and in VR (the free hand's stick on a ray-held object, a LOCAL PATCH in
  `function_pickup.gd` `_compute_ray_grab_rotation`): right yaws the far side left, up pitches it
  down, roll is counter-clockwise to the right. At the player's request; both flipped together.
- Mouse wheel with an object in hand: **wheel DOWN brings it toward you, UP sends it away**
  (`desktop_pickup.gd`, at the player's request). The wheel over the menu scrolls as any list does.
- Wayland compositors may ignore `window_set_size`/`window_set_position`; the saved size is then
  simply what the compositor allowed.
- `Tests/desktop_window_tests` is the arithmetic. How a drag really lands, and how the room
  frames at odd shapes, is `Tools/room/window_resize_probe` (windowed, **writes the prefs file**:
  run it with a scratch `XDG_DATA_HOME`).

## Updating (`AppUpdate` autoload)

- Checks `https://api.github.com/repos/RetroXR/RetroXR/releases/latest` (`UpdatePlan.REPO`) 8 s
  after launch, unless switched off (ABOUT > UPDATES). Desktop **installed** builds only
  (`OS.has_feature("template")`); an editor run does not nag. `RETROXR_UPDATE_TEST=1` turns it on
  for a manual try.
- Versions compare **numerically** (0.10.0 is later than 0.9.0); a pre-release is older than its
  release; an unparseable tag is never newer.
- The asset is chosen by name from what `release.yml` packs: `RetroXR-win-v*.zip`,
  `RetroXR-linux-x86_64-v*.AppImage`, `RetroXR-linux-arm64-v*.tar.gz`, `RetroXR-macos-*.zip`
  (universal). **Renaming a CI artifact breaks the update for that platform** -- the fallback is the
  release page, and `update_tests` pins the names against a real v0.9.0 answer.
- **Nothing is installed without the player pressing Update** (banner on every menu tab, or the
  ABOUT tab). The download is size-checked and verified against the `sha256` GitHub lists in each
  asset's `digest`; a mismatch deletes the file. **An asset with no digest is never installed in
  place** (the release page instead), and an empty checksum fails verification. A check while READY
  is refused, or it would throw the verified download away.
- Install = `SceneManager.restart_app(relaunch)` with the waiter from `UpdatePlan.waiter_command`:
  it waits for this process to be GONE, swaps the files, and starts the new build whatever
  happened (a failed swap brings the old one back). The room is carried exactly as a mods restart
  carries it. Per platform: AppImage -- the new file is staged BESIDE the old (`<file>.update`) and
  renamed over it; arm64 tarball -- unpacked over the folder; Windows -- `tar.exe -xf` (zip) over
  the exe's folder, `Expand-Archive` as the fallback OUTSIDE tar's `try` (a missing `tar.exe`
  throws rather than setting an exit code), the zip removed only once one of them unpacked it, and
  each relaunch argument quoted for `CommandLineToArgvW` (`UpdatePlan.win_arg`; run for real with
  `tar.exe` off PATH); macOS -- unzipped, old bundle moved aside,
  new one renamed in, rolled back if that fails. A read-only folder, a build that is not an
  AppImage, or no plan opens the release page instead (`install_plan` says why).
- **Inside an AppImage `OS.get_executable_path()` is a path into the image's mount**, which goes
  away with the process. `SceneManager.own_launcher()` substitutes the `APPIMAGE` variable, so a
  mods restart from an AppImage works too (it did not before).
- **`OS.execute("/bin/sh", ["-c", script, "sh", args...])` drops every argument after the script
  on Godot 4.7**; `OS.create_process` does not, and is what the app uses. A test that runs a
  waiter must use `create_process` (`update_tests._run`).
- HUD: `announced` (once per run) puts a toast on `HudToasts`; the banner is where the player
  answers. "Later" hides it for the run, "Skip this version" is saved (`user://app_update.json`).
- **Verified:** versions, asset choice, plans, the Linux AppImage and tarball swap scripts run for
  real, checksum rejection. **OWED:** a real download and swap on Windows and macOS (the scripts
  are checked for shape only), the banner looked at in a headset-less window, and a release newer
  than the running build to try the whole path against.

## The hand (`desktop_pickup.gd`)

- **Pulled all the way in, one more notch CATCHES the object into the hand** (`_catch`; wheel up lets it
  back out onto the ray at `MIN_DIST`, the pull-in limit, so one notch in catches it again; it used to
  resume at 45 cm, four notches out). It settles into `HAND_LOCAL` (camera-right 0, down 7 cm,
  40 cm ahead) over ~0.17 s (`ease_in_out`). A **handheld** takes `DesktopPickup.screen_facing_basis`:
  screen (+Y, on every handheld shell) at the eye, top edge (-Z) as upright as the view allows;
  anything else keeps its orientation. Middle-drag still turns it, in the hand's own frame, so a
  switch on a console's edge can be tipped into view.
- **The hand follows the gaze with a SMALL dead zone** (`HAND_DEADZONE_YAW/PITCH` 6/5 deg,
  `HAND_FOLLOW_RATE` 12/s, `follow_toward`), so what is in the hand stays in front of you. It was
  24/18 deg, widened with the object's size up to 60 (`dead_zone_deg`, `HAND_REACH_SLACK`), so the
  crosshair could sweep across a console to a switch on its edge -- but the object then sat well off
  to the side, trailing the view, and the player did not want that (2026-10-22). A control on an edge
  is reached by tipping the object towards you (middle-drag / LT). Do not widen it again without asking.
- **Anything with a screen is held by it, close**, and the hand finds screens the way F11 does:
  `DesktopPickup.screens_of` reads `TvFullscreen.panels_for(device, even_dark=true)` -- one query for a
  handheld, a DS's two, a VMU's LCD, a mod's `fullscreen_panels`. (2026-10-22: the PR added
  `RetroSystem.desktop_hold_focus` / `desktop_hold_basis` beside that query instead, so only a console's
  screen counted, its facing was ASSUMED to be the body's +Y, and a VMU -- whose LCD faces +Z -- was held
  40 cm out like a pad. Both are gone.) `screen_hold` reads each screen off its own node and mesh
  (`_screen_axes`: a QuadMesh faces +Z, top +Y): the held point is the middle of them all, the width the
  widest across its own face, and the facing that of the screen lying flattest on the body, so a
  clamshell is held by its base with its lid leaning back. `screen_hold_basis` turns that face toward
  the eye; `screen_facing_basis` is now its +Y special case, and every shipped handheld's screen is
  built that way, so they turn exactly as before (`desktop_hold_tests screens/`). `focus_distance`
  stands it so the screen fills `HAND_SCREEN_FRACTION` of the view's width, clamped to 14-40 cm.
  A screen is listed lit or not: the VMU's `fullscreen_panels` used to list nothing while dark, mixing
  "has a screen" with "shows a picture", and now lists its LCD as a switched-off handheld lists its
  screen (F11 draws nothing for a null picture). `even_dark` only lists a handheld whose picture is out
  on a TV, which F11 skips. Turning it turns it about that point.
- **Anything without a screen** is held a little below the line of sight: something small comes in
  until it fills `HAND_OBJECT_FRACTION` (40%) of the view's width, no nearer than 14 cm and no further
  than `HAND_LOCAL`'s 40 cm (`object_distance`; everything used to sit at 40 cm whatever its size), and
  something bigger than `HAND_ROOM_REACH` further off in proportion, as before. A console held close
  reaches ~36 deg from the held point, far outside the dead zone: its edge controls are reached by
  tipping it, not by looking across it. `hold_probe -- --vmu` / `--sys=gbc --catch-only` photograph
  the two side by side (2026-10-22: both 0.140 m, the VMU's LCD facing the eye, connector up).
- **A control on the held object lights when the crosshair passes near it**, even where the ray meets
  the object's shell first (`InteractionResolver.assist_held`, called from the pointer's
  `resolve_interaction_target`): the ray's closest approach to the control's mesh bounds
  (`desktop_aim_mesh`, on `VRSlider` and `VRButton`; `ray_box_gap`, a ternary search) within 1.25 deg
  of view or 3 mm. Where the ray reaches the control itself nothing changes.
- **A held object is let go when left comes back UP, not when it goes down** (`_drop_armed`), and not at
  all if the press began on a control (`_crosshair_on_control`: the pointer's own resolved target is
  something activatable). So a press on a held console's power switch works the switch and the hand
  keeps the console. The pointer drives the switch itself (it polls `trigger_left`); this script only
  decides about the drop.
- **A control's box is not its aim.** `VRSlider` is an Area3D whose box is the knob mesh grown 2 cm for a
  fingertip; the resolver took the ray hitting that box as "on the switch", lit it with the crosshair
  ~50 px away (at 45 cm, 2x zoom), and the same box blocked what lay behind. `accepts_pointer_ray`
  (new beside `accepts_pointer_at` in `InteractionResolver._accepts_pointer`) tests the RAY against the
  knob mesh grown by `DESKTOP_AIM_MARGIN` (4 mm, divided by the knob's own scale: the margin is in
  metres, the mesh is scaled). Other controls (`VRButton`, `VRKnob`, `VRHinge`) are NOT yet tightened.
- **One notch past the pull-in limit catches it, no resistance.** A version made the player scroll three
  notches (push-back, shiver, pad buzz) so a long scroll would not grab by accident; it was tried and the
  player did not want it (2026-10-21), so it is gone. Do not bring it back without asking.
- **Scroll in again while it is IN the hand and the pose is squared up** (`_reset_hand_pose`): the
  console turned to see its power switch comes back to screen-to-eye, still held.
- **Nothing with a screen is held by its visual centre** (`_catch` falls back to `visual_bounds`, a little
  below the line of sight at `HAND_LOCAL` scaled by `radius / HAND_ROOM_REACH` so a big thing is held
  further out, like a cable at arm's length) rather than its origin.
- **The dead zone used to be measured to the NEAR edge** of the held thing (gone with the size-widened
  zone, 2026-10-22): measured to its middle, the hand kept running away from a gaze that was on a tipped
  switch. With the small zone the object follows the gaze and a switch is tipped to the crosshair.
- **Left held on the object and dragged turns it** (`_turn_held`, shared with the middle button): past
  `CLICK_DRAG_PX` of travel the press stops being a click-to-drop (`_left_turning`, the release lets go of
  nothing); a press with no travel still drops on release, a press on a control still works the control.
  `DesktopPickup.left_drag` (static) is true from such a press to its release and `MovementDesktopTurn`
  ignores the mouse meanwhile -- without it the camera turned with the object (it asks the same way about
  the middle button). Objects whose plain click is their own (`desktop_shift_drop`, the light gun) are left
  out. `hold_probe --leftdrag`; note a synthetic motion event's `relative` is scaled by 0.1 in a probe, send 80.
- **Turning a held object switches the pointer off** (`DesktopPickup.is_turning()`: held, not FPS-snap,
  middle down or `_left_turning`; `function_desktop_pointer.resolve_interaction_target` returns none).
  Left live, the turn swept the object's own controls under the crosshair, each lit up as it passed, and
  a left click mid-turn went to whichever one the angle left there (2026-10-25). A
  left press during a middle turn is swallowed: neither a drop nor a press. Nothing held, the pointer
  is untouched. `desktop_hold_tests turning/`.
- **A control under the crosshair is the only thing lit**: `PickableHighlight.set_suppressed`, driven by
  `_dim_held_outline`, turns the held object's yellow outline OFF while the pointer is on one of its
  controls. Left on, the console's outline read as the thing aimed at and the switch's own green ring
  was hidden under it (measured: with the console's overlays hidden the ring shows; a separate stencil ref
  for widgets did NOT fix it, so that was reverted).
- `Tests/desktop_hold_tests` is the pure part; `Tools/room/hold_probe --scenario` (windowed) is the
  catch -> tip -> aim -> press -> release -> look away -> click run, with the printed truth.

## The loading screen off a headset (`loading_panel.gd`)

Not in a headset it is a flat screen: a `CanvasLayer` (layer 130, OVER the crosshair at 128 so the crosshair does not float on it)
with its own curtain on a layer of its own (129: unscaled, anchored to the viewport, since a launch
resizes the window after this is built and a script-sized curtain left the room showing outside the
old size for a frame; the content refits on `Viewport.size_changed`), centred, scaled with the window (1x at 720 px tall, 0.5-1.5x). The 3D `Screen` and `Curtain` stay
in the scene, hidden there: LoadingRig, LoadingOverlay and their tests drive those nodes, and a headset
still shows them. A CanvasLayer is not hidden by its Node3D parent, so `visibility_changed` mirrors
`visible` onto the layer (suspend/resume). `Tools/room/loading_2d_probe` photographs it.
