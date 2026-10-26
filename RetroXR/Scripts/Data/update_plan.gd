## UpdatePlan -- the decisions behind "a newer RetroXR is out", with no network,
## no window and no node in them.
##
## Everything AppUpdateService has to DECIDE lives here as a static function of
## plain values: is this tag newer than this build, which of the release's files
## is for this machine, can this install be replaced in place, and what small
## script swaps the files once the running process has gone. The service does the
## fetching and the waiting; whether it is RIGHT is checkable here without a
## release, a download or a second machine (Tests/update_tests).
class_name UpdatePlan
extends RefCounted

## The repository whose latest release is the update. The upstream organisation
## ships the builds; a fork's tags are not what a player has installed.
const REPO := "RetroXR/RetroXR"

## How a build is replaced, by what it was installed as.
const MODE_NONE := ""
## Linux AppImage: the file itself is swapped for the new one.
const MODE_APPIMAGE := "appimage"
## Linux tarball (arm64): unpacked over the folder the binary sits in.
const MODE_TAR := "tar"
## Windows zip: unpacked over the folder the .exe sits in.
const MODE_ZIP := "zip"
## macOS .app zip: the bundle is swapped for the new one.
const MODE_MAC_APP := "mac_app"


static func latest_url(repo: String = REPO) -> String:
	return "https://api.github.com/repos/%s/releases/latest" % repo


static func releases_page(repo: String = REPO) -> String:
	return "https://github.com/%s/releases/latest" % repo


# ── Versions ──────────────────────────────────────────────────────────────────

## "v0.10.0" -> {nums: [0, 10, 0], pre: ""}; "0.11.0-rc1" -> pre "rc1". {} for
## anything that is not dotted integers, so a tag like "nightly" is never newer
## than anything.
static func parse_version(text: String) -> Dictionary:
	var s := text.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	# Build metadata goes first: its own text may hold a '-' ("1.0.0+build-5"),
	# which is not a pre-release.
	var plus := s.find("+")
	if plus >= 0:
		s = s.substr(0, plus)
	var pre := ""
	var dash := s.find("-")
	if dash >= 0:
		pre = s.substr(dash + 1)
		s = s.substr(0, dash)
	if s.is_empty():
		return {}
	var nums := PackedInt32Array()
	for part: String in s.split("."):
		if not part.is_valid_int() or part.begins_with("-"):
			return {}
		nums.append(part.to_int())
	return {"nums": nums, "pre": pre}


## True when `candidate` is a later release than `current`. A pre-release of a
## version is older than that version; two unparseable strings compare as not
## newer, so a bad tag can never nag.
static func is_newer(candidate: String, current: String) -> bool:
	var a := parse_version(candidate)
	var b := parse_version(current)
	if a.is_empty() or b.is_empty():
		return false
	var an: PackedInt32Array = a["nums"]
	var bn: PackedInt32Array = b["nums"]
	for i in maxi(an.size(), bn.size()):
		var x := an[i] if i < an.size() else 0
		var y := bn[i] if i < bn.size() else 0
		if x != y:
			return x > y
	var ap := str(a["pre"])
	var bp := str(b["pre"])
	if ap == bp:
		return false
	if ap.is_empty():
		return true
	if bp.is_empty():
		return false
	# Natural order, so rc10 follows rc9 (a plain string compare puts it first).
	return ap.naturalnocasecmp_to(bp) > 0


# ── The release ───────────────────────────────────────────────────────────────

## The release's file for this machine, {name, url, size, sha256} -- {} when it
## ships none. Names are what release.yml packs:
##   RetroXR-win-v<ver>.zip            RetroXR-linux-x86_64-v<ver>.AppImage
##   RetroXR-linux-arm64-v<ver>.tar.gz RetroXR-macos-arm64-v<ver>.zip (universal)
static func pick_asset(assets: Array, os_name: String, arch: String) -> Dictionary:
	var prefix := ""
	var suffix := ""
	match os_name:
		"Windows":
			prefix = "RetroXR-win-"
			suffix = ".zip"
		"macOS":
			prefix = "RetroXR-macos-"
			suffix = ".zip"
		"Linux":
			if arch == "arm64":
				prefix = "RetroXR-linux-arm64-"
				suffix = ".tar.gz"
			else:
				prefix = "RetroXR-linux-x86_64-"
				suffix = ".AppImage"
		_:
			return {}
	for a: Variant in assets:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var name := str((a as Dictionary).get("name", ""))
		if name.begins_with(prefix) and name.ends_with(suffix):
			var digest := str((a as Dictionary).get("digest", ""))
			return {
				"name": name,
				"url": str((a as Dictionary).get("browser_download_url", "")),
				"size": int((a as Dictionary).get("size", 0)),
				"sha256": digest.trim_prefix("sha256:") if digest.begins_with("sha256:") else "",
			}
	return {}


## What a /releases/latest answer means for a build at `current`:
## {ok, error, newer, version, tag, page, notes, asset}. Drafts and pre-releases
## are refused even though /latest never returns them.
static func evaluate(release: Dictionary, current: String, os_name: String,
		arch: String) -> Dictionary:
	var tag := str(release.get("tag_name", ""))
	if bool(release.get("draft", false)) or bool(release.get("prerelease", false)):
		return {"ok": false, "error": "The newest release is not a final one."}
	if parse_version(tag).is_empty():
		return {"ok": false, "error": "The newest release has no version number (%s)." % tag}
	return {
		"ok": true,
		"error": "",
		"newer": is_newer(tag, current),
		"version": tag.trim_prefix("v").trim_prefix("V"),
		"tag": tag,
		"page": str(release.get("html_url", releases_page())),
		"notes": summarize_notes(str(release.get("body", ""))),
		"asset": pick_asset(release.get("assets", []), os_name, arch),
	}


## A release body is written for GitHub (headings, a changelog link, a download
## table). The menu wants the prose: heading marks stripped, table rows and bare
## link lines dropped, cut at a line boundary.
static func summarize_notes(body: String, max_chars: int = 480) -> String:
	var out := PackedStringArray()
	var used := 0
	for raw: String in body.replace("\r", "").split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("|") or line.begins_with("**[Full Changelog"):
			continue
		if line.begins_with("SidequestVR:") or line.begins_with("Discord:"):
			continue
		if line.to_lower().begins_with("## downloads"):
			break
		line = line.lstrip("#").strip_edges()
		if line.begins_with("- "):
			line = "• " + line.substr(2)
		if used + line.length() > max_chars:
			out.append("…")
			break
		out.append(line)
		used += line.length() + 1
	return "\n".join(out)


# ── Installing ────────────────────────────────────────────────────────────────

## How THIS install can be replaced: {mode, target, download_to, reason}. `mode`
## is MODE_NONE with a `reason` when it cannot (the player is sent to the release
## page then). `can_write` answers "may I create files in this folder?" so a test
## can say no. `appimage` is the APPIMAGE environment variable, set only inside a
## running AppImage -- the executable path there points into its read-only mount.
static func install_plan(os_name: String, exe_path: String, appimage: String,
		asset_name: String, user_dir: String, can_write: Callable) -> Dictionary:
	var none := func(why: String) -> Dictionary:
		return {"mode": MODE_NONE, "target": "", "download_to": "", "reason": why}
	if asset_name.is_empty():
		return none.call("This release has no build for this machine.")
	match os_name:
		"Linux":
			if asset_name.ends_with(".AppImage"):
				if appimage.is_empty():
					return none.call("RetroXR is not running from an AppImage, so there is "
						+ "nothing to swap in place.")
				if not can_write.call(appimage.get_base_dir()):
					return none.call("The folder holding the AppImage is read-only.")
				return {"mode": MODE_APPIMAGE, "target": appimage,
					"download_to": appimage + ".update", "reason": ""}
			var dir := exe_path.get_base_dir()
			if not can_write.call(dir):
				return none.call("RetroXR's folder is read-only.")
			return {"mode": MODE_TAR, "target": dir,
				"download_to": user_dir.path_join(asset_name), "reason": ""}
		"Windows":
			var wdir := exe_path.get_base_dir()
			if not can_write.call(wdir):
				return none.call("RetroXR's folder needs administrator rights to change.")
			return {"mode": MODE_ZIP, "target": wdir,
				"download_to": user_dir.path_join(asset_name), "reason": ""}
		"macOS":
			var marker := ".app/Contents/MacOS/"
			var at := exe_path.find(marker)
			if at < 0:
				return none.call("RetroXR is not running from an app bundle.")
			var bundle := exe_path.substr(0, at + 4)
			if not can_write.call(bundle.get_base_dir()):
				return none.call("The folder holding RetroXR.app is read-only.")
			return {"mode": MODE_MAC_APP, "target": bundle,
				"download_to": user_dir.path_join(asset_name), "reason": ""}
	return none.call("Updating in place is not supported on %s." % os_name)


## The waiter that finishes an update: [program, arguments], started by the
## running app just before it quits. It waits for `pid` to be GONE (a binary being
## replaced must not be running, and Windows will not let it), swaps the files,
## and starts the new build with `args`. Every path reaches the program as an
## argument, never inside a script string, so a space or a quote in a folder name
## cannot break it -- except in PowerShell, which has no positional form here and
## doubles single quotes instead.
##
## Whatever fails, the app still starts again afterwards (the old build if the
## swap did not happen), so a failed update never leaves the player with no app.
static func waiter_command(plan: Dictionary, _os_name: String, pid: int, exe: String,
		download: String, args: PackedStringArray) -> Array:
	var target := str(plan.get("target", ""))
	match str(plan.get("mode", MODE_NONE)):
		MODE_APPIMAGE:
			var argv := PackedStringArray(["-c",
				"while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done\n"
				+ "chmod +x \"$2\" && mv -f \"$2\" \"$3\"\n"
				+ "shift 3\nexec \"$@\"",
				"sh", str(pid), download, target, target])
			argv.append_array(args)
			return ["/bin/sh", argv]
		MODE_TAR:
			var argv2 := PackedStringArray(["-c",
				"while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done\n"
				+ "tar -xzf \"$2\" -C \"$3\" && rm -f \"$2\"\n"
				+ "shift 3\nexec \"$@\"",
				"sh", str(pid), download, target, exe])
			argv2.append_array(args)
			return ["/bin/sh", argv2]
		MODE_MAC_APP:
			# The new bundle goes in beside the old and is swapped by two renames,
			# so a failed unpack leaves the old app untouched and a failed second
			# rename puts it back. quarantine is cleared because the app was not
			# downloaded by a browser, but a copied zip may carry the flag.
			var argv3 := PackedStringArray(["-c",
				"while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done\n"
				+ "tmp=$(mktemp -d)\n"
				+ "if ditto -x -k \"$2\" \"$tmp\"; then\n"
				+ "  new=$(ls -d \"$tmp\"/*.app 2>/dev/null | head -1)\n"
				+ "  if [ -n \"$new\" ] && mv \"$3\" \"$3.old\"; then\n"
				+ "    if mv \"$new\" \"$3\"; then rm -rf \"$3.old\"; else mv \"$3.old\" \"$3\"; fi\n"
				+ "  fi\n"
				+ "fi\n"
				+ "xattr -cr \"$3\" 2>/dev/null\n"
				+ "rm -rf \"$tmp\" \"$2\"\n"
				+ "app=$3\nshift 3\nexec open \"$app\" --args \"$@\"",
				"sh", str(pid), download, target])
			argv3.append_array(args)
			return ["/bin/sh", argv3]
		MODE_ZIP:
			# Start-Process hands -ArgumentList to the new process as ONE command
			# line, so each argument is quoted the way that process will split it
			# (win_arg); q() then makes the whole line a PowerShell string, which
			# is the only place a single quote is doubled.
			var quoted := PackedStringArray()
			for a: String in args:
				quoted.append(win_arg(a))
			var q := func(s: String) -> String: return "'%s'" % s.replace("'", "''")
			# tar.exe ships with Windows 10+ and is far quicker than Expand-Archive
			# on a build this size; the cmdlet is the fallback for a machine
			# without it. A missing tar.exe THROWS rather than setting an exit
			# code, so the fallback sits outside its try. The zip goes only once
			# something unpacked it, as the tarball's does.
			var script := "Wait-Process -Id %d -ErrorAction SilentlyContinue; " % pid
			script += "$z = %s; $d = %s; $ok = $false; " % [q.call(download), q.call(target)]
			script += "try { & tar.exe -xf $z -C $d; $ok = ($LASTEXITCODE -eq 0) } catch { }; "
			script += "if (-not $ok) { try { Expand-Archive -LiteralPath $z -DestinationPath $d "
			script += "-Force -ErrorAction Stop; $ok = $true } catch { } }; "
			script += "if ($ok) { Remove-Item -LiteralPath $z -Force -ErrorAction SilentlyContinue }; "
			script += "Start-Process -FilePath %s" % q.call(exe)
			if not quoted.is_empty():
				script += " -ArgumentList %s" % q.call(" ".join(quoted))
			return ["powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive",
				"-WindowStyle", "Hidden", "-Command", script])]
	return []


## One argument of a Windows command line, quoted so CommandLineToArgvW gives it
## back unchanged: a '"' is escaped with a backslash, and the backslashes before
## a '"' -- or before the closing quote -- are doubled.
static func win_arg(a: String) -> String:
	var out := "\""
	var slashes := 0
	for ch: String in a:
		if ch == "\\":
			slashes += 1
			continue
		if ch == "\"":
			out += "\\".repeat(slashes * 2 + 1) + "\""
		else:
			out += "\\".repeat(slashes) + ch
		slashes = 0
	return out + "\\".repeat(slashes * 2) + "\""
