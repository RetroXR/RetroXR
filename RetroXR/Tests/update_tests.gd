extends "res://Tests/test_suite.gd"

## The update check: which release is newer, which of its files is ours, whether
## this install can be replaced in place, and the script that does it.
##
##   godot --headless --path RetroXR res://Tests/update_tests.tscn
##   godot --headless --path RetroXR res://Tests/update_tests.tscn -- --only=waiter
##
## No network and no real release: the service is handed its answer. What it
## cannot show is a real download or a real swap on Windows and macOS -- those
## scripts are checked for shape here and run for real only where `sh` exists.

const GROUPS := ["version", "assets", "evaluate", "plan", "waiter", "service", "network"]

## GitHub's answer for v0.9.0, trimmed to what the code reads (2026-10-20).
const RELEASE_JSON := """{
 "tag_name": "v%s", "draft": false, "prerelease": false,
 "html_url": "https://github.com/RetroXR/RetroXR/releases/tag/v%s",
 "body": "**[Full Changelog](https://github.com/x/compare/a...b)**\\n\\nSidequestVR: https://s\\nDiscord: https://d\\n\\n## MAJOR NEW FEATURES\\n\\n## Window\\nFree resizing.\\n\\n## Bug Fixes\\n\\n- fixed a thing\\n\\n## Downloads\\n\\n| Platform | File |\\n|---|---|\\n| Win | x |",
 "assets": [
  {"name": "RetroXR-linux-arm64-v%s.tar.gz", "size": 11, "browser_download_url": "https://x/arm", "digest": "sha256:aa"},
  {"name": "RetroXR-linux-x86_64-v%s.AppImage", "size": 22, "browser_download_url": "https://x/appimage", "digest": "sha256:BB"},
  {"name": "RetroXR-macos-arm64-v%s.zip", "size": 33, "browser_download_url": "https://x/mac", "digest": "sha256:cc"},
  {"name": "RetroXR-v%s.apk", "size": 44, "browser_download_url": "https://x/apk", "digest": "sha256:dd"},
  {"name": "RetroXR-win-v%s.zip", "size": 55, "browser_download_url": "https://x/win", "digest": "sha256:ee"}
 ]}"""

var _only := ""
var _scratch := "user://update_tests"


func _ready() -> void:
	suite_tag = "update"
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[update] TIMEOUT")
		get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(_scratch)
	if _want("version"):
		_test_version()
	if _want("assets"):
		_test_assets()
	if _want("evaluate"):
		_test_evaluate()
	if _want("plan"):
		_test_plan()
	if _want("waiter"):
		_test_waiter()
	if _want("service"):
		await _test_service()
	if _want("network"):
		await _test_network()
	_rmrf(ProjectSettings.globalize_path(_scratch))
	_finish()


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _release(ver: String) -> Dictionary:
	return JSON.parse_string(RELEASE_JSON.replace("%s", ver))


# ── Versions ──────────────────────────────────────────────────────────────────

func _test_version() -> void:
	# Numeric, not lexical: 0.10.0 is later than 0.9.0, which a string compare
	# gets backwards -- and RetroXR is at exactly that step.
	_ok(UpdatePlan.is_newer("0.10.0", "0.9.0"), "version/0.10.0 is newer than 0.9.0")
	_ok(not UpdatePlan.is_newer("0.9.0", "0.10.0"), "version/0.9.0 is not newer than 0.10.0")
	_ok(not UpdatePlan.is_newer("0.10.0", "0.10.0"), "version/equal is not newer")
	_ok(UpdatePlan.is_newer("v1.0.0", "0.99.9"), "version/a leading v is ignored")
	_ok(not UpdatePlan.is_newer("0.10", "0.10.0"), "version/missing parts count as zero")
	_ok(UpdatePlan.is_newer("0.10.1", "0.10"), "version/0.10.1 is newer than 0.10")
	_ok(not UpdatePlan.is_newer("0.11.0-rc1", "0.11.0"), "version/a pre-release is older than its release")
	_ok(UpdatePlan.is_newer("0.11.0", "0.11.0-rc1"), "version/the release is newer than its pre-release")
	_ok(UpdatePlan.is_newer("0.11.0-rc2", "0.11.0-rc1"), "version/rc2 is newer than rc1")
	_ok(UpdatePlan.is_newer("0.11.0-rc10", "0.11.0-rc9"), "version/rc10 is newer than rc9")
	_eq(UpdatePlan.parse_version("1.0.0+build-5").get("pre"), "",
		"version/a '-' in build metadata is not a pre-release")
	_eq(UpdatePlan.parse_version("1.0.0-rc1+build-5").get("pre"), "rc1",
		"version/a pre-release keeps its tag when build metadata follows")
	_ok(not UpdatePlan.is_newer("1.0.0+build-5", "1.0.0"), "version/build metadata is not newer")
	_ok(not UpdatePlan.is_newer("nightly", "0.1.0"), "version/a tag with no number is never newer")
	_ok(not UpdatePlan.is_newer("0.2.0", "garbage"), "version/an unreadable current build is never nagged")
	_ok(not UpdatePlan.is_newer("1..2", "0.1.0"), "version/empty parts are refused")
	_ok(UpdatePlan.parse_version("").is_empty(), "version/empty text is no version")


# ── Assets ────────────────────────────────────────────────────────────────────

func _test_assets() -> void:
	var assets: Array = _release("0.11.0")["assets"]
	var win := UpdatePlan.pick_asset(assets, "Windows", "x86_64")
	_eq(win.get("name"), "RetroXR-win-v0.11.0.zip", "assets/windows takes the win zip")
	_eq(win.get("sha256"), "ee", "assets/the sha256 digest is read off GitHub's field")
	_eq(win.get("size"), 55, "assets/size comes through")
	_eq(UpdatePlan.pick_asset(assets, "Linux", "x86_64").get("name"),
		"RetroXR-linux-x86_64-v0.11.0.AppImage", "assets/linux x86_64 takes the AppImage")
	_eq(UpdatePlan.pick_asset(assets, "Linux", "arm64").get("name"),
		"RetroXR-linux-arm64-v0.11.0.tar.gz", "assets/linux arm64 takes the tarball")
	_eq(UpdatePlan.pick_asset(assets, "macOS", "arm64").get("name"),
		"RetroXR-macos-arm64-v0.11.0.zip", "assets/macOS takes the zip")
	_eq(UpdatePlan.pick_asset(assets, "macOS", "x86_64").get("name"),
		"RetroXR-macos-arm64-v0.11.0.zip", "assets/the macOS zip is universal, so Intel takes it too")
	_ok(UpdatePlan.pick_asset(assets, "Android", "arm64").is_empty(),
		"assets/a headset never gets the apk through this path")
	_ok(UpdatePlan.pick_asset([], "Windows", "x86_64").is_empty(), "assets/no assets, no pick")
	_ok(UpdatePlan.pick_asset(assets, "Windows", "x86_64").get("sha256") != "BB",
		"assets/each digest stays with its own file")
	_eq(UpdatePlan.pick_asset([{"name": "RetroXR-win-v1.zip", "digest": ""}], "Windows",
		"x86_64").get("sha256"), "", "assets/no digest listed means none is claimed")


# ── Evaluate ──────────────────────────────────────────────────────────────────

func _test_evaluate() -> void:
	var v := UpdatePlan.evaluate(_release("0.11.0"), "0.10.0", "Windows", "x86_64")
	_ok(bool(v["ok"]) and bool(v["newer"]), "evaluate/0.11.0 over 0.10.0 is an update")
	_eq(v["version"], "0.11.0", "evaluate/version drops the v")
	_eq((v["asset"] as Dictionary).get("name"), "RetroXR-win-v0.11.0.zip",
		"evaluate/carries the asset for this machine")
	var same := UpdatePlan.evaluate(_release("0.10.0"), "0.10.0", "Windows", "x86_64")
	_ok(bool(same["ok"]) and not bool(same["newer"]), "evaluate/the same version is not an update")
	var older := UpdatePlan.evaluate(_release("0.9.0"), "0.10.0", "Windows", "x86_64")
	_ok(not bool(older["newer"]), "evaluate/an older release (a rollback) is not an update")
	var pre := _release("0.12.0")
	pre["prerelease"] = true
	_ok(not bool(UpdatePlan.evaluate(pre, "0.10.0", "Linux", "x86_64")["ok"]),
		"evaluate/a pre-release is refused")
	var draft := _release("0.12.0")
	draft["draft"] = true
	_ok(not bool(UpdatePlan.evaluate(draft, "0.10.0", "Linux", "x86_64")["ok"]),
		"evaluate/a draft is refused")
	var junk := _release("0.12.0")
	junk["tag_name"] = "nightly"
	_ok(not bool(UpdatePlan.evaluate(junk, "0.10.0", "Linux", "x86_64")["ok"]),
		"evaluate/a tag with no version is refused")
	var notes := str(v["notes"])
	_ok(notes.contains("Free resizing."), "evaluate/notes keep the prose", notes)
	_ok(notes.contains("• fixed a thing"), "evaluate/notes turn list items into bullets", notes)
	_ok(not notes.contains("Full Changelog") and not notes.contains("|") \
		and not notes.contains("Discord") and not notes.contains("Downloads"),
		"evaluate/notes drop the changelog link, chat links and the download table", notes)
	var long_body := "x".repeat(300) + "\n" + "y".repeat(300)
	_ok(UpdatePlan.summarize_notes(long_body, 400).ends_with("…"),
		"evaluate/long notes are cut at a line and say so")


# ── Install plan ──────────────────────────────────────────────────────────────

func _test_plan() -> void:
	var yes := func(_d: String) -> bool: return true
	var no := func(_d: String) -> bool: return false
	var a := UpdatePlan.install_plan("Linux", "/tmp/.mount_x/usr/bin/RetroXR.x86_64",
		"/home/p/RetroXR.AppImage", "RetroXR-linux-x86_64-v1.AppImage", "/u", yes)
	_eq(a["mode"], UpdatePlan.MODE_APPIMAGE, "plan/an AppImage swaps itself")
	_eq(a["target"], "/home/p/RetroXR.AppImage",
		"plan/the target is the APPIMAGE file, not the path inside its mount")
	_eq(a["download_to"], "/home/p/RetroXR.AppImage.update",
		"plan/the new file is staged BESIDE the old, so the swap is one rename")
	_eq(UpdatePlan.install_plan("Linux", "/opt/r/RetroXR.x86_64", "",
		"RetroXR-linux-x86_64-v1.AppImage", "/u", yes)["mode"], UpdatePlan.MODE_NONE,
		"plan/an AppImage asset with no AppImage running cannot be swapped in place")
	_eq(UpdatePlan.install_plan("Linux", "/x/RetroXR.x86_64", "/ro/R.AppImage",
		"RetroXR-linux-x86_64-v1.AppImage", "/u", no)["mode"], UpdatePlan.MODE_NONE,
		"plan/a read-only folder is refused")
	_ok(not str(UpdatePlan.install_plan("Linux", "/x/R", "/ro/R.AppImage",
		"RetroXR-linux-x86_64-v1.AppImage", "/u", no)["reason"]).is_empty(),
		"plan/a refusal says why")
	var t := UpdatePlan.install_plan("Linux", "/opt/r/RetroXR.arm64", "",
		"RetroXR-linux-arm64-v1.tar.gz", "/u", yes)
	_eq([t["mode"], t["target"], t["download_to"]],
		[UpdatePlan.MODE_TAR, "/opt/r", "/u/RetroXR-linux-arm64-v1.tar.gz"],
		"plan/the arm64 tarball unpacks over its own folder")
	var w := UpdatePlan.install_plan("Windows", "C:/Games/RetroXR/RetroXR.exe", "",
		"RetroXR-win-v1.zip", "C:/u", yes)
	_eq([w["mode"], w["target"]], [UpdatePlan.MODE_ZIP, "C:/Games/RetroXR"],
		"plan/windows unpacks over the exe's folder")
	_eq(UpdatePlan.install_plan("Windows", "C:/Program Files/R/RetroXR.exe", "",
		"RetroXR-win-v1.zip", "C:/u", no)["mode"], UpdatePlan.MODE_NONE,
		"plan/a folder that needs administrator rights is refused")
	var m := UpdatePlan.install_plan("macOS", "/Applications/RetroXR.app/Contents/MacOS/RetroXR",
		"", "RetroXR-macos-arm64-v1.zip", "/u", yes)
	_eq([m["mode"], m["target"]], [UpdatePlan.MODE_MAC_APP, "/Applications/RetroXR.app"],
		"plan/macOS swaps the whole bundle")
	_eq(UpdatePlan.install_plan("macOS", "/Users/p/godot/RetroXR", "",
		"RetroXR-macos-arm64-v1.zip", "/u", yes)["mode"], UpdatePlan.MODE_NONE,
		"plan/a binary that is not inside an app bundle is refused")
	_eq(UpdatePlan.install_plan("Windows", "C:/R.exe", "", "", "C:/u", yes)["mode"],
		UpdatePlan.MODE_NONE, "plan/a release with no file for this machine is refused")
	_eq(UpdatePlan.install_plan("Android", "/x", "", "RetroXR-v1.apk", "/u", yes)["mode"],
		UpdatePlan.MODE_NONE, "plan/a headset is never updated in place")


# ── The waiter ────────────────────────────────────────────────────────────────

func _test_waiter() -> void:
	var args := PackedStringArray(["--rendering-driver", "vulkan"])
	var win_plan := {"mode": UpdatePlan.MODE_ZIP, "target": "C:/Games/O'Neil/R"}
	var cmd := UpdatePlan.waiter_command(win_plan, "Windows", 4242, "C:/Games/O'Neil/R/RetroXR.exe",
		"C:/u/R.zip", args)
	_eq(cmd[0], "powershell.exe", "waiter/windows runs PowerShell")
	var script := str((cmd[1] as PackedStringArray)[-1])
	_ok(script.begins_with("Wait-Process -Id 4242"), "waiter/windows waits for the process first", script)
	_ok(script.contains("'C:/Games/O''Neil/R'"), "waiter/windows doubles a single quote in a path", script)
	_ok(script.find("tar.exe") < script.find("Start-Process"),
		"waiter/windows unpacks BEFORE it starts the app", script)
	_ok(script.contains("\"--rendering-driver\" \"vulkan\""), "waiter/windows carries the arguments", script)
	# A missing tar.exe throws: the cmdlet must not be inside that try.
	var tar_try := script.find("try { & tar.exe")
	var tar_end := script.find("}", tar_try)
	_ok(tar_try >= 0 and script.find("Expand-Archive") > tar_end,
		"waiter/windows falls back to Expand-Archive OUTSIDE tar.exe's try", script)
	_ok(script.find("if ($ok) { Remove-Item") >= 0,
		"waiter/windows deletes the zip only once something unpacked it", script)
	var odd := UpdatePlan.waiter_command(win_plan, "Windows", 1, "C:/R/RetroXR.exe", "C:/u/R.zip",
		PackedStringArray(["--carry=C:/Users/O'Brien/c.json", "say \"hi\"", "C:\\dir\\"]))
	var odd_script := str((odd[1] as PackedStringArray)[-1])
	_ok(odd_script.contains("-ArgumentList '\"--carry=C:/Users/O''Brien/c.json\" "),
		"waiter/windows doubles an argument's single quote ONCE", odd_script)
	_eq(UpdatePlan.win_arg("say \"hi\""), "\"say \\\"hi\\\"\"", "waiter/windows escapes a double quote")
	_eq(UpdatePlan.win_arg("C:\\dir\\"), "\"C:\\dir\\\\\"",
		"waiter/windows doubles a trailing backslash before the closing quote")
	_eq(UpdatePlan.win_arg("a\\\"b"), "\"a\\\\\\\"b\"", "waiter/windows doubles backslashes before a quote")
	_eq(UpdatePlan.waiter_command({"mode": UpdatePlan.MODE_NONE}, "Linux", 1, "/x", "/y", args),
		[], "waiter/no plan, no waiter")
	var mac := UpdatePlan.waiter_command({"mode": UpdatePlan.MODE_MAC_APP, "target": "/A/R.app"},
		"macOS", 7, "/A/R.app/Contents/MacOS/R", "/u/R.zip", args)
	var mac_script := str((mac[1] as PackedStringArray)[1])
	_ok(mac_script.contains("app=$3\nshift 3\nexec open \"$app\""),
		"waiter/macOS keeps the bundle path before shifting its arguments away", mac_script)
	_ok(mac_script.contains("mv \"$3\" \"$3.old\""), "waiter/macOS moves the old bundle aside, not over", mac_script)
	if OS.get_name() == "Windows":
		return
	_run_swap_for_real()


## The Linux scripts run for real: a fake "AppImage" that writes which version it
## is, a staged replacement, and a process id that is already gone.
func _run_swap_for_real() -> void:
	var dir := ProjectSettings.globalize_path(_scratch).path_join("swap")
	DirAccess.make_dir_recursive_absolute(dir)
	var out := dir.path_join("ran.txt")
	var target := dir.path_join("RetroXR.AppImage")
	_write(target, "#!/bin/sh\necho old \"$@\" > '%s'\n" % out, true)
	_write(target + ".update", "#!/bin/sh\necho new \"$@\" > '%s'\n" % out, false)
	var plan := {"mode": UpdatePlan.MODE_APPIMAGE, "target": target}
	var cmd := UpdatePlan.waiter_command(plan, "Linux", 2147483646, target,
		target + ".update", PackedStringArray(["--flag"]))
	_ok(_run(cmd), "waiter/AppImage swap runs to the end")
	_eq(_read(out).strip_edges(), "new --flag",
		"waiter/AppImage: the NEW build is what starts, with the arguments")
	_ok(not FileAccess.file_exists(target + ".update"), "waiter/AppImage: the staged file is consumed")

	# A swap that cannot happen still starts the old build.
	_write(out, "", false)
	_write(target, "#!/bin/sh\necho old \"$@\" > '%s'\n" % out, true)
	cmd = UpdatePlan.waiter_command(plan, "Linux", 2147483646, target,
		target + ".missing", PackedStringArray())
	_run(cmd)
	_eq(_read(out).strip_edges(), "old", "waiter/AppImage: a failed swap still brings the old app back")

	var tar_dir := dir.path_join("opt")
	DirAccess.make_dir_recursive_absolute(tar_dir)
	_write(tar_dir.path_join("RetroXR.arm64"), "#!/bin/sh\necho oldbin > '%s'\n" % out, true)
	var payload := dir.path_join("payload")
	DirAccess.make_dir_recursive_absolute(payload)
	_write(payload.path_join("RetroXR.arm64"), "#!/bin/sh\necho newbin > '%s'\n" % out, true)
	var archive := dir.path_join("R.tar.gz")
	OS.execute("tar", ["-C", payload, "-czf", archive, "."])
	var tplan := {"mode": UpdatePlan.MODE_TAR, "target": tar_dir}
	cmd = UpdatePlan.waiter_command(tplan, "Linux", 2147483646, tar_dir.path_join("RetroXR.arm64"),
		archive, PackedStringArray())
	_run(cmd)
	_eq(_read(out).strip_edges(), "newbin", "waiter/tarball: unpacked over the folder, then the new binary runs")
	_ok(not FileAccess.file_exists(archive), "waiter/tarball: the archive is removed")


## Start a waiter the way the app does (OS.create_process) and wait for it. Not
## OS.execute: on 4.7 that drops every argument after a shell's script, which is
## not how the app starts it and would test a different thing.
func _run(cmd: Array) -> bool:
	var pid := OS.create_process(str(cmd[0]), cmd[1])
	if pid < 0:
		return false
	var waited := 0
	while OS.is_process_running(pid) and waited < 8000:
		OS.delay_msec(50)
		waited += 50
	return not OS.is_process_running(pid)


# ── The service ───────────────────────────────────────────────────────────────

func _service(version: String, body: String, ok := true) -> AppUpdateService:
	var prefs := ProjectSettings.globalize_path(_scratch).path_join("prefs_%d.json" % randi())
	_write(prefs, '{"check_on_start": false}', false)
	var svc := AppUpdateService.new()
	svc.prefs_path = prefs
	svc.current_version = version
	svc.os_name = "Windows"
	svc.arch = "x86_64"
	svc.allow_in_editor = true
	svc.opener = func(_url: String) -> void: svc.set_meta("opened", true)
	svc.fetcher = func(_url: String, done: Callable) -> void:
		done.call(ok, body, "" if ok else "Could not reach GitHub.")
	add_child(svc)
	return svc


func _test_service() -> void:
	var newer := _service("0.10.0", RELEASE_JSON.replace("%s", "0.11.0"))
	var announced := [0]
	newer.announced.connect(func() -> void: announced[0] += 1)
	_ok(newer.supported(), "service/supported when driven as an install")
	newer.check()
	_eq(newer.state, AppUpdateService.State.AVAILABLE, "service/a newer release becomes AVAILABLE")
	_eq(newer.available_version(), "0.11.0", "service/it knows the version")
	_eq(announced[0], 1, "service/it announces once")
	newer.check()
	_eq(announced[0], 1, "service/a second check does not announce again")
	_ok(newer.wants_attention(), "service/the banner shows")
	newer.postpone()
	_ok(not newer.wants_attention(), "service/Later hides the banner")
	newer.check(true)
	_ok(newer.wants_attention(), "service/a manual check brings it back")
	newer.skip_this_version()
	_ok(not newer.wants_attention(), "service/Skip hides it")
	var again := AppUpdateService.new()
	again.prefs_path = newer.prefs_path
	again._load_prefs()
	_eq(again.skipped_version, "0.11.0", "service/the skipped version is remembered")
	again.free()

	var same := _service("0.11.0", RELEASE_JSON.replace("%s", "0.11.0"))
	same.check()
	_eq(same.state, AppUpdateService.State.UP_TO_DATE, "service/the same version is UP_TO_DATE")
	_ok(not same.wants_attention(), "service/up to date shows nothing")
	_eq(same.install(), "There is no update to install.", "service/nothing to install when up to date")

	var down := _service("0.10.0", "", false)
	down.check()
	_eq(down.state, AppUpdateService.State.FAILED, "service/an unreachable GitHub is FAILED")
	_ok(not down.wants_attention(), "service/a failed CHECK never raises the banner")
	_ok(not down.error.is_empty(), "service/but the ABOUT tab can say why")

	var junk := _service("0.10.0", "<html>rate limited</html>")
	junk.check()
	_eq(junk.state, AppUpdateService.State.FAILED, "service/an answer that is not JSON is FAILED")

	# No file for this machine: install() sends the player to the page, downloads nothing.
	var body := RELEASE_JSON.replace("%s", "0.11.0").replace("RetroXR-win-v0.11.0.zip", "other.zip")
	var nofile := _service("0.10.0", body)
	nofile.check()
	_eq(nofile.state, AppUpdateService.State.AVAILABLE, "service/no file for us is still AVAILABLE")
	_ok(not nofile.can_auto_install(), "service/but cannot install by itself")
	var why := nofile.install()
	_ok(not why.is_empty() and nofile.has_meta("opened"),
		"service/it opens the release page and says why, instead of downloading", why)
	_eq(nofile.state, AppUpdateService.State.AVAILABLE, "service/and stays AVAILABLE")

	# A download that does not match GitHub's digest is thrown away.
	var bad := _service("0.10.0", RELEASE_JSON.replace("%s", "0.11.0"))
	bad.check()
	var staged := ProjectSettings.globalize_path(_scratch).path_join("staged.bin")
	_write(staged, "payload", false)
	bad._download_to = staged
	bad._on_verified(FileAccess.get_sha256(staged), "00" + "ff".repeat(31))
	_eq(bad.state, AppUpdateService.State.FAILED, "service/a wrong checksum is FAILED")
	_ok(bad.install_failed and bad.wants_attention(), "service/and the banner says so")
	_ok(not FileAccess.file_exists(staged), "service/and the bad file is deleted")

	# A matching digest (compared without regard to case) goes on to restart; in a
	# suite the room is not ready, so the restart is refused and it waits in READY.
	var good := _service("0.10.0", RELEASE_JSON.replace("%s", "0.11.0"))
	good.check()
	_write(staged, "payload", false)
	good._download_to = staged
	good._on_verified(FileAccess.get_sha256(staged).to_upper(), FileAccess.get_sha256(staged))
	_eq(good.state, AppUpdateService.State.READY, "service/a matching checksum reaches READY")
	_ok(not good.error.is_empty(), "service/a refused restart says why", good.error)
	_ok(FileAccess.file_exists(staged), "service/and keeps the download for the retry")
	good.check(true)
	_eq(good.state, AppUpdateService.State.READY, "service/a check while READY keeps the download")

	# No digest listed: nothing it cannot check replaces the app.
	var nodigest := _service("0.10.0", RELEASE_JSON.replace("%s", "0.11.0")
		.replace("\"digest\": \"sha256:ee\"", "\"digest\": \"\""))
	nodigest.check()
	_eq(nodigest.state, AppUpdateService.State.AVAILABLE, "service/no digest is still AVAILABLE")
	_ok(not nodigest.can_auto_install() and nodigest.manual_reason().contains("checksum"),
		"service/but is not installed in place", nodigest.manual_reason())
	var unsure := _service("0.10.0", RELEASE_JSON.replace("%s", "0.11.0"))
	unsure.check()
	_write(staged, "payload", false)
	unsure._download_to = staged
	unsure._on_verified(FileAccess.get_sha256(staged), "")
	_eq(unsure.state, AppUpdateService.State.FAILED, "service/a download with no checksum is FAILED")
	_ok(not FileAccess.file_exists(staged), "service/and is deleted, never installed")

	for s: AppUpdateService in [newer, same, down, junk, nofile, bad, good]:
		s.queue_free()
	await get_tree().process_frame


# ── The network, for real ─────────────────────────────────────────────────────
# A server of our own on loopback, so the default fetcher and the real download
# (HTTPRequest, a redirect like GitHub's, progress, the checksum) are exercised
# rather than injected away.

var _tcp: TCPServer = null
var _routes: Dictionary = {}
var _clients: Array = []


func _serve_start() -> int:
	_tcp = TCPServer.new()
	_tcp.listen(0, "127.0.0.1")
	return _tcp.get_local_port()


func _serve_poll() -> void:
	while _tcp.is_connection_available():
		_clients.append({"peer": _tcp.take_connection(), "buf": ""})
	for c: Dictionary in _clients.duplicate():
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			c["buf"] += peer.get_utf8_string(n)
		if not (c["buf"] as String).contains("\r\n\r\n"):
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_clients.erase(c)
			continue
		var path := (c["buf"] as String).split(" ")[1]
		var route: Array = _routes.get(path, [404, {}, PackedByteArray()])
		var head := "HTTP/1.1 %d X\r\nContent-Length: %d\r\nConnection: close\r\n" \
			% [route[0], (route[2] as PackedByteArray).size()]
		for k: String in route[1]:
			head += "%s: %s\r\n" % [k, route[1][k]]
		peer.put_data((head + "\r\n").to_utf8_buffer())
		peer.put_data(route[2])
		peer.disconnect_from_host()
		_clients.erase(c)


func _until(cond: Callable, seconds := 20.0) -> bool:
	var waited := 0.0
	while not cond.call() and waited < seconds:
		_serve_poll()
		await get_tree().process_frame
		waited += get_process_delta_time()
	return cond.call()


func _test_network() -> void:
	var port := _serve_start()
	var base := "http://127.0.0.1:%d" % port
	var payload := PackedByteArray()
	payload.resize(3 * 1024 * 1024)
	for i in payload.size():
		payload[i] = (i * 31 + 7) & 0xFF
	var digest := _sha256(payload)

	var dir := ProjectSettings.globalize_path(_scratch).path_join("net")
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("RetroXR.AppImage"), "old", true)

	var release := _release("0.11.0")
	for a: Dictionary in release["assets"]:
		a["browser_download_url"] = base + "/dl/" + str(a["name"])
		if str(a["name"]).ends_with(".AppImage"):
			a["size"] = payload.size()
			a["digest"] = "sha256:" + digest
	_routes["/latest"] = [200, {}, JSON.stringify(release).to_utf8_buffer()]
	# GitHub answers a release asset with a redirect to its storage.
	_routes["/dl/RetroXR-linux-x86_64-v0.11.0.AppImage"] = [302,
		{"Location": base + "/blob"}, PackedByteArray()]
	_routes["/blob"] = [200, {}, payload]

	var svc := AppUpdateService.new()
	var prefs := ProjectSettings.globalize_path(_scratch).path_join("net_prefs.json")
	_write(prefs, '{"check_on_start": false}', false)
	svc.prefs_path = prefs
	svc.current_version = "0.10.0"
	svc.os_name = "Linux"
	svc.arch = "x86_64"
	svc.allow_in_editor = true
	svc.skip_room_check = true
	svc.appimage = dir.path_join("RetroXR.AppImage")
	svc.api_url = base + "/latest"
	add_child(svc)

	var fractions: Array = []
	svc.progress_changed.connect(func(f: float) -> void: fractions.append(f))
	svc.check()
	_ok(await _until(func() -> bool: return svc.state != AppUpdateService.State.CHECKING),
		"network/the real fetcher gets an answer")
	_ok(svc.state == AppUpdateService.State.AVAILABLE, "network/a release served over HTTP is AVAILABLE", svc.error)
	_ok(svc.can_auto_install(), "network/an AppImage run can update itself", svc.manual_reason())

	_eq(svc.install(), "", "network/install starts")
	_eq(svc.state, AppUpdateService.State.DOWNLOADING, "network/and is DOWNLOADING")
	_ok(await _until(func() -> bool: return svc.state not in [
		AppUpdateService.State.DOWNLOADING, AppUpdateService.State.VERIFYING]),
		"network/the download finishes", str(svc.state))
	_ok(svc.state == AppUpdateService.State.READY, "network/a good download is READY (the restart is refused: no room)", svc.error)
	var staged := dir.path_join("RetroXR.AppImage.update")
	_ok(FileAccess.file_exists(staged), "network/it is staged beside the AppImage")
	_eq(FileAccess.get_sha256(staged), digest, "network/and is byte for byte what was served")
	# Loopback finishes a few MB in a frame or two, so this checks the reports are
	# sane rather than how many there were.
	_ok(not fractions.is_empty() and fractions.all(func(f: float) -> bool: return f >= 0.0 and f <= 1.0),
		"network/progress was reported, within 0..1", str(fractions))
	_eq(_read(dir.path_join("RetroXR.AppImage")), "old", "network/the running AppImage is untouched until the restart")

	# Same file, wrong digest on the release: thrown away.
	svc.queue_free()
	var bad := (release["assets"] as Array).filter(func(a: Dictionary) -> bool:
		return str(a["name"]).ends_with(".AppImage"))[0] as Dictionary
	bad["digest"] = "sha256:" + "00".repeat(32)
	_routes["/latest"] = [200, {}, JSON.stringify(release).to_utf8_buffer()]
	var svc2 := AppUpdateService.new()
	svc2.prefs_path = prefs
	svc2.current_version = "0.10.0"
	svc2.os_name = "Linux"
	svc2.arch = "x86_64"
	svc2.allow_in_editor = true
	svc2.skip_room_check = true
	svc2.appimage = dir.path_join("RetroXR.AppImage")
	svc2.api_url = base + "/latest"
	add_child(svc2)
	svc2.check()
	await _until(func() -> bool: return svc2.state != AppUpdateService.State.CHECKING)
	svc2.install()
	await _until(func() -> bool: return svc2.state not in [
		AppUpdateService.State.DOWNLOADING, AppUpdateService.State.VERIFYING])
	_eq(svc2.state, AppUpdateService.State.FAILED, "network/a download that fails GitHub's checksum is FAILED")
	_ok(not FileAccess.file_exists(staged), "network/and nothing is left staged")

	# A server that is not there.
	var dead := AppUpdateService.new()
	dead.prefs_path = prefs
	dead.current_version = "0.10.0"
	dead.os_name = "Linux"
	dead.arch = "x86_64"
	dead.allow_in_editor = true
	dead.api_url = "http://127.0.0.1:1/latest"
	add_child(dead)
	dead.check()
	await _until(func() -> bool: return dead.state != AppUpdateService.State.CHECKING)
	_eq(dead.state, AppUpdateService.State.FAILED, "network/a refused connection is FAILED, not a hang")
	_ok(not dead.wants_attention(), "network/and says nothing at launch")

	svc2.queue_free()
	dead.queue_free()
	_tcp.stop()
	await get_tree().process_frame


func _sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


# ── Files ─────────────────────────────────────────────────────────────────────

func _write(path: String, text: String, executable: bool) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f = null
	if executable:
		FileAccess.set_unix_permissions(path, FileAccess.UNIX_READ_OWNER \
			| FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _rmrf(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_rmrf(dir.path_join(sub))
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir)
