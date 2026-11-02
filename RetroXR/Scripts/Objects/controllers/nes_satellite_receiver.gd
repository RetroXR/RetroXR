## NesSatelliteReceiver — the NES Satellite's receiver (NES-033), a primitive
## stand-in. From the manual and photographs (docs/dev/four-player-adapters.md):
## a small two-tone block whose back carries the two NES plugs, so it goes
## "straight into the sockets in the Control Deck" -- both of them, as the Four
## Score's block does; a black infrared lens on its upper front, angled up toward
## the room; ribbed grips either side; and a small LED on the front that flashes
## while information is received and every few seconds besides.
##
## It IS its own plug: in the controller_plug group, with the NES's connector and
## socket_span 2, so SystemPorts seats it like the Four Score's block (port 1 only,
## filling port 2 too) and tells it once per port (on_plugged_in). It routes nothing
## itself. The transmitter (NesSatellite) pairs with a seated receiver near it and
## decides the ports through it; the receiver only says where it is and lights its
## LED when told the transmitter got through.
##
## Its frame is the LEFT plug's: +Z into the console, the body standing out along
## -Z, +Y up, so the snap grab point (turned half round about X, as every
## ControllerPlug's is) seats it like any plug. Sizes are estimates from the
## photographs: about 62 x 56 x 56 mm.
class_name NesSatelliteReceiver
extends XRToolsPickable


const GROUP := "nes_satellite_receiver"
const _NES_PLUG := "res://imported-assets/controllers/nes/nes_controller_plug.res"

const BODY_W := 0.062
const BODY_H := 0.056
const BODY_D := 0.056
## How far below the plugs' middle the body's floor is: the NES's ports stand
## 30 mm off the desk, so the block rests on it.
const FLOOR_Y := -0.030
## The dark lower block's height; the light upper block stands on its back part,
## and the lens is the 45-degree face across the corner between them.
const LOWER_H := 0.032
const CHAMFER := BODY_H - LOWER_H

const LIGHT := Color(0.74, 0.74, 0.72)
const DARK := Color(0.45, 0.45, 0.46)
const BLACK := Color(0.04, 0.04, 0.05)

## What it is to a socket (SystemPorts reads these off whatever seats).
var device_type: int = 1
var device_names := PackedStringArray()
var connector: String = ""
var socket_span: int = 2

## The transmitter it serves, or null (NesSatellite._repair sets it).
var transmitter: Node = null

var _system: RetroSystem = null
var _plugged := false
var _led_mat: StandardMaterial3D = null
var _led_left := 0.0


func _init() -> void:
	connector = Connectors.controller_port_of("nes")


func _ready() -> void:
	super._ready()
	press_to_hold = false
	add_to_group("controller_plug")
	add_to_group(GROUP)
	add_to_group("spawned")
	_build()


## The middle of the infrared lens, in world space.
func lens_point() -> Vector3:
	return global_transform * _lens_local()


## Which way the lens looks: up and out of the console, in world space.
func lens_normal() -> Vector3:
	return (global_basis * Vector3(0.0, 1.0, -1.0).normalized()).normalized()


func _lens_local() -> Vector3:
	return Vector3(-NesFourScore.PLUG_PITCH * 0.5, FLOOR_Y + LOWER_H + CHAMFER * 0.5,
		_front_z() + CHAMFER * 0.5)


## The body's front face (its far side from the console), in this frame.
static func _front_z() -> float:
	return -0.020 - BODY_D


func is_plugged_in() -> bool:
	return _plugged


## The console it is in, or null.
func get_connected_system() -> RetroSystem:
	return _system if is_instance_valid(_system) else null


## The first console socket it fills, or -1.
func get_cabinet_port() -> int:
	if not is_instance_valid(_system):
		return -1
	return _system.cabinet_port_of_plug(self)


## Seated in a console port (told once per port it fills).
func on_plugged_in(system: Node3D, port_index: int) -> void:
	var was := _plugged
	_plugged = true
	_system = system as RetroSystem
	if not was:
		print("[SatelliteRx] seated in %s (libretro port %d)" % [system.name, port_index])
	_tell_transmitters()


## Out of a port. It is out of the console only when it fills none.
func on_unplugged() -> void:
	if is_instance_valid(_system) and not _system.cabinet_ports_of_plug(self).is_empty():
		return
	if not _plugged:
		return
	_plugged = false
	print("[SatelliteRx] unplugged")
	_system = null
	_tell_transmitters()


## Seat it back where a save says.
func restore_port_connection(system: RetroSystem, port_index: int) -> void:
	if _plugged and _system == system:
		return
	print("[SatelliteRx] restoring into console socket %d" % port_index)
	system.restore_controller_plug(port_index, self)


## Every transmitter looks again at which receiver it has.
func _tell_transmitters() -> void:
	if is_inside_tree():
		get_tree().call_group(NesSatellite.GROUP, "_repair")


## The LED: on for a moment. The transmitter calls it as a frame gets through.
func flash(seconds := 0.08) -> void:
	_led_left = maxf(_led_left, seconds)


func _process(delta: float) -> void:
	if _led_mat == null:
		return
	var lit := _led_left > 0.0
	_led_left = maxf(0.0, _led_left - delta)
	_led_mat.emission_enabled = lit
	_led_mat.albedo_color = Color(1.0, 0.15, 0.1) if lit else Color(0.35, 0.08, 0.06)


func _build() -> void:
	var cx := -NesFourScore.PLUG_PITCH * 0.5
	var light := _mat(LIGHT, 0.55)
	var dark := _mat(DARK, 0.6)
	var black := _mat(BLACK, 0.25)
	# The two plugs, the NES's own, out of its back.
	if ResourceLoader.exists(_NES_PLUG):
		var mesh := PlugExit.mesh_of(load(_NES_PLUG))
		for k in 2:
			var mi := MeshInstance3D.new()
			mi.name = "Plug%d" % (k + 1)
			mi.mesh = mesh
			add_child(mi)
			mi.position = Vector3(-NesFourScore.PLUG_PITCH * k, 0.0, 0.0)
	# The body, as the photographs have it: a dark lower block the full depth, a
	# light upper block on its back part, and across the corner between them, at
	# 45 degrees, the black lens looking up and out.
	var body_z := -0.020 - BODY_D * 0.5
	_box("BodyLower", Vector3(BODY_W, LOWER_H, BODY_D), Vector3(cx, FLOOR_Y + LOWER_H * 0.5, body_z), dark)
	var upper_d := BODY_D - CHAMFER
	_box("BodyUpper", Vector3(BODY_W + 0.001, CHAMFER, upper_d),
		Vector3(cx, FLOOR_Y + LOWER_H + CHAMFER * 0.5, -0.020 - upper_d * 0.5), light)
	# R_x(-45): the plate's face (+Y) looks up and toward -Z, out of the console.
	var lens := _box("Lens", Vector3(BODY_W - 0.004, 0.002, CHAMFER * sqrt(2.0)), Vector3.ZERO, black)
	lens.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-45.0)), _lens_local())
	# Ribbed grips either side, where the manual says to hold it.
	for side: float in [-1.0, 1.0]:
		for r in 4:
			_box("Rib", Vector3(0.0012, 0.003, 0.03), Vector3(cx + side * (BODY_W * 0.5 + 0.0006),
				FLOOR_Y + 0.010 + r * 0.007, body_z), dark)
	# The signal LED on the front face.
	var led := MeshInstance3D.new()
	led.name = "Led"
	var sphere := SphereMesh.new()
	sphere.radius = 0.0018
	sphere.height = 0.0036
	led.mesh = sphere
	_led_mat = _mat(Color(0.35, 0.08, 0.06), 0.3)
	_led_mat.emission = Color(1.0, 0.2, 0.1)
	_led_mat.emission_energy_multiplier = 2.0
	led.material_override = _led_mat
	add_child(led)
	led.position = Vector3(cx + 0.016, FLOOR_Y + LOWER_H * 0.55, _front_z() - 0.0008)
	# What it rests and is grabbed on: the body, and the plugs' noses.
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		var box := BoxShape3D.new()
		box.size = Vector3(BODY_W, BODY_H, BODY_D + 0.02)
		col.shape = box
		col.position = Vector3(cx, FLOOR_Y + BODY_H * 0.5, -0.010 - BODY_D * 0.5)
	# The SnapGrabPoint is authored in the scene, turned half round about X as a
	# ControllerPlug's is: a pickable collects its grab points as it readies, so
	# one added here would never be the one a socket seats it by.


func _box(node_name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	add_child(mi)
	mi.position = at
	return mi


static func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m
