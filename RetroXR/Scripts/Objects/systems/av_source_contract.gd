## AvSourceContract — what a television, a speaker pair or an amplifier calls on
## whatever is plugged into it, written down in one place.
##
## The sources a set can carry share no base class: a console (RetroSystem) is a
## pickable rigid body with a core, a VCR or a DVD player (VCRPlayer, DVDPlayer,
## both MediaTransport) is a deck with a stream. So the contract is by NAME, and
## this is the list. system_tests checks REQUIRED against all three scripts, so a
## source that drops or renames one goes red there rather than as a set that
## quietly never changes its level.
##
##   set_audio_volume(volume: float)              the set's level, 0..1
##   set_audio_channel_mode(mode: SpatialAudioEmitter.ChannelMode)
##                                                the set's mono switch
## OPTIONAL, asked with has_method by the sink that needs it:
##   set_audio_out_mode(mode) -> bool             where the set sends sound (a
##                                                machine that decodes surround)
##   set_surround_mode(mode)                      SurroundAmp.DecodeMode
##   set_audio_head_lock(l, r) / clear_audio_head_lock()   desktop fullscreen
##
## The other direction -- what a source tells its sinks (on_av_source_found /
## on_av_source_lost / on_audio_source_routed / on_rf_channel_changed) -- is the
## sinks' contract, in SystemAvPorts.apply_feed and on_rf_channel_changed.
class_name AvSourceContract
extends RefCounted

const REQUIRED: PackedStringArray = ["set_audio_volume", "set_audio_channel_mode"]

const OPTIONAL: PackedStringArray = [
	"set_audio_out_mode", "set_surround_mode", "set_audio_head_lock", "clear_audio_head_lock",
]


## The REQUIRED methods `script` (or a script it extends) does not define.
static func missing_in_script(script: Script) -> PackedStringArray:
	var out := PackedStringArray()
	if script == null:
		out.append("<null script>")
		return out
	var methods := {}
	var walk: Script = script
	while walk != null:
		for m: Dictionary in walk.get_script_method_list():
			methods[str(m.get("name", ""))] = true
		walk = walk.get_base_script()
	for method in REQUIRED:
		if not methods.has(method):
			out.append(method + "()")
	return out


## Scripts already reported as missing a REQUIRED method, so a set asking on every
## plug move logs it once.
static var _reported: Dictionary = {}


## Whether `source` answers `method`, for a sink about to call it. A REQUIRED one
## that is missing is logged (once per script) as the contract breach it is,
## rather than the set silently never changing that source's level.
static func has(source: Object, method: String) -> bool:
	if not is_instance_valid(source):
		return false
	if source.has_method(method):
		return true
	if REQUIRED.has(method):
		var script: Script = source.get_script() as Script
		var who: String = script.resource_path if script != null else source.get_class()
		var key := "%s#%s" % [who, method]
		if not _reported.has(key):
			_reported[key] = true
			push_warning("[TV] A/V source %s lacks REQUIRED AvSourceContract.%s()" % [who, method])
	return false


## The set's level, 0..1.
static func push_volume(source: Object, volume: float) -> void:
	if has(source, "set_audio_volume"):
		source.call("set_audio_volume", volume)


## The set's speaker (mono) switch.
static func push_channel_mode(source: Object, mode: int) -> void:
	if has(source, "set_audio_channel_mode"):
		source.call("set_audio_channel_mode", mode)


## Where the set sends sound. True when the source is really decoding surround;
## false for a source that cannot (a deck) as well as one that declined.
static func push_out_mode(source: Object, mode: int) -> bool:
	if has(source, "set_audio_out_mode"):
		return bool(source.call("set_audio_out_mode", mode))
	return false


## Which surround decoder to run (SurroundAmp.DecodeMode). OPTIONAL.
static func push_surround_mode(source: Object, mode: int) -> void:
	if has(source, "set_surround_mode"):
		source.call("set_surround_mode", mode)
