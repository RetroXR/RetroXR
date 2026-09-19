# §2t — the aerial, and the one RF dial

Written 2026-09-18, with the change that made it true.

### 2t. One coax socket, one dial

A television has ONE aerial socket and ONE tuner, and everything that arrives down the coax
is found by changing channel:

| what | where it comes from | dial stops |
|---|---|---|
| a Famicom | its RF OUT, through the RXR-003 switch | **1, 2** — the CH1/CH2 slide on its back |
| an NES | its RF OUT, through the RXR-003 switch | **3, 4** — the CH3/CH4 slide on its back |
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
  `Tools/av/tv_panel_probe.tscn -- --ui=antenna [--offline] [--loose]`,
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
