## VMU slots probe — do a Dreamcast pad's two slots exist, take a card, and
## survive a save?
##
## The slots are BUILT rather than authored on the primitive pad, which has no
## scene of its own to hold them, so "are they there" is a runtime question
## rather than something a scene file can be read for.
##
##     "$godot" --headless --path RetroXR res://Tools/input/vmu_slots_probe.tscn
##
## No core, no ROM, no headset. The slots are there from the start and stay
## whatever the pad is plugged into: a card seated in a loose pad, or a pad on a
## NES, is still in it when that pad reaches a Dreamcast. A NES pad with its own
## shell has none.
##
## A PAD RECEIVER is driven through the same route, because the player using a
## real gamepad holds no virtual pad and reaches a card only through the dongle.
## Its seats are authored in its scene rather than built from VmuPort's constants,
## so the probe reads the seated card's BASIS back as well as counting sockets:
## a .tscn transform is written by rows and constructed by columns, and a card
## seated upside down would still count as one card.
##
## Both hosts are then saved through ScenePersistence and the entry restored onto
## a fresh host with fresh devices, through a JSON round trip as a save file does.
##
## Exits non-zero on failure.
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const PAD_SCENE := preload("res://Scenes/Objects/controllers/retro_controller.tscn")
const NES_PAD_SCENE := preload("res://Scenes/Objects/controllers/nes/nes_controller.tscn")
const DONGLE_SCENE := preload("res://Scenes/Objects/controllers/pad_receiver.tscn")
const VMU_SCENE := preload("res://Scenes/Objects/controllers/dreamcast/vmu_card.tscn")
const JUMP_PACK_SCENE := preload("res://Scenes/Objects/controllers/dreamcast/jump_pack.tscn")

var _fail := 0


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	await _run()
	print("[probe] ---- %s ----" % ("all checks passed" if _fail == 0 else "%d FAILED" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)


func _ok(cond: bool, what: String, detail := "") -> void:
	if not cond:
		_fail += 1
	print("[probe] %s  %s%s" % ["PASS" if cond else "FAIL", what,
		"" if detail.is_empty() else "  - " + detail])


func _make_system(systemid: String) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	add_child(sys)
	return sys


func _run() -> void:
	var dc := _make_system("dreamcast")
	var nes := _make_system("nes")
	var pad_dc := PAD_SCENE.instantiate() as RetroController
	var pad_nes := PAD_SCENE.instantiate() as RetroController
	var nes_pad := NES_PAD_SCENE.instantiate() as RetroController
	add_child(pad_dc)
	add_child(pad_nes)
	add_child(nes_pad)
	for i in range(4):
		await get_tree().process_frame

	_ok(pad_dc.vmu_slot_count() == 2, "a loose primitive pad already has two VMU slots",
		"got %d" % pad_dc.vmu_slot_count())
	_ok(nes_pad.vmu_slot_count() == 0, "a NES pad, with a shell of its own, has none",
		"got %d" % nes_pad.vmu_slot_count())
	# "" means no slot at all, which is not the same as an empty one: flycast
	# would keep its own default VMU fitted to a slot the player just emptied.
	_ok(nes_pad.vmu_slot_option_value(0) == "", "and reads empty rather than None",
		"'%s'" % nes_pad.vmu_slot_option_value(0))

	# The case that used to be refused: a card put in before the pad is plugged in.
	var early := VMU_SCENE.instantiate() as VmuCard
	add_child(early)
	await get_tree().process_frame
	pad_nes.restore_vmu(early, 0)
	for i in range(3):
		await get_tree().process_frame
	_ok(pad_nes.get_vmu(0) == early, "a VMU seats in a loose pad")

	pad_dc.on_plugged_in(dc, 0)
	pad_nes.on_plugged_in(nes, 0)
	await get_tree().process_frame

	_ok(pad_dc.vmu_slot_count() == 2, "a pad on a Dreamcast has two",
		"got %d" % pad_dc.vmu_slot_count())
	_ok(pad_nes.vmu_slot_count() == 2, "and so does one on a NES",
		"got %d" % pad_nes.vmu_slot_count())
	_ok(pad_nes.get_vmu(0) == early, "which keeps the card it was given while loose")
	_ok(pad_dc.get_node_or_null("VmuSlot1") != null, "slot 1 exists by name")
	_ok(pad_dc.get_node_or_null("VmuSlot2") != null, "slot 2 exists by name")

	# An empty slot must say "None" and not "".
	_ok(pad_dc.vmu_slot_option_value(0) == "None", "an empty slot reads None",
		pad_dc.vmu_slot_option_value(0))

	# Seat one.
	var card := VMU_SCENE.instantiate() as VmuCard
	add_child(card)
	await get_tree().process_frame
	pad_dc.restore_vmu(card, 0)
	await get_tree().process_frame
	await get_tree().process_frame

	_ok(pad_dc.get_vmu(0) == card, "a VMU seats in slot 1")
	_ok(pad_dc.vmu_slot_option_value(0) == "VMU", "and the slot then reads VMU",
		pad_dc.vmu_slot_option_value(0))
	_ok(pad_dc.get_vmu(1) == null, "slot 2 is still empty")
	_ok(pad_dc.vmu_slot_option_value(1) == "None", "and still reads None")

	# The other thing those sockets take. A Jump Pack is not a VmuCard, so the
	# slot has to hold it without casting it to one -- that cast turned a seated
	# pack into null, which the port read as an EMPTY slot and reported to
	# flycast as "None", so no vibration device was created and a game's rumble
	# went nowhere. Counting sockets cannot see that; the option value can.
	var pack := JUMP_PACK_SCENE.instantiate() as JumpPack
	add_child(pack)
	await get_tree().process_frame
	pad_dc.restore_vmu(pack, 1)
	for i in range(3):
		await get_tree().process_frame
	_ok(pad_dc.vmu_slot_option_value(1) == "Purupuru",
		"a Jump Pack in slot 2 asks flycast for a Purupuru",
		pad_dc.vmu_slot_option_value(1))
	# And it is NOT a card: anything asking a slot for somewhere to read saves
	# from must get nothing rather than a pack it cannot read.
	_ok(pad_dc.get_vmu(1) == null, "and is not offered as a card to read saves from")
	_ok(pad_dc.vmu_slot_option_value(0) == "VMU",
		"while the card in slot 1 still asks for a VMU")

	# Unplugging keeps the sockets and what is in them, so a card is still in the
	# pad when it is plugged into the next machine.
	pad_dc.on_unplugged()
	await get_tree().process_frame
	_ok(pad_dc.vmu_slot_count() == 2, "unplugging keeps the slots",
		"got %d" % pad_dc.vmu_slot_count())
	_ok(pad_dc.get_vmu(0) == card, "and the card in slot 1")
	_ok(pad_dc.vmu_slot_option_value(1) == "Purupuru", "and the pack in slot 2",
		pad_dc.vmu_slot_option_value(1))

	await _check_persistence(pad_dc, card, pack, PAD_SCENE, "pad")

	# Where the storage layer would put this card's bytes, and what flycast reads.
	print("[probe] card image  : %s" % card.image_path())
	print("[probe] core file A1: %s"
		% VmuStorage.core_vmu_path("<root>", "flycast", 0, 0))
	print("[probe] core file B2: %s"
		% VmuStorage.core_vmu_path("<root>", "flycast", 1, 1))

	# --- The dongle ---------------------------------------------------------
	#
	# Same rules, different host: a seat authored in a scene rather than one of
	# VmuPort's constants, and one slot rather than two because a 47 mm card does
	# not go twice across a 70 mm case.
	var rx_dc := DONGLE_SCENE.instantiate() as PadReceiver
	var rx_nes := DONGLE_SCENE.instantiate() as PadReceiver
	add_child(rx_dc)
	add_child(rx_nes)
	# A RigidBody with no floor falls, and every measurement below is taken in the
	# dongle's own frame anyway -- but a still bench is one less thing to explain.
	rx_dc.freeze = true
	rx_nes.freeze = true
	for i in range(4):
		await get_tree().process_frame

	_ok(rx_dc.vmu_slot_count() == 2, "a loose dongle already has two VMU slots",
		"got %d" % rx_dc.vmu_slot_count())
	rx_dc.on_plugged_in(dc, 1)
	rx_nes.on_plugged_in(nes, 1)
	await get_tree().process_frame
	_ok(rx_dc.vmu_slot_count() == 2, "a dongle on a Dreamcast has two, as a pad does",
		"got %d" % rx_dc.vmu_slot_count())
	_ok(rx_nes.vmu_slot_count() == 2, "and so does one on a NES",
		"got %d" % rx_nes.vmu_slot_count())
	_ok(rx_dc.vmu_slot_option_value(0) == "None", "its empty slot reads None",
		rx_dc.vmu_slot_option_value(0))
	# Slot 2 is EMPTY, not absent. "" would tell flycast this host has no such
	# slot and to leave its own default fitted; "None" says the slot is there and
	# nothing is in it. The dongle used to answer "" here because it had one seat.
	_ok(rx_dc.vmu_slot_option_value(1) == "None", "and its second slot reads empty, not absent",
		"'%s'" % rx_dc.vmu_slot_option_value(1))

	var rx_card := VMU_SCENE.instantiate() as VmuCard
	add_child(rx_card)
	await get_tree().process_frame
	rx_dc.restore_vmu(rx_card, 0)
	for i in range(3):
		await get_tree().process_frame
	_ok(rx_dc.get_vmu(0) == rx_card, "a VMU seats in the dongle")
	_ok(rx_dc.vmu_slot_option_value(0) == "VMU", "and the slot then reads VMU",
		rx_dc.vmu_slot_option_value(0))
	# And the reason the case was widened: a card AND a pack at once, so a player
	# on a real gamepad is not choosing between saving and rumble.
	var rx_pack := JUMP_PACK_SCENE.instantiate() as JumpPack
	add_child(rx_pack)
	await get_tree().process_frame
	rx_dc.restore_vmu(rx_pack, 1)
	for i in range(3):
		await get_tree().process_frame
	_ok(rx_dc.vmu_slot_option_value(1) == "Purupuru",
		"a Jump Pack goes in its second slot", rx_dc.vmu_slot_option_value(1))
	_ok(rx_dc.vmu_slot_option_value(0) == "VMU",
		"with the card still in the first")
	# And the pack has to seat as deep as the card, measured off its ACTUAL
	# connector and body meshes rather than a local point. That distinction is the
	# check: the pack is 25 mm shorter than a card, and with its origin at its own
	# centre it floated 12.5 mm above the lid with its connector in the open -- while
	# a fixed local point, transformed by the same seat, read exactly as deep as
	# the card's and passed.
	var inv := rx_dc.global_transform.affine_inverse()
	var pconn := rx_pack.get_node("Connector") as MeshInstance3D
	var pbody := rx_pack.get_node("Body") as MeshInstance3D
	var ptip: Vector3 = inv * (pconn.global_transform
		* Vector3(0, (pconn.mesh as BoxMesh).size.y * 0.5, 0))
	var pend: Vector3 = inv * (pbody.global_transform
		* Vector3(0, (pbody.mesh as BoxMesh).size.y * 0.5, 0))
	_ok(ptip.y > 0.020 and ptip.y < 0.040, "the pack's connector is inside the boss too",
		"connector tip at y=%.1f mm, boss is 20.0..40.0" % (ptip.y * 1000.0))
	_ok(pend.y >= 0.040, "and the pack's body stops at the lid",
		"body ends at y=%.1f mm, lid at 40.0" % (pend.y * 1000.0))

	# Which way up it went in. The card's +Y is its connector and its +Z is the
	# screen; seated, the connector must point DOWN into the boss and the screen
	# must face the dongle's front, the face with the LED and the name on it.
	# Counting sockets cannot tell an upside-down card from a right way up one.
	# Read in the DONGLE's frame, so a bench that lets the body move measures the
	# same thing a bolted-down one would.
	var rel := rx_dc.global_transform.affine_inverse() * rx_card.global_transform
	print("[probe] seated card basis y=%s z=%s"
		% [str(rel.basis.y.snappedf(0.001)), str(rel.basis.z.snappedf(0.001))])
	_ok(rel.basis.y.dot(Vector3.DOWN) > 0.99, "with its connector pointing into the boss",
		"y=%s" % str(rel.basis.y.snappedf(0.001)))
	_ok(rel.basis.z.dot(Vector3.FORWARD) > 0.99, "and its screen facing the dongle's front",
		"z=%s" % str(rel.basis.z.snappedf(0.001)))
	# And how deep. Only the black connector goes in, most of the way: its tip
	# (the card's own y=46) must be inside the boss, below the 40 mm lid, while
	# the body's end (y=40) stays OUTSIDE it. "It is in the slot" cannot tell a
	# card perched on the lid from one pushed in too far; these two can, and the
	# second is the one a player saw.
	var tip: Vector3 = rel * Vector3(0, 0.046, 0)
	var body_end: Vector3 = rel * Vector3(0, 0.040, 0)
	_ok(tip.y > 0.020 and tip.y < 0.040, "its connector is inside the boss",
		"connector tip at y=%.1f mm, boss is 20.0..40.0" % (tip.y * 1000.0))
	_ok(body_end.y >= 0.040, "and the body stops at the lid rather than going in",
		"body ends at y=%.1f mm, lid at 40.0" % (body_end.y * 1000.0))

	rx_dc.on_unplugged()
	await get_tree().process_frame
	_ok(rx_dc.vmu_slot_count() == 2, "unplugging the dongle keeps its slots",
		"got %d" % rx_dc.vmu_slot_count())
	_ok(rx_dc.get_vmu(0) == rx_card, "and the card in them")

	await _check_persistence(rx_dc, rx_card, rx_pack, DONGLE_SCENE, "dongle")


## Save a host through ScenePersistence, restore that entry onto a FRESH host and
## fresh devices under the ids the save gave them, and check both slots came back.
##
## The entry goes through JSON on the way, as a save file does, because an id
## parses back as a float and a reference that only resolved as an int would pass
## here and fail on a real load.
func _check_persistence(host: Node3D, card: VmuCard, pack: JumpPack,
		scene: PackedScene, what: String) -> void:
	var sp := ScenePersistence.new()
	var nodes := get_tree().get_nodes_in_group("spawned")
	var node_to_id: Dictionary = {}
	for i in range(nodes.size()):
		node_to_id[nodes[i]] = i
	var entry: Dictionary = sp._serialize_node(host, int(node_to_id[host]), node_to_id)
	var refs: Variant = entry.get("vmus")
	var recorded := (refs is Array and (refs as Array).size() == 2
		and refs[0] != null and int(refs[0]) == int(node_to_id[card])
		and refs[1] != null and int(refs[1]) == int(node_to_id[pack]))
	_ok(recorded, "a save records the %s's card and pack by slot" % what, str(refs))

	var parsed: Variant = JSON.parse_string(JSON.stringify(entry))
	var host2 := scene.instantiate() as Node3D
	var card2 := VMU_SCENE.instantiate() as VmuCard
	var pack2 := JUMP_PACK_SCENE.instantiate() as JumpPack
	add_child(host2)
	add_child(card2)
	add_child(pack2)
	if host2 is RigidBody3D:
		(host2 as RigidBody3D).freeze = true
	for i in range(3):
		await get_tree().process_frame
	var hid := int(node_to_id[host])
	var spawned := {hid: host2, int(node_to_id[card]): card2, int(node_to_id[pack]): pack2}
	sp._restore_entry(self, hid, spawned, {hid: parsed})
	for i in range(3):
		await get_tree().process_frame
	_ok(host2.call("get_vmu", 0) == card2, "a load puts the card back in the %s's slot 1" % what)
	_ok(str(host2.call("vmu_slot_option_value", 1)) == "Purupuru",
		"and the pack back in slot 2", str(host2.call("vmu_slot_option_value", 1)))
