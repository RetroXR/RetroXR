# §2r — surround sound

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### 2r. Surround sound — a matrix decoder, six mono voices, and a phono row

Every sound in this room is two channels wide end to end: libretro's audio API is hard
stereo (the word "channel" appears twice in 7,600 lines of `libretro.h`) and `vlc-godot`
asks libVLC for stereo outright. But the spatial layer is built the other way round — **a
Meta XR Audio voice is MONO** (`MetaXRAudioServer.hpp`), and the mixer renders one mono
point source to binaural per voice. So **surround here is more VOICES, not more
channels**, and `speaker_pair.gd` already stated the other half: a sink is two markers and
a volume number, and the SOURCE owns its voices and walks them onto whatever
`get_speaker_positions()` hands back, every frame.

**It decodes Dolby Surround and Pro Logic II rather than upmixing**, which is the whole
point: a large part of the library is genuinely matrix-encoded, so the decoder is
recovering authored content rather than inventing it. GameCube/Wii is the strongest case
(the DSP mixer has a Surround channel and the AX/JAudio ucode does PLII), then PS2, then
exactly 16 N64 titles, the ~12 known SNES Dolby Surround games, PS1, and Dreamcast via
OS r11.

**The decoder is FreeSurround** (Christian Kothe, GPL-2.0-or-later), vendored from
**Dolphin's** `Externals/FreeSurround/` into its own extension, `surround-godot/`.

- **Not `tygyh/FreeSurround`**, which looks like better provenance and is broken: it drops
  the `kiss_fft_scalar=double` override while leaving `cplx` at `std::complex<double>`, so
  its FFT writes 8-byte complexes into a buffer read as 16-byte ones. Nothing restores it,
  and its `exports.props` still points at a Dolphin path for a `.vcxproj` the repo does not
  contain — it has never been built. Dolphin's copy declares `lt`/`rt`/`dst` as
  `std::vector<double>`, which makes that same mistake a COMPILE ERROR; verified by
  mutating the scalar and watching the build fail.
- **Its own extension, for licence reasons.** `libretro-godot` is MIT and published
  separately as `github.com/RetroXR/libretro-godot`, so GPL code cannot live there;
  `metaxr-audio` links Meta's proprietary blob under the GPLv3 §7 permission in
  `LICENSE-EXCEPTION.md`, which is the user's to grant over their own code and NOT over
  Kothe's. So the decoder is pure DSP that knows nothing of Meta and nothing of libretro.
- **Patents are expired.** US6920223B1 (Fosgate/Dolby, priority 1999-12-03) reads
  "Expired - Lifetime", estimated 2019-12-03.
- **`matrix4` from `bmc0/dsp` was the runner-up, rejected for one reason**: it produces NO
  centre channel (2/2 and 2/4 only) and does not implement the PLII inverse. Better
  engineering on every other axis — time domain, no FFT, ISC, actively maintained — so keep
  it as the fallback if artifacts disappoint, and read its power-compensation contour
  regardless. Do not take `matrix4_mb`: it needs FFTW3.
- **Core-side decoding is a dead end**, instructively: Dolphin's `MixSurround()` calls
  `Mix()` to get *the same stereo buffer the core already sends us*, then runs FreeSurround
  on it. The matrix is in the stereo pair — that is what matrix encoding means — so the
  decode is identical either side of the wire. It would reach 2 systems of 58 against
  58 of 58.

**Name the formats in player-facing text, not in our branding.** The SURROUND position's
OSD says `SURROUND — DOLBY PRO LOGIC II`, because a game's own options menu says "Dolby
Surround" and there is otherwise no way for a player to tell that this is the switch that
decodes it. Dolphin ships a "Dolby Pro Logic II Decoder" setting, VLC ships
`channel_mixer/dolby.c`, FFmpeg documents `-matrix_encoding dplii`. What to avoid is
narrow: no Dolby logos or device marks, no claim of certification or endorsement, and the
marks are not OUR branding — the extension is `surround-godot`, the class is
`SurroundDecoder`, and the About panel carries the trademark attribution.

**Three latency figures exist and mixing them up is easy.** FreeSurround's *inherent* delay
is `N/2` — `buffered()` returns exactly that — so 10.7 ms at N=1024/48 kHz.
`af_surround`'s total input-to-output delay is a full `win_size`, double that, which is
where an "85 ms" figure comes from. Dolphin's "80 ms" is a third framing again, a
buffer-size equivalence. A *pipeline* figure legitimately sits above `N/2`, since
`decode()` consumes N frames at a time while batches are ~800 — but say which you mean.
**N = 1024**: Dolphin measured it as having less steering glitch and less crosstalk than
512, and `sample_rate/N` is the bin width per-bin steering exists to buy.

**How the extensions reach each other.** `libretro-godot` is built against a trimmed
godot-cpp (`Tools/godot_cpp_profile.json`, 53 classes) with **no `ClassDBSingleton`**, and
adding a class there forces a full godot-cpp rebuild for every extension. `Engine` IS in
that list, so `surround-godot` exposes a **`SurroundAudio` factory singleton** with
`create_decoder(block_frames, sample_rate)` returning a `RefCounted` — the same
arm's-length route `AudioHandler` already takes to the mixer: found by string, optional at
runtime, absent without error. **A decoder is not a singleton and the factory is not one in
disguise**: the STFT carries state across blocks, so every source that decodes needs its
own, one per machine and one per deck.

**Six voices are per-machine opt-in, not a global mode.** `kMaxVoices` is 32 and a machine
already costs 2 main plus up to 8 controller voices, so at 6 main voices five powered-on
machines is 30 of 32. `SetSurroundEnabled` takes the four extra only while a set asks and
hands them back when it stops; an exhausted mixer, an absent extension and the fallback
backend each answer false and leave the stereo path untouched. **Degrade to stereo, never
to silence.**

Four things in that path are load-bearing rather than tidy:

- **The front pair IS `m_voice_l`/`m_voice_r`.** The emulation brake and the rate trim both
  read the depth of `m_voice_l` (`QueuedFrames`, `MsUntilSinkWantsFrames`), so it has to be
  a voice surround actually feeds. The first build gave the fronts voices of their own and
  left `m_voice_l` unpushed: it read empty for ever, the brake never held the core, the
  trim leant fast, and the six crept toward their 32768-frame rings — a player heard the
  game most of a second late. (The two idle voices also underran every block, which
  doubled the probe's underrun count; that was the evidence, and it was explained away.)
  All six are pushed the same frames, so FL's depth is every channel's. Four new voices.
- **The six are kept LEVEL.** A queue is a delay, and the fronts carry the stereo backlog
  across the switch while the four new voices start empty: FL and FR played 12–18 ms
  behind the centre for the whole session. `LevelSurroundVoices` tops an EMPTY channel voice
  up with silence to the fronts' depth — which is also the state `AdmitOnFirstPose` leaves
  a voice in when it drops a backlog pushed before the pose arrived, so a discarded top-up
  is simply made again.
- **The decode is in `PushFrames`**, which is already past the resampler and the DRC rate
  trim. Dolphin found a block decoder and time-stretching together "produces bad sound".
- **A new controller voice is pre-filled to the main voice's depth PLUS the decoder's
  latency.** The game's sound is now held back a window, so without the addition a Wii
  Remote beep leads the game by exactly that.
- **`set_bass_redirection` is what produces an LFE channel at all**, not a nicety. Without
  it the sub is silent and the band stays in the fronts.

**The room half.** The set's back panel grows a second socket row of six phono jacks titled
`SPEAKERS` — FL, FR, C, SUB, SL, SR in the consumer analog-5.1 colour code (white, red,
green, purple, blue, grey) — **above** the input row, because the stock body's floor is at
-0.2 against an input row at -0.15: 50 mm below, 350 above, and a legend plate needs more
than 50. A shell claims the row by carrying a `SpeakerOutSeat` marker, and that marker's
absence is the switch, as `VgaPortSeat`'s is for the DE-15.

**`AvLegend` needed a per-channel word override for it.** The derived word for the centre
channel is "AUDIO CENTER", 29 mm at the authored text size against an 18 mm socket pitch,
so three of the six would have printed over their neighbours. All or nothing per plate: a
partial override would mix two conventions on one legend.

**Which channel a cabinet carries is decided by the socket its lead is in.** A phono jack
is generic; the panel it is screwed to names it. `RcaPort.Channel` gained
`AUDIO_C, AUDIO_LFE, AUDIO_SL, AUDIO_SR, AUDIO_SPEAKER` — **appended**, because the int is
written into saves and onto the wire — and `AvSource.resolve`'s `int(in_ch) - 1` arithmetic
was retired for an explicit `CHANNEL_SPEAKER` lookup, which only worked because
`AUDIO_L`/`AUDIO_R` happen to be 1 and 2. A cabinet's own input is `AUDIO_SPEAKER`, the
generic end that takes whatever the far socket was named.

**STEREO OUT and SURROUND send the sound to the speakers and leave the set silent**, as a
real set switched to external speakers does — so with nothing plugged in, nothing is
heard. The first build folded a missing channel back onto the set's own pair, and a player
with no speakers plugged in heard SURROUND perfectly well out of the television and took
it for broken. A missing channel folds onto the speakers that ARE plugged in, walking a
fixed chain per channel (`TvFit._FOLD_CHAINS`): its own side first, so a rig of rear
speakers alone still images left-right; the centre and the sub to the phantom midpoint
between a cabled pair; and every chain names all six outputs, so one speaker plugged in
gives every channel somewhere to go. A channel landing on a speaker already playing its
own comes in **3 dB down**; one landing on a midpoint does not, since nothing else plays
there. Folding is placing a voice where a speaker is, so not a sample is touched. `speaker_tests`
`fold/nothing ever folds onto the set's own speakers` is the case that goes red if the old
rule returns.

**`RetroTV.get_speaker_positions()` answers by mode**, which is what makes AUDIO OUTPUT a
property of the set: on TV SPEAKERS it is the set's own pair, on STEREO OUT and SURROUND
the pair FL and FR resolve to. A deck and the tuner, which do not decode, follow it with no
code of their own, and nothing aims along the screen normal while `is_sound_external()`.
**STEREO OUT was not wired at all before this** — choosing it changed nothing, and the
stereo pair went on playing from the set.

**The AUDIO OUTPUT key** on the bezel and the remote steps through TV SPEAKERS, STEREO OUT
and SURROUND, all three always: with no speaker plugged in the external two go silent and
the OSD says `STEREO OUT — NO SPEAKERS CONNECTED` or `SURROUND — NO SPEAKERS CONNECTED`,
naming the position so two presses do not read the same. That outranks `SURROUND NEEDS
SPATIAL AUDIO`, because it is why nothing can be heard at all. Glyph `0xF1120`
(`md-volume_source`), checked against the shipped font's cmap by a case of its own, because
`transport_glyphs.gd` records having shipped a guessed codepoint that rendered as a
clapperboard. Its cap is deliberately NOT `audio_mode`'s palette: the two sit in the same
bezel row and both wear a speaker, and at mode 0 / TV SPEAKERS they were the same blue on
the same symbol, which read as one control pressed twice.

**Omnidirectional whenever surround is engaged.** `update_position` aims the stereo pair
along the set's screen normal, which is right for sound leaving one cabinet; a rig
scattered round a room has no single baffle to point along and two of the six are behind
the listener. The distance law measures from the middle of the RIG rather than per cabinet,
so a player standing beside the sub does not take the whole mix with them — the per-voice
HRTF already carries the individual distances. **The LFE is placed but not treated
specially**: Meta's guidance is that a predominantly low-frequency source wants pan and
attenuation rather than the HRTF, and a matrix source carries no discrete LFE anyway (ours
is a synthesised sub-120 Hz band), so it costs a voice either way.

**Linux and macOS get no surround**, by the same line HRTF already falls on: `metaxr-audio`
does not ship there, so there are no voices to place.

**With Meta XR Spatial Audio switched off, the key says `SURROUND NEEDS SPATIAL AUDIO`**
and the set still holds SURROUND, so a machine powered on later takes it up. It used to
name the format regardless — a player pressed it, read "PRO LOGIC II" and heard nothing
change. The message trusts a machine that is decoding over `SpatialAudioListener`'s flag,
which goes stale if anything switches the SDK behind the listener's back. **The Options
switch used to hide itself once turned off**: it was gated on `is_available()`, which
answers false while the SDK is disabled, so it vanished on the next build of the page. It
is gated on `SpatialAudioListener.sdk_installed()` now — the library reported a version.
A machine keeps the backend it booted with, so turning the SDK on needs a power cycle.

Every TV button logs a line, `[RetroTV] TV: pressed AUDIO OUTPUT`, connected ahead of the
button's own handler so it lands first; the remote prints `[TVRemote] TV: pressed <key>`.
AUDIO OUTPUT then reports the outcome, and each machine its own verdict: `[SystemAudio]
<machine>: surround on, 6 voices` or `declined — spatial audio is off`.

**The cabinets and their stands.** `Tools/gen/gen_speaker.gd` bakes a satellite
(95 x 165 x 110 mm) and a subwoofer (260 mm cube); `Tools/gen/gen_speaker_stand.gd` bakes
1.2 m and 1 m floor stands, the height being to the top plate's upper FACE, which is where
a cabinet's own origin lands. A stand's seat needs **no snap grab point** — the one piece
`ExpansionPort` had to invent a foot for — because a loudspeaker is baked with its origin
at its base centre, so a zone whose origin is the plate's face stands the cabinet on the
plate with no offset. `Loudspeaker` joins a group of its own for the plate's
`snap_require`, because `can_preview` refuses to draw the snap ghost for a zone without
one. The STAND records what is on it rather than the cabinet recording the stand, and
putting a stand away drops the cabinet rather than freeing it.

**Two mesh traps this cost, and both are now checks that refuse to save.** `_check_outward`
cannot judge an open funnel — it reads -1 on an axis it is edge-on to whichever way it is
wound — so the driver surface went unchecked and **shipped inside out**: the cone's faces
pointed backwards, culling dropped them, and through the baffle hole the box's own interior
is back-facing too, so the line of sight went in the front and out the back. A player saw
the wall through the speaker. `_check_forward` asserts the one thing that IS true of a
driver: it is only ever seen from in front of the baffle, so not one face of it may point
backwards. And **the cone wall takes the OPPOSITE winding to the surround above it** despite
both running front-to-back — the surround is a convex bead seen from outside, the cone a
concave funnel seen from inside. Separately, `_check_outward` picking the FIRST vertex at an
axis extreme false-positives on a tapered column, whose side wall legitimately faces
slightly upward at its bottom; the stand's copy takes the best-facing of every vertex at
the extreme.

**The composite legend plates OVERLAPPED, and it was z-fighting.** A plate measures
63.1 mm and the group pitch was 60, so each neighbour overlapped the next by 3.1 mm — and
every plate sits at the same standoff, so the overlap was two coplanar quads fighting. A
comment in `tv_panel.gd` said the plate was 57.6 mm with 2.4 mm to spare, and that figure
was believed, twice: once when the pitch was chosen, and once when the seam was first
diagnosed here as two white strips minified together, which removed the group divider and
left the overlap standing. The stock body's groups now sit at a **68 mm** pitch, 4.9 mm
clear, and `av_tests` `wiring/no two legend plates on the back panel overlap` measures the
plates the legend actually built — it went red on all three composite seams at 60 mm.
**Measure a printed width; never read one off a comment.** The divider stays gone: it
added nothing the plates' own borders do not already say.

**A speaker cable's plugs can be spawned in a colour.** The lead is neutral grey
because its channel belongs to the socket, not to it -- but six grey plugs behind a
set are hard to tell apart, so holding the Speaker Cable row for a second
(`HoldPress`, §2q) offers `RcaJack.PLUG_COLORS`. The menu sends
`speaker_cable:<id>`, the controller sets `CompositeCable.plug_color_id` before the
lead enters the tree, and `_cord_color` answers with it for every cord. Plugs only:
the jacket stays `wire_color`. The id is saved as `plug_color`, absent for a lead
left alone, and an id the table does not hold leaves the scene's grey. It changes
nothing about routing. `speaker_tests` `save/a lead keeps the plug colour it was
spawned in`.

**Binning a lead re-seated its plugs.** `CompositeCable.drop_and_free` releases every plug
IN PLACE, still standing in the panel, and every empty socket whose grab sphere the plug
body reaches takes it on the deferred `dropped` — the lead is freed at the end of the
frame, so those sockets end up holding freed plugs. Binning a lead from Composite 2 seated
its trio into SUB, SL and SR, 60.3 mm above; headless, the same case seats three input
sockets instead, so the speaker row exposed it rather than caused it. Every plug is now
disabled before the drop: `can_pick_up` refuses a disabled pickable and `let_go` does not
ask. `speaker_tests` `routing/binning a lead seats none of its plugs anywhere` counts
`has_picked_up` rather than reading state afterwards, because once the lead is freed a
socket holding a freed plug and an empty one both answer `is_instance_valid` false.

```bash
"$godot" --headless --path RetroXR res://Tests/speaker_tests.tscn
"$godot" --headless --path RetroXR res://Tests/speaker_tests.tscn -- --only=fold
python Tools/build.py windows --only surround-godot
cd surround-godot && python tests/run_tests.py     # 24 assertions, no Godot
"$godot" --path RetroXR --resolution 900x900 --position 20,20 \
  res://Tools/models/speaker_render_probe.tscn -- --out=<dir>
"$godot" --path RetroXR --resolution 1320x600 --position 20,20 \
  res://Tools/av/tv_back_panel_probe.tscn -- --out=<dir>
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/av/surround_probe.tscn -- --root=<libretro root> --core=fceumm --rom=<a ROM>
```

`speaker_tests` is 130 headless checks: `faces/`, `jack/`, `routing/`, `fold/`, `output/`,
`stand/`, `save/`. Mutation-tested — folding the surrounds to the midpoint, dropping the
3 dB, and a panel that never resolves each fail exactly the cases that name them.

**Latency and level are measured, not assumed.** After the feed check the probe takes the
surround depth twice and fails if it GREW by a decoder block or more — a snapshot cannot
see a creep, and the first latency check passed with the brake broken because five seconds
in the depth was still under any threshold. It then fails on more than one mixer block of
skew between the six. `--soak=<seconds>` samples the front voice every frame by the CLOCK
and fails on an upward trend between the first and last quarter. Frame counts are no clock
here: sharing the machine with a running game, the probe ran at 6 fps, so its "5 s" wait
was fifty. Measured 2026-09-18 after the fix: 55 ms stereo against 68 ms surround, 0 frames
of skew, and a 90 s soak at 54 ms then 53. Pass `--log-file` to a probe run while the
player is in a session, or it rotates their logs away.

**`surround_probe` is WINDOWED, never `--headless`**, and it carries a **stereo positive
control in the same run**, which is the only reason its numbers mean anything: an earlier
run read 0/6 voices fed and looked exactly like a broken decode, and the control then read
0/2 — the machine was silent for reasons that had nothing to do with surround. Measured
2026-09-18 with fceumm: stereo peak depth [1593, 1593] 2/2 fed, surround [2048 x6] 6/6
fed, the centre channel on its own cabinet, the two uncabled surrounds 3 dB down, and the
four extra voices handed back on the way out. Under `--headless` the SDK reports itself
unavailable, so there are no voices at all; and it is `mx.set_enabled(true)` that turns the
SDK on for a probe's own run, NOT `AppPrefs.spatial_audio_sdk`, which
`SpatialAudioListener` applies at BOOT. It also has to stand the cabling in at BOTH ends:
the real captive lead comes from the machine's model, which never spawns in a bare probe
scene, and the machine's OWN routing field is the load-bearing half — without it
`update_position` has no set, the voices are never posed, and `AdmitOnFirstPose` drops the
backlog of a voice that has never been placed.

**Still owed.**
- **Nobody has LISTENED to it**, on a Quest or anywhere. That is the acceptance test for
  the whole feature: Wind Waker or Metroid Prime (GC, PLII), one of the 16 N64 titles, DK64
  (which offers surround in its own options menu), Donkey Kong Country (SNES Dolby
  Surround). A centre-panned voice must come from the centre cabinet and a rear-encoded
  effect from the rear.
- **libVLC still asks for stereo**, so the DVD player and the VCR get no discrete 5.1 and
  the decks' `SpatialAudioEmitter` path is not wired for six. The libretro half — 58 of 58
  systems — is what is done.
- **No CPU measurement on a release build.** The per-bin loop runs N/2 bins at ~13
  double-precision libm calls each and is at least as expensive as the 16 transforms per
  block, so the performance order (float first, then hoist the transcendentals, then swap
  KissFFT for PFFFT) rests on a guess at which dominates rather than on a number. Upstream
  KissFFT has no NEON path at all — `USE_SIMD` covers SSE and LoongArch only — and the
  vendored copy is `double`.
- **Mono content pays six voices**, accepted deliberately. NES, Game Boy and Master System
  are mono at the hardware, so every decoder degenerates to "mono in the centre" — and six
  HRTF paths on a near-pure square wave is where comb filtering is most audible. If a
  player reports NES audio sounding hollow or phasey, an `L ~= R` correlation bypass is the
  cheap fix and this is the first thing to revisit.
- **QSound-era Capcom titles get double-processed**: QSound is pre-baked
  crosstalk-cancelled positional audio, not matrix surround, so decoding it and applying
  HRTF violates its assumptions twice over.
- **Netplay carries only the `audio_out` position**, not audio, which is right: each peer
  decodes its own, because each peer's speakers are in its own room.
- 7.1 (`cs_7point1`) would extend cleanly and nothing needs it.
