# §2l — the controller audio interface

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### 2l. A controller's own speaker — the controller audio interface

Dolphin emulates the Wii Remote's speaker completely, and stock Dolphin throws
everything a game sends it away: `SpeakerLogic::SpeakerData` returns at once unless
`MAIN_WIIMOTE_ENABLE_SPEAKER` is set, and it defaults to off. `Boot.cpp` sets it.

Switched on alone, the speaker would play in the console's main mix, i.e. out of
the television. So it comes out through a private environment call,
`RETRO_ENVIRONMENT_GET_CONTROLLER_AUDIO_INTERFACE` (96), in
`libretro-godot/src/ControllerAudioInterface.hpp` — kept byte-identical in the
Dolphin fork, like the Transfer Pak header. The core offers each controller
device's sound, every block, silence included, just before the main batch.
`push` returning false tells the core to mix that block into the main stream
instead, which is also what a frontend with no such interface gets.

The call takes a PORT and an INDEX. Index is the device on that controller: 0 is
a Wii Remote's speaker. It is there for the Dreamcast VMU buzzer, one per pad
slot, which flycast can already sound (`flycast_vmu_sound`) but through one
global generator that does not know which card beeped. Wiring that is future
work in the flycast fork; the interface needs no change for it.

- **Dolphin:** `Audio::ProbeControllerAudio` turns on
  `MAIN_WIIMOTE_AUDIO_ROUTING_ENABLED` and the four per-remote outputs ONLY when
  the frontend answers, which takes those channels out of `Mixer::Mix`; it runs
  before `BootCore` builds the mixer. `Stream::MixBlock` is now the one place a
  block is mixed and sent.
- **Frontend:** `AudioHandler::PushControllerFrames`. A voice is created the first
  time a device makes a non-silent block, so a remote that never beeps costs no
  voice. The fallback AudioStreamPlayer3D backend answers false, so on a platform
  without Meta XR Audio the beep plays from the set.
- **It is resampled at `m_last_ratio`, the main batch's ratio with the rate trim
  in it.** Resampled at the nominal ratio, the remote's voice drifts against a
  mixer whose depth the trim is holding steady.
- **An empty voice is first filled with silence to the MAIN voice's depth.** The
  MetaXRAudio mixer plays a voice with no prebuffer and counts an underrun on
  every block it finds one empty, so a voice fed in step with the main one but
  started from nothing sits at zero depth and crackles. Matching depth is also
  what makes the beep land with the game's own sound.
- **GDScript:** `Libretro.GetControllerAudioVoiceId(port, index)` is -1 until the
  voice exists. `wiimote.gd` `_update_speaker` poses it on the `Speaker` marker in
  `wiimote.tscn` (the middle of the grille, facing out of the face) with the
  distance law only: a game sets the speaker's volume itself, as it does on the
  hardware, so the television's level has no say.

`RetroXR/Tools/cores/wiimote_speaker_probe.tscn` is the check, and a probe because
it wants Dolphin and a Wii disc.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/wiimote_speaker_probe.tscn
```

**Measured 2026-09-13** against Wii Sports (USA) (Rev 1): the A press on the
health screen beeps the remote, and port 0 got voice 2 (main voices 0/1) 432 core
frames in, with samples queuing on it. The same run against the previous core
(`dolphin_libretro.dll.prespeaker`) pressed for 7200 frames and never got a voice,
so the oracle can go red.

Two traps it hit. **Windowed only:** under `--headless` the SDK reports itself
unavailable and there are no voices to give. And **the desktop Options switch
turns the SDK off for the whole process** — `SpatialAudioListener` applies
`AppPrefs.spatial_audio_sdk` at boot, and `is_available()` answers false while it is
off even with the library loaded, printing `not available ()` with an empty error.
The probe enables it for its own run. A desktop player with that option off hears
the remote from the television, which is the fallback working, not a bug.
