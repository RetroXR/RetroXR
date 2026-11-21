## Figure self-tests: amiibo, Skylanders, Disney Infinity and Lego Dimensions.
## Covers telling each line's dump from anything else, the shelf a folder of them
## makes, an amiibo on the GamePad's NFC touchpoint, and a figure on a toy base's
## spots reaching the core's readers. Headless, with no core and no headset; the
## dumps are written by the suite.
##
##     "$godot" --headless --path RetroXR res://Tests/figure_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/figure_tests.tscn -- --only=base
##
## Groups:
##   data/     the header and size tests, the amiibo id, cards by folder
##   library/  a folder tree scanned into rows, strays and other lines left off
##   zone/     a real amiibo on a real Area3D: set, lifted, set again, power cycled
##   base/     a base's lead in a socket, figures on and off its spots, a republish
##   options/  the core options a Wii U's bases pin
extends "res://Tests/test_suite.gd"

const FIGURE_SCENE := preload("res://Scenes/Objects/media/toy_figure.tscn")
const PORTAL_SCENE := preload("res://Scenes/Objects/peripherals/toys/skylanders_portal.tscn")
const INFINITY_SCENE := preload("res://Scenes/Objects/peripherals/toys/infinity_base.tscn")
const TOYPAD_SCENE := preload("res://Scenes/Objects/peripherals/toys/dimensions_toypad.tscn")
const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")

var _only := ""
var _root := ""


## Stands in for the core: what it was handed.
class FakeLib extends Node:
	signal accessory_readers_changed(readers: Array)
	var sets: Array[String] = []
	var clears := 0
	var readers: Array = []
	var inserted: Array = []
	var removed: Array[int] = []

	func SetNfcTag(path: String) -> bool:
		sets.append(path)
		return FileAccess.file_exists(path)

	func ClearNfcTag() -> void:
		clears += 1

	func RequestAccessoryReaders() -> void:
		accessory_readers_changed.emit(readers)

	func InsertAccessoryMedia(reader: int, path: String) -> void:
		inserted.append([reader, path])

	func RemoveAccessoryMedia(reader: int) -> void:
		removed.append(reader)


## Stands in for the console.
class FakeHost extends Node3D:
	var is_powered_on := true
	var systemid := "wiiu"
	var lib: Node = null
	var refreshes := 0

	func get_libretro_node() -> Node:
		return lib

	func refresh_toy_base_option() -> void:
		refreshes += 1


func _ready() -> void:
	suite_tag = "figures"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[figures] TIMED OUT")
		get_tree().quit(1))
	_root = OS.get_temp_dir().path_join("retroxr_figure_tests_%d" % OS.get_process_id())
	await _run()
	_rm(_root)
	_finish()


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _run() -> void:
	if _want("data"):
		_group_data()
	if _want("library"):
		_group_library()
	if _want("zone"):
		await _group_zone()
	if _want("base"):
		await _group_base()
	if _want("options"):
		_group_options()


## An amiibo's bytes: the lock, CC and config an NTAG215 has, `id` at 0x54.
static func _amiibo(size: int = 540, id: int = 0x01) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(size)
	b[0x0A] = 0x0F
	b[0x0B] = 0xE0
	b[0x0C] = 0xF1
	b[0x0D] = 0x10
	b[0x0E] = 0xFF
	b[0x0F] = 0xEE
	b[0x20F] = 0x04
	b[0x210] = 0x5F
	b[0x54] = id
	return b


## A Skylander: 1 KB, the UID's check byte right.
static func _skylander(uid: int = 0x12) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(1024)
	b[0] = uid
	b[1] = 0x34
	b[2] = 0x56
	b[3] = 0x78
	b[4] = b[0] ^ b[1] ^ b[2] ^ b[3]
	return b


static func _sized(size: int, first: int = 0) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(size)
	b[0] = first
	return b


func _write(rel: String, bytes: PackedByteArray) -> String:
	var path := _root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return path


func _rm(dir: String) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(sub))
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# ── data/ ────────────────────────────────────────────────────────────────────

func _group_data() -> void:
	const A := FigureShelves.AMIIBO
	_ok(FigureShelves.is_dump(A, _amiibo(540)), "data/ a 540-byte amiibo is one")
	_ok(FigureShelves.is_dump(A, _amiibo(572)), "data/ and a 572-byte one, its signature after")
	var cc := _amiibo()
	cc[0x0C] = 0xE1
	_ok(not FigureShelves.is_dump(A, cc), "data/ a wrong capability container is not")
	var cfg := _amiibo(2048)
	cfg[0x210] = 0x00
	_ok(not FigureShelves.is_dump(A, cfg), "data/ nor config elsewhere (a Switch 2 dump)")
	_ok(not FigureShelves.is_dump(A, _amiibo(540).slice(0, 532)), "data/ nor a short file")
	_eq(FigureShelves.figure_id(_amiibo(540, 0xAB)), "ab00000000000000", "data/ the amiibo id is page 21-22")
	_ok(FigureShelves.is_card_path("C:/roms/amiibo/Animal Crossing Amiibo/Amiibo Cards/Series 1/Isabelle.bin"),
		"data/ an amiibo under a Cards folder is a card")
	_ok(not FigureShelves.is_card_path("/roms/amiibo/Super Smash Bros Amiibo/Card Guy.bin"),
		"data/ the file's own name does not make one")

	const S := FigureShelves.SKYLANDERS
	_ok(FigureShelves.is_dump(S, _skylander(), 1024), "data/ a Skylander is 1 KB with its UID check byte")
	var bcc := _skylander()
	bcc[4] ^= 0xFF
	_ok(not FigureShelves.is_dump(S, bcc, 1024), "data/ a wrong check byte is not one")
	_ok(not FigureShelves.is_dump(S, _skylander(), 1025), "data/ nor a file of another size")
	_ok(FigureShelves.is_dump(FigureShelves.INFINITY, _sized(320), 320), "data/ an Infinity figure is 320 bytes")
	_ok(not FigureShelves.is_dump(FigureShelves.INFINITY, _sized(540), 540), "data/ an amiibo is not one")
	_ok(FigureShelves.is_dump(FigureShelves.DIMENSIONS, _sized(180, 0x04), 180), "data/ a Dimensions tag is 180 bytes from NXP")
	_ok(not FigureShelves.is_dump(FigureShelves.DIMENSIONS, _sized(180, 0x00), 180), "data/ another maker's is not")
	_eq(FigureShelves.kind_of(FigureShelves.SKYLANDERS), 1, "data/ a Skylander is accessory kind 1")
	_eq(FigureShelves.kind_of(FigureShelves.INFINITY), 2, "data/ an Infinity figure kind 2")
	_eq(FigureShelves.kind_of(FigureShelves.DIMENSIONS), 3, "data/ a Dimensions tag kind 3")
	_eq(FigureShelves.kind_of(FigureShelves.AMIIBO), -1, "data/ and an amiibo none (NFC)")


# ── library/ ─────────────────────────────────────────────────────────────────

func _group_library() -> void:
	var lib := _root.path_join("amiibo")
	_write("amiibo/Super Smash Bros Amiibo/Donkey Kong.bin", _amiibo())
	_write("amiibo/Mario Sports Superstars Amiibo/Tennis/Donkey Kong.bin", _amiibo(572))
	_write("amiibo/Animal Crossing Amiibo/Amiibo Cards/Isabelle.bin", _amiibo())
	_write("amiibo/Loose.bin", _amiibo())
	_write("amiibo/key_retail.bin", PackedByteArray([1, 2, 3]))
	_write("amiibo/notes.txt", _amiibo())
	FigureShelves.invalidate()
	var labels: Array[String] = []
	for r: Dictionary in FigureShelves.figures(FigureShelves.AMIIBO, lib):
		labels.append(str(r["label"]))
	_eq(labels.size(), 4, "library/ four amiibo, the key and the text file left off")
	_ok("Donkey Kong (Super Smash Bros Amiibo)" in labels and "Donkey Kong (Tennis)" in labels,
		"library/ one name in two series is two rows", str(labels))
	_ok("Loose" in labels, "library/ a dump at the top has no series", str(labels))
	var card := FigureShelves.figure_for_path(FigureShelves.AMIIBO,
		lib.path_join("Animal Crossing Amiibo/Amiibo Cards/Isabelle.bin"))
	_ok(bool(card.get("is_card", false)), "library/ and the card is a card")
	_ok(not FigureShelves.figure_for_path(FigureShelves.AMIIBO, lib.path_join("Loose.bin").replace("/", "\\")).is_empty(),
		"library/ a path from a save finds its row whatever its separators")

	var sky := _root.path_join("skylanders")
	_write("skylanders/Giants/Tree Rex.sky", _skylander())
	_write("skylanders/Spyro.bin", _skylander(0x22))
	_write("skylanders/Stray.bin", _amiibo())
	_write("skylanders/Broken.dump", _sized(1024, 0x01))
	var sky_rows := FigureShelves.figures(FigureShelves.SKYLANDERS, sky)
	_eq(sky_rows.size(), 2, "library/ two Skylanders, an amiibo and a bad dump left off")
	_eq(FigureShelves.figures(FigureShelves.INFINITY, sky).size(), 0, "library/ no Skylander is an Infinity figure")
	FigureShelves.invalidate()


# ── zone/ ────────────────────────────────────────────────────────────────────

func _group_zone() -> void:
	var path := _write("zone/Mario.bin", _amiibo())
	var host := FakeHost.new()
	var lib := FakeLib.new()
	host.lib = lib
	add_child(host)
	host.add_child(lib)
	var zone := NfcTouchZone.new()
	add_child(zone)
	zone.set_host(host)
	var fig := FIGURE_SCENE.instantiate() as ToyFigure
	fig.rom_path = path
	add_child(fig)
	fig.freeze = true
	fig.global_position = Vector3(1, 0, 0)
	await _frames(4)
	_eq(lib.sets.size(), 0, "zone/ a figure off the mark is not touched")

	fig.global_position = Vector3(0, 0.001, 0)
	await _frames(4)
	_eq(lib.sets.size(), 1, "zone/ set on the mark, it is touched once")
	_ok(lib.sets.size() == 1 and lib.sets[0] == ProjectSettings.globalize_path(path)
		and lib.sets[0].is_absolute_path(), "zone/ with its dump's path on disk", str(lib.sets))
	_ok(zone.is_touching(), "zone/ and the zone holds it")

	fig.global_position = Vector3(0, 0.05, 0)
	await _frames(4)
	_eq(lib.clears, 1, "zone/ lifted 5 cm, the tag is lifted")

	fig.global_position = Vector3(0.002, 0.003, 0.004)
	await _frames(4)
	_eq(lib.sets.size(), 2, "zone/ set down again, it is touched again")

	var lib2 := FakeLib.new()
	host.add_child(lib2)
	host.lib = lib2
	await _frames(4)
	_eq(lib2.sets.size(), 1, "zone/ a new core is handed the figure still on the mark")

	host.is_powered_on = false
	zone.set_host(null)
	await _frames(2)
	_ok(not zone.is_touching(), "zone/ unwired, it holds nothing")

	var bad := FIGURE_SCENE.instantiate() as ToyFigure
	bad.rom_path = _root.path_join("zone/missing.bin")
	add_child(bad)
	bad.freeze = true
	fig.global_position = Vector3(1, 0, 0)
	bad.global_position = Vector3(0, 0.001, 0)
	var lib3 := FakeLib.new()
	host.add_child(lib3)
	host.lib = lib3
	host.is_powered_on = true
	zone.set_host(host)
	await _frames(6)
	_eq(lib3.sets.size(), 1, "zone/ a refused dump is offered once")
	_ok(not zone.is_touching(), "zone/ and is not held")

	# A Skylander is the portal's: the GamePad does not read it.
	var sky := FIGURE_SCENE.instantiate() as ToyFigure
	sky.systemid = FigureShelves.SKYLANDERS
	sky.rom_path = _write("zone/Spyro.sky", _skylander())
	add_child(sky)
	sky.freeze = true
	bad.global_position = Vector3(1, 0, 0)
	sky.global_position = Vector3(0, 0.001, 0)
	await _frames(4)
	_eq(lib3.sets.size(), 1, "zone/ a Skylander on the GamePad is not touched")

	var card := FIGURE_SCENE.instantiate() as ToyFigure
	card.rom_path = _write("zone/Amiibo Cards/Isabelle.bin", _amiibo())
	add_child(card)
	_ok(card.is_card() and card.has_node("Card") and not card.has_node("Base"),
		"zone/ an amiibo card dump is built as a card")
	_ok(fig.has_node("Base") and fig.has_node("Standee") and (fig.get_node("Name") as Label3D).text == "Mario",
		"zone/ a figure is a base and a standee with its name")
	for n: Node in [zone, fig, bad, sky, card, host]:
		n.queue_free()
	await _frames(1)


# ── base/ ────────────────────────────────────────────────────────────────────

## A stand-in Wii U with one USB socket at `at`, and a running core whose readers
## are `readers` ({index, kind}).
func _console(at: Vector3, readers: Array) -> FakeHost:
	var host := FakeHost.new()
	host.name = "WiiU"
	var lib := FakeLib.new()
	lib.readers = readers
	host.lib = lib
	add_child(host)
	host.global_position = at
	host.add_child(lib)
	var socket := SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
	socket.name = "UsbPort1"
	socket.snap_require = "controller_plug"
	host.add_child(socket)
	return host


func _figure(sid: String, path: String, at: Vector3) -> ToyFigure:
	var fig := FIGURE_SCENE.instantiate() as ToyFigure
	fig.systemid = sid
	fig.rom_path = path
	add_child(fig)
	fig.freeze = true
	fig.global_position = at
	return fig


func _group_base() -> void:
	# The core's readers as Cemu publishes them with the portal and the Toy Pad on:
	# 16 Skylander spots, then 7 Toy Pad slots.
	var readers: Array = []
	for i in 16:
		readers.append({"index": i, "kind": FigureShelves.KIND_SKYLANDER})
	for i in 7:
		readers.append({"index": 16 + i, "kind": FigureShelves.KIND_DIMENSIONS})
	var host := _console(Vector3(0, 0, -1), readers)
	var lib := host.lib as FakeLib
	var portal := PORTAL_SCENE.instantiate() as ToyBase
	add_child(portal)
	portal.freeze = true
	portal.global_position = Vector3.ZERO
	await _frames(3)
	_ok(is_instance_valid(portal.get_plug()) and Connectors.of(portal.get_plug()) == Connectors.USB_A,
		"base/ the portal's lead ends in a USB-A plug")
	await _frames(12)
	_ok(portal.host == null and not portal.is_live(), "base/ unplugged, it has no console and no spots")

	portal.restore_connection(host, "UsbPort1")
	await _frames(14)
	_eq(portal.host, host, "base/ its plug in the Wii U's socket, the base is that console's")
	_ok(host.refreshes >= 1, "base/ and the console is told to pin its options")
	_ok(portal.is_live(), "base/ the core's 16 portal spots are its own")
	_eq(portal.socket_name(), "UsbPort1", "base/ it says which socket it is in, for a save")

	# What a save keeps: its kind, the console and the socket its lead is in.
	var sp := ScenePersistence.new()
	var entry := sp.serialize_node(portal, 1, {portal: 1, host: 2})
	_eq(str(entry.get("type", "")), ToyBase.PORTAL, "base/ saved under its kind")
	_ok(entry.get("system") == 2 and str(entry.get("socket", "")) == "UsbPort1",
		"base/ with its console and socket", str(entry))
	_ok(ScenePersistence.PLAIN_SCENES.has(str(entry.get("type", ""))), "base/ a type a load can build")

	var top := portal.global_position + Vector3(0, float(ToyBase.BASES[ToyBase.PORTAL]["size"].y) + 0.001, 0)
	var a := _figure(FigureShelves.SKYLANDERS, _write("base/Spyro.sky", _skylander(0x31)), top)
	var b := _figure(FigureShelves.SKYLANDERS, _write("base/Gill Grunt.sky", _skylander(0x32)), top + Vector3(0.04, 0, 0))
	var wrong := _figure(FigureShelves.DIMENSIONS, _write("base/Batman.bin", _sized(180, 0x04)), top + Vector3(-0.04, 0, 0))
	var fentry := sp.serialize_node(a, 3, {a: 3})
	_ok(str(fentry.get("type", "")) == ToyFigure.KIND and str(fentry.get("sys", "")) == FigureShelves.SKYLANDERS
		and str(fentry.get("rom", "")).ends_with("Spyro.sky"), "base/ a figure saves its shelf and dump", str(fentry))
	await _frames(4)
	var on: Array = []
	for e: Array in lib.inserted:
		on.append(int(e[0]))
	_eq(lib.inserted.size(), 2, "base/ two Skylanders set down, two figures on the portal")
	_ok(0 in on and 1 in on, "base/ on its first two spots", str(lib.inserted))
	_ok(lib.inserted.all(func(e: Array) -> bool: return str(e[1]).is_absolute_path()),
		"base/ with their dumps' paths on disk")

	# Which spot Spyro took depends on the order the two arrived in.
	var spot := -1
	for e: Array in lib.inserted:
		if str(e[1]).ends_with("Spyro.sky"):
			spot = int(e[0])
	a.global_position = top + Vector3(0, 0.1, 0)
	await _frames(4)
	_eq(lib.removed, [spot] as Array[int], "base/ one lifted off, its spot is emptied")
	a.global_position = top + Vector3(0, 0.002, 0.02)
	await _frames(4)
	_eq(lib.inserted.size(), 3, "base/ set down again, it is put on again")
	_eq(int(lib.inserted[2][0]), spot, "base/ on the spot it left")

	# The readers again after an insert, with both figures present: nothing resent.
	lib.inserted.clear()
	var held: Array = []
	for r: Dictionary in readers:
		held.append(r.merged({"present": int(r["index"]) < 2}))
	lib.accessory_readers_changed.emit(held)
	await _frames(4)
	_eq(lib.inserted.size(), 0, "base/ the readers again with both figures on: nothing is resent")
	# A reset: the same readers, the base empty.
	lib.accessory_readers_changed.emit(readers)
	await _frames(4)
	_eq(lib.inserted.size(), 2, "base/ after a reset empties the base, both figures are handed over again")

	# Lead out: dark again.
	portal.get_plug().get_picked_up_by().call("drop_object")
	await _frames(14)
	_ok(portal.host == null and not portal.is_live(), "base/ unplugged, the base is no console's")

	# The Toy Pad: the centre pad's one slot is reader 16 + 1, the left pad's first 16 + 0.
	var pad := TOYPAD_SCENE.instantiate() as ToyBase
	add_child(pad)
	pad.freeze = true
	pad.global_position = Vector3(1, 0, 0)
	await _frames(3)
	pad.restore_connection(host, "UsbPort1")
	await _frames(14)
	_ok(pad.is_live(), "base/ the Toy Pad takes the core's seven Dimensions slots")
	lib.inserted.clear()
	var h := float(ToyBase.BASES[ToyBase.TOY_PAD]["size"].y) + 0.001
	wrong.global_position = pad.global_position + Vector3(0, h, -0.01)
	var brick := _figure(FigureShelves.DIMENSIONS, _write("base/Gandalf.bin", _sized(180, 0x04)),
		pad.global_position + Vector3(-0.085, h, 0.01))
	a.global_position = pad.global_position + Vector3(0.085, h, 0.01)
	await _frames(4)
	var got: Array = []
	for e: Array in lib.inserted:
		got.append(int(e[0]))
	got.sort()
	_eq(got, [16, 17], "base/ a tag on the centre pad and one on the left: slots 1 and 0", )
	_ok(lib.inserted.size() == 2, "base/ and the Skylander on the right pad is not read", str(lib.inserted))

	for n: Node in [portal, pad, a, b, wrong, brick, host]:
		n.queue_free()
	await _frames(2)


# ── options/ ─────────────────────────────────────────────────────────────────

func _group_options() -> void:
	var both := ForcedCoreOptions.toy_bases("cemu", "wiiu", [ToyBase.PORTAL, ToyBase.TOY_PAD] as Array[String])
	_eq(both.get("cemu_emulate_skylander_portal"), "enabled", "options/ a portal plugged in switches its base on")
	_eq(both.get("cemu_emulate_dimensions_toypad"), "enabled", "options/ and the Toy Pad its")
	_eq(both.get("cemu_emulate_infinity_base"), "disabled", "options/ a base not plugged in is off")
	_ok(ForcedCoreOptions.toy_bases("dolphin", "wii", [ToyBase.PORTAL] as Array[String]).is_empty(),
		"options/ nothing is pinned on another core")
