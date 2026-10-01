## Bakes the git description of this checkout into an exported build.
##
## A build on a headset cannot run git, and the DEBUG tab's build plate is only
## worth having if it is right there — a version number typed into
## project.godot months ago tells you nothing about which APK is installed. So
## the stamp is taken here, at export, and added to the pack as a file that
## exists in no checkout, which is exactly what lets an editor run tell itself
## apart and ask git live instead.
##
## The file is added, not written to res://: the export file list is already
## decided by the time this runs, so a file on disk would not be packed.
##
## It also makes sure an Android build carries RetroXR's patched engine, for the
## same reason the stamp lives here: this is the one thing every export runs.
@tool
extends EditorExportPlugin


func _get_name() -> String:
	return "RetroXRBuildStamp"


func _export_begin(features: PackedStringArray, is_debug: bool,
				   _path: String, _flags: int) -> void:
	if features.has("android"):
		_ensure_patched_engine("debug" if is_debug else "release")
	var stamp := BuildInfo.collect_from_git()
	# The one field git cannot answer. UTC, because a build gets quoted in a
	# report by someone who is not in the timezone that made it.
	stamp["built"] = Time.get_datetime_string_from_system(true).replace("T", " ")
	add_file(BuildInfo.STAMP_PATH, JSON.stringify(stamp, "\t").to_utf8_buffer(), false)
	print("[build-stamp] %s built %s" % [stamp.get("describe", BuildInfo.UNKNOWN), stamp["built"]])


## The Quest has to ship the engine built from docs/godot-4.7.2-*.patch: stock
## 4.7.2 deadlocks at boot there, on the loading screen, most launches. The
## library goes into the gradle template's AAR (Tools/place_engine.py), and that
## template is shared by every export from this checkout — so one
## `place_engine.py --restore`, run to tidy up after a probe build, silently made
## every later local build stock. Placing here, before gradle reads the AAR,
## takes the step out of anyone's memory. It is a no-op when already placed.
##
## RETROXR_STOCK_ENGINE=1 skips it, for a deliberate stock comparison.
func _ensure_patched_engine(target: String) -> void:
	if OS.get_environment("RETROXR_STOCK_ENGINE") == "1":
		push_warning("[engine] RETROXR_STOCK_ENGINE=1: exporting with whatever engine the template holds")
		return
	var script := ProjectSettings.globalize_path("res://").path_join("../Tools/place_engine.py").simplify_path()
	if not FileAccess.file_exists(script):
		push_error("[engine] %s not found: this Android build may run the STOCK engine, which hangs at boot" % script)
		return
	var out: Array = []
	var code := -1
	for python: String in ["python", "python3"]:
		out.clear()
		code = OS.execute(python, PackedStringArray([script, "--target", target]), out, true)
		if code != -1:
			break
	var text := (str(out[0]) if out.size() > 0 else "").strip_edges()
	if code == 0:
		print("[engine] " + text)
	else:
		push_error(("[engine] place_engine.py --target %s failed (%d): %s. This Android"
			+ " build will run the STOCK engine, which hangs at boot on a Quest.") % [target, code, text])
