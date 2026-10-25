## libVLC export probe -- does an EXPORTED build play a video? Every source run
## finds libVLC's plugins in the project, so only an export can show that they
## shipped (v0.11.1 for Windows had none, and nothing played). Point the exported
## game at this scene with an override.cfg beside the executable (on macOS, in
## Contents/MacOS and Contents/Resources):
##
##     [application]
##     run/main_scene="res://Tools/av/vlc_export_probe.tscn"
##
## then run it headless on a short clip with picture and sound:
##
##     RetroXR.exe --headless --log-file <abs path> -- <clip.mp4>
##
## Prints "[vlcprobe] PLAYS" and exits 0 when frames and samples came out.
## release.yml's macOS job runs it on every build.
extends Node

## About two seconds of playback at 60 fps, or longer when the frames come slower.
const FRAMES := 300


func _ready() -> void:
	var exe_dir := OS.get_executable_path().get_base_dir()
	print("[vlcprobe] VlcPlayer class: %s; executable in %s" % [ClassDB.class_exists("VlcPlayer"), exe_dir])
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not ClassDB.class_exists("VlcPlayer"):
		print("[vlcprobe] FAIL: %s" % ("no clip given" if args.is_empty() else "the extension did not load"))
		get_tree().quit(2)
		return
	var vlc: Object = ClassDB.instantiate("VlcPlayer")
	var opened: bool = vlc.open(args[0], false)
	print("[vlcprobe] open %s: %s" % [args[0], opened])
	if opened:
		vlc.play()
	var frames := 0
	var samples := 0
	for i in FRAMES:
		await get_tree().process_frame
		vlc.update_frame()
		frames = vlc.get_frame_count()
		var pcm: Variant = vlc.read_audio(4096)
		if pcm is PackedVector2Array or pcm is PackedFloat32Array:
			samples += pcm.size()
	print("[vlcprobe] %d ms in: %d video frames at %s, %d audio samples" % [
		vlc.get_time(), frames, str(vlc.get_video_size()), samples])
	vlc.shutdown()
	var plays := frames > 0 and samples > 0
	print("[vlcprobe] %s" % ("PLAYS" if plays else "FAIL: nothing came out"))
	get_tree().quit(0 if plays else 1)
