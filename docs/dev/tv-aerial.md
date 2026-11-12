# §2t — the aerial, and the one RF dial

Written 2026-09-18, with the change that made it true.

### 2t. One coax socket, one dial

A television has ONE aerial socket and ONE tuner, and everything that arrives down the coax
is found by changing channel:

| what | where it comes from | dial stops |
|---|---|---|
| a Famicom | its RF OUT, through the RXR-003 switch | **1, 2** — the CH1/CH2 slide on its back |
| an NES | its RF OUT, through the RXR-003 switch | **3, 4** — the CH3/CH4 slide on its back |
| an N64 | its RF Modulator (NUS-003) on the MULTI OUT, then the RXR-003 switch | **3, 4** — the slide on the MODULATOR |
| broadcast television | an **Antenna** | whatever it receives: `2.1`, `4.1`, `10.2` … |

`RetroTV.rf_dial()` merges them **numerically** with `TVLineup.number_key` —
`1, 2, 2.1, 3, 4, 4.1, 10.2` — and the CH keys (bezel and remote) walk that list and wrap.
The four console channels are always on the dial; the broadcast ones exist only while an
aerial is reachable. `10.2` is in every test lineup on purpose: a string sort files it
between 1 and 2.

**`Source.TV` is retired, not removed.** It was the built-in tuner's input, back when every
set had broadcast channels with nothing plugged into it. The enum slot and its
`SOURCE_NAMES` entry stay because the VALUE is on disk and on the wire (`source` in a TV's
save entry, `EV_TV_SOURCE`, and `RF = 5` / `VGA = 6` sit after it). `_source_available`
answers false for it, so SOURCE never stops there, and `set_source(Source.TV)` becomes RF.
**Do not renumber the enum to tidy it up.**

**A save from before the aerial** says `source: TV` plus a `channel_index`. It loads onto RF
showing snow, with the channel remembered in `_pending_air_index`, and tunes it if an aerial
is ever plugged in. Nothing is auto-spawned: a room that had TV with no aerial now has no
TV until it gets one, which is the feature, not a regression to paper over.

### The Antenna is a lead with one connector

`Scenes/Objects/appliances/antenna.tscn`, `Scripts/Objects/tv/antenna.gd`. It **is a
`CompositeCable`**, for every reason `rf_switch.gd` gives (StorageBox bins a lead through
`plug.cable`, ScenePersistence dispatches on `is CompositeCable`, netplay seat events are
inherited). What is new is that **End A is CAPTIVE**: the scene ships a `PlugB0` and
deliberately no `PlugA0`, because the cord is moulded into the base.

- `CompositeCable._plug_at(e, c)` is what allows that — it returns null for an end with no
  plug, and everything that walks CORDS goes through it. Anything new that indexes
  `_plugs[e][c]` directly will crash on an aerial and on nothing else. The two rope-geometry
  functions (`_build_rope`, `_clamp_pair`) still index directly and are safe only because
  `Antenna` overrides `_build_rope` and `_physics_process`.
- A lead with one connector joins nothing to anything: `links()` is always empty and no
  source resolves THROUGH an aerial. `AvSource` has no arm for it and needs none.
- So the set is not told through `on_av_topology_changed` (which only reports cords with two
  seated ends). `Antenna._resolve` calls **`RetroTV.on_aerial_changed()`** on the set it
  reaches now and the one it reached a moment ago.

**How a set finds its aerial** — `TvPanel.aerial()`, asked of the socket every time, never
cached: the plug in `RfPort` belongs to an `Antenna` → that one; it belongs to an
`RfSwitch` → `RfSwitch.aerial()`, whatever is in the switch's `AntPort`. One hop, which is
what the ANT socket is for. The set ALSO listens to its own `RfPort`'s
`has_picked_up`/`has_dropped`, because a switch arriving with an aerial already in it moves
nothing of the aerial's and would otherwise never be noticed — `av_tests` seats them in that
order deliberately.

`RfSwitch.drop_and_free` shuts and empties its ANT socket before the box goes: that socket
holds somebody ELSE's plug, and freeing a snap zone that is holding a live pickable takes
the pickable's grab driver with it.

### The N64's RF Modulator (2026-11-11)

The NUS-003 is `RfModulator` (`Scenes/Objects/system_models/nintendo_64/n64_rf_modulator.tscn`,
spawn and save kind `n64_rf_modulator`, on the n64 card with the RF switch): a `CompositeCable`
of ONE plug and no rope, like `LinkAdapter`. `PlugA0` (connector `n64_av_plug`) IS the block;
its RF OUT is `PlugA0/RfOut`, an `AdapterRcaPort` (OUT, VIDEO, `rf_feed`) whose
`get_device()` is the machine the block is seated in, null while it is loose, and which is
saved under the block (`save_owner`). The block's `_resolve` re-resolves the lead in RF OUT,
as `AvAdapter` does, so the console and the set hear of a pull.

**The channel is the block's, not the console's.** `RetroSystem.get_rf_channel` asks
`RfModulator.channel_on(self)` when its model answers -1, so `TvPanel.rf_tuned` still asks one
host one question; the machine's menu row (`rf_options`, `set_rf_channel`) follows the same
fallback. The slide is `PlugA0/ChannelSwitch` (VRSlider, CH3 at value 0), saved as an
articulated control. `av_tests` `wiring/` "RF Modulator" cases hold it (mutation-checked).

### The regional switches: HVC-003 and SNSP-003 (2026-11-11)

Two subclasses of `RfSwitch`, so every `is RfSwitch` check (RetroTV, `tv_panel.gd`,
`antenna.gd`) finds them, each with its own scene, spawn and save kind (`LEAD_SCENES`):

- **`FamicomRfSwitch`** (`rf_switch_famicom.tscn`, on the famicom card in place of the
  RXR-003): the RXR-003's layout in a white box. `Body` IS RetroXR-models' glTF frame
  (meters, +Y up, base on y = 0), so a mod puts the GLB on `Body` untransformed and hides
  `Body/Shell`. `Body/AntPort` stands UP out of the top at the coax screw terminal (zone +Z
  = +Y; an F plug seats moving -Y). The TV lead keeps an F plug (the real one is bare coax).
- **`PalRfSwitch`** (`rf_switch_pal.tscn`, on the n64 and snes cards): NO TV lead. `PlugB0`
  IS the box (connector `coax_plug`; the real one is IEC), `PlugB0/AntPort` on its far end,
  the 3 m console lead from `PlugB0/DeckLeadAttach`. It overrides `ant_port`, `_build_rope`
  (one rope), the tether (the box is the hauled body), `spawn_hold_target` (the box) and
  `carried_body_pose` (empty: the box saves as a plug). `AntPort.snap_filter` refuses the
  switch's own plugs, or the box could seat in its own socket. glTF -> `PlugB0` is a pure
  translation, `p - (0, 0.009, 0.0176)` (the stock set's `RfPort` is R_x(180) off the set,
  so a seated plug's frame is the set's and the box stands upright; `av_tests` checks it).

`RfSwitch` now looks its nodes up with `get_node_or_null` so a scene without `Body`/`TvRope`
loads clean. `av_tests` `wiring/` "HVC-003" and "PAL switch" cases cover routing, the aerial
through each, pulling, and a save/restore round trip.

### Reception and playback are two nodes

`TVTuner` used to be both. It was split along the seam that was already there:

- **`TVLineup`** (`Scripts/Objects/tv/tv_lineup.gd`) — owned by the **Antenna**.
  `channels.json`, `user://tv_lineup_cache.json`, the child `HDHomeRun`, the numeric sort,
  the status line. No VlcPlayer. Built and loaded **lazily** by `Antenna.lineup()`: the two
  things that may start discovery are a set the aerial was just plugged into and a player
  opening its menu. `lineup_if_built()` is for a caller that must NOT be the reason
  (`RetroTV.has_channels`, which the remote polls).
- **`TVTuner`** — owned by the **set**. libVLC, the watchdog, the emitter, static. It takes
  the list with `set_lineup()` and reads `channels` through it. It is still built on first
  use, which is now "the first time the dial lands on a broadcast channel" — opening the
  TV's menu no longer builds one.

The tuner **follows the station by URL, not by index** (`_on_lineup_changed`): discovery
replaces the cached lineup wholesale and re-sorts a second after the cached list was shown.
`RetroTV.rf_air_index` is therefore a READ of `_tuner.current_index`, not a copy of it.

Configuration is still global — every aerial reads and edits the same `channels.json`, as
every television did before.

### IPTV playlists (M3U)

Added 2026-11-07. An aerial's lineup also carries **IPTV channels from extended-M3U
playlists** (`#EXTM3U` / `#EXTINF:-1 tvg-chno=".." group-title="..",Name` / stream URL,
the iptv-org shape). They are rows on the SAME list, so they are on the same RF dial, the
same Antenna menu and the same tuner; nothing downstream of `TVLineup.channels` knows a
playlist exists.

**Where a playlist lives** — three ways in, all global to the machine like the rest of the
lineup (never in a room save, never on the wire):

| how | where |
|---|---|
| drop a file (the main way) | any `*.m3u` directly in `<data root>/tv/` (`RomLibrary.default_tv_root()`, beside `channels.json`): desktop `~/retroxr/tv/` (or the relocated data root), Quest `/sdcard/Android/data/com.xenu.retroxr/files/tv/`, reached through the Web File Manager, which serves the whole media root. Read fresh each time; delete it to take its channels away. |
| a URL on the Antenna menu | the IPTV (M3U) ribbon's playlist box writes one `{"type":"m3u","url":…,"enabled":…}` source to `channels.json` (`TVChannels.set_playlist`; an empty URL removes it). |
| by hand | `{"type":"m3u","url":…}` or `{"type":"m3u","path":…}` in `channels.json` (a relative `path` is in the tv folder); optional `number_start` (numbers unnumbered channels from it) and `groups` (keep only those `group-title`s). A bare `{"link": "….m3u"}` is a playlist too. |

`.m3u8` is NOT read from the folder and an untyped `.m3u8` link is not a playlist: that
extension is nearly always ONE HLS stream. Typed `"type":"m3u"` it is a playlist, and if it
turns out to be an HLS media playlist (`#EXT-X-TARGETDURATION` …) it is one channel, its own
address.

**`channels.json` holds no channels any more** (2026-11-08). It used to take one-channel
`"stream"` entries (`{"name", "link"}`, a typed URL each); a two-line `.m3u` does the same
and carries groups and headers too, so they were removed, along with the starter file's
placeholder `Channel 42` (an example.com URL: a dead stop on every fresh install's dial).
`TVChannels._ingest` now knows two kinds, `hdhomerun` and `m3u`; anything else — a typed
`stream`, a link that is not `.m3u`, no link — is IGNORED: counted in `ignored`, logged
(`[TVChannels] Ignoring N stream entries … put them in a .m3u playlist in <tv folder>`),
and kept in `sources` exactly as written (no `type` stamped on it), so a save from the
Antenna panel never deletes a line the player wrote. `hdhomerun_tests channels/` holds it.

**The code**: `M3uPlaylist` (`Scripts/Data/tv/m3u_playlist.gd`) is the pure parser;
`M3uFetcher` (`m3u_fetcher.gd`, a child of `TVLineup` beside `HDHomeRun`) reads every
`TVChannels.playlist_sources()` one after another (file, or HTTP: 15 s, 20 MB, 4
redirects) and reports per source. `TVLineup` shows the last good copy of each DOWNLOADED
list from `user://tv_m3u_cache.json` at once, then replaces that source's rows whole when it
answers (`source_key`), exactly as the tuner's rows are replaced; a list that fails keeps
its cached rows. The status line is `playlist_status_line()`; `fault_text()` says
PLAYLIST ERROR only while the list is otherwise empty.

The parser's traps: the title starts at the first comma OUTSIDE quotes
(`tvg-name="A, B"`), `#EXTGRP` and `#EXTVLCOPT` belong to the NEXT stream only, and the list
is cut at `MAX_CHANNELS` (5000: the dial is walked a channel at a time).

**`#EXTVLCOPT` is an allowlist** (`M3uPlaylist.ALLOWED_VLC_OPTIONS`, repeated as
`kAllowedMediaOptions` in `VlcPlayer.cpp`): `http-user-agent`, `http-referrer`/`referer`,
`network-caching`, `adaptive-logic`. A playlist comes from anywhere and libVLC's options
reach far past playback (`sout` writes files). They reach libVLC through
`VlcPlayer.set_media_options()`, consumed by the NEXT `open()` only, which `TVTuner` calls
before every tune (empty for an ordinary channel, so nothing carries over). It is a separate
method and not an `open()` argument ON PURPOSE: the tuner calls it behind `has_method`, so a
device left on an older vlc-godot build still plays the stream, without the options, and
logs that once.

Tests: `m3u_tests` (`parse/ options/ config/ build/ lineup/`; local files in the REAL tv
folder, prefixed `zz_m3u_tests_` and removed, `channels.json` restored byte for byte; the
lineup under test has no `HDHomeRun` child). Probes, windowed:
`tv_panel_probe -- --ui=antenna --offline --tab=1 [--scroll=600]` (the IPTV ribbon: the box and grouped rows) and
`tv_channel_probe -- --mode=playlist --pick=0|1` (a scratch `.m3u` in the tv folder: 0 a
local clip, 1 Mux's public HLS test stream behind a user-agent option and a refused `sout`).
**OWED:** a real provider's playlist, a remote `.m3u` URL fetched in the room, and the Quest.

### Who owns the glass, and who is heard

`RetroTV.showing_broadcast()` (`RF` selected and `rf_air_index >= 0`) is what everything
that used to ask "is the TV input selected" asks now.

- On a **broadcast stop** the tuner owns the glass; the socket's host is refused
  (`TvDisplay.can_paint`), is not the `selected_input()` (so the volume and power keys do
  not go to it), and is silent.
- On a **console stop** a host whose `get_rf_channel()` matches has the glass; otherwise
  snow. A host answering `-1` ("no switch") still matches everything — a deck through an RF
  switch — but **the Famicom no longer answers -1**: it answers 1 or 2.
- **Sound follows the dial** (`TvAudio.volume_for`): a console on a channel the set is not
  tuned to is silent, whether the set is on a broadcast stop or just the wrong console
  channel. It used to be snow you could hear the game through.

### The menu moved with the settings

The HDHomeRun box is what the aerial IS in this room, so "Find tuner automatically",
the address, Refresh, the status line and the channel list are on the **Antenna's** Tab
menu (`AntennaOptionsPanel` / `AntennaOptions2D`), created on demand like
`ObjectOptionsPanel`. `TVOptions2D` is Options | CRT and nothing else.

The Antenna menu has one ribbon per source: **HDHomeRun** (the tuner box and the rows
whose `source` is `hdhomerun`) and **IPTV (M3U)** (the playlist box and the `m3u` rows).
Each ribbon's list indexes into the one merged `TVLineup.channels`, so a click emits the
same index either way; the "Feeding …" line sits above both.

The options walk stops at the first pickable going UP from what the pointer hit, and on an
aerial that is the BASE (`AntennaBody`), not the `Antenna` root — so the base answers
`toggle_options_ui` and forwards it. Without that forward the aerial opens the generic
lock-only menu and the tuner settings cannot be reached at all. The panel's subject is the
base for the same reason: it is what moves, and what the lock row locks.

Clicking a channel calls `RetroTV.set_channel_index` on the set the lead reaches; with the
lead loose the list still shows (it is how you find out the aerial works) and the rows are
disabled under a line saying why.

### Testing it

- `av_tests` — `wiring/an aerial…`, `wiring/a Famicom's CH1/CH2 slide…`, `display/…dial…`,
  `display/a broadcast channel owns the glass…`, `display/pulling the aerial…`,
  `display/a save from before the aerial…`. Twelve mutations were run against them and all
  went red.
- **No network in a suite.** `StubLineup` overrides `_ready`, `is_loaded` and
  `reload_channels`. A RESTORED aerial builds its own lineup, so the round-trip case sets
  the `Antenna.lineup_override` seam — and must keep it set until the restore has SETTLED:
  pass 2 seats plugs deferred, the seat is what makes an aerial go looking, and lifting the
  seam one line after `instantiate_objects` read the player's real lineup cache and
  broadcast for a tuner from inside the suite.
- `StubTuner` overrides `_start_current`; the base reports "no libVLC" as a fault on the
  glass, which changes the OSD banner under test.
- Probes, windowed: `Tools/av/antenna_probe.tscn` (three photos, each beside a log line
  saying what the SET believes — a lead that looks seated is not proof),
  `Tools/av/tv_panel_probe.tscn -- --ui=antenna [--offline] [--loose] [--tab=0|1]`,
  `Tools/av/tv_channel_probe.tscn` (the only end-to-end check against a real HDHomeRun),
  `Tools/models/famicom_render_probe.tscn` (CH1 and CH2, both positions).
- **OWED:** nobody has watched a real broadcast through an Antenna yet.
  `tv_channel_probe -- --mode=live` with the HDHomeRun on the LAN is that check.

### Geometry

`Tools/gen/gen_antenna.gd` → `antenna_body.res`: 150 × 32 × 100 mm base, rods to 0.39 m
over the origin, 476 mm across. Origin at the centre of the BASE so it stands on a set. Two
surfaces (plastic, plated). Everything round is `_tube`, and its winding only holds while
`(u, dir, w)` is a RIGHT-HANDED frame — get it backwards and a 3 mm rod renders inside out,
which reads as the rod not being there. Only the base collides; the pointer box is taller
than the base but narrower than the ears' span, or it swallows clicks meant for the set.
