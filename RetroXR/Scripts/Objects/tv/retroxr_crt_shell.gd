## RetroXRCrtShell — the RETRO XR CRT television (RetroXR-models generic/crt-tv), the set's stock cabinet.
##
## Geometry and markers only, as every RetroTVShell: the GLB's three levels come in through ApplianceModel and
## carry ScreenSeat / PortSeat / SpeakerOutSeat / VgaPortSeat / AmbilightSeat, so TvFit seats the set's own tube,
## sockets and ambilight on them. On top of that this shell:
##   - names RfPortSeat from the model's aerial socket (the stock pose would be inside this deeper body);
##   - hides the model's own Screen (the set's tube, with the CRT shader, draws the picture there);
##   - dresses the twelve bezel buttons with the model's keys (adopt_button, so a key presses with its button);
##   - lights the power lamp while the set is on;
##   - hangs the key door on a hinge of its own (TvKeyDoor: a push-push catch, poked or pressed to fall open, pushed
##     back up to latch), and leaves the five keys behind it dead until it stands open (KEYS_LIVE_DEG).
## The model prints its own legends round every socket, so the set prints none (print_legends = false).
class_name RetroXRCrtShell
extends RetroTVShell

const LEVELS := [
	"res://imported-assets/appliances/crt_tv/tv_mobile.glb",
	"res://imported-assets/appliances/crt_tv/tv_mobile_lod1.glb",
	"res://imported-assets/appliances/crt_tv/tv_mobile_lod2.glb",
]

## RetroTV's bezel button -> the model's key.
const KEYS := {
	"TVToggleButton": "ButtonTVToggle", "SourceButton": "ButtonSource",
	"ChannelDownButton": "ButtonChannelDown", "ChannelUpButton": "ButtonChannelUp",
	"VolumeDownButton": "ButtonVolumeDown", "VolumeUpButton": "ButtonVolumeUp", "MuteButton": "ButtonMute",
	"AudioModeButton": "ButtonAudioMode", "AudioOutButton": "ButtonAudioOut", "CRTButton": "ButtonCRT",
	"AspectButton": "ButtonAspect", "StereoButton": "ButtonStereo",
}
## The five behind the door.
const DOOR_KEYS := ["AudioModeButton", "AudioOutButton", "CRTButton", "AspectButton", "StereoButton"]

## The model marks every socket's mouth with an empty of the socket's own name. Renamed `<name>Mouth` so a
## recursive find on the set never meets one before the real socket.
const MOUTHS := [
	"CompositePort", "AudioLIn", "AudioRIn", "CompositePort2", "AudioLIn2", "AudioRIn2",
	"CompositePort3", "AudioLIn3", "AudioRIn3", "CompositePort4", "AudioLIn4", "AudioRIn4",
	"RfPort", "VgaPort", "SpeakerOutL", "SpeakerOutR", "SpeakerOutC", "SpeakerOutLfe", "SpeakerOutSl",
	"SpeakerOutSr",
]

## The five keys behind the door come alive once it has swung this far open (a fingertip fits behind it), and go
## dead again below it.
const KEYS_LIVE_DEG := 60.0

const LED_ON := Color8(60, 235, 110)
const LED_OFF := Color8(14, 44, 20)

var _model: ApplianceModel = null
var _door: TvKeyDoor = null
var _door_keys: Array[VRButton] = []
var _keys_live: Variant = null
var _led_on: Variant = null
var _led_mat: StandardMaterial3D = null


func _ready() -> void:
	_model = ApplianceModel.new()
	_model.name = "Model"
	for path in LEVELS:
		_model.level_scenes.append(load(path) as PackedScene)
	add_child(_model)
	for mouth in MOUTHS:
		for p in _model.parts(mouth):
			p.name = mouth + "Mouth"
	var rf := _model.part("RfPortMouth")
	if rf:
		var seat := Marker3D.new()
		seat.name = "RfPortSeat"
		add_child(seat)
		seat.global_transform = rf.global_transform
	else:
		push_warning("[TV] RETRO XR cabinet: the model has no aerial socket mouth")
	_led_mat = StandardMaterial3D.new()
	for led in _model.parts("PowerLed"):
		(led as MeshInstance3D).material_override = _led_mat
	super._ready()          # hide_meshes: the model's Screen
	print("[TV] RETRO XR cabinet: %d levels, body %s" % [_model.levels.size(), body_size])


func on_buttons_built(buttons: Array) -> void:
	var adopted := 0
	for b in buttons:
		var btn := b as VRButton
		if btn == null or not KEYS.has(String(btn.name)):
			continue
		_model.adopt_button(btn, KEYS[String(btn.name)])
		adopted += 1
		if DOOR_KEYS.has(String(btn.name)):
			_door_keys.append(btn)
	_build_door()
	_fit_collision()
	_update_door_keys()
	print("[TV] RETRO XR cabinet: %d of %d bezel keys on the model; the key door is shut" % [adopted, buttons.size()])


func _process(_delta: float) -> void:
	_update_door_keys()
	var tv := get_parent() as RetroTV
	if tv == null:
		return
	var on := tv.is_on()
	if on == _led_on:
		return
	_led_on = on
	_led_mat.albedo_color = LED_ON if on else LED_OFF
	_led_mat.emission_enabled = on
	_led_mat.emission = LED_ON
	_led_mat.emission_energy_multiplier = 2.0


## The set's body and the laser's box are what the cabinet draws (TvFit sized them from body_size and padded the
## pointer's by 20 mm, which stood in front of every bezel key). The keys behind the door sit 7.6 mm into the bezel,
## deeper than the pointer lets a control win from inside a shell, so a pocket over them is carved out of both;
## the door is its own hinge's box (_build_door) and no longer under the model, so the body's leaves it out.
func _fit_collision() -> void:
	var tv := get_parent() as Node3D
	if tv == null:
		return
	var keys: Array[Node] = []
	for k in _door_keys:
		var cap := k.get_node_or_null("ButtonMesh")
		if cap:
			keys.append(cap)
	for path in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
		var shape := tv.get_node_or_null(path) as CollisionShape3D
		if shape == null:
			push_warning("[TV] RETRO XR cabinet: the set has no %s to fit" % path)
			continue
		var space := shape.get_parent() as Node3D
		var body := _model.bounds(space, ["KeyDoor"])
		var boxes: Array[AABB] = [body]
		if not keys.is_empty():
			var pocket := AABB()
			for i in keys.size():
				var b := ApplianceModel.node_bounds(keys[i], space)
				pocket = b if i == 0 else pocket.merge(b)
			# From the keys' backs out through the front of the cabinet: a pocket floor level with the faces ties
			# with the key for the ray, and the shell won the tie.
			pocket.size.z = body.end.z - pocket.position.z + 0.01
			boxes = ApplianceModel.carve(body, pocket)
		ApplianceModel.fit_collision(shape, boxes)
		print("[TV] RETRO XR cabinet: %s is the cabinet, %s mm, in %d boxes" % [path, (body.size * 1000.0).snapped(Vector3.ONE * 0.1), boxes.size()])


## The key door on a hinge of its own: a pivot on the door's bottom edge (the KeyDoor's own origin, about whose X
## the model's DoorOpen turns it), every level's door hung under it, and a TvKeyDoor whose box is the door as drawn,
## no margin, in the pivot's frame, so it turns with the door.
func _build_door() -> void:
	var door := _model.part("KeyDoor") as MeshInstance3D
	if door == null:
		push_warning("[TV] RETRO XR cabinet: the model has no KeyDoor")
		return
	var pivot := Node3D.new()
	pivot.name = "KeyDoorPivot"
	add_child(pivot)
	# The door's own place and turn in the cabinet, scale left to the cabinet: rotation.x is then the door's swing.
	var local := global_transform.affine_inverse() * door.global_transform
	pivot.transform = Transform3D(local.basis.orthonormalized(), local.origin)
	_model.attach_part("KeyDoor", pivot)
	var drawn := ApplianceModel.node_bounds(door, pivot)
	var hinge := TvKeyDoor.new()
	hinge.name = "KeyDoorHinge"
	hinge.target = pivot
	hinge.min_deg = 0.0
	hinge.max_deg = TvKeyDoor.OPEN_DEG
	hinge.start_closed = true
	hinge.push_push = true
	hinge.box_engages = true
	hinge.poke_close_faces = VRHinge.FACE_Z_POS      # its outer face: pushed in shut, pushed up open
	hinge.close_latch_deg = 2.0
	# A couple of millimetres in at the door's top edge before the catch lets go.
	hinge.push_push_unlatch_depth = 0.002
	hinge.push_push_overtravel_deg = rad_to_deg(atan2(0.002, maxf(drawn.end.y, 0.01)))
	hinge.position = drawn.get_center()
	hinge.edge_local = Vector3(drawn.get_center().x, drawn.end.y, drawn.get_center().z)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = drawn.size
	shape.shape = box
	hinge.add_child(shape)
	pivot.add_child(hinge)
	hinge.place_hint(Vector3(0, 0, drawn.size.z * 0.5 + 0.014))
	_door = hinge
	print("[TV] RETRO XR cabinet: key door on its hinge, %s mm, pivot basis x %s, latched shut" % [
		(drawn.size * 1000.0).snapped(Vector3.ONE * 0.1), pivot.transform.basis.x.snapped(Vector3.ONE * 0.001)])


## The five keys behind the door are live only while it stands open past KEYS_LIVE_DEG.
func _update_door_keys() -> void:
	var live := _door != null and not _door.is_latched_closed() and _door.get_rotation_deg() >= KEYS_LIVE_DEG
	if live == _keys_live:
		return
	_keys_live = live
	for k in _door_keys:
		k.set_interactive(live)
	print("[TV] key door: the five keys behind it are %s (door at %.1f deg)" % ["live" if live else "dead",
		_door.get_rotation_deg() if _door else 0.0])


## The door's hinge (saved and synced as every spring-latched hinge is).
func key_door() -> TvKeyDoor:
	return _door


## For tests and probes: the door open (unlatched, all the way) or latched shut, at once.
func set_door_open(open: bool) -> void:
	if _door == null:
		return
	_door.set_state_remote(TvKeyDoor.OPEN_DEG if open else 0.0, not open)
	_update_door_keys()


func is_door_open() -> bool:
	return _door != null and not _door.is_latched_closed()


func model() -> ApplianceModel:
	return _model
