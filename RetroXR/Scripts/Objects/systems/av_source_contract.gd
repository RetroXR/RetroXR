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
## sinks' contract, in RetroSystem._apply_av_feed and on_rf_channel_changed.
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
