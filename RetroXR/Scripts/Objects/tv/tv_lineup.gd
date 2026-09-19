## TVLineup — what an aerial RECEIVES: the channel list, and the HDHomeRun behind it.
##
## Owned by an Antenna, not by a television. It used to be the top half of TVTuner,
## which meant every set in the room had channels with nothing plugged into it; now
## the list arrives down a coax lead, and a set with an empty aerial socket has none.
## The tuner that PLAYS a channel is still the set's own (see tv_tuner.gd) — this node
## never opens a stream, so an antenna standing on a shelf costs one discovery look
## and no VlcPlayer.
##
## Where the list comes from is unchanged: channels.json (TVChannels) for the tuner's
## address and any hand-written streams, user://tv_lineup_cache.json for the last
## lineup the box reported, and a fresh lookup over the top of both. All of that is
## global, so every antenna in the room reads and edits the same configuration —
## exactly as every television did before.
class_name TVLineup
extends Node

## Emitted when the channel list changes (discovery finished, refresh, load).
signal channels_changed

var channels: Array[Dictionary] = []

var _hdhr: HDHomeRun = null
var _cfg: TVChannels = null
# What discovery reported, for the options panel's status line.
var _tuner_info: Dictionary = {}
var _tuner_error := ""
# Whether a look is actually in flight. Without it the status line cannot tell
# "searching" from "never started", and reports the former for both.
var _searching := false
# A broken channels.json, already worded for the glass. Empty when the file is fine
# or simply absent.
var _config_error := ""


func _ready() -> void:
	_hdhr = HDHomeRun.new()
	_hdhr.name = "HDHomeRun"
	_hdhr.lineup_ready.connect(_on_lineup_ready)
	_hdhr.discovery_failed.connect(_on_discovery_failed)
	add_child(_hdhr)


## Whether reload_channels has ever run. The antenna uses it to look once, the first
## time something actually wants the list, rather than the moment it is spawned.
func is_loaded() -> bool:
	return _cfg != null


# ── channel list ──────────────────────────────────────────────────────────────

## Read channels.json and, if it names a tuner, go and find it. Safe to call
## repeatedly; the panel's Refresh button does exactly this.
func reload_channels() -> void:
	_cfg = TVChannels.load_config()
	channels.clear()

	# Show the cached lineup immediately so a list exists before the network
	# answers -- and so a cold start with the tuner asleep still has channels.
	var cache := HDHomeRun.load_cache()
	if cache.has("channels"):
		for c: Variant in cache["channels"]:
			if c is Dictionary:
				channels.append(c as Dictionary)

	for c in _cfg.stream_channels:
		channels.append(c)
	_sort_channels()

	# A broken file is worth saying out loud. A MISSING one is not: discovery
	# needs no configuration at all, so the normal case for a fresh install is
	# no file and a tuner found anyway.
	_config_error = ""
	if _cfg.status == TVChannels.Status.PARSE_ERROR:
		_config_error = "CHANNEL LIST ERROR\n%s" % _cfg.error_message
	channels_changed.emit()

	# Always go looking. This used to be gated on the file naming a tuner, which
	# dated from before broadcast discovery worked -- and meant a machine with no
	# channels.json (every fresh install, and every headset) never even started
	# looking, then sat on "Looking for a tuner..." forever because nothing ever
	# reported success or failure.
	_searching = true
	_hdhr.find_lineup(_cfg.tuner_host(), _cfg.tuner_auto())


## What a set with nothing to tune should say on the glass, or "" when there is no
## fault worth a banner. A missing tuner only counts while there is nothing else to
## watch -- a hand-written stream list is a perfectly good aerial without one.
func fault_text() -> String:
	if not _config_error.is_empty():
		return _config_error
	if channels.is_empty() and not _tuner_error.is_empty():
		return "TUNER NOT FOUND\n%s" % _tuner_error.to_upper()
	return ""


# ── tuner configuration (the antenna panel's Tuner box) ───────────────────────

func tuner_auto() -> bool:
	return _cfg.tuner_auto() if _cfg else true


func tuner_host() -> String:
	return _cfg.tuner_host() if _cfg else ""


## The address discovery actually reached, so the panel can show it even when the
## user never typed one.
func discovered_host() -> String:
	return str(_tuner_info.get("host", ""))


## One already-worded line for the panel's status label.
func tuner_status_line() -> String:
	if not _tuner_error.is_empty():
		return _tuner_error
	if _tuner_info.is_empty():
		return "Looking for a tuner…" if _searching else "No tuner searched for yet"
	return "%s — %s — %d tuner(s) — %d channels" % [
		_tuner_info.get("name", "HDHomeRun"),
		_tuner_info.get("host", "?"),
		int(_tuner_info.get("tuners", 0)),
		_hdhr_channel_count(),
	]


func _hdhr_channel_count() -> int:
	var n := 0
	for c in channels:
		if str(c.get("source", "")) == "hdhomerun":
			n += 1
	return n


## Persist auto/address to channels.json and go looking again.
func set_tuner_config(auto: bool, host: String) -> void:
	if _cfg == null:
		_cfg = TVChannels.load_config()
	if _cfg.tuner_auto() == auto and _cfg.tuner_host() == host.strip_edges():
		return
	_cfg.set_tuner(auto, host)
	_tuner_info = {}
	_tuner_error = ""
	_searching = true
	_hdhr.find_lineup(_cfg.tuner_host(), _cfg.tuner_auto())
	channels_changed.emit()


func _on_lineup_ready(found: Array, info: Dictionary) -> void:
	_searching = false
	_tuner_info = info
	_tuner_error = ""
	# Replace the tuner's channels wholesale; hand-written streams are untouched.
	var kept: Array[Dictionary] = []
	for c in channels:
		if str(c.get("source", "")) != "hdhomerun":
			kept.append(c)
	channels = kept
	for c: Variant in found:
		if c is Dictionary:
			channels.append(c as Dictionary)
	_sort_channels()
	channels_changed.emit()


func _on_discovery_failed(message: String) -> void:
	_searching = false
	_tuner_error = message
	_tuner_info = {}
	channels_changed.emit()


## Broadcast numbering is "4.1", "10.2" — sort on the pair, not the string, or
## channel 10 lands between 1 and 2.
func _sort_channels() -> void:
	channels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := number_key(str(a.get("number", "")))
		var pb := number_key(str(b.get("number", "")))
		if pa != pb:
			return pa < pb
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)


## Static and public because the set merges this list with its two RF-switch
## channels into one dial (RetroTV.rf_dial) and has to order them by the same rule.
static func number_key(number: String) -> float:
	if number.is_empty():
		return 1e9          # unnumbered entries sort last, not first
	var parts := number.split(".")
	var major := float(parts[0]) if parts[0].is_valid_float() else 1e8
	var minor := 0.0
	if parts.size() > 1 and parts[1].is_valid_float():
		minor = float(parts[1])
	return major * 1000.0 + minor
