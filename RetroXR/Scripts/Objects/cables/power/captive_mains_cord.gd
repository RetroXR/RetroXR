## CaptiveMainsCord — an appliance's own mains cord: fixed at the strain relief on
## its back (the model's PowerCordExit, cord along its local -Z) and ending in the
## wall plug of the player's region (docs/dev/power.md).
##
## The TV, the VCR, the DVD player, the decks, the amplifier and the arcade cabinet
## each make one with attach() and hand it to their PowerInput (`captive`). Like the
## captive video lead (SystemVideoLead), the cord is a child of the current scene,
## not of the body it hangs from, and is freed with it (its host's tree_exiting); it
## is never in "spawned", because the HOST's save entry records its plug
## (ScenePersistence `mains_cord`).
##
## Its plug follows the region as the strip's does (set_region; MainsSplice moves a
## seated one into the new plate, or splices a travel adapter in). Loose, the plug is
## reeled in through PlugTether; seated, carrying the appliance past the cord's reach
## pulls it out of the wall, as it would.
##
## Hidden (set_hidden, the device menu's Show Power Cord switch), the plug leaves its
## socket and the cord stops being drawn or simulated, and the appliance counts as
## plugged in out of sight (PowerInput reads `hidden`).
class_name CaptiveMainsCord
extends Node3D

const SCENE := preload("res://Scenes/Objects/cables/captive_mains_cord.tscn")
## Every captive cord in the tree, for a change of region.
const GROUP := "captive_mains_cord"
const PLUG_MESH := "res://Scenes/Objects/cables/%s.res"
## How far past its reach the appliance may be carried before the plug comes out.
const YANK_SLACK := 0.05

## Fired when the cord is shown or hidden.
signal hidden_changed(hidden: bool)

## The appliance it belongs to.
var host: Node3D = null
## Where it leaves the appliance: its local -Z is the way the cord goes.
var exit: Node3D = null
## A grounded plug (an arcade cabinet's) rather than an appliance's two-pin one.
var grounded := false
## Not drawn, not simulated, the plug in no socket: plugged in out of sight.
var hidden := false
## The region the plug was last made as; "" before the first.
var region := ""

@onready var rope: VerletRope = $VerletRope
@onready var wall_plug: PowerPlug = $WallPlug

var _reach := 0.0
var _rope_built := false


## Give `host` its cord, leaving from `exit`. Returns the cord, which enters the room
## a frame later (it hangs off the current scene).
static func attach(owner_body: Node3D, exit_point: Node3D, is_grounded := false) -> CaptiveMainsCord:
	var cord := SCENE.instantiate() as CaptiveMainsCord
	cord.host = owner_body
	cord.exit = exit_point
	cord.grounded = is_grounded
	cord.name = "%sMainsCord" % owner_body.name
	owner_body.tree_exiting.connect(cord.drop_and_free)
	cord._enter_room.call_deferred()
	return cord


func _enter_room() -> void:
	if not is_instance_valid(host) or not host.is_inside_tree() or is_queued_for_deletion():
		queue_free()
		return
	var scene := host.get_tree().current_scene
	if scene == null:
		queue_free()
		return
	scene.add_child(self)
	# An appliance a room authors (the den's set) is furnished: plugged in behind
	# the furniture. Its cord starts put away; one spawned or restored (in
	# "spawned" by now) starts shown, and a save says otherwise if it does.
	if not host.is_in_group("spawned"):
		set_hidden(true)


func _ready() -> void:
	add_to_group(GROUP)
	wall_plug.cable = self
	if host is CollisionObject3D:
		wall_plug.add_collision_exception_with(host)
	set_region(AppPrefs.mains_region)
	park_plug()
	_build_rope.call_deferred()


func _build_rope() -> void:
	if not is_inside_tree() or not is_instance_valid(exit):
		return
	rope.start_node = exit
	rope.end_node = wall_plug
	rope.end_anchor_offset = wall_plug.cable_anchor
	rope._init_points()
	_reach = float(rope.segment_count) * rope.segment_length
	_rope_built = true
	rope.visible = not hidden


## Lay the plug down behind the appliance, a short way out along the cord's exit.
func park_plug() -> void:
	if not is_instance_valid(exit) or not exit.is_inside_tree():
		return
	var out := -exit.global_basis.z.normalized()
	var at := exit.global_position + out * 0.25
	wall_plug.global_position = at
	wall_plug.look_at(at + out, Vector3.UP)
	wall_plug.linear_velocity = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	if hidden or not _rope_built or not is_instance_valid(exit) or not is_instance_valid(wall_plug):
		return
	var from := exit.global_position
	var to := wall_plug.global_transform * wall_plug.cable_anchor
	if not wall_plug.is_held():
		PlugTether.reel_in(wall_plug, to, from, _reach)
		return
	# Carried too far from the wall (or seated by a hand that carried the plug past the
	# cord's reach): the plug comes out, as it would. Drawn clear of the outlet with its
	# socket shut for two ticks (MainsSync.release) and then reeled in toward the
	# appliance: dropped where it was, the duplex's other socket took it straight back
	# and the two traded it every tick.
	var holder := PowerCord.socket_holding(wall_plug)
	if holder != null and from.distance_to(to) > _reach + YANK_SLACK:
		print("[Power] %s: %.2f m from %s, past its cord's %.2f m -- its plug came out"
			% [_host_label(), from.distance_to(to), PowerInput.describe_wall_plug(wall_plug), _reach])
		MainsSync.release(wall_plug)
		PlugTether.reel_in(wall_plug, wall_plug.global_transform * wall_plug.cable_anchor, from, _reach)


## Show or hide the cord. Hidden, its plug leaves its socket and the appliance counts
## as plugged in out of sight; shown again, the plug lies loose behind it.
func set_hidden(on: bool) -> void:
	if on == hidden:
		return
	hidden = on
	if on:
		var holder := PowerCord.socket_holding(wall_plug)
		if holder != null:
			holder.drop_object()
		wall_plug.freeze = true
	wall_plug.visible = not on
	wall_plug.enabled = not on
	_set_solid(not on)
	if is_instance_valid(rope):
		rope.visible = not on
		rope.set_physics_process(not on)
	if not on:
		wall_plug.freeze = false
		park_plug()
		# Laid again from where the plug now is, in this same frame (rope.md).
		if _rope_built:
			rope._init_points()
	print("[Power] %s: power cord %s" % [_host_label(), "hidden (plugged in out of sight)" if on else "shown"])
	hidden_changed.emit(on)
	MainsPower.changed(get_tree() if is_inside_tree() else null)


func _set_solid(on: bool) -> void:
	for shape in wall_plug.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).disabled = not on


## The plug an appliance sold in `id` comes with: a two-pin one, or for a grounded
## cord the region's own (the strip's plug).
static func plug_for(id: String, is_grounded: bool) -> String:
	var want := MainsRegions.resolve(id)
	var strip: Dictionary = MainsRegions.of(want).get("strip", {})
	if is_grounded:
		return str(strip.get("plug", "nema_5_15_plug"))
	if want == MainsRegions.DEFAULT:
		return "nema_1_15_polarized_plug"
	for token: String in MainsRegions.of(want).get("cords", []):
		var row: Dictionary = MainsRegions.CORDS.get(token, {})
		if row.get("grounded", true) == false:
			return str(row.get("plug", "nema_1_15_plug"))
		if token == "nema_1_15_to_c7_cord":
			return "nema_1_15_plug"
	return str(strip.get("plug", "nema_5_15_plug"))


## Make the plug `id`'s. One that stops fitting the socket it is in falls out
## (MainsSplice puts it back, through an adapter if it must).
func set_region(id: String) -> void:
	var want := MainsRegions.resolve(id)
	if want == region:
		return
	region = want
	var connector := plug_for(want, grounded)
	wall_plug.set_connector(connector)
	var tip := wall_plug.get_node_or_null("PlugTip") as MeshInstance3D
	var path := PLUG_MESH % connector
	if tip != null and ResourceLoader.exists(path):
		tip.mesh = load(path) as Mesh
		var box := tip.mesh.get_aabb()
		for shape_path: String in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
			var shape := wall_plug.get_node_or_null(shape_path) as CollisionShape3D
			if shape == null:
				continue
			var b := BoxShape3D.new()
			b.size = box.size + (Vector3(0.012, 0.012, 0.004) if shape_path.begins_with("Pointer")
				else Vector3.ZERO)
			shape.shape = b
			shape.position = box.get_center()
	var holder := PowerCord.socket_holding(wall_plug)
	if holder != null and not wall_plug.is_in_group(holder.snap_require):
		holder.drop_object()


## Remake every captive cord's plug as `id`'s (MainsSplice, before the plates).
static func apply_region(tree: SceneTree, id: String) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		(node as CaptiveMainsCord).set_region(id)


func on_plug_seating_changed() -> void:
	# Named by the appliance on the wire (MainsSync.report_captive).
	MainsSync.report_captive(self)


## The plug out of whatever holds it, then the cord freed. Its host's tree_exiting
## calls this: a socket left holding a freed plug walks a dangling grab driver.
func drop_and_free() -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(wall_plug):
		var holder := PowerCord.socket_holding(wall_plug)
		if holder != null:
			holder.drop_object()
	# queue_free in or out of the tree: a cord freed before it entered the room (a deck
	# built into a set, in the frame it was made) has its _enter_room still pending,
	# which sees the queued deletion and stays out. A deferred free() used to run AFTER
	# it: the cord entered the room, hid itself, queued its rope and was freed mid-frame.
	queue_free()


# ── Mains (MainsPower) ─────────────────────────────────────────────────────────

## The cord feeds nothing of the room's: its power goes into its own appliance,
## which asks PowerInput about its wall plug directly.
func mains_live_at(_at: Node, _seen: Dictionary) -> bool:
	return false


func mains_noun() -> String:
	return "built-in cord"


func mains_wall_plug() -> Node3D:
	return wall_plug


# ── Persistence: the host's entry carries it (ScenePersistence `mains_cord`) ─────

## What the host's save entry records: hidden, and where the plug is.
func save_record() -> Dictionary:
	var p := wall_plug.global_position
	var r := wall_plug.global_rotation_degrees
	var holder := PowerCord.socket_holding(wall_plug)
	return {
		"hidden": hidden,
		"position": [p.x, p.y, p.z],
		"rotation": [r.x, r.y, r.z],
		"device": holder.get_device() if holder != null else null,
		"port": String(holder.name) if holder != null else "",
	}


## Put it back as saved: hidden or not, the plug in its socket or lying where it was.
## `device` is already resolved to a node (or null).
func restore_record(rec: Dictionary) -> void:
	if not is_inside_tree():
		_restore_when_in.call_deferred(rec)
		return
	_apply_record.call_deferred(rec)


func _restore_when_in(rec: Dictionary) -> void:
	restore_record(rec)


func _apply_record(rec: Dictionary) -> void:
	if bool(rec.get("hidden", false)):
		set_hidden(true)
		return
	set_hidden(false)
	var pos: Array = rec.get("position", [])
	var rot: Array = rec.get("rotation", [])
	if pos.size() == 3:
		wall_plug.global_position = Vector3(pos[0], pos[1], pos[2])
	if rot.size() == 3:
		wall_plug.global_rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	var device: Variant = rec.get("device")
	var port_name := str(rec.get("port", ""))
	if device is Node and is_instance_valid(device) and not port_name.is_empty():
		var port := CompositeCable.port_named(device as Node, port_name)
		if port != null and wall_plug.is_in_group(port.snap_require):
			port.pick_up_object(wall_plug)
		else:
			print("[Power] %s: its saved socket %s is gone or no longer takes its plug; left loose"
				% [_host_label(), port_name])
	if _rope_built:
		rope._init_points()


func _host_label() -> String:
	if not is_instance_valid(host):
		return "<gone>"
	var shown: Variant = host.get("display_name")
	return str(shown) if shown is String and not (shown as String).is_empty() else str(host.name)
