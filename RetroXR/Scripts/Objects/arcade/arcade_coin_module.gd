## ArcadeCoinModule — a coin door: the one way to put a credit in the cabinet.
##
## Poke the coin slot (`CoinSlot`, a VRButton) and a coin is tossed from `CoinSpawn`
## to `CoinDrop` along an arc, spinning. You hear it drop into the box, and AT THAT
## MOMENT the module says `coin_inserted(player)`: ArcadeInput turns that into the
## pulse the core reads as a coin. Coins are infinite and uncounted; nothing is
## saved, and the coin in flight is a plain mesh, never a physics body or a
## `spawned` object. Animation and sound are local; only the pulse is input.
##
## The sound is synthesised for now (no recorded asset exists): a metal coin on a
## metal tray, two bounces. A real recording replaces it through the hardware-sfx
## workflow.
class_name ArcadeCoinModule
extends ArcadeModule

signal coin_inserted(player: int)

## Seconds a coin is in the air.
const FLIGHT_SECONDS := 0.28
## How high the toss rises above the straight line, in metres.
const TOSS_HEIGHT := 0.05
const COIN_RADIUS := 0.0115
const COIN_THICKNESS := 0.0018
const SAMPLE_RATE := 22050

static var _clink: AudioStreamWAV = null

var _slot_button: VRButton = null
var _spawn: Node3D = null
var _drop: Node3D = null
var _voice: AudioStreamPlayer3D = null
var _coin_mesh: CylinderMesh = null
var _coin_material: StandardMaterial3D = null
## Coins in the air, for the tests: a press with no tween leaves this at zero.
var in_flight: int = 0


func _init() -> void:
	kind = ArcadeProfiles.KIND_COIN


func attach(p_cabinet: RetroSystemModel) -> void:
	super.attach(p_cabinet)
	_slot_button = find_child("CoinSlot", true, false) as VRButton
	_spawn = find_child("CoinSpawn", true, false) as Node3D
	_drop = find_child("CoinDrop", true, false) as Node3D
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
	if _slot_button != null:
		_slot_button.button_pressed.connect(insert_coin)


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
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	_clink = wav
	return wav
