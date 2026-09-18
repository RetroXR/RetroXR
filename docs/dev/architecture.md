# libretro-godot architecture and dependencies

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

## Architecture

### Multi-Instance Design (post-refactor)
Each `Libretro` GDExtension Node owns its own `Wrapper` instance and emulation thread. Multiple `Libretro` nodes can run simultaneously in the same scene, each with a different core/content. This replaced an earlier singleton design.

### Threading Model
Emulation runs on a dedicated `std::thread` owned by `Wrapper`. The main Godot thread communicates with it via a lock-free `ReaderWriterQueue` using a **command pattern** (`ThreadCommand` subclasses: `ThreadCommandCreateTexture`, `ThreadCommandInitAudio`, `ThreadCommandUpdateTexture`). The `Libretro` node's `_process()` drains this queue each frame.

Because libretro callbacks are static C functions, the correct `Wrapper*` is found via a `thread_local` pointer:
```cpp
// Set at emulation thread start, cleared at end:
thread_local Wrapper* t_current_wrapper = nullptr;

// All handlers and Core call:
Wrapper* w = Wrapper::GetCurrentThreadWrapper();
```
ThreadCommands that execute on the main thread carry an explicit `Wrapper*` and call `SetCurrentThreadWrapper` around their work so handler callbacks invoked during Execute() can also resolve the right instance.

### Key Classes (libretro-godot/src/)

- **Wrapper** — Per-instance emulation orchestrator. Owns the emulation thread, all handlers, the command queue, and a back-pointer `Libretro* m_libretro_node`. Exposes `GetCurrentThreadWrapper()` / `SetCurrentThreadWrapper(Wrapper*)` as static helpers for the thread-local pattern.
- **Core** — Dynamically loads a libretro core (`.dll` on Windows, `.so` on Linux/Android,
  `.dylib` on macOS) via `DynLib.hpp`, copies it to a temp directory for isolation, and
  binds all libretro callback function pointers. All callbacks resolve the current wrapper
  via `GetCurrentThreadWrapper()`.
- **Libretro** — The GDExtension Node exposed to GDScript. Instance methods only (`StartContent`, `StopContent`, `SetCoreOption`). Owns a `std::unique_ptr<Wrapper> m_wrapper`. Emits the `options_ready` signal via `NotifyOptionsReady()` (called from Wrapper across the thread boundary using `call_deferred`).

### Handler Subsystems
Each handler is owned by a `Wrapper` instance and manages one libretro subsystem:
- **VideoHandler** — Texture creation/updates, hardware rendering, rotation. It owns the
  HW-render contexts, and there are more than the software/Vulkan/OpenGL trio named
  elsewhere in this file: `VulkanContext` (with a `VulkanContextStub` for platforms
  without it), `D3D11Context` and `D3D12Context` on Windows, and `MacMetalLayer.mm` on
  macOS. `PixelSwizzle.hpp` handles the format conversions between them.
- **AudioHandler** — Audio stream generation and playback
- **InputHandler** — Per-port input state and joypad/mouse/keyboard mapping (Godot keycodes ↔ libretro keycodes). It does **not** read the global Godot `Input` singleton — there is not one reference to it in `InputHandler.cpp`. State is PUSHED in from GDScript, per port: `Libretro.SetJoypadState(port, buttons, alx, aly, arx, ary)` plus `SetMousePosition`/`SetMouseButtons`, `SetKeyState`, `SetLightgunPosition`/`SetLightgunButtons`, `SetPointerIndexState` (multi-touch/IR), `SetAnalogLeft`/`Right`, `SetSensorAccel`/`SetSensorGyro` and `SetPortDevice`. So two `Libretro` nodes in one scene have entirely independent controller state, which is what lets one room hold several machines — and what lets netplay replay a remote peer's port without touching local hardware. The callers are `retro_controller.gd`, `pad_receiver.gd`, `wiimote.gd`, `handheld_input.gd` and `netplay_session.gd`.
- **EnvironmentHandler** — Libretro environment callbacks (system dirs, VFS, disk control)
- **OptionsHandler** — Core option parsing (v1/v2 formats), categorization, persistence
- **MessageHandler** — Notification/message interface
- **LogHandler** — Log callback forwarding
- **RetroAchievements** — `RetroAchievements.cpp/.hpp`, backed by the `external/rcheevos`
  submodule, whose `src/`, `src/rcheevos/`, `src/rapi/` and `src/rhash/` trees are
  compiled straight into the extension (no external dependency). It hashes content by
  RetroAchievements' own console-specific rules rather than by plain file digest. The
  GDScript half lives in `RetroXR/Scripts/Data/ra/` (`ra_config`, `ra_consoles`,
  `ra_session`) and `RetroXR/Scripts/Net/ra/ra_http_bridge.gd`.
- **LinkCoordinator** — `LinkCoordinator.cpp/.hpp` + `LinkInterface.hpp`. A process-wide
  singleton joining two cores on one emulated wire; see §2g. Not per-`Wrapper`, unlike
  everything else in this list.

### Data Flow
```
GDScript UI → Libretro Node (instance) → Wrapper (per-node) → Core + Handlers → Libretro Core (.dll/.so/.dylib)
                                               ↑ ThreadCommand queue (ReaderWriterQueue) ↓
                                         Main thread (_process drains queue)
```

### Heap pointer tagging (Android)
`RegisterTypes.cpp` turns off Android's native heap pointer tagging when the extension
loads (`mallopt(M_BIONIC_SET_HEAP_TAGGING_LEVEL, M_HEAP_TAGGING_LEVEL_NONE)`, API 31+).
With it on, `malloc` pointers carry a tag in the top byte but a signal handler receives
fault addresses without it, so a core that matches faults against its own memory never
claims them: flycast without nvmem died on its first write to a protected RAM page
(flyinghead/flycast#2498). RetroArch opts out in its manifest instead
(libretro/RetroArch#19280).

### GDScript Side
- `RetroXR/Scenes/BootScene.tscn` is `run/main_scene` on every platform. It enters
  `SceneManager.boot_room()`: the last room a transition brought the player to, recorded
  once its contents finished arriving (`room` in `user://scenes/prefs.json`), else the
  arcade on Android and the bedroom elsewhere. A room run directly (F6, a suite, a probe)
  is never recorded. The root is still readying its children when the boot
  scene's `_ready` runs, so the swap is deferred: a room's `_ready` runs inside the first
  `SceneTree.process`, after that frame's `xrWaitFrame`, not inside `SceneTree.initialize`.
- `RetroXR/Scripts/Objects/systems/system.gd` — Per-arcade-cabinet controller. Has `@onready var _libretro: Libretro = $Libretro` wired to a child `Libretro` node in the scene tree.
- `RetroXR/Scenes/Objects/system.tscn` — Cabinet scene. Contains a `Libretro` child node. Its `unique_id` is the value 4000000010, but Godot writes it SIGNED, so the file reads `unique_id=-294967286` — grep for that, not for the decimal above.
- GDExtension registration at `MODULE_INITIALIZATION_LEVEL_SCENE`.

## Dependencies

- **godot-cpp** (submodule, 4.5 branch) — Godot C++ bindings
- **SDL3** — On Windows: core DLL loading (`DynLib.hpp`) + the OpenGL HW-render window. On Linux: the OpenGL HW-render window only (core loading uses `dlopen`); linked against the system `libSDL3.so.0` by soname, headers from `libretro-godot/external/SDL3/`. Not used on Android (`dlopen` + EGL via `DynLib.hpp`).
- **libretro-common** — Reference implementations for VFS, audio conversion, etc. (`libretro-godot/external/libretro-common/`)
- **rcheevos** (submodule, `libretro-godot/external/rcheevos/`) — RetroAchievements support, compiled into the extension. Carries no external dependency of its own.
- **Vulkan-Headers** (submodule, `libretro-godot/external/vulkan-headers/`) — headers for the Vulkan HW-render path.
- **moodycamel::ReaderWriterQueue** — Lock-free SPSC queue for cross-thread communication
- **godot-xr-tools v4.5.1 — FORKED IN PLACE, not a vendored drop-in.** VR locomotion,
  interactions, finger poses (`RetroXR/addons/godot-xr-tools/`). `plugin.cfg` still
  says 4.5.1 and it is no longer that: 30 commits have landed on it here, 59 files,
  +2841/-381, in snap_zone, player_body, the grab driver and pickable teardown —
  the local patch behind `function_pickup._on_grip_pressed` asking a controller
  whether it wants the grip, the snap zone releasing what it holds when it leaves
  the tree, and the `_property_get_revert` returns Godot 4.7 made mandatory.
  **Dropping a fresh upstream copy over this silently reverts all of it**, and the
  symptoms are grabs and teardown, which no headless suite covers. Diff before
  upgrading: `git log --oneline -- RetroXR/addons/godot-xr-tools`.
- **vlc-godot** (libVLC) — the `VlcPlayer` GDExtension; single video backend for both the DVD
  player and the VHS/VCR. Replaced `eirteam.ffmpeg` (dropped 2026-07-14; libVLC also does x265).
- **godot-pdfium** (PDFium) — the `PDFRenderer` GDExtension for rendering PDF pages (books) to
  Godot `Image`s. Prebuilt `libpdfium` from bblanchon/pdfium-binaries.
- **surround-godot** (FreeSurround) — the `SurroundDecoder` GDExtension, a Dolby Surround /
  Pro Logic II matrix decoder, plus the `SurroundAudio` factory singleton another extension
  reaches it through. GPL-2.0-or-later, vendored from Dolphin's copy, which is why it is an
  extension of its own rather than part of MIT-licensed `libretro-godot`. See §2r.

## Code Conventions

- C++latest standard (MSVC on Windows), C++20 (GCC/Clang/NDK elsewhere)
- Debug logging via `Log`, `LogOK`, `LogWarning`, `LogError` macros
- Libretro option data exposed to GDScript as `LibretroOptionCategory`, `LibretroOptionDefinition`, `LibretroOptionValue` objects
- Callback-based design throughout (video_refresh, audio_sample, input_poll, environment)
- All static libretro callbacks resolve their `Wrapper*` via `Wrapper::GetCurrentThreadWrapper()` — never store a raw global pointer
- `call_deferred` used when Wrapper needs to signal back to the `Libretro` node on the main thread (e.g. `NotifyOptionsReady`)
