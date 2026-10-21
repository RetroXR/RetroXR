## AppUpdateService -- is a newer RetroXR out, and can this install take it.
##
## An autoload (`AppUpdate`), for the reason Modio is one: a download must not be
## cancelled by walking through a door, and this node is what the banner, the
## ABOUT tab and the HUD toast all read from rather than three copies of the state.
## Desktop builds only; a headset updates through its store.
##
## The flow, which is the whole file:
##   check()     ask GitHub for RetroXR/RetroXR's latest release (UpdatePlan.REPO)
##   AVAILABLE   a newer one exists; `announced` fires once so the HUD can say so
##   install()   the player said yes: download it beside what it replaces, check its
##               sha256 against the digest GitHub lists, then hand over to a waiter
##               (UpdatePlan.waiter_command) and quit; the room is carried across
##               exactly as a mods restart carries it (SceneManager.restart_app)
## Anything that cannot be done in place (a read-only folder, a build that is not an
## AppImage, a platform without a plan) falls back to opening the release page.
##
## Nothing here touches the network until check() runs, and the startup check can
## be switched off. Nothing is installed without the player pressing the button.
class_name AppUpdateService
extends Node

## The release was found, newer than this build, and not one the player skipped.
## Once per run -- the HUD toast hangs off it.
signal announced
signal state_changed
signal progress_changed(fraction: float)

enum State {
	IDLE,
	CHECKING,
	UP_TO_DATE,
	AVAILABLE,
	DOWNLOADING,
	VERIFYING,
	## Downloaded and checked; the restart that swaps it in has not happened (the
	## room was busy, or the player has not pressed Restart yet).
	READY,
	INSTALLING,
	FAILED,
}

const PREFS_PATH := "user://app_update.json"
const STAGING_DIR := "user://update"
## After the room has come up and the loading curtain is down.
const STARTUP_DELAY := 8.0
const REQUEST_TIMEOUT := 20.0

var state: State = State.IDLE
## UpdatePlan.evaluate() of the newest release, {} before the first answer.
var release: Dictionary = {}
## Why the last check or install failed, "" otherwise.
var error := ""
## True once an INSTALL (not a check) has failed -- the banner shows that one.
var install_failed := false
var check_on_start := true
var skipped_version := ""
## "Later": hide the banner for this run, ask again next launch.
var postponed := false

## (url: String, done: Callable(ok: bool, body: String, why: String)). Replaced by a
## test; the default is an HTTPRequest.
var fetcher: Callable
var prefs_path := PREFS_PATH
## Opens the release page; replaced by a test, which must not open a browser.
var opener: Callable = OS.shell_open
var current_version := ""
var os_name := ""
var arch := ""
## An editor run is not an install, so it never checks by itself; a test turns this on.
var allow_in_editor := false
## Where to ask for the latest release; "" is GitHub's (UpdatePlan.latest_url). A test
## points it at a server of its own.
var api_url := ""
## A test has no room to restart out of, so it cannot wait for one.
var skip_room_check := false
## The AppImage this run came from, "" to read the APPIMAGE variable. A test sets it
## instead of the variable: setenv is not safe beside the engine's worker threads,
## and changing it under them corrupted the heap at exit.
var appimage := ""

var _plan: Dictionary = {}
var _announced := false
var _http: HTTPRequest = null
var _download_to := ""
var _last_progress := -1.0
var _hash_task := -1


func _ready() -> void:
	# Set already, a test is driving it as another machine.
	if current_version.is_empty():
		current_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	if os_name.is_empty():
		os_name = OS.get_name()
	if arch.is_empty():
		arch = Engine.get_architecture_name()
	_load_prefs()
	if not supported():
		return
	_sweep_leftovers()
	if check_on_start:
		get_tree().create_timer(STARTUP_DELAY).timeout.connect(func() -> void: check(false))


## Whether this run can update at all: a desktop OS, and an installed build (an
## editor or a dev checkout has nothing to replace and would nag every launch).
func supported() -> bool:
	if os_name not in ["Windows", "Linux", "macOS"]:
		return false
	return OS.has_feature("template") or allow_in_editor \
		or OS.has_environment("RETROXR_UPDATE_TEST")


## The banner shows for these. A failed CHECK is not one of them -- it says so on
## the ABOUT tab, but a launch with no network should not open with a red bar.
func wants_attention() -> bool:
	match state:
		State.AVAILABLE:
			return not postponed and str(release.get("version", "")) != skipped_version
		State.DOWNLOADING, State.VERIFYING, State.READY, State.INSTALLING:
			return true
		State.FAILED:
			return install_failed
	return false


func available_version() -> String:
	return str(release.get("version", ""))


## Whether install() can finish the job without the player doing anything by hand.
func can_auto_install() -> bool:
	return str(_plan.get("mode", UpdatePlan.MODE_NONE)) != UpdatePlan.MODE_NONE


## Why it cannot, "" when it can.
func manual_reason() -> String:
	return str(_plan.get("reason", ""))


# ── Checking ──────────────────────────────────────────────────────────────────

## `manual` is the ABOUT tab's button: it brings back a banner the player said
## "Later" to. A failure is kept in `error` either way; only an install failure
## raises the banner.
func check(manual: bool = true) -> void:
	# READY holds a checked download waiting on a restart; asking again would put
	# it back to AVAILABLE and the next install() would fetch it all over again.
	if state in [State.CHECKING, State.DOWNLOADING, State.VERIFYING, State.READY,
			State.INSTALLING]:
		return
	if manual:
		postponed = false
	error = ""
	_set_state(State.CHECKING)
	var done := func(ok: bool, body: String, why: String) -> void: _on_release(ok, body, why)
	var url := api_url if not api_url.is_empty() else UpdatePlan.latest_url()
	if fetcher.is_valid():
		fetcher.call(url, done)
	else:
		_fetch(url, done)


func _on_release(ok: bool, body: String, why: String) -> void:
	if state != State.CHECKING:
		return
	if not ok:
		error = why
		_set_state(State.FAILED)
		return
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(body) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY:
		error = "GitHub's answer could not be read."
		_set_state(State.FAILED)
		return
	var verdict := UpdatePlan.evaluate(parsed, current_version, os_name, arch)
	if not bool(verdict.get("ok", false)):
		error = str(verdict.get("error", "Unreadable release."))
		_set_state(State.FAILED)
		return
	release = verdict
	if not bool(verdict["newer"]):
		_set_state(State.UP_TO_DATE)
		return
	_plan = UpdatePlan.install_plan(os_name, OS.get_executable_path(),
		_appimage(), str((verdict["asset"] as Dictionary).get("name", "")),
		ProjectSettings.globalize_path(STAGING_DIR), _can_write)
	# A file GitHub lists no digest for cannot be checked, and an unchecked file
	# never replaces the app: the player gets the release page instead.
	if can_auto_install() and str((verdict["asset"] as Dictionary).get("sha256", "")).is_empty():
		_plan = {"mode": UpdatePlan.MODE_NONE, "target": "", "download_to": "",
			"reason": "GitHub lists no checksum for this release's download, so it "
			+ "cannot be checked here."}
	_set_state(State.AVAILABLE)
	if wants_attention() and not _announced:
		_announced = true
		announced.emit()


func _fetch(url: String, done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS:
				done.call(false, "", "Could not reach GitHub.")
			elif code == 403 or code == 429:
				done.call(false, "", "GitHub is limiting requests from this address. Try later.")
			elif code < 200 or code >= 300:
				done.call(false, "", "GitHub answered %d." % code)
			else:
				done.call(true, body.get_string_from_utf8(), ""))
	var err := http.request(url, _headers())
	if err != OK:
		http.queue_free()
		done.call(false, "", "Could not start the request.")


func _headers() -> PackedStringArray:
	return PackedStringArray(["Accept: application/vnd.github+json",
		"User-Agent: RetroXR/%s" % current_version])


# ── The player's answer ───────────────────────────────────────────────────────

func postpone() -> void:
	postponed = true
	state_changed.emit()


func skip_this_version() -> void:
	skipped_version = available_version()
	_save_prefs()
	state_changed.emit()


func set_check_on_start(on: bool) -> void:
	check_on_start = on
	_save_prefs()


func open_release_page() -> void:
	opener.call(str(release.get("page", UpdatePlan.releases_page())))


## Download the update and restart into it. Returns "" once under way, else why not
## (and, where nothing can be done in place, having opened the release page).
func install() -> String:
	if state == State.READY:
		return _restart_into_update()
	if state not in [State.AVAILABLE, State.FAILED] or not bool(release.get("newer", false)):
		return "There is no update to install."
	if not can_auto_install():
		open_release_page()
		return manual_reason()
	var why := _blocker()
	if not why.is_empty():
		return why
	var asset: Dictionary = release["asset"]
	_download_to = str(_plan["download_to"])
	DirAccess.make_dir_recursive_absolute(_download_to.get_base_dir())
	if FileAccess.file_exists(_download_to):
		DirAccess.remove_absolute(_download_to)
	install_failed = false
	error = ""
	_last_progress = -1.0
	_http = HTTPRequest.new()
	_http.download_file = _download_to
	_http.timeout = 0.0
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_downloaded.bind(asset))
	if _http.request(str(asset["url"]), _headers()) != OK:
		_http.queue_free()
		_http = null
		return _fail_install("Could not start the download.")
	_set_state(State.DOWNLOADING)
	set_process(true)
	return ""


## What stops an install from starting. The same two things a restart refuses for,
## asked BEFORE a few hundred megabytes are fetched.
func _blocker() -> String:
	if has_node("/root/NetworkManager") and NetworkManager.is_active():
		return "Leave the netplay session first."
	if not skip_room_check and has_node("/root/SceneManager") \
			and not SceneManager.is_scene_content_ready(
			SceneManager.current_scene_id):
		return "Wait for the room to finish loading."
	return ""


func _process(_delta: float) -> void:
	if state != State.DOWNLOADING or _http == null:
		set_process(false)
		return
	var total := int((release.get("asset", {}) as Dictionary).get("size", 0))
	if total <= 0:
		total = _http.get_body_size()
	if total <= 0:
		return
	var frac := clampf(float(_http.get_downloaded_bytes()) / float(total), 0.0, 1.0)
	if absf(frac - _last_progress) >= 0.005:
		_last_progress = frac
		progress_changed.emit(frac)


func _on_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray,
		asset: Dictionary) -> void:
	if _http != null:
		_http.queue_free()
		_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_discard_download()
		_fail_install("The download did not finish.")
		return
	var want := int(asset.get("size", 0))
	var got := FileAccess.open(_download_to, FileAccess.READ)
	var have := got.get_length() if got != null else -1
	got = null
	if want > 0 and have != want:
		_discard_download()
		_fail_install("The download is %d bytes; expected %d." % [have, want])
		return
	_set_state(State.VERIFYING)
	var path := _download_to
	var expected := str(asset.get("sha256", ""))
	_hash_task = WorkerThreadPool.add_task(func() -> void:
		var digest := FileAccess.get_sha256(path)
		_on_verified.call_deferred(digest, expected))


func _on_verified(digest: String, expected: String) -> void:
	# A pool task must be waited for even once it has finished; one that never is
	# keeps its callable until the pool is torn down at exit, after the node it
	# captured is long gone.
	if _hash_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_hash_task)
		_hash_task = -1
	if expected.is_empty():
		_discard_download()
		_fail_install("GitHub lists no checksum for the download, so it was thrown away.")
		return
	if digest.to_lower() != expected.to_lower():
		_discard_download()
		_fail_install("The download does not match GitHub's checksum, so it was thrown away.")
		return
	_set_state(State.READY)
	var why := _restart_into_update()
	if not why.is_empty():
		error = why
		state_changed.emit()


func _restart_into_update() -> String:
	if not has_node("/root/SceneManager"):
		return "The app cannot restart from here."
	var plan := _plan
	var download := _download_to
	var relaunch := func(pid: int, exe: String, args: PackedStringArray) -> Array:
		return UpdatePlan.waiter_command(plan, os_name, pid, exe, download, args)
	var why: String = SceneManager.restart_app(PackedStringArray(), Callable(), relaunch)
	if why.is_empty():
		error = ""
		_set_state(State.INSTALLING)
	else:
		error = why
		state_changed.emit()
	return why


func _fail_install(why: String) -> String:
	install_failed = true
	error = why
	_set_state(State.FAILED)
	return why


func _discard_download() -> void:
	if not _download_to.is_empty() and FileAccess.file_exists(_download_to):
		DirAccess.remove_absolute(_download_to)


# ── Housekeeping ──────────────────────────────────────────────────────────────

func _set_state(s: State) -> void:
	state = s
	state_changed.emit()


## A download that never got installed (a crash, a refused restart) is a few hundred
## megabytes nobody asked to keep. This runs at launch, when no waiter can still
## want the file.
func _sweep_leftovers() -> void:
	var dir := DirAccess.open(STAGING_DIR)
	if dir != null:
		for f: String in dir.get_files():
			dir.remove(f)
	var image := _appimage()
	if not image.is_empty() and FileAccess.file_exists(image + ".update"):
		DirAccess.remove_absolute(image + ".update")


func _appimage() -> String:
	return appimage if not appimage.is_empty() else OS.get_environment("APPIMAGE")


static func _can_write(folder: String) -> bool:
	var probe := folder.path_join(".retroxr_write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f = null
	DirAccess.remove_absolute(probe)
	return true


func _load_prefs() -> void:
	var data := JsonStore.read_dict(prefs_path, "AppUpdate")
	check_on_start = JsonStore.get_bool(data, "check_on_start", true)
	skipped_version = JsonStore.get_string(data, "skipped_version", "")


func _save_prefs() -> void:
	JsonStore.write_dict(prefs_path, {
		"check_on_start": check_on_start,
		"skipped_version": skipped_version,
	}, "AppUpdate")
