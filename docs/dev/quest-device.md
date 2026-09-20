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
  `compression.zstd` and grep the payload for a string you just added.
- `FileAccess.file_exists("res://….tscn")` is **false in exported builds** (paths are
  remapped into the pck) — use `ResourceLoader.exists()`.

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

### Log capture
The logcat ring buffer rotates away in **under a minute** (VrApi spam) — poll-grepping
loses boot output. Stream from before the launch instead:
```bash
adb logcat -c && adb logcat -s godot:* > quest.log &
```
