## TvFit — fitting a RetroTV's functional nodes onto a cabinet shell.
##
## A child of the RetroTV it serves, created unconditionally in _init, in the same
## shape as TvResize.
##
## Everything here runs once, from RetroTV._ready. The set is built and then this
## is done with it — the one exception is speaker_positions(), which reads back the
## markers seated here and is asked every time something places the set's sound.
##
## The shell itself stays on RetroTV as `_shell`: the back panel reads it for its
## input count and legend plate, and the display reads it for a screen shader.
class_name TvFit
extends Node

## The set this fits. Every node moved below is one of its children.
var _tv: RetroTV = null

## Cabinet ids that were renamed. Mapped before the lookup, so a saved room still
## finds its shell; "" is the stock body.
const _LEGACY_TV_MODELS := {
	"crt_90s": "",
	"crt_monitor": "crt_plain",
}

## Whether the shell named BOTH speaker seats. place_default_speakers() computes
## the pair when it did not.
var _speakers_seated: bool = false



## The shell body this set is wearing, or null for the stock cabinet.
##
## Owned here because this helper is the only thing that ever builds one — it
## used to be stored on RetroTV, which never read it, purely so the other
## helpers could see it. They ask the set, and the set asks here.
var _shell: RetroTVShell = null


func shell() -> RetroTVShell:
	return _shell

func setup(tv: RetroTV) -> void:
	_tv = tv


## Put a node on a marker's pose, if the shell named one. Static because the back
## panel seats its own sockets the same way.
static func seat(node: Node3D, at: Variant) -> void:
	if node != null and at is Transform3D:
		node.transform = at


## Wear a cabinet variant. A no-op but for the headphone jack when tv_model is
## empty — that is the acceptance test for this whole mechanism, since the arcade
## and den TVs must look and behave exactly as they did before. The jack is the one
## addition, on the stock body's front, clear of its keys (STOCK_PHONES_SEAT).
##
## Only nodes the shell actually names a seat for are moved; everything else keeps
## its tv.tscn pose, so a shell describes differences rather than the whole layout.
## The stock body's headphone jack: the lower right of its front face (z 0.15),
## right of the lower row of keys, which end at x 0.1625, 2 mm proud where a seated
## TRS plug stops.
const STOCK_PHONES_SEAT := Transform3D(Basis(), Vector3(0.2, -0.155, 0.152))


func load_shell() -> void:
	if _LEGACY_TV_MODELS.has(_tv.tv_model):
		_tv.tv_model = _LEGACY_TV_MODELS[_tv.tv_model]
	if _tv.tv_model.is_empty():
		_tv.panel().seat_phones(STOCK_PHONES_SEAT)
		return
	var path: String = RetroTV.shell_scene_path(_tv.tv_model)
	if path.is_empty():
		push_warning("[RetroTV] unknown tv_model '%s' — falling back to the stock body" % _tv.tv_model)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[RetroTV] failed to load shell scene: %s" % path)
		return
	_shell = packed.instantiate() as RetroTVShell
	if _shell == null:
		push_warning("[RetroTV] shell scene root is not a RetroTVShell: %s" % path)
		return
	_tv.add_child(_shell)
	_tv.get_node("TVBody").hide()

	var fitted: RetroTVShell = _shell
	seat(_tv.screen_mesh(), fitted.screen_seat())
	seat(_tv.tube_collar(), fitted.screen_seat())
	_tv.panel().seat_av_row(fitted.port_seat())
	_tv.panel().seat_vga_port(fitted.vga_port_seat())
	_tv.panel().seat_speaker_row(fitted.speaker_out_seat())
	_tv.panel().seat_phones(fitted.phones_seat())
	seat(_tv.ambilight(), fitted.ambilight_seat())

	# Both or neither: one seated speaker and one still on the stock tube's edge
	# would be a lopsided stereo image nobody authored. place_default_speakers
	# falls back to the computed pair when this stays false.
	var spk_l: Variant = fitted.speaker_l_seat()
	var spk_r: Variant = fitted.speaker_r_seat()
	_speakers_seated = spk_l is Transform3D and spk_r is Transform3D
	if _speakers_seated:
		seat(_tv.speaker_l_marker(), spk_l)
		seat(_tv.speaker_r_marker(), spk_r)

	# Bezel buttons march along the row marker's local +X from the first cap, and
	# wrap onto a second row below it. Same order the stock cabinet authors, so a
	# shelled set and the plain box read alike.
	var row: Variant = fitted.button_row_seat()
	var buttons: Array[Node3D] = _tv.bezel_buttons()
	if not fitted.show_button_row:
		for btn in buttons:
			(btn as VRButton).set_active(false)
	elif row is Transform3D:
		var base: Transform3D = row
		var per_row: int = maxi(1, fitted.buttons_per_row)
		for i in buttons.size():
			var b: Node3D = buttons[i]
			# Keep each cap's authored basis (they are rotated to face outward);
			# only the origin walks the row.
			@warning_ignore("integer_division")
			b.transform = Transform3D(b.transform.basis, base * Vector3(
				float(i % per_row) * fitted.button_pitch,
				float(i / per_row) * -fitted.button_row_drop,
				0.0))

	_resize_body_collision(fitted.body_size)


## Resize the pickup collider and the pointer box to the cabinet.
##
## BoxShape3D_body and BoxShape3D_pointer are plain sub_resources in tv.tscn, i.e.
## SHARED between every TV in the scene — writing a size straight onto them would
## resize the den's TV too. Duplicate first. (Same trap the resource_local_to_scene
## note on Mat_phosphor_a already documents for the phosphor materials.)
func _resize_body_collision(size: Vector3) -> void:
	var body_col := _tv.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_col and body_col.shape is BoxShape3D:
		var s := (body_col.shape as BoxShape3D).duplicate() as BoxShape3D
		s.size = size
		body_col.shape = s
	var ptr_col := _tv.get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D
	if ptr_col and ptr_col.shape is BoxShape3D:
		var p := (ptr_col.shape as BoxShape3D).duplicate() as BoxShape3D
		# The stock pointer box is 20 mm proud of the body on each axis.
		p.size = size + Vector3(0.02, 0.02, 0.02)
		ptr_col.shape = p


## World positions of the set's left and right speakers, in that order.
##
## Read straight off the SpeakerL / SpeakerR markers, so where a set radiates
## from is authored in the scene and can be dragged in the editor like any other
## node. Being children of the root they ride scale_factor and any parent's
## transform for free.
##
## Left and right are the LISTENER's. The set faces +Z (the screen sits proud of
## the front face, the composite port is on the back at -Z), so someone watching
## it has its +X on their right, and SpeakerR is the one at +X.
##
## Emitting from the cabinet centre instead makes the sound appear to come from
## inside the box -- inaudible with amplitude panning, obvious with HRTF.
func speaker_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	var spk_l := _tv.speaker_l_marker()
	var spk_r := _tv.speaker_r_marker()
	if spk_l != null and spk_r != null:
		out.push_back(spk_l.global_position)
		out.push_back(spk_r.global_position)
		return out
	# No markers (a scene predating them): the defaults, computed in place.
	var frame := _tv.global_transform.basis
	var face: Vector3 = _tv.screen_mesh().global_position + frame.z * 0.005
	var right: Vector3 = frame.x * (_tv.screen_size_m().x * 0.5 + 0.055)
	var down: Vector3 = -frame.y * (_tv.screen_size_m().y * 0.35)
	out.push_back(face - right + down)
	out.push_back(face + right + down)
	return out


## -3 dB, for a channel folded onto a speaker already playing its own. The rule and
## the fold chains now live in SpeakerRig, which the surround amplifier shares; the
## name stays here because SystemAudio's device matrix and the suites read it here.
const FOLD_GAIN := SpeakerRig.FOLD_GAIN


## World positions for the six decoded channels, in the decoder's order —
## FL, FR, C, LFE, SL, SR, which is RcaPort.SPEAKER_OUT_CHANNELS. A channel with a
## speaker plays from its cone; one without folds along SpeakerRig.FOLD_CHAINS.
## Folding is placing a voice where a speaker already is, so not a sample is touched.
func surround_positions() -> PackedVector3Array:
	return _route()[0]


## Per-channel gain to go with surround_positions(), same order: 1 for a channel on
## its own speaker or on a phantom midpoint, FOLD_GAIN on another speaker, 0 when
## nothing is plugged in at all.
func surround_gains() -> PackedFloat32Array:
	return _route()[1]


## Which speakers each channel landed on, same order: a PackedInt32Array of one
## speaker index, of the two whose midpoint it plays at, or empty with nothing
## plugged in.
func surround_targets() -> Array:
	return _route()[2]


## Whether any of the six outputs reaches a speaker. An amplifier with none of its
## own does not count (SpeakerRig.cabinet_of).
func has_cabled_speakers() -> bool:
	return SpeakerRig.has_cabled(_tv.panel().speaker_destinations())


## The front pair of _route, for a source that plays stereo through a set switched
## to external speakers: its left and right go where FL and FR go.
func external_pair() -> PackedVector3Array:
	var pos: PackedVector3Array = _route()[0]
	return PackedVector3Array([pos[0], pos[1]])


## The surround amplifier this set's FRONT pair is cabled into, or null — what a
## real set's line out is for. Found off FL first, then FR, so one cord of the pair
## is enough to name it; whether the amplifier has speakers of its own is its own
## business (has_cabled_speakers), and it is returned either way so the set can
## say which of the two is missing.
func decoder() -> Node3D:
	var dest := _tv.panel().speaker_destinations()
	for ch in [RcaPort.Channel.AUDIO_L, RcaPort.Channel.AUDIO_R]:
		var entry: Variant = dest.get(ch)
		if not entry is Dictionary:
			continue
		var sink := (entry as Dictionary).get("sink") as Node3D
		if is_instance_valid(sink) and sink.has_method("is_surround_decoder"):
			return sink
	return null


func _route() -> Array:
	# Where a silent voice waits: between the set's own pair. Its gain is 0, so this
	# is never heard; it only keeps the voice somewhere sane rather than at the origin.
	var pair := speaker_positions()
	return SpeakerRig.route(_tv.panel().speaker_destinations(), (pair[0] + pair[1]) * 0.5)


## Put the speaker markers where a set of this size wears them: flanking the tube
## 5.5 cm outboard of its edges, a little below its centre, and just proud of the
## glass -- which is where a CRT of this vintage puts them.
##
## Only for a shell that names no speaker seats. tv.tscn's own markers are already
## these numbers for the stock 0.35 x 0.25 tube, so this exists for a cabinet that
## moves and rescales the screen without saying where its speakers went; leaving
## the stock markers there would strand them on the old tube's edges.
##
## Local metres throughout, since the markers are children of the root: no basis
## juggling, and the scale that ScreenSeat gave the tube is already inside
## _screen_size_m.
func place_default_speakers() -> void:
	if _shell == null or _speakers_seated:
		return
	var spk_l := _tv.speaker_l_marker()
	var spk_r := _tv.speaker_r_marker()
	if spk_l == null or spk_r == null:
		return
	var half_w: float = _tv.screen_size_m().x * 0.5 + 0.055
	var drop_m: float = _tv.screen_size_m().y * 0.35
	var face: Vector3 = _tv.screen_mesh().position + Vector3(0.0, 0.0, 0.005)
	spk_l.position = face + Vector3(-half_w, -drop_m, 0.0)
	spk_r.position = face + Vector3(half_w, -drop_m, 0.0)
