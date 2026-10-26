## SpeakerRig — where six decoded channels play, given which cabinet is cabled to
## each of a device's six speaker outputs.
##
## Lifted out of TvFit, which was its only user until the surround amplifier: a set's
## SPEAKERS row and an amplifier's are the same six sockets with the same fold rules,
## and two copies of those rules would drift the way the three source resolvers did
## before AvSource. Static throughout — the routing is a function of the cabling, and
## the cabling is the caller's (`AvSource.resolve(device, true).audio_dest`).
##
## Channels are in the decoder's order, FL, FR, C, LFE, SL, SR = 0..5, which is
## RcaPort.SPEAKER_OUT_CHANNELS.
class_name SpeakerRig
extends RefCounted


## -3 dB, for a channel folded onto a speaker that is already playing its own. Two
## channels arriving at one point is twice the power, so each comes in at half of it.
## A channel folded onto the MIDPOINT of a pair is not attenuated: nothing else is
## playing there, and two speakers carrying it is what puts it there.
const FOLD_GAIN := 0.7071068

## Where each channel goes when its own speaker is missing. The first CABLED target
## wins; an int is one speaker, a pair is the phantom point between two. The device's
## own speakers are on no chain: a set switched to external speakers is silent, as a
## real one is, and an amplifier has none — so a channel folds onto the speakers that
## ARE plugged in, and nothing plugged in means nothing heard.
##
## Own side first, so a rig of rear speakers alone still images left-right. Every
## chain names all six, so one cabled speaker gives every channel somewhere to go.
const FOLD_CHAINS := [
	[0, 4, 2, 1, 5, 3],
	[1, 5, 2, 0, 4, 3],
	[2, [0, 1], 0, 1, [4, 5], 4, 5, 3],
	[3, [0, 1], 0, 1, 2, [4, 5], 4, 5],
	[4, 0, 2, 5, 1, 3],
	[5, 1, 2, 4, 0, 3],
]


## Route the six. `dest` is keyed by RcaPort.Channel, each entry
## `{"sink": Node3D, "speaker": int}`; `rest` is where a channel with nowhere to go
## waits, silent — its gain is 0, so the point only keeps the voice somewhere sane.
##
## Returns [positions, gains, targets], each in decoder order: the world point a
## channel plays from; 1 on its own speaker or a phantom midpoint, FOLD_GAIN on
## another speaker, 0 with nothing plugged in; and the speakers it landed on, a
## PackedInt32Array of one index, of the two whose midpoint it plays at, or empty.
static func route(dest: Dictionary, rest: Vector3) -> Array:
	var cones: Array = []
	for ch in RcaPort.SPEAKER_OUT_CHANNELS:
		cones.append(cabinet_cone(dest.get(ch)))
	var positions := PackedVector3Array()
	var gains := PackedFloat32Array()
	var targets: Array = []
	for i in FOLD_CHAINS.size():
		var placed := false
		for target: Variant in FOLD_CHAINS[i]:
			if target is Array:
				var a: Variant = cones[target[0]]
				var b: Variant = cones[target[1]]
				if a != null and b != null:
					positions.push_back(((a as Vector3) + (b as Vector3)) * 0.5)
					gains.push_back(1.0)
					targets.append(PackedInt32Array([target[0], target[1]]))
					placed = true
					break
			elif cones[target] != null:
				positions.push_back(cones[target] as Vector3)
				gains.push_back(1.0 if target == i else FOLD_GAIN)
				targets.append(PackedInt32Array([target]))
				placed = true
				break
		if not placed:
			positions.push_back(rest)
			gains.push_back(0.0)
			targets.append(PackedInt32Array())
	return [positions, gains, targets]


## Whether any of the six reaches something that makes a sound.
static func has_cabled(dest: Dictionary) -> bool:
	for ch in RcaPort.SPEAKER_OUT_CHANNELS:
		if cabinet_of(dest.get(ch)) != null:
			return true
	return false


## The device an entry names, or null for a channel with none — and for one whose
## device has since been freed, which a room where anything can be picked up and put
## in a box has to expect.
##
## Also null for an amplifier with no speakers of its own. A set's front pair cabled
## into one is how the set reaches a decoder, and an amplifier with nothing plugged
## into it is silent — it must not count as a cabinet and play from its own box.
## Asked by a method only an amplifier has, so a second television on the far end of
## a lead keeps answering for its own speakers as it always did.
static func cabinet_of(entry: Variant) -> Node3D:
	if not entry is Dictionary:
		return null
	var sink := (entry as Dictionary).get("sink") as Node3D
	if not is_instance_valid(sink):
		return null
	if sink.has_method("is_surround_decoder") and not sink.has_cabled_speakers():
		return null
	return sink


## The cone an entry reaches, or null.
static func cabinet_cone(entry: Variant) -> Variant:
	var sink := cabinet_of(entry)
	if sink == null:
		return null
	var cones: PackedVector3Array = sink.get_speaker_positions()
	var idx: int = int((entry as Dictionary).get("speaker", 0))
	if idx >= 0 and idx < cones.size():
		return cones[idx]
	return null
