## quality_tests — the GRAPHICS tab's decisions in QualityManager, with no headset.
##
##   "$godot" --headless --path RetroXR res://Tests/quality_tests.tscn
##   "$godot" --headless --path RetroXR res://Tests/quality_tests.tscn -- --only=persist
##
## What a preset drives and what it never touches, that moving any one row makes
## the preset Custom, the clamps on every setter and on a hand-edited prefs file,
## which headset a model string names (3S before 3), where each device starts and
## that a saved file outranks that start, what an unsupported setting stands down
## to, and how a light and an Environment are configured from the tier.
##
## Pure decisions run on a FRESH QualityManager that never enters the tree (its
## _ready would read the player's prefs and push them at the viewport). Setters
## need the tree, so those run on the live autoload, whose fields and
## Engine.max_fps are put back afterwards. Both write the player's real
## user://graphics_prefs.json, which is snapshotted and restored byte for byte.
##
## Not covered: anything that needs OpenXR initialised (eye buffer, refresh rate,
## perf levels, foveation) beyond "not offered on a desktop", and how a tier looks.
extends "res://Tests/test_suite.gd"

const QM := preload("res://Scripts/quality_manager.gd")

## The live autoload's fields this suite moves, put back as found.
const LIVE_FIELDS := ["msaa_3d", "post_aa", "preset", "shadow_quality", "ao_quality",
	"frame_cap", "cpu_level", "gpu_level", "glow_enabled", "screen_lights_enabled",
	"device"]

var _only := ""
var _live: Node = null
var _saved_file: Variant = null
var _saved_live := {}
var _saved_max_fps := 0


func _ready() -> void:
	suite_tag = "quality"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr("--only=".length())
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[quality] TIMEOUT")
		_restore()
		get_tree().quit(1))

	_live = get_node_or_null("/root/QualityManager")
	_ok(_live != null, "setup/the QualityManager autoload is running")
	if _live == null:
		_finish()
		return
	_snapshot()

	_group_presets()
	_group_custom()
	_group_clamps()
	_group_persist()
	_group_device()
	_group_effective()
	_group_lights()

	_restore()
	_finish()


## Group filter on the check's own name, as the other suites do it.
func _wanted(what: String) -> bool:
	return _only.is_empty() or what.begins_with(_only)


func _fresh() -> Node:
	return QM.new()


func _snapshot() -> void:
	_saved_file = _snapshot_file(QM.PREFS_PATH)
	for key: String in LIVE_FIELDS:
		_saved_live[key] = _live.get(key)
	_saved_max_fps = Engine.max_fps


func _restore() -> void:
	if _live == null or _saved_live.is_empty():
		return
	for key: String in _saved_live:
		_live.set(key, _saved_live[key])
	_live.apply_msaa()
	_live.apply_post_aa()
	_live.apply_shadow_quality()
	_live.apply_ao_quality()
	Engine.max_fps = _saved_max_fps
	_restore_file(QM.PREFS_PATH, _saved_file)
	_saved_live.clear()


# ── presets/ ─────────────────────────────────────────────────────────────────

func _group_presets() -> void:
	for level: int in [QM.Preset.LOW, QM.Preset.MEDIUM, QM.Preset.HIGH]:
		var qm := _fresh()
		qm.render_scale = 1.3
		qm.eye_buffer_scale = 1.6
		qm.apply_preset(level, false)
		var row: Dictionary = QM.PRESETS[level]
		var tier: String = QM.Preset.keys()[level]
		_eq(qm.preset, level, "presets/%s is the preset it was asked for" % tier)
		_ok(qm.msaa_3d == row["msaa"] and qm.post_aa == row["post_aa"]
				and qm.shadow_quality == row["shadows"],
			"presets/%s drives MSAA, post AA and shadows to its row" % tier,
			"msaa %d post %d shadows %d" % [qm.msaa_3d, qm.post_aa, qm.shadow_quality])
		# AO is Forward+ only, so a preset must not switch on what the backend ignores.
		var want_ao: int = row["ao"] if qm.supports_post_effects() else QM.AOQuality.OFF
		_eq(qm.ao_quality, want_ao, "presets/%s sets AO only where the backend has it" % tier)
		_ok(qm.render_scale == 1.3 and qm.eye_buffer_scale == 1.6,
			"presets/%s never moves render scale or the eye buffer" % tier)
		qm.free()

	# CUSTOM has no row: it names the state, and changes nothing.
	var custom := _fresh()
	custom.apply_preset(QM.Preset.HIGH, false)
	custom.apply_preset(QM.Preset.CUSTOM, false)
	_ok(custom.preset == QM.Preset.CUSTOM and custom.shadow_quality == QM.ShadowQuality.HIGH
			and custom.msaa_3d == QM.PRESETS[QM.Preset.HIGH]["msaa"],
		"presets/Custom is a name for the rows as they stand, not a tier of its own")
	custom.free()


# ── custom/ — any row off its preset makes the preset Custom ─────────────────

func _group_custom() -> void:
	var rows := {
		"MSAA": func() -> void: _live.set_msaa(Viewport.MSAA_2X),
		"post AA": func() -> void: _live.set_post_aa(QM.PostAA.FXAA),
		"shadows": func() -> void: _live.set_shadow_quality(QM.ShadowQuality.LOW),
		"AO": func() -> void: _live.set_ao_quality(QM.AOQuality.LOW),
		"glow": func() -> void: _live.set_glow_enabled(false),
		"screen lights": func() -> void: _live.set_screen_lights_enabled(false),
	}
	for label: String in rows:
		_live.apply_preset(QM.Preset.HIGH, false)
		(rows[label] as Callable).call()
		_eq(_live.preset, QM.Preset.CUSTOM, "custom/moving %s makes the preset Custom" % label)

	# The control: performance levels are not a quality row, so they leave it alone.
	_live.apply_preset(QM.Preset.HIGH, false)
	_live.set_cpu_level(QM.PerfLevel.BOOST)
	_eq(_live.preset, QM.Preset.HIGH, "custom/a CPU level is not a quality row and keeps the preset")


# ── clamps/ — every setter keeps its value in range ──────────────────────────

func _group_clamps() -> void:
	_live.set_cpu_level(99)
	_eq(_live.cpu_level, QM.PerfLevel.BOOST, "clamps/a CPU level past BOOST is BOOST")
	_live.set_gpu_level(-4)
	_eq(_live.gpu_level, QM.PerfLevel.POWER_SAVINGS, "clamps/a GPU level below the lowest is the lowest")
	_live.set_shadow_quality(17)
	_eq(_live.shadow_quality, QM.ShadowQuality.HIGH, "clamps/a shadow tier past HIGH is HIGH")
	_live.set_msaa(-1)
	_eq(_live.msaa_3d, Viewport.MSAA_DISABLED, "clamps/MSAA below off is off")
	# Under no XR runtime the cap is Engine.max_fps itself.
	_live.set_frame_cap(60)
	_eq(Engine.max_fps, 60, "clamps/a frame cap is the engine's max_fps off a headset")
	_live.set_frame_cap(-30)
	_ok(_live.frame_cap == 0 and Engine.max_fps == 0, "clamps/a negative frame cap is uncapped")


# ── persist/ — the prefs file, both ways ─────────────────────────────────────

func _group_persist() -> void:
	# A preset and one row moved off it, saved by the live manager and read back
	# by a fresh one: the row, the rest of the preset, and that it is Custom.
	_live.apply_preset(QM.Preset.MEDIUM, false)
	_live.set_shadow_quality(QM.ShadowQuality.HIGH)
	var back := _fresh()
	back.load_prefs()
	_ok(back.preset == QM.Preset.CUSTOM and back.shadow_quality == QM.ShadowQuality.HIGH
			and back.msaa_3d == QM.PRESETS[QM.Preset.MEDIUM]["msaa"]
			and back.post_aa == QM.PRESETS[QM.Preset.MEDIUM]["post_aa"],
		"persist/a preset with one row moved comes back Custom, the row and the rest kept",
		"preset %d shadows %d msaa %d post %d" % [back.preset, back.shadow_quality,
			back.msaa_3d, back.post_aa])
	# A file on disk outranks the device's starting point for ever after.
	back.device = QM.Device.QUEST_2
	back.eye_buffer_scale = 1.6
	back.apply_device_defaults()
	_eq(back.eye_buffer_scale, 1.6, "persist/with a prefs file the device default stands aside")
	back.free()

	# A hand-edited file: every value out of range, and a bool that is a string.
	var f := FileAccess.open(QM.PREFS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"msaa_3d": 99, "post_aa": 7, "preset": 42, "shadow_quality": -3, "ao_quality": 9,
		"frame_cap": -30, "zoom": 50.0, "render_scale": 9.0, "eye_buffer_scale": 9.0,
		"display_rate": -5.0, "cpu_level": 10, "gpu_level": -10, "foveation_level": 12,
		"glow_enabled": "yes", "screen_lights_enabled": 0,
	}))
	f.close()
	var odd := _fresh()
	var glow_default: bool = odd.glow_enabled
	var lights_default: bool = odd.screen_lights_enabled
	odd.load_prefs()
	_ok(odd.msaa_3d == Viewport.MSAA_8X and odd.post_aa == QM.PostAA.SMAA
			and odd.preset == QM.Preset.CUSTOM and odd.shadow_quality == QM.ShadowQuality.OFF
			and odd.ao_quality == QM.AOQuality.HIGH,
		"persist/an out-of-range tier loads clamped into range",
		"msaa %d post %d preset %d shadows %d ao %d" % [odd.msaa_3d, odd.post_aa, odd.preset,
			odd.shadow_quality, odd.ao_quality])
	_ok(odd.frame_cap == 0 and odd.zoom == QM.ZOOM_MAX and odd.display_rate == 0.0
			and odd.eye_buffer_scale == QM.EYE_BUFFER_SCALE_MAX,
		"persist/so do the frame cap, zoom, refresh rate and eye buffer")
	_ok(odd.cpu_level == QM.PerfLevel.BOOST and odd.gpu_level == QM.PerfLevel.POWER_SAVINGS
			and odd.foveation_level == QM.Foveation.MAX,
		"persist/and the performance and foveation levels")
	# Forced to 1.0 off Forward+, so a desktop value synced to a headset cannot
	# bring the broken scaling path back with it.
	var want_scale: float = QM.RENDER_SCALE_MAX if odd.supports_post_effects() else 1.0
	_eq(odd.render_scale, want_scale, "persist/render scale is clamped on Forward+ and 1.0 elsewhere")
	_ok(odd.glow_enabled == glow_default and odd.screen_lights_enabled == lights_default,
		"persist/a switch that is not a bool in the file keeps its default")
	odd.free()

	# No file at all: nothing is loaded, and the device default is where it starts.
	_restore_file(QM.PREFS_PATH, null)
	var first := _fresh()
	first.load_prefs()
	first.device = QM.Device.QUEST_2
	first.apply_device_defaults()
	_eq(first.eye_buffer_scale, 1.0, "persist/a first launch takes the device's starting eye buffer")
	first.free()


# ── device/ — which headset a string names, and where each starts ────────────

func _group_device() -> void:
	var probe := _fresh()
	var names := {
		"Oculus Quest 3S": QM.Device.QUEST_3S,
		"quest3s": QM.Device.QUEST_3S,
		"Meta Quest 3": QM.Device.QUEST_3,
		"Adreno (TM) 740": QM.Device.QUEST_3,
		"Quest 2": QM.Device.QUEST_2,
		"Adreno (TM) 650": QM.Device.QUEST_2,
		"GenericDevice": QM.Device.UNKNOWN,
		"": QM.Device.UNKNOWN,
		# What XR_META_headset_id really answers on a Quest 2: a per-device UUID.
		"3f2a1c9e-5b7d-4e2a-9c1f-8d6e4b2a7c10": QM.Device.UNKNOWN,
	}
	for id: String in names:
		_eq(probe.device_from_id(id), names[id], "device/'%s' names %s" % [id,
			QM.Device.keys()[names[id]]])
	probe.free()

	var starts := {
		QM.Device.QUEST_2: 1.0, QM.Device.UNKNOWN: 1.0,
		QM.Device.QUEST_3: QM.EYE_BUFFER_PANEL, QM.Device.QUEST_3S: QM.EYE_BUFFER_PANEL,
		QM.Device.DESKTOP: QM.EYE_BUFFER_PANEL,
	}
	for dev: int in starts:
		var qm := _fresh()
		qm.eye_buffer_scale = 1.9
		qm.device = dev
		qm.apply_device_defaults()
		_ok(is_equal_approx(qm.eye_buffer_scale, starts[dev]),
			"device/%s starts at eye buffer x%.3f" % [QM.Device.keys()[dev], starts[dev]],
			"got x%.3f" % qm.eye_buffer_scale)
		qm.free()

	if _live.is_desktop():
		_eq(_live.detect_device(), QM.Device.DESKTOP, "device/a desktop run is the desktop")


# ── effective/ — what an unsupported setting stands down to ──────────────────

func _group_effective() -> void:
	var qm := _fresh()
	qm.post_aa = QM.PostAA.SMAA
	_eq(qm.effective_post_aa(), QM.PostAA.SMAA if qm.supports_smaa() else QM.PostAA.FXAA,
		"effective/SMAA stands down to FXAA, not to nothing, where it cannot run")
	qm.post_aa = QM.PostAA.FXAA
	_eq(qm.effective_post_aa(), QM.PostAA.FXAA, "effective/FXAA is FXAA everywhere")
	qm.post_aa = QM.PostAA.OFF
	_eq(qm.effective_post_aa(), QM.PostAA.OFF, "effective/and off is off")
	qm.render_scale = 1.3
	_eq(qm.effective_render_scale(), 1.3 if qm.supports_render_scale() else 1.0,
		"effective/render scale is 1.0 wherever scaling the 3D pass is unsafe")
	_eq(qm.render_scale, 1.3, "effective/and the stored preference is left alone")
	qm.foveation_level = QM.Foveation.OFF
	_eq(qm.stencil_safe(), qm.supports_post_effects(),
		"effective/stencil materials only on Forward+ with foveation off")
	qm.foveation_level = QM.Foveation.HIGH
	_ok(not qm.stencil_safe(), "effective/and never under foveation")
	qm.shadow_quality = QM.ShadowQuality.OFF
	_ok(not qm.shadows_enabled(), "effective/shadow tier OFF casts nothing")
	qm.shadow_quality = QM.ShadowQuality.LOW
	_ok(qm.shadows_enabled(), "effective/and LOW casts")
	qm.free()

	if _live.is_desktop():
		_ok(not _live.supports_eye_buffer_scale() and not _live.supports_perf_levels()
				and not _live.supports_foveation(),
			"effective/a desktop offers no eye buffer, perf levels or foveation")


# ── lights/ — a light and an Environment from the tier ───────────────────────

func _group_lights() -> void:
	# A fresh instance never ran _ready, so it answers as a headset does
	# (_desktop false); the live one on this run is the desktop.
	var headset := _fresh()
	headset.shadow_quality = QM.ShadowQuality.MEDIUM
	var omni := OmniLight3D.new()
	headset.configure_light(omni)
	_ok(omni.shadow_enabled, "lights/a light casts at a tier with shadows")
	var opted := OmniLight3D.new()
	opted.add_to_group("no_shadow")
	opted.shadow_enabled = true
	headset.configure_light(opted)
	_ok(not opted.shadow_enabled, "lights/a no_shadow light never casts")
	var mobile_only := OmniLight3D.new()
	mobile_only.add_to_group("no_shadow_mobile")
	headset.configure_light(mobile_only)
	_ok(not mobile_only.shadow_enabled, "lights/a no_shadow_mobile light is dark on a headset")
	if _live.is_desktop():
		var keep: int = _live.shadow_quality
		_live.shadow_quality = QM.ShadowQuality.MEDIUM
		_live.configure_light(mobile_only)
		_ok(mobile_only.shadow_enabled, "lights/and casts on the desktop")
		_live.shadow_quality = keep

	var sun := DirectionalLight3D.new()
	headset.configure_light(sun)
	_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"lights/the sun takes four splits above LOW")
	headset.shadow_quality = QM.ShadowQuality.LOW
	headset.configure_light(sun)
	_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL,
		"lights/and one orthogonal map at LOW")
	headset.shadow_quality = QM.ShadowQuality.OFF
	headset.configure_light(sun)
	_ok(not sun.shadow_enabled, "lights/and none at OFF")

	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.glow_enabled = true
	headset.glow_enabled = false
	headset.ao_quality = QM.AOQuality.HIGH
	headset.configure_environment(we)
	_ok(not we.environment.glow_enabled, "lights/the glow switch reaches the room's Environment")
	_eq(we.environment.ssao_enabled, headset.supports_post_effects(),
		"lights/AO is switched on only where the backend draws it")
	headset.ao_quality = QM.AOQuality.OFF
	headset.configure_environment(we)
	_ok(not we.environment.ssao_enabled, "lights/and off at OFF")

	for n: Node in [omni, opted, mobile_only, sun, we]:
		n.free()
	headset.free()
