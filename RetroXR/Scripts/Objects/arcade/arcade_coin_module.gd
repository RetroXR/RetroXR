## ArcadeCoinModule — a coin door: the one way to put a credit in the cabinet.
##
## The slot (`CoinSlot`, an ArcadeCoinSlot) takes a token two ways. In a headset a free hand near it has a token pinched at
## its fingertip, and pushing it through the slot's mouth puts it in: the token slides on inside from where the hand had it.
## With a pointer (the desktop reticle, a laser) a click on the slot sends a token flying in from the lower corner of the view,
## turning edge-on to the slot as it comes, and sliding in. Either way you hear it scrape as it enters, and DROP_SECONDS later
## it lands in the cash box with a clunk, and AT THAT MOMENT the module says `coin_inserted(player)`: ArcadeInput turns that
## into the pulse the core reads as a coin. Tokens are infinite and uncounted; nothing is saved, and a token is a plain mesh,
## never a physics body or a `spawned` object. Animation and sound are local; only the pulse is input.
##
## The coin return (`CoinReturn`, a VRButton over the `ReturnButton` cap) does what one does on a
## real door: it gives back a coin the machine has NOT counted. Nothing a game has counted ever comes
## back (no core has a refund input: on real hardware the button is mechanical), so it returns the
## coins ArcadeInput is still holding for a game that is booting or only shown (`return_pressed`),
## and a coin put into a cabinet that cannot take one rolls straight out (`return_coin`). Either way
## the coin drops into `ReturnCup` with a rattle and lies there a moment. While coins are held the
## slot's lamp blinks (`set_held`): the coin is in, the game has not got it yet.
##
## The token is the RETRO XR arcade token (`TOKEN_PATH`, a built-in model); a plain brass disc stands in when it is missing.
## The sounds are synthesised for now (no recorded asset exists): a scrape at the slot, a clunk in the box, and a coin
## rattling down the chute into the cup. Real recordings replace them through the hardware-sfx workflow.
class_name ArcadeCoinModule
extends ArcadeModule

signal coin_inserted(player: int)
## The coin return was pressed on this door.
signal return_pressed(player: int)

## A token flying in from a click: how fast, and the shortest and longest it takes to reach the slot's mouth.
const FLY_SPEED := 1.4
const FLY_MIN := 0.12
const FLY_MAX := 0.35
## How high the flight rises above the straight line, in metres.
const TOSS_HEIGHT := 0.03
## The slide from the mouth into the slot, and the fall inside from there to the box.
const SLIDE_SECONDS := 0.08
const DROP_SECONDS := 0.25
## The longest from a press to the credit.
const CREDIT_SECONDS := FLY_MAX + SLIDE_SECONDS + DROP_SECONDS
## How far inside the slot the slide ends, out of sight.
const SLIDE_DEPTH := 0.03
## A click's token starts FROM_VIEW_SHARE of the way from the eye to the slot, moved this much right and down in the view.
const FROM_VIEW_SHARE := 0.35
const FROM_VIEW := Vector2(0.06, -0.06)
## Each play of a sound is pitched by up to this much either way.
const PITCH_SPREAD := 0.05
const TOKEN_PATH := "res://imported-assets/arcade/arcade_token.glb"
const COIN_RADIUS := 0.0125
const COIN_THICKNESS := 0.002
const SAMPLE_RATE := 22050
## A returned coin: how long it takes to fall into the cup, and how long it lies there before it goes.
const RETURN_FALL_SECONDS := 0.22
const RETURN_REST_SECONDS := 1.4
## How fast the slot's lamp blinks while coins are held, per second.
const HELD_BLINK_HZ := 2.5

static var _clink: AudioStreamWAV = null
static var _rattle: AudioStreamWAV = null
static var _scrape: AudioStreamWAV = null
static var _clunk: AudioStreamWAV = null
static var _token_mesh: Mesh = null

var _slot: ArcadeCoinSlot = null
var _return_button: VRButton = null
var _cup: Node3D = null
var _voice: AudioStreamPlayer3D = null
var _scrape_voice: AudioStreamPlayer3D = null
var _return_voice: AudioStreamPlayer3D = null
var _lamp: MeshInstance3D = null
var _lamp_material: StandardMaterial3D = null
var _lamp_energy := 0.0
var _held := 0
var _blink := 0.0
## Coins on their way in, until the credit: for the tests, a press with no tween leaves this at zero.
var in_flight: int = 0
## Coins rolled out into the cup and still lying there, for the tests.
var returned: int = 0


func _init() -> void:
	kind = ArcadeProfiles.KIND_COIN


func attach(p_cabinet: RetroSystemModel) -> void:
	super.attach(p_cabinet)
	_slot = find_child("CoinSlot", true, false) as ArcadeCoinSlot
	_return_button = find_child("CoinReturn", true, false) as VRButton
	_cup = find_child("ReturnCup", true, false) as Node3D
	_voice = _make_voice("CoinVoice", clunk(), -6.0)
	_scrape_voice = _make_voice("ScrapeVoice", scrape(), -10.0)
	_return_voice = _make_voice("ReturnVoice", rattle(), -4.0)
	if _cup != null:
		_return_voice.position = _cup.position
	if _slot != null:
		_scrape_voice.position = _slot.position
		_voice.position = _slot.position + _slot.insert_dir.normalized() * 0.08
		_slot.set_token(token_mesh(), null)
		_slot.clicked.connect(insert_coin)
		_slot.coin_entered.connect(func(from: Transform3D) -> void: insert_coin_from(from, true))
		_lamp = _slot.find_child("ButtonMesh", true, false) as MeshInstance3D
	if _lamp != null and _lamp.mesh != null and _lamp.mesh.surface_get_material(0) is StandardMaterial3D:
		# Its own copy: the blink is this door's, and the baked material is shared by every door.
		_lamp_material = (_lamp.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
		_lamp.material_override = _lamp_material
		_lamp_energy = _lamp_material.emission_energy_multiplier
	if _return_button != null:
		_return_button.button_pressed.connect(func() -> void: return_pressed.emit(player))


func _make_voice(voice_name: String, stream: AudioStream, db: float) -> AudioStreamPlayer3D:
	var v := AudioStreamPlayer3D.new()
	v.name = voice_name
	v.stream = stream
	v.unit_size = 0.6
	v.max_distance = 6.0
	v.volume_db = db
	add_child(v)
	return v


func _play(v: AudioStreamPlayer3D) -> void:
	if v != null and is_inside_tree():
		v.pitch_scale = randf_range(1.0 - PITCH_SPREAD, 1.0 + PITCH_SPREAD)
		v.play()


## The RETRO XR token's mesh (its materials in it), loaded once; a brass disc when the model is missing.
static func token_mesh() -> Mesh:
	if _token_mesh != null:
		return _token_mesh
	if ResourceLoader.exists(TOKEN_PATH):
		var scene := load(TOKEN_PATH) as PackedScene
		if scene != null:
			var root := scene.instantiate()
			for n in root.find_children("*", "MeshInstance3D", true, false):
				if (n as MeshInstance3D).mesh != null:
					_token_mesh = (n as MeshInstance3D).mesh
					break
			root.free()
	if _token_mesh == null:
		var disc := CylinderMesh.new()
		disc.top_radius = COIN_RADIUS
		disc.bottom_radius = COIN_RADIUS
		disc.height = COIN_THICKNESS
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color(0.80, 0.62, 0.30)
		brass.metallic = 0.9
		brass.roughness = 0.3
		disc.material = brass
		_token_mesh = disc
	return _token_mesh


## A game with one coin input has one coin door: the other is taken off the front and cannot be aimed at.
func set_door_enabled(on: bool) -> void:
	visible = on
	if _slot != null:
		_slot.set_interactive(on)
	if _return_button != null:
		_return_button.set_interactive(on)


func door_enabled() -> bool:
	return visible


## A token from a click (or anything else that inserts one): from the corner of the view when there is a camera, else from
## a little way out in front of the slot.
func insert_coin() -> void:
	if _slot == null or not is_inside_tree():
		_land()
		return
	var into := _slot.insert_dir_world()
	var start := Transform3D(_slot.slot_basis(), _slot.mouth() - into * 0.25 + Vector3.UP * 0.05)
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null and cam.is_inside_tree():
		# A third of the way from the eye to the slot, low and to the right: always between the two, however near the door
		# the player stands (a fixed distance ahead of the eye put it inside the door from close by).
		var cb := cam.global_basis.orthonormalized()
		var at := cam.global_position.lerp(_slot.mouth(), FROM_VIEW_SHARE) + cb.x * FROM_VIEW.x + cb.y * FROM_VIEW.y
		# Face to the camera at first, as if just let go.
		start = Transform3D(Basis(cam.global_basis.x, -cam.global_basis.z, cam.global_basis.y), at)
	insert_coin_from(start)


## A token from `from` (world): it flies to the slot's mouth turning edge-on (unless `slide_only`: a hand put it there), then
## slides in, and after the drop the credit is said.
func insert_coin_from(from: Transform3D, slide_only := false) -> void:
	if _slot == null or not is_inside_tree():
		_land()
		return
	var coin := MeshInstance3D.new()
	coin.name = "Coin"
	coin.mesh = token_mesh()
	coin.top_level = true
	coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(coin)
	coin.global_transform = from
	in_flight += 1
	var tween := create_tween()
	if not slide_only:
		var t := clampf(from.origin.distance_to(_slot.mouth()) / FLY_SPEED, FLY_MIN, FLY_MAX)
		tween.tween_method(_fly.bind(coin, from), 0.0, 1.0, t)
	var at_mouth := from if slide_only else Transform3D(_slot.slot_basis(), _slot.mouth())
	tween.tween_callback(_play.bind(_scrape_voice))
	tween.tween_method(_slide.bind(coin, at_mouth, slide_only), 0.0, 1.0, SLIDE_SECONDS)
	tween.tween_callback(func() -> void:
		if is_instance_valid(coin):
			coin.queue_free())
	tween.tween_interval(DROP_SECONDS)
	tween.tween_callback(_arrived)


## Start → the slot's mouth on a small arc, turning from how it started to edge-on in the slot's line. No spin.
func _fly(t: float, coin: MeshInstance3D, from: Transform3D) -> void:
	if not is_instance_valid(coin) or _slot == null:
		return
	var e := smoothstep(0.0, 1.0, t)
	var pos := from.origin.lerp(_slot.mouth(), e)
	pos += Vector3.UP * TOSS_HEIGHT * 4.0 * t * (1.0 - t)
	var q := Quaternion(from.basis.orthonormalized()).slerp(Quaternion(_slot.slot_basis()), minf(t * 1.4, 1.0))
	coin.global_transform = Transform3D(Basis(q), pos)


## The mouth → SLIDE_DEPTH inside, straight along the slot. A token from a hand turns the rest of the way to the slot's line
## as it goes in (the hand had it nearly there).
func _slide(t: float, coin: MeshInstance3D, at_mouth: Transform3D, from_hand: bool) -> void:
	if not is_instance_valid(coin) or _slot == null:
		return
	var into := _slot.insert_dir_world()
	var end := _slot.global_position + into * SLIDE_DEPTH
	var b := _slot.slot_basis()
	if from_hand:
		b = Basis(Quaternion(at_mouth.basis.orthonormalized()).slerp(Quaternion(b), minf(t * 2.0, 1.0)))
	coin.global_transform = Transform3D(b, at_mouth.origin.lerp(end, t))


func _arrived() -> void:
	in_flight = maxi(in_flight - 1, 0)
	_land()


## The coin is in the box: the clunk, then the credit.
func _land() -> void:
	_play(_voice)
	coin_inserted.emit(player)


## A coin comes back out: it drops from inside the door into the return cup, rattles, lies there a
## moment and is gone (coins are infinite: there is nothing to pick up). For a coin the escrow gives
## back, and for one the cabinet could not take.
func return_coin() -> void:
	returned += 1
	_play(_return_voice)
	if _cup == null or not is_inside_tree():
		returned = maxi(returned - 1, 0)
		return
	var coin := MeshInstance3D.new()
	coin.name = "ReturnedCoin"
	coin.mesh = token_mesh()
	add_child(coin)
	# From behind the plate above the cup, down into it, ending flat on the cup's floor face up.
	var rest := _cup.position + Vector3(0.0, -0.006, 0.004)
	var from := rest + Vector3(0.0, 0.05, -0.012)
	coin.position = from
	var tween := create_tween()
	tween.tween_method(_fall.bind(coin, from, rest), 0.0, 1.0, RETURN_FALL_SECONDS)
	tween.tween_interval(RETURN_REST_SECONDS)
	tween.tween_callback(func() -> void:
		returned = maxi(returned - 1, 0)
		if is_instance_valid(coin):
			coin.queue_free())


func _fall(t: float, coin: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	if not is_instance_valid(coin):
		return
	# Falls (t squared), with a small bounce at the bottom, and tips from on edge to leaning in the cup with
	# its face to the player (lying flat it showed only its rim from where a player stands).
	var fall := minf(t * t * 1.15, 1.0)
	var pos := from.lerp(to, fall)
	if t > 0.85:
		pos.y += 0.004 * sin((t - 0.85) / 0.15 * PI)
	coin.position = pos
	coin.basis = Basis(Vector3.RIGHT, lerpf(PI * 0.5, deg_to_rad(50.0), t))


## How many coins the cabinet holds for this door's player that the game has not had yet: the slot's
## lamp blinks while there are any.
func set_held(count: int) -> void:
	if count == _held:
		return
	_held = count
	if count == 0:
		_set_lamp(1.0)


func held() -> int:
	return _held


func tick(delta: float) -> void:
	if _held <= 0:
		return
	_blink = fmod(_blink + delta * HELD_BLINK_HZ, 1.0)
	_set_lamp(1.0 if _blink < 0.5 else 0.15)


func _set_lamp(level: float) -> void:
	if _lamp_material != null:
		_lamp_material.emission_energy_multiplier = _lamp_energy * level


## The lamp's emission now, as a share of its own, for the tests.
func lamp_level() -> float:
	if _lamp_material == null or _lamp_energy <= 0.0:
		return 1.0
	return _lamp_material.emission_energy_multiplier / _lamp_energy


## A metal coin dropped on a tray: a bright ring that decays, and a quieter, lower
## second bounce. Built once and shared by every coin door.
static func clink() -> AudioStreamWAV:
	if _clink != null:
		return _clink
	var seconds := 0.32
	var n := int(SAMPLE_RATE * seconds)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var partials := [[2640.0, 1.0, 24.0], [4180.0, 0.6, 30.0], [6350.0, 0.35, 42.0]]
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var v := 0.0
		for p: Array in partials:
			v += float(p[1]) * sin(TAU * float(p[0]) * t) * exp(-float(p[2]) * t)
		var t2 := t - 0.085
		if t2 > 0.0:
			for p: Array in partials:
				v += 0.4 * float(p[1]) * sin(TAU * float(p[0]) * 0.86 * t2) * exp(-float(p[2]) * 1.4 * t2)
		bytes.encode_s16(i * 2, int(clampf(v * 0.28, -1.0, 1.0) * 32767.0))
	_clink = _wav(bytes)
	return _clink


## A token going into the slot: a short metal scrape (noise, roughened, swelling and gone in about a tenth of a second) with a
## faint ring from the slot's edge. Built once and shared by every coin door.
static func scrape() -> AudioStreamWAV:
	if _scrape != null:
		return _scrape
	var seconds := 0.14
	var n := int(SAMPLE_RATE * seconds)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var state := 24680
	var prev := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		state = (state * 1103515245 + 12345) & 0x7fffffff
		var noise := float(state % 2001) / 1000.0 - 1.0
		# A difference of the noise takes the low end off: a scrape, not a hiss.
		var hp := noise - prev
		prev = noise
		var env := sin(PI * minf(t / 0.11, 1.0)) * (0.6 + 0.4 * sin(TAU * 90.0 * t))
		var ring := 0.25 * sin(TAU * 3300.0 * t) * exp(-30.0 * t)
		bytes.encode_s16(i * 2, int(clampf((hp * 0.35 * env + ring) * 0.6, -1.0, 1.0) * 32767.0))
	_scrape = _wav(bytes)
	return _scrape


## A token landing in the cash box: a dull low thud and the box's ring, then a smaller second bounce. Lower and duller than the
## clink of a coin on a tray. Built once and shared by every coin door.
static func clunk() -> AudioStreamWAV:
	if _clunk != null:
		return _clunk
	var seconds := 0.36
	var n := int(SAMPLE_RATE * seconds)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var partials := [[930.0, 1.0, 34.0], [1520.0, 0.6, 44.0], [2310.0, 0.35, 60.0]]
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var v := 0.9 * sin(TAU * 120.0 * t) * exp(-45.0 * t)
		for p: Array in partials:
			v += float(p[1]) * sin(TAU * float(p[0]) * t) * exp(-float(p[2]) * t)
		var t2 := t - 0.07
		if t2 > 0.0:
			for p: Array in partials:
				v += 0.3 * float(p[1]) * sin(TAU * float(p[0]) * 1.04 * t2) * exp(-float(p[2]) * 1.6 * t2)
		bytes.encode_s16(i * 2, int(clampf(v * 0.30, -1.0, 1.0) * 32767.0))
	_clunk = _wav(bytes)
	return _clunk


## A coin coming back: a short slide down the chute (a soft scrape), then four bounces in the steel cup,
## each quicker and quieter than the last, the cup lower and duller than the tray the clink is. Built once
## and shared by every coin door.
static func rattle() -> AudioStreamWAV:
	if _rattle != null:
		return _rattle
	var seconds := 0.55
	var n := int(SAMPLE_RATE * seconds)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var partials := [[1870.0, 1.0, 34.0], [3110.0, 0.55, 46.0], [4730.0, 0.3, 60.0]]
	var hits := [[0.12, 1.0], [0.21, 0.6], [0.27, 0.36], [0.31, 0.2]]
	var noise_state := 12345
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var v := 0.0
		# The slide: a little filtered noise, fading in and out over the first tenth of a second.
		if t < 0.11:
			noise_state = (noise_state * 1103515245 + 12345) & 0x7fffffff
			var noise := float(noise_state % 2001) / 1000.0 - 1.0
			v += 0.07 * noise * sin(PI * t / 0.11)
		for h: Array in hits:
			var th := t - float(h[0])
			if th < 0.0:
				continue
			for p: Array in partials:
				v += float(h[1]) * float(p[1]) * sin(TAU * float(p[0]) * th) * exp(-float(p[2]) * th)
		bytes.encode_s16(i * 2, int(clampf(v * 0.26, -1.0, 1.0) * 32767.0))
	_rattle = _wav(bytes)
	return _rattle


static func _wav(bytes: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav
