## Serves a SCRATCH data folder with the real WebFileServer, for
## Tools/art/film_web_upload.py to film the welcome page's upload clip
## (Welcome2D.UPLOAD_CLIP) in a browser: the same pages, PIN and upload a Quest's
## Web File Manager serves, over a folder that is not the player's.
##
## The data root is redirected with DataPaths' test seam to <scratch>/data, laid out
## as a fresh install's (roms/<system>/ for a few systems, books, videos ...), and
## the server runs with PIN 1234 until <scratch>/stop appears or 10 minutes pass.
##
##     "$godot" --headless --path RetroXR res://Tools/net/web_upload_probe.tscn -- \
##         --scratch=/tmp/webfilm [--port=8080]
extends Node

const PIN := "1234"
const SYSTEMS: Array[String] = ["gb", "gba", "genesis", "n64", "nes", "psx", "snes"]
const MEDIA: Array[String] = ["books", "videos", "dvd", "music", "posters"]

var _srv: WebFileServer = null
var _stop := ""


func _ready() -> void:
	var scratch := ""
	var port := WebFileServer.DEFAULT_PORT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scratch="):
			scratch = a.trim_prefix("--scratch=")
		elif a.begins_with("--port="):
			port = int(a.trim_prefix("--port="))
	if scratch.is_empty():
		print("[webprobe] FAIL --scratch=<dir> is required: it never serves the player's own folder")
		get_tree().quit(1)
		return
	var data := scratch.path_join("data")
	for system: String in SYSTEMS:
		DirAccess.make_dir_recursive_absolute(data.path_join("roms").path_join(system))
	for m: String in MEDIA:
		DirAccess.make_dir_recursive_absolute(data.path_join(m))
	var cfg := scratch.path_join("data_root.json")
	JsonStore.write_dict(cfg, {"path": data, "pending_move_from": ""}, "webprobe")
	DataPaths.set_config_path_for_tests(cfg)
	if WebFileServer.server_root() != DataPaths.normalize(data):
		print("[webprobe] FAIL the server would serve %s, not the scratch %s" % [WebFileServer.server_root(), data])
		get_tree().quit(1)
		return
	_stop = scratch.path_join("stop")
	DirAccess.remove_absolute(_stop)
	_srv = WebFileServer.new()
	_srv.pin = PIN
	add_child(_srv)
	if not _srv.start(port):
		print("[webprobe] FAIL the server did not start on %d" % port)
		get_tree().quit(1)
		return
	print("[webprobe] serving %s on http://localhost:%d  PIN %s" % [data, port, PIN])
	get_tree().create_timer(600.0).timeout.connect(_finish)


func _process(_delta: float) -> void:
	if not _stop.is_empty() and FileAccess.file_exists(_stop):
		_finish()


func _finish() -> void:
	_stop = ""
	if _srv != null:
		_srv.stop()
	DataPaths.set_config_path_for_tests("")
	print("[webprobe] stopped")
	get_tree().quit(0)
