## How the update banner and the ABOUT tab's UPDATES section LOOK, in each state.
##
## Feeds the real AppUpdate autoload a canned GitHub answer (no network), then
## draws the banner over the ABOUT tab inside a menu-coloured panel and saves one
## picture per state. WINDOWED (a headless renderer returns blank images):
##
##     "$godot" --path RetroXR --resolution 1100x760 --position 20,20 \
##         res://Tools/room/update_ui_probe.tscn -- --out=/tmp/update_ui
##
## It sets the AppImage path for the run so the "Update now" path (not the release-page
## fallback) is the one drawn, and touches no real file.
extends Control

const RELEASE := {
	"tag_name": "v0.11.0", "draft": false, "prerelease": false,
	"html_url": "https://github.com/RetroXR/RetroXR/releases/tag/v0.11.0",
	"body": "## MAJOR NEW FEATURES\n\n## Desktop window\nFree resizing, a Resolution row that follows it, and an update check.\n\n## Bug Fixes\n\n- fixed a thing\n- fixed another thing\n\n## Downloads\n\n| Platform | File |",
	"assets": [{"name": "RetroXR-linux-x86_64-v0.11.0.AppImage", "size": 412345678,
		"browser_download_url": "https://x/appimage", "digest": "sha256:ab"}],
}

var _out := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	var svc := get_node("/root/AppUpdate") as AppUpdateService
	svc.allow_in_editor = true
	svc.appimage = _out.path_join("RetroXR.AppImage")
	svc.current_version = "0.10.0"
	svc.opener = func(_u: String) -> void: pass
	svc.fetcher = func(_url: String, done: Callable) -> void:
		done.call(true, JSON.stringify(RELEASE), "")

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", MenuStyle.rounded(MenuStyle.COLOR_BG, 10))
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	vbox.add_child(SpawnMenuUpdateBanner.create(null))
	var about := SpawnMenuAboutView.create(null)
	vbox.add_child(about)

	await _frames(5)
	await _shot("0_idle")
	svc.check(true)
	await _frames(5)
	await _shot("1_available")
	svc.state = AppUpdateService.State.DOWNLOADING
	svc.state_changed.emit()
	await _frames(3)
	svc.progress_changed.emit(0.42)
	await _frames(3)
	await _shot("2_downloading")
	svc.state = AppUpdateService.State.READY
	svc.error = "Wait for the room to finish loading."
	svc.state_changed.emit()
	await _frames(3)
	await _shot("3_ready")
	svc.state = AppUpdateService.State.FAILED
	svc.install_failed = true
	svc.error = "The download does not match GitHub's checksum, so it was thrown away."
	svc.state_changed.emit()
	await _frames(3)
	await _shot("4_failed")
	svc.state = AppUpdateService.State.UP_TO_DATE
	svc.install_failed = false
	svc.state_changed.emit()
	await _frames(3)
	await _shot("5_up_to_date")
	get_tree().quit(0)


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(label + ".png"))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
