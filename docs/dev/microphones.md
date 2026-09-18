# §2o — microphones

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### 2o. Microphones — one reader, and every machine that asked

libretro's microphone interface (`RETRO_ENVIRONMENT_GET_MICROPHONE_INTERFACE`, 75 |
EXPERIMENTAL) is answered by `libretro-godot/src/MicrophoneHandler.cpp`, and the real
microphone is read by exactly one thing in the app: the `Microphone` autoload,
`Scripts/Audio/microphone_input.gd`.

**One reader, because Godot keeps one cursor.** `AudioServer.get_input_frames()` (Godot 4.6+)
advances a single process-wide read offset, so two readers would each get part of the audio
and neither would know. The service drains it once a frame and hands the same frames to every
machine that wants them. It must drain EVERY frame while the device is on: the ring is only
four driver buffers long — 2048 × 4 frames on Android, about 186 ms at OpenSL's hardcoded
44100 Hz with the mono input duplicated into both channels, and a 1 s buffer × 4 on WASAPI,
which rate-adjusts capture to the output mix rate. Nothing captures without
`audio/driver/enable_input=true`; `set_input_device_active` warns and fails.

**Which input, when the machine has more than one.** Options -> Microphone carries an **Input**
dropdown built from `AudioServer.get_input_device_list()` as the page opens (this desk offers
five; a Quest offers one and the row reads Default). `AppPrefs.microphone_device` stores the
NAME, never the index -- an index means a different microphone the moment one is unplugged --
and `Microphone.resolve_device` falls back to `Default` for a name the platform is not currently
offering, while KEEPING the preference: a USB microphone plugged back in is used again, and
capturing from nothing would read as a broken microphone rather than a missing one. The input is
selected BEFORE the device is switched on, because a driver opens the one it was pointed at, so
a preference changed mid-run closes and re-opens rather than leaving capture on the old input.

**The device opens only while a core is listening.** Each frame the service collects the
powered-on `retro_system` machines whose `Libretro.IsMicrophoneActive()` is true — a handle
open and enabled, the machine running and not in netplay — and turns the device on only while
that list is non-empty and Options → Microphone (`AppPrefs.microphone_enabled`, default on)
allows it. Every transition prints a `[Microphone]` line.

**Every open microphone hears the player, fading with distance.** Gain is
`SpatialAudioEmitter.distance_gain(mic, head, 0.5, audio_max_distance)`: full level within arm's
reach, 1/d beyond, nothing past the machine's own `audio_max_distance`. The reference distance
is the microphone's, not the speaker's `audio_unit_size` (3 m), under which a DS across the
room would get the player's voice at full level. `RetroSystem.microphone_position()` is a
seated microphone's body when there is one, otherwise the machine.

**How the extension answers.**
- **`open_mic` is a callback trampoline**, the eighth in `CallbackTrampolines`. Dolphin calls
  it from its CPU thread (`EXI_DeviceMic.cpp` `StreamStart`, reached from `TransferByte`),
  where the thread-local Wrapper was never set. Every later call carries the handle and may
  arrive on any thread.
- **Handles come from a process-wide pool of 32 that is never freed.** Each slot has its own
  mutex, and a handle is validated by address rather than dereferenced, so a Dolphin CPU thread
  reading during teardown gets -1 or silence, never freed memory. Four per core.
- **`read_mic` returns silence and the FULL count** whenever the mic is off, the machine is
  stopped or in netplay, or the ring runs dry; -1 only for a pointer that is not a handle.
  NooDS stores the result in a `size_t` and virtualjaguar assumes all-or-nothing reads.
  RetroArch answers the same way.
- **`get_params` reports the rate the core asked for,** and each handle resamples to it: linear,
  and pass-through when the rates match.
- **Latency is bounded per handle.** A 150 ms cap drops the oldest samples. 40 ms of silence is
  served after an enable, a flush or an underflow. A read that leaves more than 100 ms trims
  back to 60 ms. The trim is what keeps a core that reads less than it is sent from sitting at
  the cap.
- **Silent in netplay.** An `NpFrame` is 128 ints, 735 samples a frame have nowhere to ride, and
  a microphone is not the same on two peers anyway.
- **Not silenced by `SetAudioPlaying(false)`.** That follows display cabling ("a machine wired to
  nothing is silent"), and a console with no television still hears its microphone.

**Permissions.**
- **Android.** `input_start()` requests `RECORD_AUDIO` itself, and the grant callback restarts
  capture (`platform/android/java_godot_lib_jni.cpp`), so switching the device on is the whole
  request. The Quest preset declares `permissions/record_audio=true`. With nobody wearing the
  headset, grant it before launch — there is no one to tap the dialog:
  ```bash
  adb shell pm grant com.xenu.retroxr android.permission.RECORD_AUDIO
  ```
- **macOS.** Needs `privacy/microphone_usage_description` and `codesign/entitlements/audio_input`
  in the preset AND `com.apple.security.device.audio-input` in `entitlements/macos.entitlements`,
  because `release.yml` signs with that file rather than the preset's.

**Which cores hear a microphone**, read at source:

| core | hardware | asks for | switched by | calls from |
|---|---|---|---|---|
| melondsds | DS / DSi mic | 44100, 735 a frame | `melonds_mic_input` (default `microphone`), `melonds_mic_input_active` (default `hold`, on L3) | emulation thread |
| noods | DS mic | 44100 | `noods_micInputMode`, `noods_micButtonMode` (L2) | emulation thread |
| dolphin (fork) | GameCube DOL-022, Wii Speak, Logitech USB | the game's rate, a frame's worth at a time | see below; `dolphin_wiispeak_enable`, `dolphin_wii_logi_microphone_enable` | open and state on its CPU thread, reads in `retro_run` |
| azahar (buildbot) | 3DS mic | opens at 48000 and resamples itself | `citra_input_type` (`auto`, `none`, `static_noise`, `frontend`) | emulation thread |
| virtualjaguar | Jaguar voice modem | 8000 | — | emulation thread |
| mupen64plus-next (fork) | N64 Voice Recognition Unit | 48000, decoded by Vosk | the port's device id; captures while the game listens | opens and reads in `retro_run`, decodes on its own worker |
| flycast (fork) | Dreamcast HKT-7200 | 48000, decimated to the device's 8000 or 11025 | `reicast_device_port<N>_slot<M>` = `Microphone` | opens and reads in `retro_run`, drained on the emulation thread |

A mic that is only a BUTTON, with no audio behind it: DeSmuME (`desmume_mic_mode`, L3 "Make
Microphone Noise"), legacy melonDS (L2), and Nestopia and Mesen for the Famicom (below). No
libretro core hears a PS2 SingStar mic (LRPS2 has no USB microphone) or PSP Talkman
(PPSSPP's libretro build reports no recording).

**The DS listens the whole time, because a DS has no mic button.** melonDS DS gates its mic on
L3 with a default of `hold`, and the DS model masks L3 (`nds_model.gd`
`get_unsupported_button_mask`), so out of the box nothing could switch the mic on. The model
pins `melonds_mic_input=microphone` and `melonds_mic_input_active=always`, and the game decides
when it listens, as on the hardware. The host device therefore stays open for as long as a DS
runs on melonDS DS. DeSmuME has no audio path at all: its `physical` mode reads a buffer the
libretro frontend never fills.

**Measured 2026-09-15** with `Tools/cores/mic_probe`: melonDS DS 1.3.1 opened its microphone at
44100 Hz while loading Super Mario 64 DS and switched it on 4 frames in; over 6 s the service
opened the desktop device and pushed 279,343 host frames at 48000 Hz in 553 pushes. The probe
cannot run against a build without the interface, which has no `IsMicrophoneActive`.

**The GameCube Microphone (DOL-022) seats like a memory card, live.** The hardware:
- A 21 × 140 mm gray stick with an aqua push-to-talk button about 43 mm from the tip, 2 m of
  cord, and a memory-card-shaped plug unit 35.6 × 63 × 13.7 mm.
- It fits either memory card slot; Mario Party 6 and 7 ask for B.
- The button is ON THE MICROPHONE — the EXI status word carries it (`EXI_DeviceMic.h`: "The
  actual button on the mic") — and Mario Party 6 ignores speech until it is held. Odama talks on
  the controller's X instead, with the stick clipped to the pad.

In the Dolphin fork (v11):
- **`dolphin_memcard_a_path` / `_b_path` accept `mic`,** which `Memcard::Resolve` turns into the
  Microphone EXI device. `CheckForUpdates` already `ChangeDevice`s a slot whose answer changed —
  one emulated second of nothing, then the new device — so seating or pulling a microphone is a
  real eject and insert, exactly like a card.
- **`poll_microphone` polls every GameCube microphone that exists.** A `CEXIMic` adds itself to
  `g_gc_microphones` when it is built and removes itself first thing when it is destroyed, under
  `g_gc_microphones_lock`, so a swap on the CPU thread can never hand the libretro thread a
  device that is gone or not yet a microphone. It used to latch `dolphin_enable_gamecube_mic` on
  `IsUpdated`, which never fires for a value that arrived in the `.opt`: a microphone enabled at
  boot was never polled, and nothing said so.
- **The button is read whenever a microphone exists.** In the libretro build
  `GCPad::GetMicButton` ignores the pad number and ORs the button mapped by
  `dolphin_hotkey_activate_microphone` across all four ports (`GCPadEmu.cpp`). Standalone
  Dolphin reads slot A's button from pad 1 and slot B's from pad 2, which is what its forum
  answers describe, and does not apply here.
- **`GetRetroButtonId` did not know `L1` or `R1`,** though the option offers both. Its `L` ↔ `L2`
  swap is deliberate: a GameCube's analog L is libretro L2.
- **The older `dolphin_enable_gamecube_mic` still works,** and still loses slot B to a named card.
- **Seating or pulling a microphone says so,** as `Memory Card B: microphone seated` / `pulled`,
  a warning under BOOT.
- **Each poll reads a frame's worth**, `sample_rate` over the target refresh rate with the
  fraction carried (fork `9a2b37e`, after v11). v11 read one `buff_size_samples` buffer, 16 to
  64 samples, against the ~184 a frame an 11025 Hz game takes; the ring ran dry and
  `StreamReadOne` re-served the previous buffer several times a frame, a buzz no game could hear
  a word in. Measured 2026-09-16 in a player's session: Mario Party 6 answers speech through a
  DOL-022 in slot B with the fix, and did not with v11. It reaches players only with a v12
  release and a `known_tag` bump.

In RetroXR:
- **Objects.** `GcMicrophone` is the stick. `GcMicrophonePlug` is in group `memory_card` with
  `family = "gamecube"`, `is_microphone = true` and no `card_id`, so the shared `_accepts_card`
  seats it in either slot and `_mount_core_cards` writes `mic` for that slot, live through
  `set_core_option`.
- **The button.** The trigger of the hand holding the stick is the aqua button; on desktop it is
  the left mouse button, and the stick sets `desktop_shift_drop` so that click does not put it
  down (Shift+click does), which `microphone_tests` `gc/` pins. Every controller
  writes its whole button mask each frame, so a bit set by another object is gone by the next
  one. The stick uses `Libretro.SetJoypadExtraButtons(0, 1 << R3)`, ORed in when the core reads,
  and the machine pins `dolphin_hotkey_activate_microphone=R3` — no GameCube pad maps R3.
- **Saves.** The plug is on the cord rather than an entry of its own, so the stick's entry
  records `system` and `slot`, and `_apply_references` seats it again.
- **Group sweeps.** Anything that sweeps the `memory_card` group must not assume a card: the card
  poller skips an object with no `card_id`, and card numbering counts only `MemoryCard`s.

**A cord leaves a body along the anchor's local -Z**, which both of these are built against:
the DOL-022's grille and the NUS-021's are at -Z with the cord boss at +Z, so left at the
default each cord came out of the nose and doubled back through its own body. Both ropes now say
`start_exit_axis` and `end_exit_axis` explicitly. The oracle is a SIGN, not a look --
`microphone_tests` and `n64_vru_tests` dot the exit direction against the body's nose-to-boss
vector and want it positive; the default reads exactly -1.00.

**Measured 2026-09-15** with `Tools/input/gc_mic_probe` on the GameCube IPL, no disc. With the
DOL-022 in slot B the options file read `dolphin_memcard_b_path=mic` and
`dolphin_hotkey_activate_microphone=R3`, and v11 logged `Memory Card B: microphone seated` at
boot, `microphone pulled` when the plug came out mid-run and `microphone seated` when it went
back, with the IPL running through both. The same run against the previous build
(`+40a25ffd80`) passes every frontend check and prints none of the three lines: it refuses `mic`
as a card path, in a log category no frontend sees. That is why the line is a warning under
BOOT — the libretro listener leaves EXPANSIONINTERFACE disabled, and libretro-godot passes
nothing below a warning. The IPL never samples the microphone, so no handle was opened.

Shut BOTH card slots to pull the plug in a probe: slot A sits beside B and catches it, and the
mount log then reads `0=microphone`. `Tools/models/gc_microphone_render_probe` renders the stick
seated and prints the plug's axes — its +Z matches slot B's and the cord end points out of the
console.

```bash
"$godot" --headless --path RetroXR res://Tests/microphone_tests.tscn
"$godot" --path RetroXR --resolution 320x240 --position 20,20 res://Tools/cores/mic_probe.tscn
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/input/gc_mic_probe.tscn -- --root=<throwaway root with cores/dolphin_libretro.dll and system/dolphin/dolphin-emu/Sys>
```

**The N64 Voice Recognition Unit is built, and it is a speech recognizer rather than
a microphone.** The hardware: NUS-020 goes in controller socket 4, and its NUS-021
microphone hangs on a cord (clipped to the pad by NUS-025 in Hey You, Pikachu!), with an
ordinary pad in socket 1. Both VRU games want socket 4 — RMG offers the VRU on its last
port alone and says why (`RMG-Input/UserInterface/MainDialog.cpp`) — though `osVoiceInit`
takes any channel and the core attaches a VRU wherever the input plugin reports
`CONT_TYPE_VRU`.

**The emulation was already complete and unreachable.** `vru_controller.c` speaks the whole
joybus protocol, but `plugin.c:317` stamps every port `CONT_TYPE_STANDARD` and the five
recognition calls pointed at the no-ops in `dummy_input.c`, so no frontend could get at it.

In the fork (`retroxr-mupen64plus-next-libretro-v4`):
- **`RETRO_DEVICE_SUBCLASS(RETRO_DEVICE_JOYPAD, 0)` on a port makes it a VRU**, kept in
  `pad_types[]` beside the existing `pad_present[]` idiom and applied in
  `inputInitiateControllers` — which runs after `plugin_start_input`'s blanket overwrite and
  before the joybus channels are built, and is therefore the only window in which a VRU can
  be asked for. An id the core does not know still falls through to a pad.
- **It attaches at content load, not at reset.** `retro_reset` never re-enters the channel
  build, so a unit pushed in mid-game is heard at the next load; the core says so once, as a
  warning and an on-screen line naming a reload rather than a reset.
- **Five plugin calls, not three.** `ClearVRUWords` is the only signal that a new word list
  is starting — without it the grammar grows for ever. `SetVRUWordMask` really is unused.
  All five arrive on the emulation thread, so they only touch flags under a lock: Vosk lives
  on a worker of its own, and every microphone call belongs to the thread that runs
  `retro_run`.
- **The game decides when the unit listens, and nothing the player holds does.** The real
  VRU has no button: a game sends it "listen" and "stop" (`JCMD_VRU_WRITE_CONFIG` 0x4E /
  0xEF, arriving as `SetMicState(1)` / `(0)`), and the chip inside reports "busy" while
  someone talks and "ready" when they stop. `vru_controller.c` cannot hear, so it fakes that
  status from Z on the VRU's own port (its comment says HACK). Both working plugins raise that
  line from the game's own mic state — RMG-Input's `GetVRUMicState()` sets `Keys->Value =
  0x0020`, simple64-input-qt does the same with a 2 s timer — and so does
  `vru_recognizer_talking` now. Capture runs from the game's "listen" to its "stop", the stop
  queues the decode, and `ReadVRUResults`, which the game sends straight after, waits for that
  utterance's result (the references decode inside it, so the game is held either way).
  **The first build took the line from the player instead** — the NUS-021's trigger — and
  words were recognised, logged and never reached the game at the moment it asked. In Hey
  You, Pikachu! the player holds Z on their own controller; that is the game's business, and
  the "listen"/"stop" it sends is the only thing the core follows. `mupen64plus-vru-mic-mode`
  is gone with the button, and `mupen64plus-vru-port` with it: which socket holds a VRU is the
  port's device, "Voice Recognition Unit" in the controller list.
- **Vosk is opened at run time, never linked.** A `DT_NEEDED` on `libvosk` would make the
  N64 core everyone installs fail to load when the speech pack is absent. Missing library,
  missing symbol or missing model costs the recognition and nothing else: the VRU still
  attaches, the game still boots, and it simply never understands you.
- **A word is looked up, not guessed.** `vru_word_table.h` is generated by
  `tools/gen_vru_word_table.py` from RMG's `VRUwords.cpp` (GPLv3, so the recognizer is
  GPLv3): 677 unique keys out of 717 rows, first spelling winning, exactly as RMG's own
  lookup does. The table maps the big-endian phoneme codes a game sends to the text a
  recognizer listens for — including Densha de GO!'s Shift-JIS words, which RMG maps to
  English, so Densha de GO! 64 is played by speaking **English**. Pikachuu Genki de Chuu
  has no rows at all: it sends text, below. The lookup still runs first for every word,
  which is what keeps Densha de GO! on its English table text.
- **The model is chosen by what the grammar contains**, not by the ROM's country code: a
  word that decoded to kana wants `model-ja`, an all-ASCII list `model-en-us`.
  `mupen64plus-vru-language` overrides it, and forcing either one against its game hears
  nothing — Densha de GO!'s English text is not in `model-ja`, and Pikachuu Genki de Chuu's
  kana are not in `model-en-us`.
- **A Japanese title sends its words as Shift-JIS text**, one character to each uint16,
  and the unknown-word path used to copy those bytes straight into the grammar. Vosk reads
  and answers in UTF-8, so the grammar and the answers were in two encodings and no Japanese
  word could ever match. Four steps now:
  - **Decoded at the door** (`vru_recognizer_decode_word`) through a built-in kana table —
    hiragana `0x829F–0x82F1`, katakana `0x8340–0x8396` stepping over `0x837F`, `ー` `0x815B`,
    the full-width space — checked against Python's codec for all 171 codes. No iconv, since
    the core builds for MinGW and the NDK. A character outside it refuses the word, which
    still holds its slot, empty.
  - **Folded to katakana** (`vru_recognizer_fold_kana`). A game spells in hiragana; the
    model's lexicon spells ピカチュウ only in katakana and こんにちわ in both.
  - **Split into lexicon words** (`vru_segment_words`). Vosk 0.3.45's `UpdateGrammarFst`
    turns the list into a bigram model and DROPS each token its lexicon lacks, and most of
    what this game sends is not a lexicon word: it sends the ways a child might say one,
    ぴかっちゅう and ぴかてう beside ぴかちゅう. Each word goes to Vosk as the fewest
    `model-ja/graph/words.txt` words that spell it once folded — `ゲーム スタート`,
    `ピカ っちゅう`. When a stretch has both spellings the katakana one is given, because a
    hiragana entry can be a particle and は read as a particle is "wa". The 200,000-line
    lexicon is scanned once per list and not kept.
  - **Matched a whole folded word at a time.** Vosk's answer is folded the same way and a
    word matches when its folded phrase appears in it between spaces, so ぴかってう is not
    also heard as the かって inside it. English matching is unchanged.
- **Lists are bigger than they looked.** Pikachuu Genki de Chuu sends **84** words, where
  the recognizer held 64 and its grammar loop read past the array for the rest. It holds 256
  now (the count is a uint8) at 128 bytes each (40 uint16s of kana). A result is matched
  against the worker's own copy of the list the recognizer was built from, and an unreadable
  word's slot is held empty rather than keeping the last list's word, which used to match
  every utterance.
- **The reply is RMG's**, transcribed rather than invented: five (slot, distance) pairs
  defaulting to `0x7FFF`/0, distance = alternative rank × 256, matches sorted longest-first,
  `mic_level`/`voice_level` `0x0BB8` and `voice_length` `0x8004`. `error_flags` is `0x8000`
  when the decoder refuses the audio and **`0x4000` when something was heard that matched
  nothing** — that flag is the whole difference between "understood" and "did not", because
  the no-match reply also reports slot 0. **Every field is written on every read**, the error
  word included: they point into the joybus reply, which still holds old bytes, and the error
  word used to be written only on an error — a clean match reached Hey You, Pikachu! as
  `0xFE78`, both the decode-failed and the no-match bit. The selftest now starts that word at
  `0xFE78`, which a missed write reads straight back.
- **Every core log level now reaches the frontend.** `n64DebugCallback` mapped every
  `M64MSG_*` to `RETRO_LOG_INFO`, which frontends drop, so no warning the core raised was
  ever visible. It carries the real level across now, which is what makes the line below an
  oracle.
- **A real out-of-bounds read was fixed on the way past**: `vru_controller.c` tested
  `word[offset]` before the bound, reading two bytes past the controller struct.

In RetroXR:
- **It is three objects, as the hardware is three parts.** `N64Vru` is the dongle,
  `N64VruMic` the microphone, and `N64VruMicPlug` the 3.5 mm plug on the microphone's cord.
  The dongle hangs off a second cord that ends in an ordinary `ControllerPlug` — the same
  generic moulding every N64 pad wears, since `n64_controller.tscn` declares no
  `plug_mesh_path` of its own.
- **The PLUG is what a socket takes, not the box**, which is why this needed no new plug
  class. `ControllerPlug.set_controller(unit)` copies `device_type` and `systemid` off the
  dongle, the plug is the one in the `controller_plug` group, and `_bind_port` unwraps it
  with `get_controller()` before filing it in `_port_controllers` — so the console still
  sees a VRU and the unit still answers `microphone_position()`. The box was in that group
  until 2026-09-17 and its front end was moulded as a connector tongue to suit.
- **The microphone plugs in and pulls out.** The dongle carries a `MicJack` snap zone
  filtered on `N64VruMicPlug.GROUP` — its own group, because `snap_require` on
  `controller_plug` would take a console controller's plug, the trap `n64_pak_port.gd`
  names for the pad's expansion bay. It spawns plugged in, and the unit's entry records
  `mic` so a save remembers. **Out of the jack the unit reports ITS OWN position**, not the
  microphone's: `microphone_position()` is a total function with no way to say "nothing"
  (`system.gd:4182-4203` falls back to the console), so a microphone left on a table across
  the room must stop setting the gain. Whether the machine hears at all is not decided
  there and gets no N64-special case — the unit keeps announcing `DEVICE_VRU` while seated,
  because the NUS-020 is on the joybus with or without a microphone in it.
- **The NUS-021 has no button.** It is what the player speaks into and where the distance
  law measures from; when the unit listens is the game's decision, above.
- **No two faces may share a plane.** The microphone's grille used to be a flat collar
  ending on exactly the body's front cap at z −0.0475, one albedo 0.73 and one 0.18: the two
  cap triangle-fans interleaved and the nose drew as a flickering pinwheel. It is a ball
  head sunk into a tapered body now, and `n64_vru_tests` `faces/` walks both scenes'
  meshes and fails on any two coplanar faces **that point the same way** — a butt joint,
  where the normals oppose, is safe because culling draws only one of them. Reverted, it
  reports `Body|Grille at 0.0475`. `Tools/models/n64_vru_render_probe` renders the set
  (windowed, never `--headless`) and prints the facings.
- **`RetroSystem.microphone_position()` walks the controller ports** as well as the card
  slots, so the distance law follows the NUS-021 in the player's hand rather than the
  console.
- **The speech pack lives under the core's own system directory**,
  `<libretro>/system/mupen64plus_next/vru/`, holding `libvosk` (`.dll` with its MinGW
  runtime DLLs, `.so`, or `.dylib`, from the same Vosk 0.3.45 release as the header) and
  `model-en-us` / `model-ja` (`vosk-model-small-ja-0.22`, needed for the Japanese games).
  That directory is per core name, so the Quest's `mupen64plus_next_gles3` has one of its
  own. On Android it must stay on internal storage: `dlopen` outside the app's own
  namespace is refused.
- **It is downloaded from OPTIONS > Cores > BIOS / Extras**, on the Nintendo 64 page: one
  row per language, "Voice Recognition Unit speech: English" and "…: Japanese". A row is
  a **pack** (`SystemAssetCatalog.PACKS`), the kind of download libretro does not host:
  each part is a zip from its own author -- the library from Vosk's GitHub release
  (`vosk-win64` / `vosk-linux-x86_64` / `vosk-android` 0.3.45, `vosk-osx` 0.3.42, the
  last universal build Vosk published) and the models from alphacephei.com -- with the
  folder inside the zip to take (`from`), the folder of the system dir it goes to (`into`)
  and which files to keep (`only`, so the library zip leaves its headers and import
  library behind). A part already on disk is skipped, so the second language downloads
  only its model; a row reads Installed when every part's marker exists, and pressing it
  again re-fetches everything as a repair.
  - **GitHub answers a release asset with a 302 to a signed link that expires within the
    hour**, and `RommHttp` follows no redirects, so `FirmwareInstaller` resolves the URL
    with HEAD requests at the start of every attempt, not once.
  - **Measured 2026-09-16** against the real hosts into a scratch system dir: Japanese
    fetched the library (4 files) and its model (16), English then fetched only its model
    (14), 13 s in all; `vru_selftest` pointed at the result passes every English and
    Japanese case. `archive_tests` `pack/` covers the remapping, the `only` list, a zip
    missing a listed file or renamed underneath us, a member climbing out of `into`, URL
    splitting, the per-platform library name the core opens, and installed-means-every-part.
- **Every platform builds it.** `vosk_api.h` is vendored in the fork under
  `custom/dependencies/vosk/` with its Apache-2.0 licence. It was a git submodule, which
  the release workflow cannot check out (this repository vendors by subrepo, and a leftover
  gitlink makes `submodules: recursive` fail), so a build from the committed tree stopped at
  `vosk_api.h: No such file or directory` on every platform. `retroxr-release.yml` now has
  Linux x86_64 and macOS arm64/x86_64 jobs beside Windows and Android, and fails a Linux or
  macOS build that links libvosk.

**Measured 2026-09-15.** `tools/vru_selftest` loads the same library and model the core
loads, sends the word list the way a game sends it, and pushes a recorded utterance through
the same entry point the microphone feeds: a spoken "pikachu" comes back as slot 0 with no
error flags, and a control utterance the game is not listening for comes back `0x4000`,
refused. Swapping the two makes both checks fail, which is what makes them checks. Vosk's
own answers are `{"text": "pikachu"}` and `{"text": "[unk]"}`.

`Tools/input/vru_probe` then proves it against the game itself. With a NUS-020 in socket 4,
**Hey You, Pikachu! loads its vocabulary into the unit** -- the core logs the grammar it built
from the phoneme codes the game sent, which is also what proves the word table was transcribed
correctly:

```
["pikachu", ... , "hey", "come here", "this way", "good bye", "see you later", "bye bye",
 "start", "lets play", "hello", "open sesame", "go away", "good morning", "im sorry",
 "i choose you", "hey you pikachu", "pika pikachu", "pika pika pi", "pi ka ka pi",
 "bring that here", "go get it", "give it to me", ...]
```

and `Game controller 3 (VRU controller) attached` names `g_vru_controller_flavor`, so the joybus
device was selected rather than inferred. **One leg per process**: `--leg=control` runs the
same game with an empty socket and prints none of those lines. The probe speaks with Z held on
the socket-1 controller, but only a scene where Pikachu listens starts the unit, and its opening
is not one; the log says `VRU: the game started listening` when a scene does.

**Measured 2026-09-16 in a player's session**, Hey You, Pikachu! in gameplay, a real voice
through a C920 webcam, VRU Logging on: holding Z brackets each utterance with `the game started
listening` / `stopped listening`, and the game reads its answer 10 ms after the stop:

```
VRU: heard "hello" as word 14 "hello"
VRU: the game read 1 result(s), first slot 14, flags FE78 (10 ms)
VRU: heard "throw it" as word 41 "throw it"
```

and the player reported it working. `FE78` there is the unwritten error word above; the build
after that run writes 0, and has not yet been played. A scene loads its own list —
two grammars in that session held "stay at my house" and "throw it" in one and not the other.
**The log shows a blank line after every core line**: mupen ends each message in `\n`, the
libretro convention, and libretro-godot's `LogHandler` prints it with `print_line_rich`,
which adds another. Every core that follows the convention does the same there.

**Measured 2026-09-16, the Japanese half.** Pikachuu Genki de Chuu, same probe, a NUS-020 in
socket 4: the game sends 84 words, every one of them spelled by `model-ja`'s lexicon
(`ぴかっつう` as `ピカ っつう`, `きみにきめた` as `キミ ニキ メタ`, `つぎのすてーじへれっつごー` as
`つぎ のす テー ジヘ レッツゴー`), and an Open JTalk ぴかちゅう pushed through the microphone
interface comes back four times out of four as

```
VRU: heard "ピ カッ ちゅ" as word 9 "ぴかっちゅ"
```

-- one of the misheard spellings the game lists so that a child's "pikachu" still counts.
`--leg=control` with socket 4 empty prints no VRU line and loads no model. The selftest's
`engine-ja` group does the same offline: ぴかちゅう (whole in the lexicon) and げーむすたーと
(only as `ゲーム スタート`) each return their slot with no error, ばなな returns `0x4000`. Each
of five mutations fails exactly its own cases -- no Shift-JIS conversion, no fold, no katakana
preference, the English match rule, no segmentation. **The same selftest passes on Linux**
(WSL Ubuntu 24.04, gcc 13, Vosk 0.3.45's `libvosk.so` through `dlopen`), where
`make platform=unix` builds a core with no `libvosk` among its NEEDED entries.

Two traps from getting there. **A test that speaks the moment it sends the list is timing the
model load**, not the recognizer: `model-ja` takes seconds to open, `ReadVRUResults` waits
250 ms, and the reply comes back empty. `vru_recognizer_grammar_ready()` is what the selftest
waits on, the way a game has sent its list long before anyone talks. And **Japanese in a core
log arrives mangled twice**: libretro-godot widens each byte to a code point, and `ゅ` is UTF-8
`E3 82 85`, so its last byte becomes U+0085, a line break -- the line is cut there, and a
Python `splitlines()` cuts it again. Rebuild the bytes (code points below 256, plus cp1252 for
0x80-0x9F) and split on `\n` only.

```bash
"$godot" --headless --path RetroXR res://Tests/n64_vru_tests.tscn
"$godot" --headless --path RetroXR res://Tests/n64_vru_tests.tscn -- --only=faces
"$godot" --path RetroXR --resolution 900x700 --position 20,20 \
  res://Tools/models/n64_vru_render_probe.tscn -- --out=<dir>
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/input/vru_probe.tscn -- --root=<throwaway root> \
  --rom="<Hey You, Pikachu! or Pikachuu Genki de Chuu>" --leg=seated --speak=<48 kHz mono wav>
# in the fork
uv run tools/vru_render_ja_clips.py <clip dir>      # Open JTalk, pinned in the script
gcc -std=gnu99 -O1 -o vru_selftest tools/vru_selftest.c \
  custom/mupen64plus-core/plugin/vru_recognizer.c -Icustom -Icustom/mupen64plus-core \
  -Imupen64plus-core/src -Imupen64plus-core/src/api -Ilibretro-common/include \
  -Icustom/dependencies/vosk -Ilibretro -lpthread -ldl        # no -ldl on Windows
./vru_selftest <system dir> <english wav> <control wav> --ja-clips=<clip dir>
```

**Still owed.** Every utterance measured is synthesized speech, English from SAPI and
Japanese from Open JTalk, which is cleaner than any player; how well either model hears a
real voice is untested. Nobody has watched Pikachu obey on screen, in either language -- the
probe speaks during the opening, and what is proven is that the game asked for a word list
and got answers back. Densha de GO! 64 has not reached a word upload in a probe run: it wants
menu navigation first, so its table path is covered by the English selftest and not by the
game. The macOS jobs in `retroxr-release.yml` have not run -- the workflow runs on a tag or
by hand -- and a macOS RetroXR runs software-rendered cores only, so whether this core runs
there at all is untried. `core_sources.gd` names no Linux or macOS asset for this fork yet.
The speech pack download is measured on Windows only; the Android, Linux and macOS
libraries are chosen by `SystemAssetCatalog.library_part_id` from their zips' listings and
have not been installed through the app. Quest is built -- the arm64 library carries the
recognizer and resolves dlopen -- but unmeasured: libvosk is 8.9 MB and a loaded model about
300 MB, `model-ja` included. A pack installed while an N64 is running is not heard until
that machine is powered on again, because the recognizer tries the library once per load.

**The Dreamcast Microphone (HKT-7200) is built.** It fits either expansion socket on the pad
and has no button of its own: each game talks on a controller button, A in Seaman and Y in
Alien Front Online. Seaman will not start unless the pad is in port A with the VMU in socket 1
and the microphone in socket 2, which is why the core offers it in both.

**The device was already emulated and unreachable.** `maple_microphone` in
`core/hw/maple/maple_devs.cpp` speaks the whole protocol — 8000 or 11025 Hz, mono, read 240
samples at a time — but `StartAudioRecording`, `RecordAudio` and `StopAudioRecording` in
`shell/libretro/audiostream.cpp` were empty and `RecordAudio` returned 0, so the device
reported no samples for ever.

In the fork (`retroxr` branch):
- **One rule makes it safe:** the emulation thread never calls the frontend, takes a lock or
  waits. The three functions arrive there from inside maple DMA and only move atomics or drain
  a single-producer queue; every libretro microphone call belongs to the thread that runs
  `retro_run`, which is where the pump lives — outside the `retro_audio_upload()` branch,
  because that branch is skipped whenever the renderer is threaded and the rate unlimited.
- **Short reads are normal, not degraded.** 240 samples at 11025 Hz is 21.8 ms, longer than a
  frame, so a game polling once a frame structurally cannot get a full read. That is what the
  protocol's count byte is for, and it is why nothing here ever waits for more.
- **The frontend is asked for 48000 and the rate conversion happens in the core.** Asked for
  11025 it would decimate with no filter at all, folding a 9 kHz component back to 2025 Hz at
  full amplitude — onto the formants of the only two games that use this device.
  `MicrophoneResampler.h` is a windowed-sinc low-pass then interpolation between filtered
  samples: 95 taps for 11025 Hz, 133 for 8000.
- **The vendored `libretro.h` stops at environment call 74**, so `MicrophoneInterface.h`
  backports the definitions verbatim, guarded so the file empties itself the day
  `core/deps/libretro-common` is updated. The probe writes `interface_version` **going in**: a
  zero-initialised struct is refused, so the `probe_controller_interfaces()` pattern beside it
  would have failed silently.
- **`"Microphone"` joins both slot options**, across the table and all 43 translations. Those
  translated rows are generated from Crowdin upstream, so a future rebase onto master will drop
  them — the option keeps working, translated frontends lose the label.

In RetroXR:
- **`DcMicrophone` is a `JumpPack` clone.** A slot device costs no edits at all in `VmuPort`,
  `VmuStorage` or `system.gd`: those ask by method, so answering `slot_option_value()` with
  `"Microphone"` is the whole of the wiring. It carries the same origin rule as the card and
  the pack — a seat places an object's ORIGIN, so the connector sits at +42.5 mm.
- **The pads answer `seated_microphone()`, not `microphone_position()`**, and that distinction
  is load-bearing: `RetroSystem.microphone_position()` walks its port controllers for the first
  thing that can say where it hears from, so a pad that always answered would shadow a device
  that really is one — an N64 VRU in a later socket.
- **Power-on only**, like every slot device; the binding is read when the machine starts.

**Measured 2026-09-15** with `Tools/cores/dc_mic_probe` against Seaman (Japan, 2001 edition),
the pad in port A with a VMU in slot 1 and the microphone in slot 2. The game reaches its
microphone and switches it on, and the core says so:

```
[AUDIO] microphone: open, 48000 Hz from the frontend -> 11025 Hz for the game, 95 taps
```

with `maple_microphone::dma MDCF_MICControl` traffic either side of it and
`IsMicrophoneActive` true. **One leg per process**: `--leg=control` runs the same disc with
slot 2 empty, and the core neither opens a microphone nor prints that line.

That line is a WARNING rather than info on purpose — frontends drop everything below warn, and
it is the only way to tell a microphone a game is really using from one it was merely offered.

The core's own tests cover the two decisions that are easiest to undo later: a 9 kHz tone must
come out ≥40 dB down, which a filterless decimator fails at 1 dB, and the queue must never
hang, must bound its own latency and must drop what was queued before a savestate. The last of
those already caught a real defect — a drain that left a part-block behind, which would have
replayed pre-savestate audio into the game.

```bash
"$godot" --headless --path RetroXR res://Tests/microphone_tests.tscn -- --only=dreamcast
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/dc_mic_probe.tscn -- --root=<throwaway root> --rom=<a disc> --leg=seated
```

**Still owed.** Nobody has confirmed Seaman *understands* what is said to it — the game does
its own recognition, in Japanese, and what is proven here is that it opens the device and
receives audio at the rate it asked for. Alien Front Online is untested. Two microphones share
one stream, because `RecordAudio` carries no device identity: right for Seaman, wrong for a
multi-microphone game, and fixing it means changing shared core API. Quest is unbuilt for this
fork so far.

**The Famicom Controller II microphone is a BIT, not a capture device**, and that one fact
decides everything below. It is part of player 2's pad, where Start and Select are on Controller
I, and reaches the console at `$4016` bit 2 as an instantaneous one-bit threshold detector
sitting on the waveform:
- **The bit flickers between 0 and 1 while there is sound** and is a steady 0 in silence; the
  volume slider turns it off at far left.
- **Games look for the flicker** (Bokosuka Wars is strict about it). Zelda's Pols Voice, Hikari
  Shinwa's haggling (with A held on pad 2) and Takeshi no Chousenjou's karaoke use it.
- **The AV Famicom's second pad and the NES have no microphone.**

| core | where the mic is | when | the bit |
|---|---|---|---|
| nestopia | port 0, L3 | always | steady while held — a frontend must toggle it |
| mesen | port 0, L3 (mapped to player 2's mic) | only when Mesen decides the game is a Famicom: its database tag, FDS, Dendy, or an expansion device | pulsed one frame in three by the core |
| fceumm (fork) | **port 1's Start** | `fceumm_famicom_microphone` | toggled by the core on every `$4016` read while held |

**Why the fork, and why Start.** fceumm had no microphone at all (libretro-fceumm#521), and it
is the core that matters most here: the Android default, the only netplay-verified NES core and
the FDS boot core. Nestopia and Mesen both put the microphone on port 0's L3, which is
unavailable in fceumm — `bindmap[]` already gives L3 to A+B and R3 to Turbo A+B. Port 1's Start
is free AND hardware-correct, because a Controller II has no Start to lose.

In `C:\Users\rymcc\libretro-fceumm`, branch `retroxr`:
- `JPRead` nullifies player 2's Start at `$4017` while the option is on, and toggles bit 2 at
  `$4016` while the frontend holds the button. Two fixes against fceux, which fceumm forked
  from: the bit is set at `$4016` ONLY (fceux reports a microphone to `$4017` as well), and
  `MicBit` is in `FCEUCTRL_STATEINFO`, so a state restored mid-flicker does not resume on the
  opposite phase.
- `joy_readbit` is post-incremented, so the read that just delivered Start (bit 3, `JOY_START`
  is `0x08`) leaves the counter at **4** — that is why the nullify tests `== 4` and not `== 3`.
- The engage line is `log_cb` at **WARN** and only on a change. `FCEUD_Message` logs at info,
  which libretro-godot drops, and this is the only way to tell a microphone that is really live
  from one merely offered.
- Not guarded against a Four Score, which reassigns what `joy_readbit` counts. A Famicom
  microphone and an NES four-player adapter are not a combination any game asks for.

**The level is measured in C++ and is deliberately STATIC.** `Libretro.MeasureMicrophoneLevel`
(`libretro-godot/src/MicrophoneLevel.hpp`) returns the `(rms, peak)` of a block of host frames,
high-passed at 80 Hz and mixed to mono. GDScript cannot visit 800 frames a tick. It is not a
method on a running machine because **fceumm opens no microphone**: there is no handle to hang a
level off, and `IsMicrophoneActive()` never goes true for a Famicom, so a capture service that
asked only the core would never switch the device on for one. `RetroSystem.hears_microphone()`
answers that question instead, and `microphone_input.gd` measures **once per tick** and scales
per machine — rms and peak are both linear in the gain, which `tests/microphone_level_test.cpp`
pins, and that is what keeps the one-reader rule.

Two properties of the measure worth knowing. The high-pass is **seeded from the block's own
first sample**, so it starts matched to the signal and a block boundary contributes no step of
its own — that is what makes a stateless per-block measurement correct, and removing the seed
makes a tone measured over a DC offset read several per cent loud. The filter's OUTPUT still
starts from rest, so a tone already running when a block opens overshoots its amplitude by about
5% in `peak`, once; removing that would mean carrying state between blocks.

**In RetroXR:** `famicom` is a systemid of its own now, where it used to collapse into `nes`.
- `SystemInfo/famicom.tres`, a `model_registry` row, both icons (the theme's `HVC-001` file and
  the NES's `(J)` cartridge — see `Textures/SystemIcons/ATTRIBUTIONS.txt`), and rows in
  `romm_platforms`, `screenscraper_systems`, `ra_consoles`, `core_recommendations`,
  `media_dimensions`, `netplay_cores` and `spawn_catalog`.
- **The tile comes from the core-info overlay**, not from any of those: a systemid reaches the
  browser through `CoreInfoDatabase`, so `libretro-core-info-retroxr/fceumm_libretro.info` adds
  `famicom` to `secondary_systemids`. That same declaration is what gives a spawned Famicom a
  core at all — the Cores panel walks `systemids_of()` and adopts a first default for every
  platform an installed core serves.
- **`famicom_primitive.tscn`** is the HVC-001 at 220 x 150 x 60 mm: a dark red base the full
  width, a cream deck 114 mm wide on the middle of it, and the two 53 mm strips of base left
  either side as the controller wells. 114 + 53 + 53 is the whole width, which is why the
  machine has almost no wall between a cartridge and a controller, and why the cartridge mouth
  is simply the gap between the deck's front and rear blocks.
- **The pads are HARDWIRED, as they are on the machine.** Both cords leave the back through a
  grommet at each rear corner and there is no socket to unplug. `RetroSystemModel.captive_
  controllers()` names the two scenes and `captive_controller_rests()` says where they lie;
  `RetroSystem._spawn_captive_controllers` builds them with the console, seats each in a port
  and then LOCKS that port, hiding its recess and number. Everything downstream is unchanged —
  bindings, netplay and the core still see two ordinary port controllers.
  - **`RetroController.captive` keeps them out of the `"spawned"` group**, which is the whole
    reason the flag exists rather than a hidden port: persistence and object sync both sweep
    that group, so a captive pad a save could see would come back as a SECOND pad on every load.
    `RetroSystem._exit_tree` frees them and their cords instead, the way it frees its own
    captive A/V lead. Set the flag BEFORE `add_child`, or the pad's own `_ready` joins the group
    first.
  - **The plug mesh is hidden too.** A hardwired cord has no connector: the rope ends inside the
    grommet, and hiding the plug is also what puts it out of a hand's reach. A hidden plug has
    no moulding for the cord to leave BY, either, so `retro_controller.gd` gives a captive cord
    `end_anchor_offset = Vector3.ZERO` rather than the generic plug's `cable_anchor`: that boot
    offset is 40 mm of nothing here, and the cord ended in mid-air behind the machine.
  - **The two wells hold the pads MIRRORED, and the cord decides that.** A Famicom pad's cord
    leaves its far long edge (local -Z); turned lengthways into a 53 mm well that edge can only
    face the console's +X or -X, and the grommet each cord must reach is at its own rear corner.
    So the left rest is R_y(90) and the right R_y(-90), and each cord leaves over the OUTER wall
    of the well it lies in. Both turned the same way — which is what shipped — sent Controller
    II's lead inboard across the cartridge deck. The price is that the two pads face opposite
    ways lengthways, which is what a mirrored pair of wells does to a flat object.
  - **A stowed cord has to be LAID, not left to the rope.** `VerletRope._init_points` draws a
    straight line between its two anchors, and a stowed pad's boss is ~130 mm from its grommet
    while the cord is a metre long — so every particle starts at a seventh of its rest length
    and the solver spends the rest putting it somewhere. In a void it stands the cord up in
    arches over the machine and sleeps in them; on a desk it flings the spare out sideways and
    it comes to rest sprawled round the FRONT of the console, 120–180 mm past a front face at
    75 mm. `RetroSystemModel.captive_cord_routes(length)` answers with a polyline per cord —
    over the side of the well, down to the surface, round the rear corner, the spare coiled
    behind the machine, back into the grommet — which `RetroController._lay_captive_cord`
    resamples at equal arc length onto the particles and hands to `restore_points`.
    - **The coil's turns must clear `collision_radius` × 2, or the cord never sleeps.**
      controller_cable.tscn self-collides at 0.0036, so turns laid closer than 7.2 mm push each
      other apart for ever: four turns of a metre of cord sat 7.4 mm apart and crept across the
      desk all session at 0.13 mm a tick. Three turns sit 15 mm apart and the pair is asleep
      about 800 ticks after the lay. `_COIL_MAX_TURNS` is that cap.
    - **Measure the ROUTE for anything the route decides.** Where the spare ends up is decided
      by gravity and the desk, so a coil authored at deck height reads as flat a second later
      and a settled-height assertion cannot fail. `famicom_tests` asks the model for its routes
      and checks those; the settled cord is only asked the things settling cannot fix (it ends
      at the grommet, it is laid at about its own length, it never comes round the front).
  - **Each well is a snap zone, so a pad goes back in.** `RetroSystem._build_controller_well`
    puts one at each rest — the transform IS the rest, measured: a pad carries no snap grab
    point, so a zone seats one at its own basis. `snap_require = "hand_held_device"` (a zone
    with none never lights a ghost and no ray grab can reach it) plus a filter bound to the ONE
    pad that came out of that well, because a cord reaches its own rear corner and no other.
  - **Both scenes carry `cable_length = 1.0`** rather than the 1.80 m every other pad inherits
    from controller_cable.tscn. No dimensioned figure for an HVC-001 cord was found in a
    primary source; the Famicom's hardwired cords are famously short (Old School Gamer says
    18 in, against an NES lead "three times that length"), so a metre is an estimate made from
    that and from the reach a player needs to a console standing on a table. One constant.
  - **The order is load-bearing.** Controller I is port 1 and Controller II port 2, because the
    core reads the microphone off `joy[1]` alone — a Controller II built into player one's port
    would have no microphone at all.
- **One socket, and it is not composite.** The HVC-001's rear panel carries AC ADAPTER,
  TV/GAME, CH1/CH2 and RF SWITCH, and nothing else; everything the machine puts out goes down
  that one coax to the RXR-003 switch box and into the set's aerial socket. So
  `av_port_channels()` is `[VIDEO]` — the channel an RF feed resolves as everywhere in this room,
  the same thing the NES's own RF OUT says — and the built port is renamed `RfOut`, so a cord
  reads the same in a save on either machine. Listing a channel at all is also what stops the
  cabinet spawning a captive composite lead, which this console has none of. `configure_av_legend`
  hides the generic plate: it reads "AV OUT" over a "VIDEO" jack, which is the one thing this
  panel is not, and the scene prints "RF OUT" on the panel's own black strip above the socket,
  where the real machine silk-screens its four labels.
- **An RF cord carries the SOUND as well**, which is what makes this machine audible at all.
  `RcaPort.rf_feed` marks a modulator output — one coax, picture and sound — against a baseband
  composite jack, which carries nothing an amplifier can use. `AvSource.resolve` applies that
  sink **after every link has been walked**, and only if no dedicated audio cord claimed the
  sound: a machine wired both ways is still heard through its phono pair, whichever order
  `AvGraph` returns the links in, and RF is what a machine with no audio socket has instead. A
  set demodulates it onto BOTH its speakers, unlike a mono phono cord, which is heard from the
  one speaker its input drives. The NES's own RF OUT is marked too, so an NES reached ONLY over
  RF gains sound it never had — the same latent gap, invisible for as long as every machine with
  a coax also wore a phono pair. `av_tests` `wiring/an RF cord carries the sound as well` pins
  both halves, and goes red if the RF feed is allowed to outrank an audio cord.
- **`FamicomControllerII` holds port 1's Start** through `SetJoypadExtraButtons` while the room
  is louder than the volume slider allows, and **does not flicker** — that is the core's job,
  and a pad that flickered too would only alias against the core's own toggle. It holds nothing
  at all when seated in port 1 (`drives_port`), because the core reads `joy[1]` alone: a
  Controller II in player one's port that held the bit anyway would have every noise in the room
  pressing Start and pausing the game.
- The slider's threshold falls **logarithmically** from a shout to near-silence so its travel is
  even in decibels, with hysteresis at `RELEASE` so a voice sitting on the threshold does not
  chatter, and its far left switches the microphone off as the real one does.

```bash
"$godot" --headless --path RetroXR res://Tests/famicom_tests.tscn
"$godot" --headless --path RetroXR res://Tests/famicom_tests.tscn -- --only=gate
"$godot" --headless --path RetroXR res://Tools/cores/famicom_mic_probe.tscn -- \
  --root=<throwaway root with cores/fceumm_libretro.dll> \
  --rom="Z:/roms/nes/Bokosuka Wars (Japan).nes" --leg=mic
```

`Tools/models/famicom_render_probe` renders the machine front, top and rear and prints the
pads' ports and groups — windowed, never `--headless`, which returns a correctly sized blank. It
spawns no pads of its own: both arrive with the console, and a probe that made its own would put
four in the room.

**Measured 2026-09-15** against Bokosuka Wars (Japan) on the forked core: the option reached
`fceumm.opt` and the core logged `Famicom Controller II microphone on -- player 2's Start is now
the noise you make`. The same ROM on an NES machine (`--leg=nes`) prints nothing and gets no
`enabled` key, which is the leg that makes the first one mean something. **Wipe
`<root>/core_options` between legs** — a core serialises its whole option set on shutdown, so
the Famicom leg leaves the key behind for the NES leg to read.

Three things this does NOT show, and one trap. **`SnapshotMappedRam()` is not an oracle here**:
it is read on the main thread while emulation runs on its own, so the frame it catches varies —
the same leg run three times gave two different digests, and the mic and quiet legs gave the
SAME one. A "the game reacted" check needs the emulation gated to an exact frame AND a ROM
driven to the moment it listens; 1800 frames of Bokosuka Wars is its title screen. **The pad's
own bit has not been driven into a game by a hand**, only through the same call the pad makes.
And **the Disk System still hosts on `nes`**: `ExpansionCatalog`'s `host` is single-valued, so
the Famicom Disk System is on the NES's card despite the name.

**`famicom_tests`** is 72 headless cases over the threshold curve, the gate and its hysteresis,
the C++ measure read back from GDScript, the service's one-measurement fan-out, the port rule,
both pads, the captive pair the console builds, and every table row. Mutation-tested: making the
microphone drive any port, ignoring the slider's off position, dropping the distance scaling, or
letting a captive pad join the `"spawned"` group each fails exactly the cases that name them. It also waits for `ModelWarmer.is_warmed()` before quitting — SceneManager's boot
warm fires four process frames in, and a suite short enough to quit mid-warm prints a screenful
of parse errors from a loader thread as the class cache goes away.

**Others.**
- **Wii Speak and the Logitech USB microphone** are Dolphin options: `dolphin_wiispeak_enable`
  (with `dolphin_wiispeak_muted`, muted by default) and `dolphin_wii_logi_microphone_enable`.
  No source names a particular USB port.
- **The 3DS** listens through `citra_input_type=auto` or `frontend`.

**Still owed.**
- **A game answering the player.** There is no microphone-reading ROM here for any of these
  machines, so the probes prove the device, the handles and the hot swap — not Pikachu, a Pols
  Voice or a Mario Party minigame.
- **Netplay carries no microphone.**
