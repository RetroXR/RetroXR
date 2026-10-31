# On-device testing (Quest over adb)

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

## On-Device Testing (Quest over adb, nobody wearing the headset)

The Quest 3 usually sits on the desk on USB (`adb devices` → authorized; USB keeps it
charged). RetroXR can be exported, installed, launched, and probed on it fully
unattended. Verified end-to-end 2026-07-06 (x64↔arm64 netplay determinism run).

In Git Bash, `export MSYS_NO_PATHCONV=1` first or `/sdcard/...` args get mangled into
`C:/Program Files/Git/sdcard/...`.

### Export + install
```bash
"$godot" --headless --path "$proj" --export-debug "Quest" out.apk
adb install -r out.apk        # -r keeps app data
```
- **Stale-script trap**: the gradle export can silently ship an old compiled script —
  `RetroXR/android/build/src/main/assets/**.gdc` is not always re-staged after a source
  edit. If an on-device change doesn't take: `rm -rf RetroXR/android/build/src/main/assets
  RetroXR/android/build/build/intermediates/assets` and re-export. To verify before
  installing: a `.gdc` is a 12-byte `GDSC` header + zstd; decompress with Python 3.14's
  `compression.zstd` and grep the payload for a string LITERAL you just added. Not an
  identifier or function name: 4.7's tokens do not store those as searchable text, and
  their absence proves nothing (2026-09-30: `request_shells` was "missing" from a build
  that certainly had it).
- `FileAccess.file_exists("res://….tscn")` is **false in exported builds** (paths are
  remapped into the pck) — use `ResourceLoader.exists()`.
- **`INSTALL_FAILED_UPDATE_INCOMPATIBLE ... signatures do not match`** (2026-10-18): the
  device holds an APK signed with a different key than the one exporting. A release/CI
  build is signed `CN=retroXR` (`ANDROID_KEYSTORE_*` secrets, never on a dev PC); the
  editor's Run and `--export-debug` sign with Godot's debug keystore
  (`%APPDATA%\Godot\keystores\debug.keystore`, `CN=Android Debug`). Android will not
  update across keys and `adb install -r`/`-d` cannot override it. Compare with
  `apksigner verify --print-certs <apk>` (pull the installed one via `pm path`).
  The only way out is `adb uninstall com.xenu.retroxr`, which ALSO deletes
  `/sdcard/Android/data/com.xenu.retroxr/` (ROMs, mods) and the internal `user://`.
  **Back both up first**: `adb pull /sdcard/Android/data/com.xenu.retroxr/files ext`
  and `adb exec-out run-as com.xenu.retroxr tar cf - files > internal.tar`. Restore
  internal with `adb push` to `/data/local/tmp` then
  `run-as com.xenu.retroxr tar xf …` (app-owned, so it can still write it). For external,
  launch the app once so it creates its own folders, then push FILES only into them (not
  `.romm/` dirs, not `romm_config.json`: pushed files are `shell`-owned and the app can
  never overwrite them, and `run-as` cannot reach `/sdcard`, so RomM must be re-paired).
  Keep the debug keystore: losing it forces this again on the next install.

### Launching with no one wearing it — ALL three are required
```bash
adb shell am broadcast -a com.oculus.vrpowermanager.prox_close   # fake "worn"
adb shell setprop debug.oculus.guardian_pause 1                  # else a Guardian dialog blocks
adb shell monkey -p com.xenu.retroxr 1                           # GodotApp isn't exported; am start = Permission Denial
```
- The manifest must declare `oculus.software.handtracking` or the shell blocks with a
  controllers-required dialog (controllers are off/dead). That needs BOTH the export
  preset `meta_xr_features/hand_tracking=1` AND project.godot
  `xr/openxr/extensions/hand_tracking=true` — the vendors plugin only injects the
  manifest feature when the OpenXR project setting is on (enabled since b9f1481).
- If an OS dialog is showing, the launch is **cached** and fires once it clears
  (`adb shell input keyevent KEYCODE_BACK` can dismiss).
- Cleanup when done: `guardian_pause 0`, broadcast `prox_open`, `am force-stop`.

### Paths on device
- `user://` = **internal** `/data/user/0/com.xenu.retroxr/files/` — readable/writable via
  `run-as com.xenu.retroxr` (debug builds). Cores + system dirs live there
  (`files/libretro/…`, populated by the in-app CoreDownloadManager).
- ROMs/books/videos live on the **external** dir `/sdcard/Android/data/com.xenu.retroxr/files/`
  (plain `adb push`/`ls` works there).
- **Never `adb push` over a file, or into a directory, that the app itself writes.** The
  app is `other` for everything `shell` creates in its own tree, and no chmod fixes that
  sanely. Confirm the group list before theorising — `cat /proc/$(pidof
  com.xenu.retroxr)/status` reports `Groups: 3003 9997 20198 50198`, i.e. `inet`,
  `everybody`, `<uid>_cache` and `all_a<uid>`. **`ext_data_rw` (1078) is not among them**,
  and it is the group on every `adb`-created file and directory here. Owner is `shell`,
  group is unreachable, so only the `other` bits apply:
  - `adb push` lands a file `0644` — other `r--`. The app can read it forever and can
    never overwrite it. Fine for ROMs, fatal for state files.
  - `adb` creates directories `0770` — other `---`. The app cannot create anything inside
    one, so a system folder made by push gets no `.romm/` index. `romm_catalog.gd` ignores
    the return of `make_dir_recursive_absolute`, so this surfaces one line later and one
    level down as "Cannot write to …/n64/.romm".
  - Granting the app access through the bits alone would mean `0666` on files and `0777`
    on directories, because the group is useless to it. Don't. Let the app own what it
    writes: delete the pushed copy and let it be recreated in-app.
  - **`chmod 660` is actively harmful here** — it clears the `other` read bit the app was
    relying on, and grants write to a group the app is not in. A config the app can no
    longer read looks exactly like a config that was wiped.
  - Diagnose by owner, not by logs, and never with `run-as com.xenu.retroxr test -w …` —
    that shell does not get the app's storage mount view and reports NOT-WRITABLE for
    files the app demonstrably just wrote. The reliable tell is that every `.romm/` on the
    device is owned by the same uid as its parent directory, never a mix.
- Extra cores: same source the app uses (core_download_manager.gd) —
  `buildbot.libretro.com/nightly/android/latest/arm64-v8a/<core>_libretro_android.so.zip`.

### Running a probe scene on device (probe-only export)

A probe is never booted automatically, so it has to BE the launched scene. The pattern, used
by `Quest flycast probe` and `Quest page turn probe`:

1. `project.godot`: `run/main_scene.<feature>="res://Tools/…/<probe>.tscn"`.
2. `export_presets.cfg`: clone the Quest preset with `custom_features="<feature>"` and — the
   part that matters — **its own `package/unique_name`** (`com.xenu.retroxr.fqprobe`,
   `…ptprobe`). A probe build that keeps `com.xenu.retroxr` REPLACES the real app on the
   headset; under its own id it installs alongside and is uninstalled afterwards.
3. `python Tools/place_engine.py --target debug`, then export **debug** (`run-as` and
   readable logs need it).

```bash
"$godot" --headless --path RetroXR --export-debug "Quest page turn probe" probe.apk
adb install -r probe.apk && adb logcat -c && adb logcat -s godot:* > probe.log &
# …the three launch steps above, with the PROBE's package name…
adb uninstall com.xenu.retroxr.ptprobe     # when done
```

- **Quote the preset name.** PowerShell's `Start-Process -ArgumentList` does not quote for
  you, so `Quest page turn probe` arrives as four arguments: Godot exports the preset named
  `Quest` into a file called `page` and fails with "Invalid filename".
- Godot headless does not always exit after a successful export — the APK is complete and a
  waiting script just sits there. Check for the APK and the `[ DONE ] export` line before
  assuming a hang, and kill only your own PID (`Get-CimInstance Win32_Process` prints the
  command lines; an open editor and a `--remote-debug` run look the same in `tasklist`).
- A probe that runs on a headset needs its own **give-up timer** — there is no console to
  close it from, and a wedged one sits there until the battery dies.

### Running the netplay determinism spike on-device
`Tools/netplay/netplay_spike.tscn` reads its `--spike-*` args from `user://spike.cfg`
(one per line) when there are no command-line args, and deletes the cfg immediately so
a crash can't wedge the app. Nothing boots this one automatically — its NetworkManager
cfg-file hook and its own `run/main_scene.<feature>` preset were removed 2026-09-09 — so the
scene has to be the one launched (the probe-only export above, or a desktop run).
```bash
printf -- '--spike-core=fceumm
--spike-rom=/sdcard/Android/data/com.xenu.retroxr/files/roms/nes/ROM.nes
--spike-root=/data/user/0/com.xenu.retroxr/files/libretro
' > spike.cfg
adb push spike.cfg /data/local/tmp/
adb shell "cat /data/local/tmp/spike.cfg | run-as com.xenu.retroxr sh -c 'cat > files/spike.cfg'"
```
Then compare the `[crc]` lines against a Windows spike run.

### Catching a controller that will not drop

Open since 2026-09-20: a held controller occasionally refuses to fall and hangs where it was
let go. It clears itself — grab it again, release, and it drops — which is what rules out
every freeze-based explanation, because those latch. `pick_up()` snapshots
`restore_freeze = freeze` and `let_go()` hands it back, so a bad snapshot hangs the object
*every* time thereafter, not once; the same goes for a stale ray grab, a netplay replica
freeze and a scene restore's `gravity_scale = 0`.

`Tools/vr/pad_drop_probe` drives the real `pick_up`/`let_go` path on a real pad, settled until
it is genuinely asleep, across five release shapes (one hand, two hands either order, a release
racing the toggle-hold re-grab, a release mid-lerp) — **all of them fall**, so whatever it is
needs the real `XRToolsFunctionPickup` (its grip/combo logic, or a ray grab).

So the build reports it instead. `HeldObjectPhysics` photographs any `hand_held_device` that is
still within 5 mm of its release point 0.75 s later with nothing within 15 cm beneath it:

```bash
adb logcat -s godot:* | grep -a "\[stuck\]"
# [stuck] RetroController hung in the air 0.75s after release: freeze=true
#   restore_freeze=false sleeping=true gravity_scale=1.00 picked_up=false held_by=nobody
```

Read it as: `freeze=true, picked_up=false` → an owner froze it and never let go;
`picked_up=true` → a grab survives, and `held_by` names it (or says the grabber was FREED);
`sleeping=true` with everything else clean → the body slept in mid-air;
`gravity_scale=0.00` → a scene restore left it weightless. The downward clearance check is what
keeps a pad resting on a table out of the log.

**Reproduced once, on the desktop, with a Taiko drummer's sticks (2026-10-27)**, so the "sleeping in mid-air"
branch is real: the second of a pair released together with the first (`DesktopPickup._drop`:
`_release_companion()` then the primary's `let_go`) was dynamic (`freeze=false`, server mode RIGID,
`is_picked_up()` false, gravity on it, nothing within 1 m under it, no overlap) and AWAKE for one physics
step, then ASLEEP with its position and its release nudge (-0.05 m/s) unchanged, and stayed so: **setting
`sleeping = false` again did not wake it, giving it a velocity did** (`linear_velocity = Vector3(0, -1, 0)`, or
moving it). 4 runs in 5 under `Tools/models/taiko_desktop_probe` (windowed, llvmpipe: a few frames a second); a
headless run with two fake pivots, 8 physics steps a frame at 60 Hz, never did, and an unrelated state query
(`PhysicsServer3D.body_get_direct_state`) in the probe made it fall, so it depends on timing. Not found:
which write loses the wake. The sticks work round it (`ArcadeHeldGear._wake_if_hung`: four steps after a
release, an asleep body with nothing 4 cm under it gets 0.3 m/s down; the control, with the push removed, hung the
stick in 2 runs out of 2); the pads and the other pickables do not. A generic version of that push in
`HeldObjectPhysics._on_dropped` (it already has the "nothing underneath" test in `_report_if_stuck`) is the
obvious next step, unmeasured on a Quest.

### Log capture
The logcat ring buffer rotates away in **under a minute** (VrApi spam) — poll-grepping
loses boot output. Stream from before the launch instead:
```bash
adb logcat -c && adb logcat -s godot:* > quest.log &
```

### "Stuck on the loading screen": which engine is it running?

Read the banner first. `Godot Engine v4.7.2.stable.official…` is **stock** Godot, which
deadlocks at boot on a Quest (engine-patches.md); ours prints `…custom_build…`, and boot
now logs `[Boot] running STOCK Godot` as an error when it is not. The 2026-09-30 report
was exactly this: a `place_engine.py --restore` used to tidy up after a probe build had
left the shared gradle template stock, so every local export after it hung (stock 0/4
launches, patched 5/5). Every Android export now re-places the engine itself.

A hang shows as the app's VrApi lines going quiet (`FPS=1/72`, then nothing) with every
thread asleep: `run-as com.xenu.retroxr sh -c 'for t in /proc/<pid>/task/*; do echo
$(cat $t/comm) $(cat $t/wchan); done'` — the main loop is the thread named `VkThread`.

**Native stacks without root.** `debuggerd -b` needs root, but the app is debuggable, so
the NDK's lldb-server can attach as the app:
```bash
adb push "C:/android/android-ndk-r27d/toolchains/llvm/prebuilt/windows-x86_64/lib/clang/18/lib/linux/aarch64/lldb-server" /data/local/tmp/
adb shell "run-as com.xenu.retroxr sh -c 'cp /data/local/tmp/lldb-server . && chmod 755 lldb-server && ./lldb-server gdbserver --attach <pid> 127.0.0.1:5039 > /dev/null 2>&1 &'"
adb forward tcp:5039 tcp:5039
lldb.cmd -b -o "gdb-remote 127.0.0.1:5039" -o "thread backtrace all" -o detach -o quit   # PowerShell; lldb.exe alone cannot find its DLLs
```
Frames come back as raw addresses. Map them with `run-as … cat /proc/<pid>/maps`: the
libraries are mapped straight out of `base.apk` (stored uncompressed), so an address is
`base.apk+offset`, and the zip's local headers say which `.so` that offset falls in. The
installed `libgodot_android.so`'s build-id (`llvm-readelf -n`) tells stock from patched
without symbols. A SIGSEGV in a `binder:` thread on attach is ART's implicit null check,
not a crash. Delete the lldb-server copy from the app dir afterwards.

### Profiling a boot (where the time goes)

`simpleperf` ships on the headset and samples a debuggable app without root, user space
only:
```bash
adb shell monkey -p com.xenu.retroxr 1
adb shell simpleperf record --app com.xenu.retroxr -e cpu-clock:u -f 500 --duration 78 -o /data/local/tmp/perf.data
adb shell "simpleperf report-sample -i /data/local/tmp/perf.data" > samples.txt   # one block per sample: time, thread, file, symbol
```
The engine is stripped, but bucketing samples by thread and LIBRARY across the boot's log
milestones is usually enough: `libllvm-qgl.so` is the Adreno driver compiling pipelines,
`libpdfium.so` is page rendering, `libgodot_android.so` on `VkThread` is the main loop. A
debug export with `command_line/extra_args="--verbose"` on the preset adds a `Loading
resource:` line (with its thread id) for every load, and the PSO cache verdict
(`Startup PSO cache (N MiB)`). Revert the preset afterwards.
