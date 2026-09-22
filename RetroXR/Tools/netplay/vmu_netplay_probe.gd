## A standalone VMU under netplay: two processes, the real NetworkManager, the
## real VmuCard scene and the real vemulator core, over loopback ENet.
##
##   host:   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##             res://Tools/netplay/vmu_netplay_probe.tscn -- --net-host [--game=<file in roms/vmu>]
##   client: "$godot" --path RetroXR --resolution 320x240 --position 360,20 \
##             res://Tools/netplay/vmu_netplay_probe.tscn -- --net-join=127.0.0.1
##
## Start the host first. The host powers its card on with a library minigame
## while the session is up, which is the path a player takes: VmuCard offers the
## game to the session, every peer finds the same file by hash, and each boots
## it under the gate. Whoever owns port 0 plays a scripted pattern through
## set_input (the real input path). At HANDOFF_AT the host hands the port to the
## client, a scheduled transfer as a grab would make it, so the rest of the run
## is the other player's hands. The session's own state-CRC checkpoints are the
## oracle: a desync anywhere prints DESYNC and fails.
##
## --card (host only) plays the game OFF A CARD instead: the host's card is
## written holding it and play_save runs it, so the image reaches the client in
## the spec's SRAM field and the client's library is never consulted. The card
## file is removed afterwards.
##
## A probe, not a test: it wants the RetroXR vemulator build that has savestates
## and the "clock" option, and a minigame in roms/vmu. It writes the player's
## core_options/vemulator.opt; snapshot it first. Scratch images are per card id
## (vmu_probe_host / vmu_probe_client) under user://vmu_play and are removed.
extends Node3D

const VMU_SCENE := "res://Scenes/Objects/controllers/dreamcast/vmu_card.tscn"
const END_AT := 1800
const HANDOFF_AT := 700

var _is_host := false
var _game := "Alien Shooter (200x)(Dream Machine)(PD).vms"
var _vmu: VmuCard = null
var _started := false
var _done := false
var _client_id := 0
var _handed := false
var _card := false
## Checkpoints both peers reported and agreed on, read off the session's own
## table before it prunes them. Silence is not agreement: a client that never
## reports is never compared, so PASS needs these.
var _agreed := {}
var _last_log := 0
## A pass needs at least this many agreed checkpoints (the session hashes every
## 60 frames, so a full run gives ~29).
const MIN_AGREED := 20


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--net-host":
			_is_host = true
		elif arg == "--card":
			_card = true
		elif arg.begins_with("--game="):
			_game = arg.trim_prefix("--game=")
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[vmunet] TIMEOUT")
		_finish(false))

	_vmu = load(VMU_SCENE).instantiate() as VmuCard
	_vmu.card_id = "vmu_probe_host" if _is_host else "vmu_probe_client"
	add_child(_vmu)
	NetworkManager._netplay.system_override = _vmu
	print("[vmunet] capable=%s" % NetworkManager.netplay_capable("vemulator"))
	NetworkManager._netplay.desync_detected.connect(func(pid: int, f: int) -> void:
		print("[vmunet] DESYNC peer %d @frame %d" % [pid, f])
		_finish(false))
	NetworkManager._netplay.session_stopped.connect(func(reason: String) -> void:
		if not _done and not _is_host:
			print("[vmunet] session stopped: %s" % reason)
			_finish(reason == "finished"))
	if _is_host:
		NetworkManager.peer_registered.connect(_on_peer_registered)


func _on_peer_registered(id: int, _info: Dictionary) -> void:
	if _started:
		return
	_started = true
	_client_id = id
	await get_tree().create_timer(0.5).timeout
	var path := RomLibrary.rom_dir_for_system(VmuCard.LIBRARY_SYSTEMID).path_join(_game)
	var ok := false
	if _card:
		var image := VMUCard.insert_save(VMUCard.blank_image(),
			VMUCard.dci_from_vms(FileAccess.get_file_as_bytes(path), "GAME"))
		var card_path := SramPaths.card_save_path(VmuCard.FAMILY, _vmu.card_id)
		DirAccess.make_dir_recursive_absolute(card_path.get_base_dir())
		var f := FileAccess.open(card_path, FileAccess.WRITE)
		f.store_buffer(image)
		f.close()
		var block := int(VMUCard.list_saves(image, false)[0]["block"])
		ok = _vmu.play_save(block, "card game")
	else:
		ok = _vmu.power_on(path)
	var np: NetplaySession = NetworkManager._netplay
	print("[vmunet] power_on -> %s, session active=%s" % [ok, np.is_active()])
	if not ok or not np.is_active():
		_finish(false)


## The owner's pattern: MODE and A to get into a game, then the d-pad and A.
## Keyed to the emulated frame so either player's hands produce the same thing.
func _pattern(f: int) -> int:
	var btn := 0
	if (f >= 120 and f < 130) or (f >= 240 and f < 250):
		btn |= 1 << 8                      # A
	if f >= 300:
		btn |= (1 << 7) if (f / 60) % 2 == 0 else (1 << 6)   # RIGHT / LEFT
		if f % 45 < 8:
			btn |= 1 << 8
		if f % 97 < 6:
			btn |= 1 << 5                  # UP
	return btn


func _process(_delta: float) -> void:
	if _done:
		return
	var np: NetplaySession = NetworkManager._netplay
	if not np.is_running():
		return
	var lib: Node = _vmu.get_libretro_node()
	var emu: int = lib.GetFrameCount()
	if not _vmu.is_running_standalone():
		return
	if _is_host and not _handed and emu >= HANDOFF_AT:
		_handed = true
		print("[vmunet] strategy rollback=%s; handing port 0 to peer %d @%d"
			% [np._rollback, _client_id, emu])
		NetworkManager.netplay_handoff_port(_vmu, 0, _client_id)
	# Only the owner's hands reach the core; set_input is the real path either way.
	if np._local_ports.has(0):
		_vmu.set_input(_pattern(emu + 1))
	if emu - _last_log >= 300:
		_last_log = emu
		print("[vmunet] %s at frame %d, port 0 local=%s" % [
			"host" if _is_host else "client", emu, np._local_ports.has(0)])
	if _is_host:
		for frame: int in np._crc_table:
			var t: Dictionary = (np._crc_table[frame] as Dictionary).get(0, {})
			if t.size() >= 2 and t.values().count(t.values()[0]) == t.size():
				_agreed[frame] = true
	if _is_host and emu >= END_AT:
		print("[vmunet] checkpoints agreed by both peers: %d (last @%d)" % [
			_agreed.size(), _agreed.keys().max() if not _agreed.is_empty() else -1])
		_finish(_agreed.size() >= MIN_AGREED)


func _finish(ok: bool) -> void:
	if _done:
		return
	_done = true
	var lib: Node = _vmu.get_libretro_node() if _vmu else null
	if lib != null:
		if lib.has_method("GetNetplayRollbackCount"):
			print("[vmunet] rollbacks performed: %d" % lib.GetNetplayRollbackCount())
		print("[vmunet] finished at frame %d" % lib.GetFrameCount())
	print("[vmunet] RESULT=%s" % ("PASS" if ok else "FAIL"))
	if _is_host:
		NetworkManager.netplay_stop("finished")
	for _i in range(90):
		await get_tree().process_frame
	if _card:
		var card_path := SramPaths.card_save_path(VmuCard.FAMILY, _vmu.card_id)
		if FileAccess.file_exists(card_path):
			DirAccess.remove_absolute(card_path)
	for ext in [".bin", ".json"]:
		var p := ProjectSettings.globalize_path(VmuCard.PLAY_DIR.path_join(_vmu.card_id + ext))
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	get_tree().quit(0 if ok else 1)
