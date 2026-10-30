## RetroXRCrtShell — the RETRO XR CRT television (RetroXR-models generic/crt-tv), the set's stock cabinet.
##
## Geometry and markers only, as every RetroTVShell: the GLB's three levels come in through ApplianceModel and
## carry ScreenSeat / PortSeat / SpeakerOutSeat / VgaPortSeat / AmbilightSeat, so TvFit seats the set's own tube,
## sockets and ambilight on them. On top of that this shell:
##   - names RfPortSeat from the model's aerial socket (the stock pose would be inside this deeper body);
##   - hides the model's own Screen (the set's tube, with the CRT shader, draws the picture there);
##   - dresses the twelve bezel buttons with the model's keys (adopt_button, so a key presses with its button);
##   - lights the power lamp while the set is on;
##   - opens and closes the key door (DoorOpen / DoorClose) when it is pressed, and leaves the five keys behind it
##     dead while it is shut.
## The model prints its own legends round every socket, so the set prints none (print_legends = false).
class_name RetroXRCrtShell
extends RetroTVShell

const LEVELS := [
	"res://imported-assets/appliances/crt_tv/tv_mobile.glb",
	"res://imported-assets/appliances/crt_tv/tv_mobile_lod1.glb",
	"res://imported-assets/appliances/crt_tv/tv_mobile_lod2.glb",
]
const VR_BUTTON := preload("res://Scripts/Objects/widgets/vr_button.gd")

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

const LED_ON := Color8(60, 235, 110)
const LED_OFF := Color8(14, 44, 20)

var _model: ApplianceModel = null
var _door_button: VRButton = null
var _door_keys: Array[VRButton] = []
var _door_open := false
var _door_busy := false
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
	_build_door_button()
	_fit_collision()
	_set_door_keys(false)
	print("[TV] RETRO XR cabinet: %d of %d bezel keys on the model; the key door is shut" % [adopted, buttons.size()])


func _process(_delta: float) -> void:
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
## the door itself is its own box (_fit_door_button), so it is left out of the body's.
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


## The door is pressed on its face: a VRButton with no cap of its own, laid over the door wherever it stands.
func _build_door_button() -> void:
	if _model.part("KeyDoor") == null:
		push_warning("[TV] RETRO XR cabinet: the model has no KeyDoor")
		return
	var b := Area3D.new()
	b.set_script(VR_BUTTON)
	b.name = "KeyDoorButton"
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	b.add_child(shape)
	var cap := MeshInstance3D.new()
	cap.name = "ButtonMesh"
	b.add_child(cap)
	_door_button = b as VRButton
	_door_button.depress_depth = 0.0
	_door_button.depress_axis = Vector3(0, 0, -1)     # pressed on its face
	add_child(_door_button)
	_door_button.button_pressed.connect(_toggle_door)
	_fit_door_button()


## The door's press box is the door as it stands now, no margin.
func _fit_door_button() -> void:
	var door := _model.part("KeyDoor") as MeshInstance3D
	if door == null or _door_button == null:
		return
	_door_button.transform = Transform3D.IDENTITY
	ApplianceModel.fit_box(_door_button.get_node("CollisionShape3D") as CollisionShape3D,
		ApplianceModel.node_bounds(door, _door_button))


func _toggle_door() -> void:
	if _door_busy:
		return
	_door_busy = true
	_door_open = not _door_open
	var anim := "DoorOpen" if _door_open else "DoorClose"
	_model.play(anim)
	print("[TV] key door %s" % ("opening" if _door_open else "closing"))
	if not _door_open:
		_set_door_keys(false)
	await get_tree().create_timer(maxf(_model.animation_length(anim), 0.05)).timeout
	if not is_inside_tree():
		return
	if _door_open:
		_set_door_keys(true)
	_fit_door_button()
	_door_busy = false


func _set_door_keys(live: bool) -> void:
	for k in _door_keys:
		k.set_interactive(live)


## For tests and probes: open or shut the door at once.
func set_door_open(open: bool) -> void:
	if open == _door_open:
		return
	_door_open = open
	var anim := "DoorOpen" if open else "DoorClose"
	_model.seek(anim, _model.animation_length(anim))
	_set_door_keys(open)
	_fit_door_button()
	print("[TV] key door set %s" % ("open" if open else "shut"))


func is_door_open() -> bool:
	return _door_open


func model() -> ApplianceModel:
	return _model
