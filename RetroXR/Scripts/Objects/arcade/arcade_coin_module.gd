## ArcadeCoinModule — a coin door: the one way to put a credit in the cabinet.
##
## Poke the coin slot (`CoinSlot`, a VRButton) and a coin is tossed from `CoinSpawn`
## to `CoinDrop` along an arc, spinning. You hear it drop into the box, and AT THAT
## MOMENT the module says `coin_inserted(player)`: ArcadeInput turns that into the
## pulse the core reads as a coin. Coins are infinite and uncounted; nothing is
## saved, and the coin in flight is a plain mesh, never a physics body or a
## `spawned` object. Animation and sound are local; only the pulse is input.
##
## The coin return (`CoinReturn`, a VRButton over the `ReturnButton` cap) does what one does on a
## real door: it gives back a coin the machine has NOT counted. Nothing a game has counted ever comes
## back (no core has a refund input: on real hardware the button is mechanical), so it returns the
## coins ArcadeInput is still holding for a game that is booting or only shown (`return_pressed`),
## and a coin put into a cabinet that cannot take one rolls straight out (`return_coin`). Either way
## the coin drops into `ReturnCup` with a rattle and lies there a moment. While coins are held the
## slot's lamp blinks (`set_held`): the coin is in, the game has not got it yet.
##
## The sounds are synthesised for now (no recorded asset exists): a metal coin on a metal tray, two
## bounces, and a coin rattling down the chute into the cup. Real recordings replace them through the
## hardware-sfx workflow.
class_name ArcadeCoinModule
extends ArcadeModule

signal coin_inserted(player: int)
## The coin return was pressed on this door.
signal return_pressed(player: int)

## Seconds a coin is in the air.
const FLIGHT_SECONDS := 0.28
## How high the toss rises above the straight line, in metres.
const TOSS_HEIGHT := 0.05
const COIN_RADIUS := 0.0115
const COIN_THICKNESS := 0.0018
const SAMPLE_RATE := 22050
## A returned coin: how long it takes to fall into the cup, and how long it lies there before it goes.
const RETURN_FALL_SECONDS := 0.22
const RETURN_REST_SECONDS := 1.4
## How fast the slot's lamp blinks while coins are held, per second.
const HELD_BLINK_HZ := 2.5

static var _clink: AudioStreamWAV = null
static var _rattle: AudioStreamWAV = null

var _slot_button: VRButton = null
var _return_button: VRButton = null
var _spawn: Node3D = null
var _drop: Node3D = null
var _cup: Node3D = null
var _voice: AudioStreamPlayer3D = null
var _return_voice: AudioStreamPlayer3D = null
var _coin_mesh: CylinderMesh = null
var _coin_material: StandardMaterial3D = null
var _lamp: MeshInstance3D = null
var _lamp_material: StandardMaterial3D = null
var _lamp_energy := 0.0
var _held := 0
var _blink := 0.0
## Coins in the air, for the tests: a press with no tween leaves this at zero.
var in_flight: int = 0
## Coins rolled out into the cup and still lying there, for the tests.
var returned: int = 0


func _init() -> void:
	kind = ArcadeProfiles.KIND_COIN


func attach(p_cabinet: RetroSystemModel) -> void:
	super.attach(p_cabinet)
	_slot_button = find_child("CoinSlot", true, false) as VRButton
	_return_button = find_child("CoinReturn", true, false) as VRButton
	_spawn = find_child("CoinSpawn", true, false) as Node3D
	_drop = find_child("CoinDrop", true, false) as Node3D
	_cup = find_child("ReturnCup", true, false) as Node3D
	_coin_mesh = CylinderMesh.new()
	_coin_mesh.top_radius = COIN_RADIUS
	_coin_mesh.bottom_radius = COIN_RADIUS
	_coin_mesh.height = COIN_THICKNESS
	_coin_material = StandardMaterial3D.new()
	_coin_material.albedo_color = Color(0.95, 0.78, 0.30)
	_coin_material.metallic = 0.6
	_coin_material.roughness = 0.35
	_coin_material.emission_enabled = true
	_coin_material.emission = Color(0.9, 0.7, 0.2)
	_coin_material.emission_energy_multiplier = 0.35
	_voice = AudioStreamPlayer3D.new()
	_voice.name = "CoinVoice"
	_voice.stream = clink()
	_voice.unit_size = 0.6
	_voice.max_distance = 6.0
	_voice.volume_db = -6.0
	add_child(_voice)
	if _drop != null:
		_voice.position = _drop.position
	_return_voice = AudioStreamPlayer3D.new()
	_return_voice.name = "ReturnVoice"
	_return_voice.stream = rattle()
	_return_voice.unit_size = 0.6
	_return_voice.max_distance = 6.0
	_return_voice.volume_db = -4.0
	add_child(_return_voice)
	if _cup != null:
		_return_voice.position = _cup.position
	if _slot_button != null:
		_slot_button.button_pressed.connect(insert_coin)
		_lamp = _slot_button.find_child("ButtonMesh", true, false) as MeshInstance3D
	if _lamp != null and _lamp.mesh != null and _lamp.mesh.surface_get_material(0) is StandardMaterial3D:
		# Its own copy: the blink is this door's, and the baked material is shared by every door.
		_lamp_material = (_lamp.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
		_lamp.material_override = _lamp_material
		_lamp_energy = _lamp_material.emission_energy_multiplier
	if _return_button != null:
		_return_button.button_pressed.connect(func() -> void: return_pressed.emit(player))


## A game with one coin input has one coin door: the other is taken off the front and cannot be aimed at.
func set_door_enabled(on: bool) -> void:
	visible = on
	if _slot_button != null:
		_slot_button.set_interactive(on)
	if _return_button != null:
		_return_button.set_interactive(on)


func door_enabled() -> bool:
	return visible


## Toss a coin. Also the entry point for anything else that inserts one.
func insert_coin() -> void:
	if _spawn == null or _drop == null or not is_inside_tree():
		_land()
		return
	var coin := MeshInstance3D.new()
	coin.name = "Coin"
	coin.mesh = _coin_mesh
	coin.material_override = _coin_material
	add_child(coin)
	# Stands on edge, face toward the player, and spins about its own vertical.
	var from := _spawn.position
	var to := _drop.position
	coin.position = from
	in_flight += 1
	var tween := create_tween()
	tween.tween_method(_fly.bind(coin, from, to), 0.0, 1.0, FLIGHT_SECONDS)
	tween.tween_callback(_arrived.bind(coin))


func _fly(t: float, coin: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	if not is_instance_valid(coin):
		return
	var pos := from.lerp(to, t)
	pos.y += TOSS_HEIGHT * 4.0 * t * (1.0 - t)
	coin.position = pos
	coin.basis = Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, t * TAU * 2.0)


func _arrived(coin: MeshInstance3D) -> void:
	if is_instance_valid(coin):
		coin.queue_free()
	in_flight = maxi(in_flight - 1, 0)
	_land()


## The coin is in the box: sound, then the credit.
func _land() -> void:
	if _voice != null and is_inside_tree():
		_voice.play()
	coin_inserted.emit(player)


## A coin comes back out: it drops from inside the door into the return cup, rattles, lies there a
## moment and is gone (coins are infinite: there is nothing to pick up). For a coin the escrow gives
## back, and for one the cabinet could not take.
func return_coin() -> void:
	returned += 1
	if _return_voice != null and is_inside_tree():
		_return_voice.play()
	if _cup == null or not is_inside_tree():
		returned = maxi(returned - 1, 0)
		return
	var coin := MeshInstance3D.new()
	coin.name = "ReturnedCoin"
	coin.mesh = _coin_mesh
	coin.material_override = _coin_material
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
